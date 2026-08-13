import 'dart:convert';

import '../models/models.dart';
import 'xmav_http.dart';

class XmavApi {
  XmavApi({required this.http, required this.base});

  final XmavHttp http;
  String base;

  Map<String, String>? _parseMap;
  Uri _u(String path, [Map<String, String>? query]) {
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$root$p').replace(queryParameters: query);
  }

  Future<XmavPageResult> list({int page = 1, int limit = 20, int? tid}) async {
    final q = <String, String>{
      'mid': '1',
      'page': '$page',
      'limit': '$limit',
    };
    if (tid != null && tid > 0) q['tid'] = '$tid';
    final res = await http.get(_u('/index.php/ajax/data', q).toString(), referer: base);
    if (res.status < 200 || res.status >= 300) {
      throw StateError('列表失败 HTTP ${res.status}');
    }
    final json = jsonDecode(res.body);
    if (json is! Map) throw StateError('列表响应非 JSON 对象');
    final code = json['code'];
    if (code != 1 && code != '1') {
      throw StateError('列表失败: ${json['msg'] ?? code}');
    }
    final list = json['list'];
    final items = <XmavVideoItem>[];
    if (list is List) {
      for (final row in list) {
        if (row is Map) {
          items.add(XmavVideoItem.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }
    int asInt(dynamic v, int d) {
      if (v is int) return v;
      return int.tryParse('$v') ?? d;
    }

    return XmavPageResult(
      items: items,
      page: asInt(json['page'], page),
      pageCount: asInt(json['pagecount'], 1),
      limit: asInt(json['limit'], limit),
      total: asInt(json['total'], items.length),
    );
  }

  Future<List<XmavSuggestItem>> suggest(String keyword, {int limit = 10}) async {
    final wd = keyword.trim();
    if (wd.isEmpty) return const [];
    final res = await http.get(
      _u('/index.php/ajax/suggest', {'mid': '1', 'wd': wd, 'limit': '$limit'}).toString(),
      referer: base,
    );
    if (res.status < 200 || res.status >= 300) return const [];
    final json = jsonDecode(res.body);
    if (json is! Map) return const [];
    final list = json['list'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) => XmavSuggestItem.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<XmavPageResult> searchHtml(String keyword, {int page = 1}) async {
    final wd = keyword.trim();
    if (wd.isEmpty) {
      return XmavPageResult(items: const [], page: page, pageCount: 1);
    }
    // MacCMS search path; page often encoded in path segment pattern.
    final path = page <= 1 ? '/xmsearch/-------------/' : '/xmsearch/-------------/page/$page/';
    final res = await http.get(_u(path, {'wd': wd}).toString(), referer: base);
    if (res.status < 200 || res.status >= 300) {
      throw StateError('搜索失败 HTTP ${res.status}');
    }
    final items = _parseSearchHtml(res.body);
    // Heuristic page count: if full-ish page, allow next.
    final pageCount = items.isEmpty ? (page > 1 ? page : 1) : (items.length >= 10 ? page + 1 : page);
    return XmavPageResult(items: items, page: page, pageCount: pageCount, total: items.length);
  }

  List<XmavVideoItem> _parseSearchHtml(String html) {
    final out = <XmavVideoItem>[];
    final seen = <int>{};
    final re = RegExp(
      r'''href\s*=\s*["']([^"']*xmdetail/(\d+)/?)["'][^>]*>(.*?)</a>''',
      caseSensitive: false,
      dotAll: true,
    );
    for (final m in re.allMatches(html)) {
      final id = int.tryParse(m.group(2) ?? '') ?? 0;
      if (id <= 0 || seen.contains(id)) continue;
      seen.add(id);
      final rawTitle = m.group(3) ?? '';
      final title = rawTitle.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (title.isEmpty) continue;
      out.add(XmavVideoItem(id: id, title: title));
    }
    // Fallback: bare detail links
    if (out.isEmpty) {
      final re2 = RegExp(r'''/xmdetail/(\d+)/?''');
      for (final m in re2.allMatches(html)) {
        final id = int.tryParse(m.group(1) ?? '') ?? 0;
        if (id <= 0 || seen.contains(id)) continue;
        seen.add(id);
        out.add(XmavVideoItem(id: id, title: '视频 $id'));
      }
    }
    return out;
  }

  Future<List<XmavCategory>> loadCategories() async {
    try {
      final res = await http.get('$base/', referer: base);
      if (res.status >= 200 && res.status < 300) {
        final parsed = _parseCategories(res.body);
        if (parsed.isNotEmpty) return parsed;
      }
    } catch (_) {}
    return List<XmavCategory>.from(xmavFallbackCategories);
  }

  List<XmavCategory> _parseCategories(String html) {
    final out = <XmavCategory>[];
    final seen = <int>{};
    final re = RegExp(
      r'''href\s*=\s*["'][^"']*xmtype/(\d+)/?["'][^>]*>(.*?)</a>''',
      caseSensitive: false,
      dotAll: true,
    );
    for (final m in re.allMatches(html)) {
      final tid = int.tryParse(m.group(1) ?? '') ?? 0;
      if (tid <= 0 || seen.contains(tid)) continue;
      final name = (m.group(2) ?? '').replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (name.isEmpty) continue;
      seen.add(tid);
      out.add(XmavCategory(tid: tid, name: name));
    }
    return out;
  }

  Future<XmavPlayback> resolvePlayback(int vodId, {int sid = 1, int nid = 1}) async {
    final playPath = '/xmplay/$vodId-$sid-$nid/';
    final res = await http.get(_u(playPath).toString(), referer: base);
    if (res.status < 200 || res.status >= 300) {
      throw StateError('播放页失败 HTTP ${res.status}');
    }
    final obj = _extractPlayerAaaa(res.body);
    if (obj == null) {
      throw StateError('播放页未找到 player_aaaa');
    }

    final encrypt = _asInt(obj['encrypt']);
    var url = '${obj['url'] ?? ''}'.trim();
    url = decodePlayerUrl(url, encrypt);
    final from = '${obj['from'] ?? ''}'.trim();
    final title = '${(obj['vod_data'] is Map) ? (obj['vod_data']['vod_name'] ?? '') : ''}'.trim();

    var usedParse = false;
    if (!_looksDirectPlayable(url)) {
      final parsed = await _applyParseIfNeeded(url: url, from: from);
      if (parsed != null && parsed.isNotEmpty) {
        url = parsed;
        usedParse = true;
      }
    }

    if (url.isEmpty) {
      throw StateError('无法解析播放地址');
    }

    return XmavPlayback(url: url, from: from, encrypt: encrypt, title: title, usedParse: usedParse);
  }

  Map<String, dynamic>? _extractPlayerAaaa(String html) {
    final idx = html.indexOf('player_aaaa');
    if (idx < 0) return null;
    // Find first `{` after assignment
    final assign = html.indexOf('=', idx);
    if (assign < 0) return null;
    final start = html.indexOf('{', assign);
    if (start < 0) return null;
    final end = _matchJsonObjectEnd(html, start);
    if (end < 0) return null;
    final raw = html.substring(start, end + 1);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Some sites emit JS object with unquoted keys — rare for player_aaaa; fail soft.
    }
    return null;
  }

  int _matchJsonObjectEnd(String s, int start) {
    var depth = 0;
    var inStr = false;
    var esc = false;
    var quote = '';
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (inStr) {
        if (esc) {
          esc = false;
          continue;
        }
        if (c == r'\') {
          esc = true;
          continue;
        }
        if (c == quote) inStr = false;
        continue;
      }
      if (c == '"' || c == "'") {
        inStr = true;
        quote = c;
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static String decodePlayerUrl(String url, int encrypt) {
    var v = url;
    if (encrypt == 1) {
      v = jsUnescape(v);
    } else if (encrypt == 2) {
      try {
        final bytes = base64.decode(_normalizeB64(v));
        v = jsUnescape(utf8.decode(bytes, allowMalformed: true));
      } catch (_) {
        // keep original
      }
    }
    return v.trim();
  }

  static String _normalizeB64(String s) {
    var t = s.trim().replaceAll('-', '+').replaceAll('_', '/');
    final mod = t.length % 4;
    if (mod > 0) t = t.padRight(t.length + (4 - mod), '=');
    return t;
  }

  static String jsUnescape(String input) {
    // Handle %uXXXX and %XX similar to JS unescape.
    final buf = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (c == '%' && i + 1 < input.length) {
        if (input[i + 1] == 'u' && i + 5 < input.length) {
          final hex = input.substring(i + 2, i + 6);
          final cp = int.tryParse(hex, radix: 16);
          if (cp != null) {
            buf.writeCharCode(cp);
            i += 5;
            continue;
          }
        } else if (i + 2 < input.length) {
          final hex = input.substring(i + 1, i + 3);
          final cp = int.tryParse(hex, radix: 16);
          if (cp != null) {
            buf.writeCharCode(cp);
            i += 2;
            continue;
          }
        }
      }
      buf.write(c);
    }
    try {
      return Uri.decodeFull(buf.toString());
    } catch (_) {
      return buf.toString();
    }
  }

  static bool _looksDirectPlayable(String url) {
    final u = url.trim().toLowerCase();
    if (!(u.startsWith('http://') || u.startsWith('https://'))) return false;
    if (u.contains('.m3u8') || u.contains('.mp4') || u.contains('.flv') || u.contains('.mkv')) return true;
    // some CDNs omit extension but still HLS
    if (u.contains('m3u8') || u.contains('/hls/')) return true;
    return false;
  }

  Future<String?> _applyParseIfNeeded({required String url, required String from}) async {
    if (url.isEmpty) return null;
    await _ensureParseMap();
    final parse = _parseMap?[from] ?? _parseMap?['_default'];
    if (parse == null || parse.isEmpty) {
      // last resort: if url is absolute http, return as-is
      if (url.startsWith('http')) return url;
      return null;
    }
    final absParse = parse.startsWith('http') ? parse : _u(parse).toString();
    // parse endpoints usually expect `parse + url`
    if (absParse.contains('url=')) {
      if (absParse.endsWith('url=') || absParse.endsWith('url=')) {
        return '$absParse${Uri.encodeQueryComponent(url)}';
      }
      return '$absParse${Uri.encodeQueryComponent(url)}';
    }
    return '$absParse${Uri.encodeQueryComponent(url)}';
  }

  Future<void> _ensureParseMap() async {
    if (_parseMap != null) return;
    _parseMap = {};
    try {
      final res = await http.get(_u('/static/js/playerconfig.js').toString(), referer: base);
      if (res.status < 200 || res.status >= 300) return;
      final body = res.body;
      // player_list:{ jsp:{...,parse:"/dp.php?url=",ps:"1"}, ...}
      final block = RegExp(r'player_list\s*[:=]\s*\{', caseSensitive: false).firstMatch(body);
      if (block == null) return;
      final start = body.indexOf('{', block.start);
      final end = _matchJsonObjectEnd(body, start);
      if (end < 0) return;
      final chunk = body.substring(start, end + 1);
      final fromRe = RegExp(
        r'''["']?(\w+)["']?\s*:\s*\{[^}]*?parse\s*:\s*["']([^"']+)["']''',
        caseSensitive: false,
      );
      for (final m in fromRe.allMatches(chunk)) {
        final key = m.group(1)!;
        final parse = m.group(2)!;
        _parseMap![key] = parse;
      }
      // common defaults
      _parseMap!.putIfAbsent('jsp', () => '/dp.php?url=');
      _parseMap!.putIfAbsent('_default', () => '/dp.php?url=');
    } catch (_) {
      _parseMap = {
        'jsp': '/dp.php?url=',
        '_default': '/dp.php?url=',
      };
    }
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }
}
