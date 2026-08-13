import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../models/models.dart';
import 'api_catalog.dart';
import 'edge_probe.dart';
import 'upstream_client.dart';

class LocalApiServer {
  LocalApiServer({
    required this.catalog,
    required this.upstream,
    required this.edgeProbe,
    this.configuredIp = '104.25.243.202',
  });

  final ApiCatalog catalog;
  final UpstreamClient upstream;
  final EdgeProbeService edgeProbe;
  final String configuredIp;

  HttpServer? _server;
  EdgeStatus edgeStatus = EdgeStatus(
    status: 'idle',
    activeIp: '104.25.243.202',
    configuredIp: '104.25.243.202',
  );
  bool _edgeLocked = false;
  Future<void>? _edgeRun;

  int get port => _server?.port ?? 0;
  String get baseUrl => 'http://127.0.0.1:$port';

  Future<void> start() async {
    if (_server != null) return;
    final router = Router();

    router.get('/api/health', (Request request) async {
      return _json({
        'ok': true,
        'service': 'iwara-signal-desk',
        'forcedIp': upstream.resolveIp,
        'configuredIp': configuredIp,
        'apiHost': upstream.apiHost,
        'filesHost': upstream.filesHost,
        'edgeStatus': edgeStatus.status,
      });
    });

    router.get('/api/config', (Request request) async {
      return _json({
        'apiHost': upstream.apiHost,
        'filesHost': upstream.filesHost,
        'resolveIp': upstream.resolveIp,
        'configuredResolveIp': configuredIp,
        'forcedResolution': true,
        'edgeStatus': edgeStatus.status,
        'edgeSource': edgeStatus.source,
        'hosts': [
          upstream.apiHost,
          upstream.filesHost,
          'apiq.iwara.tv',
          'filesq.iwara.tv',
          'service.iwara.tv',
          'www.iwara.tv',
          'news.iwara.tv',
          'support.iwara.tv',
          'i.iwara.tv',
        ],
      });
    });

    router.get('/api/catalog', (Request request) async {
      return _json({
        'operations': catalog.operations.values
            .map((op) => {
                  'operation': op.operation,
                  'method': op.method,
                  'host': op.host,
                  'route': op.route,
                  'scope': op.scope,
                  'body': op.body,
                })
            .toList(),
        'auxiliaryOperations': catalog.auxiliary.values
            .map((op) => {
                  'operation': op.operation,
                  'method': op.method,
                  'host': op.host,
                  'route': op.route,
                })
            .toList(),
      });
    });

    router.get('/api/edge/status', (Request request) async => _json(edgeStatus.toJson()));
    router.get('/api/speed-test', (Request request) async => _json(edgeStatus.toJson()));

    router.post('/api/edge/refresh', (Request request) async {
      unawaited(runEdgeTest(force: true));
      return _json(edgeStatus.toJson());
    });
    router.post('/api/speed-test/refresh', (Request request) async {
      unawaited(runEdgeTest(force: true));
      return _json(edgeStatus.toJson());
    });

    router.post('/api/edge/select', (Request request) async {
      final body = await _readJson(request);
      final ip = '${body['ip'] ?? ''}'.trim();
      if (ip.isEmpty) {
        return _json({'message': 'A valid IPv4 or IPv6 address is required.'}, status: 400);
      }
      final allowed = edgeStatus.results.any((item) => item.ip == ip) || ip == configuredIp;
      if (!allowed && edgeStatus.results.isNotEmpty) {
        return Response(
          409,
          body: jsonEncode({
            'message': 'Select an address from the current CloudflareSpeedTest results.',
            ...edgeStatus.toJson(),
          }),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      _edgeLocked = true;
      upstream.resolveIp = ip;
      edgeStatus = EdgeStatus(
        status: edgeStatus.status,
        activeIp: ip,
        configuredIp: configuredIp,
        fastestIp: edgeStatus.fastestIp,
        selectedIp: ip,
        selectionMode: 'manual',
        source: edgeStatus.source,
        warning: edgeStatus.warning,
        durationMs: edgeStatus.durationMs,
        results: edgeStatus.results,
      );
      return _json(edgeStatus.toJson());
    });

    router.post('/api/call/<operation>', (Request request, String operation) async {
      final op = catalog.operations[operation];
      if (op == null) {
        return _json({'message': 'Unknown or restricted API operation.'}, status: 404);
      }
      if (operation == 'uploadFile') {
        return _json({'message': 'Use /api/upload for uploadFile.'}, status: 400);
      }
      final payload = await _readJson(request);
      try {
        final route = _routeForOperation(op, payload);
        final headers = upstream.upstreamHeaders(
          token: '${payload['token'] ?? request.headers['authorization'] ?? ''}',
          captcha: payload['captcha']?.toString(),
        );
        List<int>? bodyBytes;
        final method = op.method.toUpperCase();
        if (method != 'GET' && method != 'DELETE') {
          final shouldSendBody = op.body || payload.containsKey('body');
          if (shouldSendBody) {
            final body = payload.containsKey('body') ? payload['body'] : <String, dynamic>{};
            final text = body is String ? body : jsonEncode(body ?? {});
            bodyBytes = utf8.encode(text);
            headers['Content-Type'] = 'application/json';
          }
        }
        final result = await upstream.request(
          host: op.host,
          method: method,
          route: route,
          headers: headers,
          body: bodyBytes,
        );
        return _upstream(result);
      } catch (error) {
        return _json({'message': error.toString()}, status: 502);
      }
    });

    router.post('/api/aux/<operation>', (Request request, String operation) async {
      final op = catalog.auxiliary[operation];
      if (op == null) {
        return _json({'message': 'Unknown auxiliary operation.'}, status: 404);
      }
      final payload = await _readJson(request);
      try {
        if (operation == 'fetchSignedFile') {
          var rawUrl = '${payload['url'] ?? ''}';
          if (rawUrl.isEmpty) {
            final fileId = payload['args'] is Map ? '${payload['args']['fileId'] ?? ''}' : '';
            final expires = payload['query'] is Map ? '${payload['query']['expires'] ?? ''}' : '';
            final hash = payload['query'] is Map ? '${payload['query']['hash'] ?? ''}' : '';
            if (fileId.isEmpty || expires.isEmpty || hash.isEmpty) {
              return _json({
                'message': 'fetchSignedFile requires url or args.fileId + query.expires + query.hash.',
              }, status: 400);
            }
            rawUrl = 'https://filesq.iwara.tv/file/${Uri.encodeComponent(fileId)}?expires=${Uri.encodeComponent(expires)}&hash=${Uri.encodeComponent(hash)}';
          }
          final target = Uri.parse(rawUrl.startsWith('//') ? 'https:$rawUrl' : rawUrl);
          if (!upstream.isAllowedHost(target.host)) {
            return _json({'message': 'Signed file host is not allowlisted.'}, status: 403);
          }
          final headers = upstream.mediaHeaders(target, accept: 'application/json');
          final result = await upstream.request(
            host: target.host,
            method: 'GET',
            route: '${target.path}${target.hasQuery ? '?${target.query}' : ''}',
            headers: headers,
          );
          return _upstream(result);
        }

        final route = _routeForOperation(op, payload);
        final headers = upstream.upstreamHeaders(
          token: '${payload['token'] ?? request.headers['authorization'] ?? ''}',
        );
        final result = await upstream.request(
          host: op.host,
          method: op.method,
          route: route,
          headers: headers,
        );
        return _upstream(result);
      } catch (error) {
        return _json({'message': error.toString()}, status: 502);
      }
    });

    router.get('/api/media/sources', (Request request) async {
      final raw = request.url.queryParameters['url'] ?? '';
      if (raw.isEmpty) {
        return _json({'message': 'A valid allowlisted media URL is required.'}, status: 400);
      }
      try {
        final target = Uri.parse(raw.startsWith('//') ? 'https:$raw' : raw);
        if (target.scheme != 'https' || !upstream.isAllowedHost(target.host)) {
          return _json({'message': 'A valid allowlisted media URL is required.'}, status: 400);
        }
        final result = await upstream.request(
          host: target.host,
          method: 'GET',
          route: '${target.path}${target.hasQuery ? '?${target.query}' : ''}',
          headers: upstream.mediaHeaders(target, accept: 'application/json'),
        );
        if (result.statusCode < 200 || result.statusCode >= 300) {
          return _upstream(result);
        }
        final decoded = result.jsonBody;
        final sources = _playableSources(decoded)
            .map((source) => {
                  'label': source.label,
                  'url': '/api/media?url=${Uri.encodeComponent(source.url)}',
                  if (source.downloadUrl != null)
                    'downloadUrl': '/api/media?url=${Uri.encodeComponent(source.downloadUrl!)}',
                })
            .toList();
        if (sources.isEmpty) {
          return _json({
            'sources': [
              {'label': 'Source', 'url': '/api/media?url=${Uri.encodeComponent(target.toString())}'}
            ]
          });
        }
        return _json({'sources': sources});
      } catch (error) {
        return _json({'message': error.toString()}, status: 502);
      }
    });


    router.get('/api/media', (Request request) async {
      final raw = request.url.queryParameters['url'] ?? '';
      final depth = int.tryParse(request.url.queryParameters['depth'] ?? '0') ?? 0;
      if (raw.isEmpty) {
        return _json({'message': 'A valid media URL is required.'}, status: 400);
      }
      try {
        var target = Uri.parse(raw.startsWith('//') ? 'https:$raw' : raw);
        if (target.scheme != 'https' || !upstream.isAllowedHost(target.host) || target.path == '/admin' || target.path.startsWith('/admin/')) {
          return _json({'message': 'Media host is not allowlisted.'}, status: 403);
        }
        final range = request.headers['range'];
        var currentDepth = depth;

        // Single-stream resolve: open once. JSON manifests hop; binary pipes immediately.
        // Never buffer whole video files. All hosts still use forced edge IP.
        while (true) {
          final opened = await upstream.openStream(
            host: target.host,
            method: 'GET',
            route: '${target.path}${target.hasQuery ? '?${target.query}' : ''}',
            headers: upstream.mediaHeaders(
              target,
              accept: request.headers['accept'] ?? '*/*',
              range: range,
            ),
          );
          final response = opened.response;
          final contentType = response.headers.contentType?.mimeType ?? response.headers.value('content-type') ?? '';
          final isJson = contentType.contains('json');

          if (currentDepth < 3 && response.statusCode >= 200 && response.statusCode < 300 && isJson) {
            final builder = BytesBuilder(copy: false);
            var size = 0;
            const maxJson = 2 * 1024 * 1024;
            await for (final chunk in response) {
              final next = size + chunk.length;
              if (next <= maxJson) {
                builder.add(chunk);
                size = next;
              } else {
                break;
              }
            }
            opened.client.close(force: true);
            dynamic decoded;
            try {
              decoded = jsonDecode(utf8.decode(builder.takeBytes(), allowMalformed: true));
            } catch (_) {
              decoded = null;
            }
            final next = _playableSources(decoded);
            if (next.isNotEmpty) {
              target = Uri.parse(next.first.url);
              currentDepth += 1;
              continue;
            }
            return _json({'message': 'Media manifest did not contain a playable source.'}, status: 422);
          }

          final headers = <String, String>{};
          for (final name in [
            'content-type',
            'content-length',
            'content-range',
            'accept-ranges',
            'last-modified',
            'etag',
            'cache-control',
          ]) {
            final value = response.headers.value(name);
            if (value != null && value.isNotEmpty) headers[name] = value;
          }
          headers.putIfAbsent('accept-ranges', () => 'bytes');
          // Avoid accidental caching of signed CDN URLs.
          headers.putIfAbsent('cache-control', () => 'private, max-age=0');

          final controller = StreamController<List<int>>(
            onCancel: () {
              opened.client.close(force: true);
            },
          );
          response.listen(
            controller.add,
            onError: (Object error, StackTrace stack) {
              if (!controller.isClosed) controller.addError(error, stack);
              opened.client.close(force: true);
            },
            onDone: () {
              if (!controller.isClosed) controller.close();
              opened.client.close(force: true);
            },
            cancelOnError: true,
          );

          return Response(
            response.statusCode,
            body: controller.stream,
            headers: headers,
            context: {'shelf.io.buffer_output': false},
          );
        }
      } catch (error) {
        return _json({'message': error.toString()}, status: 502);
      }
    });

    final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router.call);
    _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    // Edge probe is started only on first launch or from Account settings.
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> runEdgeTest({bool force = false}) async {
    if (_edgeRun != null && !force) return _edgeRun!;
    final started = DateTime.now();
    edgeStatus = EdgeStatus(
      status: 'running',
      activeIp: upstream.resolveIp,
      configuredIp: configuredIp,
      selectionMode: _edgeLocked ? 'manual' : 'configured',
      selectedIp: _edgeLocked ? upstream.resolveIp : null,
    );
    final future = () async {
      try {
        final results = await edgeProbe.run(configuredIp: configuredIp, limit: 10);
        final fastest = results.isNotEmpty ? results.first.ip : null;
        if (fastest != null && !_edgeLocked) {
          upstream.resolveIp = fastest;
        }
        edgeStatus = EdgeStatus(
          status: results.isNotEmpty ? 'ready' : 'error',
          activeIp: upstream.resolveIp,
          configuredIp: configuredIp,
          fastestIp: fastest,
          selectedIp: _edgeLocked ? upstream.resolveIp : fastest,
          selectionMode: _edgeLocked ? 'manual' : 'automatic',
          source: 'node-tcp-fallback',
          durationMs: DateTime.now().difference(started).inMilliseconds,
          results: results,
          warning: results.isEmpty ? 'No Cloudflare edge responded to the latency probe.' : null,
        );
      } catch (error) {
        edgeStatus = EdgeStatus(
          status: 'error',
          activeIp: upstream.resolveIp,
          configuredIp: configuredIp,
          source: 'error',
          warning: error.toString(),
          durationMs: DateTime.now().difference(started).inMilliseconds,
        );
      }
    }();
    _edgeRun = future.whenComplete(() => _edgeRun = null);
    return _edgeRun!;
  }

  Future<void> applySavedIp(String ip, {bool locked = true}) async {
    final value = ip.trim();
    if (value.isEmpty) return;
    _edgeLocked = locked;
    upstream.resolveIp = value;
    edgeStatus = EdgeStatus(
      status: edgeStatus.status == 'idle' ? 'ready' : edgeStatus.status,
      activeIp: value,
      configuredIp: configuredIp,
      fastestIp: edgeStatus.fastestIp,
      selectedIp: locked ? value : edgeStatus.selectedIp,
      selectionMode: locked ? 'manual' : edgeStatus.selectionMode,
      source: edgeStatus.source ?? 'saved',
      warning: edgeStatus.warning,
      durationMs: edgeStatus.durationMs,
      results: edgeStatus.results,
    );
  }

  Future<void> selectIp(String ip) async {
    _edgeLocked = true;
    upstream.resolveIp = ip;
    edgeStatus = EdgeStatus(
      status: edgeStatus.status,
      activeIp: ip,
      configuredIp: configuredIp,
      fastestIp: edgeStatus.fastestIp,
      selectedIp: ip,
      selectionMode: 'manual',
      source: edgeStatus.source,
      warning: edgeStatus.warning,
      durationMs: edgeStatus.durationMs,
      results: edgeStatus.results,
    );
  }

  String _routeForOperation(ApiOperation operation, Map<String, dynamic> payload) {
    final args = payload['args'] is Map ? Map<String, dynamic>.from(payload['args'] as Map) : <String, dynamic>{};
    var route = operation.route.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (match) {
      final expression = match.group(1)!;
      final value = _readArg(args, expression);
      if (value == null || '$value'.isEmpty) {
        throw StateError('Missing route argument: $expression');
      }
      return Uri.encodeComponent('$value');
    });
    if (operation.method.toUpperCase() == 'GET') {
      route = _appendQuery(route, payload['query']);
    }
    return route;
  }

  dynamic _readArg(Map<String, dynamic> args, String expression) {
    final parts = expression.split('.');
    dynamic value = args[parts.first];
    for (final part in parts.skip(1)) {
      if (value is Map) {
        value = value[part];
      } else {
        return null;
      }
    }
    return value;
  }

  String _appendQuery(String route, dynamic query) {
    if (query is! Map) return route;
    final parts = <String>[];
    query.forEach((key, value) {
      if (value == null) return;
      if (value is List) {
        for (final item in value) {
          if (item == null) continue;
          parts.add('${Uri.encodeQueryComponent('$key')}=${Uri.encodeQueryComponent('$item')}');
        }
      } else if ('$value'.isEmpty) {
        return;
      } else {
        parts.add('${Uri.encodeQueryComponent('$key')}=${Uri.encodeQueryComponent('$value')}');
      }
    });
    if (parts.isEmpty) return route;
    final suffix = parts.join('&');
    return route.contains('?') ? '$route&$suffix' : '$route?$suffix';
  }


  List<PlayableMediaSource> _playableSources(dynamic value) {
    final sources = <PlayableMediaSource>[];

    void addSource(String label, String raw, {String? downloadRaw}) {
      final url = _mediaUrl(raw);
      if (url == null) return;
      sources.add(
        PlayableMediaSource(
          label: label,
          url: url.toString(),
          downloadUrl: downloadRaw == null ? null : _mediaUrl(downloadRaw)?.toString(),
        ),
      );
    }

    void visit(dynamic node, [String label = '']) {
      if (node is List) {
        for (final item in node) {
          visit(item, label);
        }
        return;
      }
      if (node is! Map) return;
      final record = Map<String, dynamic>.from(node);
      final name = '${record['name'] ?? record['quality'] ?? record['resolution'] ?? label}'.trim();

      // Common Iwara manifest shape: { name, src: { view, download } }
      final src = record['src'];
      if (src is Map) {
        final srcMap = Map<String, dynamic>.from(src);
        if (srcMap['view'] is String) {
          addSource(name.isEmpty ? 'Source' : name, '${srcMap['view']}', downloadRaw: srcMap['download'] is String ? '${srcMap['download']}' : null);
        }
        if (srcMap['url'] is String) {
          addSource(name.isEmpty ? 'Source' : name, '${srcMap['url']}');
        }
      }

      for (final key in ['view', 'download', 'url', 'fileUrl', 'src']) {
        final candidate = record[key];
        if (candidate is String) {
          addSource(name.isEmpty ? key : name, candidate, downloadRaw: record['download'] is String ? '${record['download']}' : null);
        }
      }

      record.forEach((key, child) {
        if (['id', 'name', 'quality', 'resolution', 'src', 'view', 'download', 'url', 'fileUrl'].contains(key)) {
          return;
        }
        if (child is Map || child is List) {
          visit(child, name.isEmpty ? key : name);
        }
      });
    }

    visit(value);
    final nonPreview = sources.where((s) => !RegExp(r'preview', caseSensitive: false).hasMatch(s.label)).toList();
    final selected = nonPreview.isNotEmpty ? nonPreview : sources;
    // Default to Source first, then progressive ladders (360 -> higher).
    int rank(PlayableMediaSource source) {
      final label = source.label.toLowerCase();
      if (label.contains('preview')) return 100000;
      if (label.contains('source') || label.contains('原始') || label.contains('origin')) return 0;
      final match = RegExp(r'(\d{3,4})p').firstMatch(label);
      if (match != null) {
        final height = int.tryParse(match.group(1)!) ?? 9999;
        return 1000 + height;
      }
      return 5000;
    }

    selected.sort((a, b) => rank(a).compareTo(rank(b)));
    // de-dupe by url
    final seen = <String>{};
    return selected.where((s) => seen.add(s.url)).toList();
  }

  Uri? _mediaUrl(String value) {
    try {
      final normalized = value.trim();
      if (normalized.isEmpty) return null;
      final url = Uri.parse(normalized.startsWith('//') ? 'https:$normalized' : normalized);
      if (url.scheme == 'https' && upstream.isAllowedHost(url.host)) return url;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final text = await request.readAsString();
    if (text.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  Response _json(Object body, {int status = 200}) {
    return Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Response _upstream(UpstreamResponse result) {
    final contentType = result.headers.value('content-type') ?? 'application/octet-stream';
    if (contentType.contains('application/json')) {
      final decoded = result.jsonBody;
      if (decoded != null) {
        return Response(
          result.statusCode,
          body: jsonEncode(decoded),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    }
    return Response(
      result.statusCode,
      body: result.body,
      headers: {'content-type': contentType},
    );
  }
}
