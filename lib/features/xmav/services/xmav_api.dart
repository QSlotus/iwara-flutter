import 'dart:convert';

import '../models/models.dart';
import 'xmav_http.dart';

/// HTML-first Xmav client.
///
/// All list/category/search/detail/play data comes from public MacCMS pages
/// under the resolved content [base]. No site proxy / local HLS proxy.
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

  Future<String> _getHtml(String path, {Map<String, String>? query}) async {
    final res = await http.get(_u(path, query).toString(), referer: base);
    if (res.status < 200 || res.status >= 300) {
      throw StateError('页面失败 HTTP ${res.status}: $path');
    }
    return res.body;
  }

  /// Categories from home nav links `/xmtype/{tid}/`.
  Future<List<XmavCategory>> loadCategories() async {
    try {
      final html = await _getHtml('/');
      final parsed = XmavHtml.parseCategories(html);
      if (parsed.isNotEmpty) return parsed;
    } catch (_) {}
    return List<XmavCategory>.from(xmavFallbackCategories);
  }

  /// Homepage "最新视频" block. Site home has no multi-page; page>1 returns empty.
  Future<XmavPageResult> latest({int page = 1}) async {
    if (page > 1) {
      return XmavPageResult(items: const [], page: page, pageCount: 1);
    }
    final html = await _getHtml('/');
    final items = XmavHtml.parseVideoCards(html);
    return XmavPageResult(
      items: items,
      page: 1,
      pageCount: 1,
      limit: items.length,
      total: items.length,
    );
  }

  /// Category list page: `/xmtype/{tid}/` or `/xmtype/{tid}-{page}/`.
  Future<XmavPageResult> categoryList(int tid, {int page = 1}) async {
    if (tid <= 0) {
      throw StateError('无效分类 tid');
    }
    final p = page < 1 ? 1 : page;
    final path = p <= 1 ? '/xmtype/$tid/' : '/xmtype/$tid-$p/';
    final html = await _getHtml(path);
    final items = XmavHtml.parseVideoCards(html);
    final pager = XmavHtml.parsePager(html);
    return XmavPageResult(
      items: items,
      page: pager.page ?? p,
      pageCount: pager.pageCount ?? (items.isEmpty ? p : p),
      limit: items.length,
      total: pager.total ?? items.length,
    );
  }

  /// Search result pages.
  Future<XmavPageResult> search(String keyword, {int page = 1}) async {
    final wd = keyword.trim();
    if (wd.isEmpty) {
      return XmavPageResult(items: const [], page: page, pageCount: 1);
    }
    final p = page < 1 ? 1 : page;
    final path = p <= 1 ? '/xmsearch/-------------/' : '/xmsearch/-------------/page/$p/';
    final html = await _getHtml(path, query: {'wd': wd});
    final items = XmavHtml.parseVideoCards(html);
    final pager = XmavHtml.parsePager(html);
    return XmavPageResult(
      items: items,
      page: pager.page ?? p,
      pageCount: pager.pageCount ?? (items.isEmpty ? 1 : p),
      limit: items.length,
      total: pager.total ?? items.length,
    );
  }

  /// Optional soft suggest via site ajax (not used for core lists).
  Future<List<XmavSuggestItem>> suggest(String keyword, {int limit = 10}) async {
    final wd = keyword.trim();
    if (wd.isEmpty) return const [];
    try {
      final res = await http.get(
        _u('/index.php/ajax/suggest', {'mid': '1', 'wd': wd, 'limit': '$limit'}).toString(),
        referer: base,
      );
      if (res.status < 200 || res.status >= 300) return const [];
      final json = jsonDecode(res.body);
      if (json is! Map) return const [];
      final list = json['list'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => XmavSuggestItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Detail metadata from `/xmdetail/{id}/`.
  Future<XmavVideoItem> detail(int id) async {
    if (id <= 0) throw StateError('无效视频 id');
    final html = await _getHtml('/xmdetail/$id/');
    return XmavHtml.parseDetail(html, id: id, base: base);
  }

  /// Play URL from `/xmplay/{id}-1-1/` → `player_aaaa` (+ optional parse fallback).
  Future<XmavPlayback> resolvePlayback(int vodId, {int sid = 1, int nid = 1}) async {
    final playPath = '/xmplay/$vodId-$sid-$nid/';
    final html = await _getHtml(playPath);
    final obj = XmavHtml.extractPlayerAaaa(html);
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

    return XmavPlayback(
      url: url,
      from: from,
      encrypt: encrypt,
      title: title,
      usedParse: usedParse,
    );
  }

  Future<String?> _applyParseIfNeeded({required String url, required String from}) async {
    if (url.isEmpty) return null;
    await _ensureParseMap();
    final parse = _parseMap?[from] ?? _parseMap?['_default'];
    if (parse == null || parse.isEmpty) {
      if (url.startsWith('http')) return url;
      return null;
    }
    final absParse = parse.startsWith('http') ? parse : _u(parse).toString();
    if (absParse.contains('url=')) {
      return '$absParse${Uri.encodeQueryComponent(url)}';
    }
    return '$absParse${Uri.encodeQueryComponent(url)}';
  }

  Future<void> _ensureParseMap() async {
    if (_parseMap != null) return;
    _parseMap = {};
    try {
      final res = await http.get(_u('/static/js/playerconfig.js').toString(), referer: base);
      if (res.status < 200 || res.status >= 300) {
        _parseMap = {'jsp': '/dp.php?url=', '_default': '/dp.php?url='};
        return;
      }
      final body = res.body;
      final block = RegExp(r'player_list\s*[:=]\s*\{', caseSensitive: false).firstMatch(body);
      if (block == null) {
        _parseMap = {'jsp': '/dp.php?url=', '_default': '/dp.php?url='};
        return;
      }
      final start = body.indexOf('{', block.start);
      final end = XmavHtml.matchJsonObjectEnd(body, start);
      if (end < 0) {
        _parseMap = {'jsp': '/dp.php?url=', '_default': '/dp.php?url='};
        return;
      }
      final chunk = body.substring(start, end + 1);
      final fromRe = RegExp(
        r'''["']?(\w+)["']?\s*:\s*\{[^}]*?parse\s*:\s*["']([^"']+)["']''',
        caseSensitive: false,
      );
      for (final m in fromRe.allMatches(chunk)) {
        _parseMap![m.group(1)!] = m.group(2)!;
      }
      _parseMap!.putIfAbsent('jsp', () => '/dp.php?url=');
      _parseMap!.putIfAbsent('_default', () => '/dp.php?url=');
    } catch (_) {
      _parseMap = {'jsp': '/dp.php?url=', '_default': '/dp.php?url='};
    }
  }

  static String decodePlayerUrl(String url, int encrypt) {
    var v = url;
    if (encrypt == 1) {
      v = jsUnescape(v);
    } else if (encrypt == 2) {
      try {
        final bytes = base64.decode(_normalizeB64(v));
        v = jsUnescape(utf8.decode(bytes, allowMalformed: true));
      } catch (_) {}
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
    if (u.contains('.m3u8') || u.contains('.mp4') || u.contains('.flv') || u.contains('.mkv')) {
      return true;
    }
    if (u.contains('m3u8') || u.contains('/hls/')) return true;
    return false;
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }
}

class XmavPagerInfo {
  const XmavPagerInfo({this.page, this.pageCount, this.total});
  final int? page;
  final int? pageCount;
  final int? total;
}

/// Pure HTML extractors for MacCMS XM template pages.
class XmavHtml {
  static List<XmavCategory> parseCategories(String html) {
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
      final name = _stripTags(m.group(2) ?? '');
      if (name.isEmpty) continue;
      seen.add(tid);
      out.add(XmavCategory(tid: tid, name: name));
    }
    return out;
  }

  /// Card pattern:
  /// `<a href="/xmdetail/123/" title="..."><img src="..." ...><br /><span>08-13.</span> title</a>`
  static List<XmavVideoItem> parseVideoCards(String html) {
    final out = <XmavVideoItem>[];
    final seen = <int>{};

    final cardRe = RegExp(
      r'''<a\s+href\s*=\s*["'][^"']*xmdetail/(\d+)/?["']([^>]*)>(.*?)</a>''',
      caseSensitive: false,
      dotAll: true,
    );
    for (final m in cardRe.allMatches(html)) {
      final id = int.tryParse(m.group(1) ?? '') ?? 0;
      if (id <= 0 || seen.contains(id)) continue;
      final attrs = m.group(2) ?? '';
      final inner = m.group(3) ?? '';
      var title = _attr(attrs, 'title');
      if (title.isEmpty) {
        title = _stripTags(inner).replaceFirst(RegExp(r'^\d{1,2}-\d{1,2}\.\s*'), '').trim();
      }
      if (title.isEmpty) title = '视频 $id';
      var cover = '';
      final img = RegExp(
        r'''<img[^>]+(?:src|data-original|data-src)\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ).firstMatch(inner);
      if (img != null) cover = (img.group(1) ?? '').trim();
      var time = '';
      final span = RegExp(r'''<span[^>]*>\s*([^<]+?)\s*</span>''', caseSensitive: false).firstMatch(inner);
      if (span != null) {
        time = (span.group(1) ?? '').replaceAll('.', '').trim();
      }
      seen.add(id);
      out.add(XmavVideoItem(id: id, title: title, cover: cover, time: time));
    }

    if (out.isEmpty) {
      final bare = RegExp(r'''/xmdetail/(\d+)/?''');
      for (final m in bare.allMatches(html)) {
        final id = int.tryParse(m.group(1) ?? '') ?? 0;
        if (id <= 0 || seen.contains(id)) continue;
        seen.add(id);
        out.add(XmavVideoItem(id: id, title: '视频 $id'));
      }
    }
    return out;
  }

  /// `共3574条数据,当前1/149页`
  static XmavPagerInfo parsePager(String html) {
    final tip = RegExp(r'共\s*(\d+)\s*条数据\s*,\s*当前\s*(\d+)\s*/\s*(\d+)\s*页').firstMatch(html);
    if (tip != null) {
      return XmavPagerInfo(
        total: int.tryParse(tip.group(1) ?? ''),
        page: int.tryParse(tip.group(2) ?? ''),
        pageCount: int.tryParse(tip.group(3) ?? ''),
      );
    }
    final simple = RegExp(r'当前\s*(\d+)\s*/\s*(\d+)\s*页').firstMatch(html);
    if (simple != null) {
      return XmavPagerInfo(
        page: int.tryParse(simple.group(1) ?? ''),
        pageCount: int.tryParse(simple.group(2) ?? ''),
      );
    }
    return const XmavPagerInfo();
  }

  static XmavVideoItem parseDetail(String html, {required int id, required String base}) {
    var title = '';
    final titleDt = RegExp(r'片名[：:]\s*([^<]+)').firstMatch(html);
    if (titleDt != null) title = titleDt.group(1)!.trim();
    if (title.isEmpty) {
      final t = RegExp(r'<title>([^<]+)').firstMatch(html);
      if (t != null) {
        title = t.group(1)!.split(RegExp(r'在线观看|-')).first.trim();
      }
    }
    if (title.isEmpty) title = '视频 $id';

    var cover = '';
    final mediaImg = RegExp(
      r'''class="media"[\s\S]*?<img[^>]+src\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    if (mediaImg != null) {
      cover = mediaImg.group(1)!.trim();
    } else {
      final any = RegExp(
        r'''src\s*=\s*["'](https?://[^"']+\.(?:jpg|jpeg|png|webp)[^"']*)["']''',
        caseSensitive: false,
      ).firstMatch(html);
      if (any != null) cover = any.group(1)!.trim();
    }

    var vodClass = '';
    final typeDt = RegExp(r'类型[：:]\s*([^<]+)').firstMatch(html);
    if (typeDt != null) vodClass = typeDt.group(1)!.trim();

    var typeId = 0;
    final typeLink = RegExp(r'''xmtype/(\d+)/?["'][^>]*>([^<]*)</a>''').firstMatch(html);
    if (typeLink != null) {
      typeId = int.tryParse(typeLink.group(1) ?? '') ?? 0;
      if (vodClass.isEmpty) vodClass = (typeLink.group(2) ?? '').trim();
    }

    return XmavVideoItem(
      id: id,
      title: title,
      cover: cover.startsWith('//') ? 'https:$cover' : cover,
      vodClass: vodClass,
      typeId: typeId,
    );
  }

  static Map<String, dynamic>? extractPlayerAaaa(String html) {
    final idx = html.indexOf('player_aaaa');
    if (idx < 0) return null;
    final assign = html.indexOf('=', idx);
    if (assign < 0) return null;
    final start = html.indexOf('{', assign);
    if (start < 0) return null;
    final end = matchJsonObjectEnd(html, start);
    if (end < 0) return null;
    final raw = html.substring(start, end + 1);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static int matchJsonObjectEnd(String s, int start) {
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

  static String _stripTags(String raw) => raw.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _attr(String attrs, String name) {
    final m = RegExp('''$name\\s*=\\s*["']([^"']*)["']''', caseSensitive: false).firstMatch(attrs);
    return (m?.group(1) ?? '').trim();
  }
}
