import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../models/models.dart';
import 'qinav_hls.dart';
import 'qinav_http.dart';
import 'qinav_site.dart';

/// Fixed loopback port for Qinav module (separate from Iwara dynamic port).
const qinavLocalPort = 18766;

class QinavServer {
  QinavServer({required this.site, required this.http});

  final QinavSite site;
  final QinavHttp http;
  HttpServer? _server;

  String get baseUrl => 'http://127.0.0.1:$qinavLocalPort';
  int get port => _server?.port ?? qinavLocalPort;

  Future<void> start() async {
    if (_server != null) return;
    final router = Router();

    router.get('/api/new', (Request request) => _list(request, site.listNew));
    router.get('/api/hot', (Request request) => _list(request, site.listHot));
    router.get('/api/like', (Request request) => _list(request, site.listLike));
    router.get('/api/rank', (Request request) async {
      try {
        final items = await site.rank();
        return _json({'items': items.map(_itemJson).toList()});
      } catch (e) {
        return _json({'error': '$e'}, status: 502);
      }
    });
    router.get('/api/tags', (Request request) async {
      try {
        final tags = await site.tags();
        return _json({
          'items': [
            for (final t in tags)
              {'tagId': t.tagId, 'name': t.name, 'count': t.count, 'url': t.url},
          ],
        });
      } catch (e) {
        return _json({'error': '$e'}, status: 502);
      }
    });
    router.get('/api/site', (Request request) async {
      final cid = int.tryParse(request.url.queryParameters['cid'] ?? '1') ?? 1;
      final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
      try {
        final items = await site.listSite(cid, page);
        return _json({'cid': cid, 'items': items.map(_itemJson).toList()});
      } catch (e) {
        return _json({'error': '$e'}, status: 502);
      }
    });
    router.get('/api/search', (Request request) async {
      final kw = (request.url.queryParameters['kw'] ?? '').trim();
      final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
      if (kw.isEmpty) return _json({'error': 'kw required'}, status: 400);
      try {
        final r = await site.search(kw, page);
        return _json({
          'keyword': r.keyword,
          'items': r.items.map(_itemJson).toList(),
          'total': r.total,
          'tagId': r.tagId,
          'tagName': r.tagName,
          'page': r.page,
          'url': r.url,
        });
      } catch (e) {
        return _json({'error': '$e'}, status: 502);
      }
    });
    router.get('/api/video/<vid>', (Request request, String vid) async {
      try {
        final d = await site.videoDetail(int.parse(vid));
        return _json({
          'vid': d.vid,
          'title': d.title,
          'description': d.description,
          'embedUrl': d.embedUrl,
          'zan': d.zan,
          'cai': d.cai,
          'favorites': d.favorites,
          'related': d.related.map(_itemJson).toList(),
        });
      } catch (e) {
        return _json({'error': '$e'}, status: 502);
      }
    });
    router.get('/api/video/<vid>/play', (Request request, String vid) async {
      try {
        final play = await site.playback(int.parse(vid));
        final playable = resolvePlayableProxyUrl(play.url);
        return _json({
          'vid': int.parse(vid),
          'master': play.url,
          'reachable': play.reachable,
          'variants': [
            for (final v in play.variants) {'bandwidth': v.bandwidth, 'url': v.url},
          ],
          'proxyMaster': playable,
          'proxyPlay': playable,
        });
      } catch (e) {
        return _json({'error': '$e'}, status: 502);
      }
    });

    // Preferred single entry for ExoPlayer: always returns a media playlist.
    // .m3u8 suffix helps ExoPlayer format sniffing when formatHint is missing.
    Future<Response> playHandler(Request request) async {
      try {
        final source = _safeUrl(request.url.queryParameters['url']);
        final body = await _mediaPlaylistBody(source);
        return _m3u8(body);
      } catch (e) {
        return _json({'error': '$e'}, status: 502);
      }
    }

    Future<Response> mediaHandler(Request request) async {
      try {
        final source = _safeUrl(request.url.queryParameters['url']);
        final text = await http.getText(source, maxBytes: 4 * 1024 * 1024);
        // Nested master is rare but flatten just in case.
        final body = isMasterPlaylist(text)
            ? await _mediaPlaylistBody(source)
            : rewriteMedia(text, source, baseUrl);
        return _m3u8(body);
      } catch (e) {
        return _json({'error': '$e'}, status: 502);
      }
    }

    router.get('/api/hls/play', playHandler);
    router.get('/api/hls/play.m3u8', playHandler);
    router.get('/api/hls/master', playHandler);
    router.get('/api/hls/master.m3u8', playHandler);
    router.get('/api/hls/media', mediaHandler);
    router.get('/api/hls/media.m3u8', mediaHandler);
    router.get('/api/hls/variant', mediaHandler);
    router.get('/api/hls/seg', (Request request) => _proxyBinary(request, 'video/mp2t'));
    router.get('/api/hls/key', (Request request) => _proxyBinary(request, 'application/octet-stream'));
    router.get('/api/img', (Request request) async {
      try {
        final imgUrl = _safeUrl(request.url.queryParameters['url']);
        final r = await http.request(imgUrl, maxBytes: 4 * 1024 * 1024);
        if (r.status >= 400) return _json({'error': 'upstream ${r.status}'}, status: 502);
        return Response.ok(
          r.body,
          headers: {
            'content-type': r.headers['content-type'] ?? 'image/jpeg',
            'cache-control': 'public, max-age=86400',
          },
        );
      } catch (e) {
        return _json({'error': '$e'}, status: 400);
      }
    });

    final handler = const Pipeline().addHandler(router.call);
    _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, qinavLocalPort);
  }

  /// Flatten master -> best media on the server, expose one stable local URL.
  String resolvePlayableProxyUrl(String upstreamUrl) {
    return '$baseUrl/api/hls/play.m3u8?url=${Uri.encodeQueryComponent(upstreamUrl)}';
  }

  Future<String> _mediaPlaylistBody(String sourceUrl) async {
    final text = await http.getText(sourceUrl, maxBytes: 4 * 1024 * 1024);
    if (isMasterPlaylist(text)) {
      final best = bestVariantUrl(text, sourceUrl);
      if (best == null) {
        return rewriteMaster(text, sourceUrl, baseUrl);
      }
      final media = await http.getText(best, maxBytes: 4 * 1024 * 1024);
      // Guard against nested masters.
      if (isMasterPlaylist(media)) {
        final nested = bestVariantUrl(media, best);
        if (nested != null) {
          final nestedText = await http.getText(nested, maxBytes: 4 * 1024 * 1024);
          return rewriteMedia(nestedText, nested, baseUrl);
        }
      }
      return rewriteMedia(media, best, baseUrl);
    }
    return rewriteMedia(text, sourceUrl, baseUrl);
  }

  Future<Response> _list(
    Request request,
    Future<List<QinavVideoItem>> Function([int page]) loader,
  ) async {
    final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
    try {
      final items = await loader(page);
      return _json({'items': items.map(_itemJson).toList()});
    } catch (e) {
      return _json({'error': '$e'}, status: 502);
    }
  }

  Future<Response> _proxyBinary(Request request, String contentType) async {
    try {
      final url = _safeUrl(request.url.queryParameters['url']);
      final r = await http.request(
        url,
        maxBytes: 32 * 1024 * 1024,
        timeout: const Duration(seconds: 45),
      );
      if (r.status >= 400) {
        return _json({'error': 'upstream ${r.status}'}, status: 502);
      }
      final upstreamType = r.headers['content-type'];
      return Response.ok(
        r.body,
        headers: {
          'content-type': (upstreamType != null && upstreamType.isNotEmpty)
              ? upstreamType
              : contentType,
          'cache-control': 'public, max-age=60',
          'access-control-allow-origin': '*',
          'accept-ranges': 'bytes',
        },
      );
    } catch (e) {
      return _json({'error': '$e'}, status: 502);
    }
  }

  String _safeUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) throw ArgumentError('url required');
    final u = Uri.parse(value);
    if (u.scheme != 'http' && u.scheme != 'https') {
      throw ArgumentError('bad url');
    }
    return u.toString();
  }

  Map<String, dynamic> _itemJson(QinavVideoItem item) {
    return {
      'vid': item.vid,
      'title': item.title,
      'url': item.url,
      'cover': item.cover,
      'duration': item.duration,
      'views': item.views,
      'likes': item.likes,
      'time': item.time,
    };
  }

  Response _m3u8(String body) {
    return Response.ok(
      body,
      headers: {
        'content-type': 'application/vnd.apple.mpegurl',
        'cache-control': 'no-store',
        'access-control-allow-origin': '*',
      },
    );
  }

  Response _json(Object data, {int status = 200}) {
    return Response(
      status,
      body: jsonEncode(data),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
