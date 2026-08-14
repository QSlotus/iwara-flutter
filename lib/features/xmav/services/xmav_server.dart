import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'xmav_hls.dart';
import 'xmav_http.dart';

/// Fixed loopback port for Xmav HLS proxy (site traffic stays direct).
const xmavLocalPort = 18767;

class XmavServer {
  XmavServer({required this.http, required this.siteBase});

  final XmavHttp http;
  String siteBase;
  HttpServer? _server;

  String get baseUrl => 'http://127.0.0.1:$xmavLocalPort';
  int get port => _server?.port ?? xmavLocalPort;

  Future<void> start() async {
    if (_server != null) return;
    final router = Router();

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
        final text = await _getText(source);
        final body = isMasterPlaylist(text)
            ? rewriteMaster(text, source, baseUrl)
            : rewriteMedia(text, source, baseUrl);
        return _m3u8(body);
      } catch (e) {
        return _json({'error': '$e'}, status: 502);
      }
    }

    router.get('/api/hls/play', playHandler);
    router.get('/api/hls/play.m3u8', playHandler);
    router.get('/api/hls/media', mediaHandler);
    router.get('/api/hls/media.m3u8', mediaHandler);
    router.get('/api/hls/seg', (Request request) => _proxyBinary(request, 'video/mp2t'));
    router.get('/api/hls/key', (Request request) => _proxyBinary(request, 'application/octet-stream'));

    final handler = const Pipeline().addHandler(router.call);
    _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, xmavLocalPort);
  }

  String resolvePlayableProxyUrl(String upstreamUrl) {
    return '$baseUrl/api/hls/play.m3u8?url=${Uri.encodeQueryComponent(upstreamUrl)}';
  }

  Future<String> _mediaPlaylistBody(String sourceUrl) async {
    final text = await _getText(sourceUrl);
    if (isMasterPlaylist(text)) {
      final best = bestVariantUrl(text, sourceUrl);
      if (best == null) {
        return rewriteMaster(text, sourceUrl, baseUrl);
      }
      final media = await _getText(best);
      if (isMasterPlaylist(media)) {
        final nested = bestVariantUrl(media, best);
        if (nested != null) {
          final nestedText = await _getText(nested);
          return rewriteMedia(nestedText, nested, baseUrl);
        }
      }
      return rewriteMedia(media, best, baseUrl);
    }
    return rewriteMedia(text, sourceUrl, baseUrl);
  }

  Future<String> _getText(String url) async {
    final res = await http.get(
      url,
      referer: siteBase.isNotEmpty ? siteBase : null,
      timeout: const Duration(seconds: 30),
    );
    if (res.status < 200 || res.status >= 300) {
      throw StateError('upstream HTTP ${res.status} for $url');
    }
    return res.body;
  }

  Future<Response> _proxyBinary(Request request, String contentType) async {
    try {
      final url = _safeUrl(request.url.queryParameters['url']);
      final bytes = await http.getBytes(
        url,
        referer: siteBase.isNotEmpty ? siteBase : null,
        timeout: const Duration(seconds: 45),
      );
      return Response.ok(
        bytes,
        headers: {
          'content-type': contentType,
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
    final s = _server;
    _server = null;
    if (s != null) {
      await s.close(force: true);
    }
  }
}
