import 'package:shared_preferences/shared_preferences.dart';

import 'xmav_http.dart';

class XmavBaseStore {
  XmavBaseStore(this._prefs);

  final SharedPreferences _prefs;

  static const entryUrl = 'http://xmav.vip';
  static const _keyUrl = 'xmav.base.url';
  static const _keyAt = 'xmav.base.at';
  static const ttl = Duration(hours: 24);

  String? get cachedBase {
    final v = _prefs.getString(_keyUrl)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  DateTime? get cachedAt {
    final ms = _prefs.getInt(_keyAt);
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool get isFresh {
    final base = cachedBase;
    final at = cachedAt;
    if (base == null || at == null) return false;
    return DateTime.now().difference(at) < ttl;
  }

  Future<void> save(String base) async {
    final normalized = XmavBaseResolver.normalizeBase(base);
    await _prefs.setString(_keyUrl, normalized);
    await _prefs.setInt(_keyAt, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> clear() async {
    await _prefs.remove(_keyUrl);
    await _prefs.remove(_keyAt);
  }
}

class XmavBaseResolver {
  XmavBaseResolver({required this.http, required this.store});

  final XmavHttp http;
  final XmavBaseStore store;

  /// Resolve content base. Uses cache unless [force] or stale/missing.
  Future<String> resolve({bool force = false}) async {
    if (!force && store.isFresh) {
      return store.cachedBase!;
    }

    final entry = await http.get(XmavBaseStore.entryUrl, timeout: const Duration(seconds: 15));
    if (entry.status < 200 || entry.status >= 400) {
      // stale cache fallback
      final stale = store.cachedBase;
      if (stale != null) return stale;
      throw StateError('入口站不可用 HTTP ${entry.status}');
    }

    final relay = _extractLocationReplace(entry.body) ?? _extractFirstHttpUrl(entry.body);
    if (relay == null || relay.isEmpty) {
      final stale = store.cachedBase;
      if (stale != null) return stale;
      throw StateError('无法从 xmav.vip 解析中转地址');
    }

    final relayUrl = relay.trim();
    final relayRes = await http.get(relayUrl, referer: XmavBaseStore.entryUrl, timeout: const Duration(seconds: 15));
    if (relayRes.status < 200 || relayRes.status >= 400) {
      final stale = store.cachedBase;
      if (stale != null) return stale;
      throw StateError('中转页不可用 HTTP ${relayRes.status}');
    }

    final baseCandidate = _extractUrlList(relayRes.body) ??
        _extractLocationReplace(relayRes.body) ??
        _extractHrefAssign(relayRes.body) ??
        _extractFirstHttpUrl(relayRes.body);

    if (baseCandidate == null || baseCandidate.trim().isEmpty) {
      final stale = store.cachedBase;
      if (stale != null) return stale;
      throw StateError('无法从中转页解析内容站 base');
    }

    final base = normalizeBase(baseCandidate);
    await store.save(base);
    return base;
  }

  static String normalizeBase(String raw) {
    var s = raw.trim();
    if (s.startsWith('//')) s = 'https:$s';
    final uri = Uri.parse(s);
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw StateError('非法 base: $raw');
    }
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  static String? _extractLocationReplace(String html) {
    final re = RegExp(
      r'''location\.replace\s*\(\s*["']\s*([^"']+?)\s*["']\s*\)''',
      caseSensitive: false,
    );
    final m = re.firstMatch(html);
    return m?.group(1)?.trim();
  }

  static String? _extractHrefAssign(String html) {
    final re = RegExp(
      r'''(?:window\.)?location(?:\.href)?\s*=\s*["']\s*(https?://[^"']+)\s*["']''',
      caseSensitive: false,
    );
    final m = re.firstMatch(html);
    return m?.group(1)?.trim();
  }

  static String? _extractUrlList(String html) {
    final re = RegExp(r'urlList\s*=\s*\[([^\]]+)\]', caseSensitive: false);
    final m = re.firstMatch(html);
    if (m == null) return null;
    final inner = m.group(1)!;
    final urls = RegExp(r'''["'](https?://[^"']+)["']''').allMatches(inner).map((e) => e.group(1)!).toList();
    if (urls.isEmpty) return null;
    urls.shuffle();
    return urls.first;
  }

  static String? _extractFirstHttpUrl(String html) {
    final m = RegExp(r"""https?://[^\s"'<>]+""").firstMatch(html);
    return m?.group(0);
  }
}
