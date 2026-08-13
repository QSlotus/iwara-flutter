import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// HTTP client with optional Cloudflare forced-IP for qinav.com hosts.
/// CDN hosts use normal DNS but always send the site Referer.
class QinavHttp {
  QinavHttp({String resolveIp = '104.25.243.202'}) : _resolveIp = resolveIp;

  static const base = 'https://www.qinav.com';
  static const ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
  static const referer = 'https://www.qinav.com/';
  static const origin = 'https://www.qinav.com';

  static const pinnedHosts = {'qinav.com', 'www.qinav.com'};

  String _resolveIp;
  String get resolveIp => _resolveIp;
  set resolveIp(String value) {
    final v = value.trim();
    if (v.isNotEmpty) _resolveIp = v;
  }

  Future<HttpClient> _client({bool pin = false, Duration? timeout}) async {
    final client = HttpClient();
    client.connectionTimeout = timeout ?? const Duration(seconds: 20);
    client.idleTimeout = const Duration(seconds: 120);
    client.autoUncompress = true;
    client.userAgent = ua;
    if (pin) {
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
    }
    return client;
  }

  bool _shouldPin(String host) => pinnedHosts.contains(host.toLowerCase());

  Future<({int status, Map<String, String> headers, Uint8List body, String finalUrl})> request(
    String url, {
    String method = 'GET',
    Map<String, String>? headers,
    List<int>? body,
    int maxRedirects = 5,
    Duration timeout = const Duration(seconds: 20),
    int maxBytes = 8 * 1024 * 1024,
  }) async {
    var current = url;
    var currentMethod = method.toUpperCase();
    List<int>? currentBody = body;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      final uri = Uri.parse(current);
      final pin = _shouldPin(uri.host);
      final client = await _client(pin: pin, timeout: timeout);
      try {
        final req = await client.openUrl(currentMethod, uri);
        req.followRedirects = false;
        req.headers.set(HttpHeaders.userAgentHeader, ua);
        req.headers.set(HttpHeaders.refererHeader, referer);
        req.headers.set('Origin', origin);
        req.headers.set(HttpHeaders.acceptHeader, '*/*');
        req.headers.set('Accept-Language', 'zh-CN,zh;q=0.9');
        headers?.forEach((k, v) {
          if (k.toLowerCase() == 'host') return;
          req.headers.set(k, v);
        });
        req.headers.set(HttpHeaders.hostHeader, uri.host);
        if (currentBody != null) req.add(currentBody);
        final response = await req.close().timeout(timeout + const Duration(seconds: 5));
        final status = response.statusCode;
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (status >= 300 && status < 400 && location != null && hop < maxRedirects) {
          await response.drain<void>();
          // POST + 302/303 becomes GET (site search behavior)
          if (currentMethod == 'POST' && status != 307 && status != 308) {
            currentMethod = 'GET';
            currentBody = null;
          }
          current = uri.resolve(location).toString();
          continue;
        }
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
        final hdrs = <String, String>{};
        response.headers.forEach((name, values) {
          if (values.isNotEmpty) hdrs[name.toLowerCase()] = values.join(',');
        });
        return (status: status, headers: hdrs, body: builder.takeBytes(), finalUrl: current);
      } finally {
        client.close(force: true);
      }
    }
    throw StateError('Too many redirects for $url');
  }

  Future<String> getText(
    String url, {
    int retries = 3,
    int maxBytes = 8 * 1024 * 1024,
  }) async {
    Object? last;
    for (var i = 0; i <= retries; i++) {
      try {
        final r = await request(url, maxBytes: maxBytes);
        if (r.status < 400) return utf8.decode(r.body, allowMalformed: true);
        if (r.status == 404) throw StateError('HTTP 404: $url');
        last = StateError('HTTP ${r.status}: $url');
      } catch (e) {
        final msg = '$e';
        if (msg.contains('HTTP 404')) rethrow;
        last = e;
      }
      await Future<void>.delayed(Duration(milliseconds: 500 * (i + 1)));
    }
    throw last ?? StateError('request failed: $url');
  }

  Future<Uint8List> getBuffer(
    String url, {
    int retries = 3,
    int maxBytes = 16 * 1024 * 1024,
  }) async {
    Object? last;
    for (var i = 0; i <= retries; i++) {
      try {
        final r = await request(url, maxBytes: maxBytes, timeout: const Duration(seconds: 30));
        if (r.status < 400) return r.body;
        if (r.status == 404) throw StateError('HTTP 404: $url');
        last = StateError('HTTP ${r.status}: $url');
      } catch (e) {
        final msg = '$e';
        if (msg.contains('HTTP 404')) rethrow;
        last = e;
      }
      await Future<void>.delayed(Duration(milliseconds: 500 * (i + 1)));
    }
    throw last ?? StateError('request failed: $url');
  }

  Future<({int status, Map<String, String> headers, Uint8List body, String finalUrl})> postForm(
    String url,
    String body,
  ) {
    return request(
      url,
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: utf8.encode(body),
    );
  }
}
