import 'qinav_http.dart';

class QinavCdnResolver {
  QinavCdnResolver(this.http);

  final QinavHttp http;

  final Set<String> knownDomains = {
    'v.didibo2.com',
    'v.douvod.com',
    'v.didoucdn.com',
    'v6.lbv325627.com',
    '2604.sysl2026.com',
    '2605.lajiao2026.com',
    '2605.dadi2026.com',
    'v2025.ddcdnbf.com',
    'v202510.ddcdnbf.com',
  };

  final Map<String, _Health> _health = {};
  final Map<String, _PathHit> _pathCache = {};

  static const healthTtl = Duration(minutes: 5);
  static const failCooldown = Duration(seconds: 30);
  static const pathTtl = Duration(minutes: 10);

  void addDomain(String host) {
    if (host.isNotEmpty) knownDomains.add(host);
  }

  bool _isHealthy(String domain) {
    final h = _health[domain];
    if (h == null) return true;
    final age = DateTime.now().difference(h.at);
    if (h.ok && age < healthTtl) return true;
    if (!h.ok && age < failCooldown) return false;
    return true;
  }

  void _remember(String domain, bool ok) {
    _health[domain] = _Health(ok, DateTime.now());
  }

  Future<bool> _probe(String url) async {
    try {
      final r = await http.request(url, timeout: const Duration(seconds: 6));
      return r.status == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String?> resolvePlayable(String m3u8Url) async {
    final u = Uri.parse(m3u8Url);
    final pathKey = u.path;
    final cached = _pathCache[pathKey];
    if (cached != null && DateTime.now().difference(cached.at) < pathTtl) {
      return cached.url;
    }

    final original = '${u.scheme}://${u.host}${u.path}';
    if (await _probe(original)) {
      _remember(u.host, true);
      _pathCache[pathKey] = _PathHit(original, DateTime.now());
      return original;
    }
    _remember(u.host, false);

    for (final d in knownDomains) {
      if (d == u.host || !_isHealthy(d)) continue;
      final alt = 'https://$d${u.path}';
      if (await _probe(alt)) {
        _remember(d, true);
        _pathCache[pathKey] = _PathHit(alt, DateTime.now());
        return alt;
      }
      _remember(d, false);
    }
    return null;
  }
}

class _Health {
  _Health(this.ok, this.at);
  final bool ok;
  final DateTime at;
}

class _PathHit {
  _PathHit(this.url, this.at);
  final String url;
  final DateTime at;
}
