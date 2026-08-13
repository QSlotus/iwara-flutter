import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class UpstreamResponse {
  UpstreamResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final HttpHeaders headers;
  final Uint8List body;

  String get bodyText => utf8.decode(body, allowMalformed: true);

  dynamic get jsonBody {
    try {
      return jsonDecode(bodyText);
    } catch (_) {
      return null;
    }
  }
}

class UpstreamClient {
  UpstreamClient({
    this.apiHost = 'api.iwara.tv',
    this.filesHost = 'files.iwara.tv',
    String resolveIp = '104.25.243.202',
  }) : _resolveIp = resolveIp;

  final String apiHost;
  final String filesHost;
  String _resolveIp;

  String get resolveIp => _resolveIp;
  set resolveIp(String value) => _resolveIp = value.trim().isEmpty ? _resolveIp : value.trim();

  bool isAllowedHost(String hostname) {
    final normalized = hostname.toLowerCase();
    const known = {
      'api.iwara.tv',
      'apiq.iwara.tv',
      'files.iwara.tv',
      'filesq.iwara.tv',
      'service.iwara.tv',
      'www.iwara.tv',
      'news.iwara.tv',
      'support.iwara.tv',
      'i.iwara.tv',
    };
    return known.contains(normalized) || normalized == 'iwara.tv' || normalized.endsWith('.iwara.tv');
  }

  Map<String, String> upstreamHeaders({
    String? token,
    String? captcha,
    String accept = 'application/json',
  }) {
    final headers = <String, String>{
      'Accept': accept,
      'User-Agent': 'iwara-signal-desk/0.1',
      'X-Site': 'www.iwara.tv',
      'Origin': 'https://www.iwara.tv',
      'Referer': 'https://www.iwara.tv/',
    };
    final normalized = _normalizeToken(token);
    if (normalized.isNotEmpty) headers['Authorization'] = normalized;
    if (captcha != null && captcha.isNotEmpty) headers['X-Captcha'] = captcha;
    return headers;
  }

  String signedFileVersion(Uri target) {
    if (!target.path.startsWith('/file/')) return '';
    final parts = target.path.split('/').where((e) => e.isNotEmpty).toList();
    final fileId = parts.isEmpty ? '' : parts.last;
    final expires = target.queryParameters['expires'];
    if (fileId.isEmpty || expires == null || expires.isEmpty) return '';
    final digest = sha1.convert(utf8.encode('${fileId}_${expires}_mSvL05GfEmeEmsEYfGCnVpEjYgTJraJN'));
    return digest.toString();
  }

  Map<String, String> mediaHeaders(Uri target, {String accept = '*/*', String? range}) {
    final headers = <String, String>{
      'Accept': accept,
      'User-Agent': 'iwara-signal-desk/0.1',
      'Origin': 'https://www.iwara.tv',
      'Referer': 'https://www.iwara.tv/',
    };
    final version = signedFileVersion(target);
    if (version.isNotEmpty) headers['X-Version'] = version;
    if (range != null && range.isNotEmpty) headers['Range'] = range;
    return headers;
  }

  Future<HttpClient> _client({Duration? connectionTimeout, Duration? idleTimeout}) async {
    final client = HttpClient();
    client.connectionTimeout = connectionTimeout ?? const Duration(seconds: 20);
    client.idleTimeout = idleTimeout ?? const Duration(seconds: 180);
    client.autoUncompress = true;
    // Always force the selected Cloudflare edge IP for every upstream host
    // (API + CDN). SNI/Host stay as the original hostname.
    final ip = InternetAddress(_resolveIp);
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      final port = uri.hasPort ? uri.port : (uri.scheme == 'http' ? 80 : 443);
      final raw = await Socket.connect(ip, port, timeout: const Duration(seconds: 20));
      if (uri.scheme == 'http') {
        return ConnectionTask.fromSocket(Future<Socket>.value(raw), raw.destroy);
      }
      final secure = await SecureSocket.secure(raw, host: uri.host);
      return ConnectionTask.fromSocket(Future<Socket>.value(secure), secure.destroy);
    };
    return client;
  }

  Future<UpstreamResponse> request({
    required String host,
    required String method,
    required String route,
    Map<String, String>? headers,
    List<int>? body,
    int maxBytes = 4 * 1024 * 1024,
  }) async {
    if (!isAllowedHost(host)) throw StateError('Host is not allowlisted: $host');
    if (!route.startsWith('/') || route.contains('..') || route.contains('\\')) {
      throw StateError('Unsafe upstream route.');
    }

    final client = await _client();
    try {
      final uri = Uri.parse('https://$host$route');
      final req = await client.openUrl(method.toUpperCase(), uri);
      req.followRedirects = true;
      req.maxRedirects = 8;
      headers?.forEach((key, value) {
        if (key.toLowerCase() == 'host') return;
        req.headers.set(key, value);
      });
      req.headers.set(HttpHeaders.hostHeader, host);
      if (body != null) req.add(body);
      final response = await req.close().timeout(const Duration(seconds: 45));
      final builder = BytesBuilder(copy: false);
      var size = 0;
      await for (final chunk in response) {
        final next = size + chunk.length;
        if (next <= maxBytes) {
          builder.add(chunk);
          size = next;
        } else {
          final remain = maxBytes - size;
          if (remain > 0) builder.add(chunk.sublist(0, remain));
          break;
        }
      }
      return UpstreamResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        body: builder.takeBytes(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<({HttpClient client, HttpClientResponse response})> openStream({
    required String host,
    required String method,
    required String route,
    Map<String, String>? headers,
  }) async {
    if (!isAllowedHost(host)) throw StateError('Host is not allowlisted: $host');
    if (!route.startsWith('/') || route.contains('..') || route.contains('\\')) {
      throw StateError('Unsafe upstream route.');
    }
    final client = await _client(
      connectionTimeout: const Duration(seconds: 25),
      idleTimeout: const Duration(minutes: 10),
    );
    try {
      final uri = Uri.parse('https://$host$route');
      final req = await client.openUrl(method.toUpperCase(), uri);
      req.followRedirects = true;
      req.maxRedirects = 8;
      headers?.forEach((key, value) {
        if (key.toLowerCase() == 'host') return;
        req.headers.set(key, value);
      });
      req.headers.set(HttpHeaders.hostHeader, host);
      final response = await req.close().timeout(const Duration(seconds: 45));
      return (client: client, response: response);
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  String _normalizeToken(String? value) {
    final token = (value ?? '').trim();
    if (token.isEmpty) return '';
    return token.toLowerCase().startsWith('bearer ') ? token : 'Bearer $token';
  }
}
