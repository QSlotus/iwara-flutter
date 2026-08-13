import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class XmavHttp {
  XmavHttp();

  static const userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  final http.Client _client = http.Client();

  Map<String, String> _headers({String? referer, Map<String, String>? extra}) {
    return {
      'User-Agent': userAgent,
      'Accept': '*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      if (referer != null && referer.isNotEmpty) 'Referer': referer,
      ...?extra,
    };
  }

  Future<({int status, String body, String finalUrl, Map<String, String> headers})> get(
    String url, {
    String? referer,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final uri = Uri.parse(url);
    final res = await _client
        .get(uri, headers: _headers(referer: referer, extra: headers))
        .timeout(timeout);
    return (
      status: res.statusCode,
      body: res.body,
      finalUrl: res.request?.url.toString() ?? url,
      headers: res.headers.map((k, v) => MapEntry(k.toLowerCase(), v)),
    );
  }

  Future<Uint8List> getBytes(
    String url, {
    String? referer,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final uri = Uri.parse(url);
    final res = await _client
        .get(uri, headers: _headers(referer: referer))
        .timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('HTTP ${res.statusCode} for $url');
    }
    return res.bodyBytes;
  }

  void close() {
    _client.close();
  }
}

String decodeBodyAsUtf8(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);
