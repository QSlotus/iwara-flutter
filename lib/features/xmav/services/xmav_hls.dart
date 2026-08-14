/// Shared HLS playlist rewrite helpers for local loopback proxying.
bool isMasterPlaylist(String text) => text.contains('#EXT-X-STREAM-INF');

bool isMediaPlaylist(String text) =>
    text.contains('#EXTINF') || text.contains('#EXT-X-TARGETDURATION');

String rewriteForProxy(String text, String baseUrl, String proxyBase) {
  if (isMasterPlaylist(text)) {
    return rewriteMaster(text, baseUrl, proxyBase);
  }
  return rewriteMedia(text, baseUrl, proxyBase);
}

String rewriteMaster(String text, String baseUrl, String proxyBase) {
  final base = Uri.parse(baseUrl);
  final root = _proxyRoot(proxyBase);
  return text.split(RegExp(r'\r?\n')).map((line) {
    final t = line.trim();
    if (t.isNotEmpty && !t.startsWith('#')) {
      final abs = base.resolve(t).toString();
      return '$root/api/hls/media.m3u8?url=${Uri.encodeQueryComponent(abs)}';
    }
    return line;
  }).join('\n');
}

String rewriteMedia(String text, String baseUrl, String proxyBase) {
  final base = Uri.parse(baseUrl);
  final root = _proxyRoot(proxyBase);
  final out = <String>[];
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final t = line.trim();
    if (t.startsWith('#EXT-X-KEY')) {
      if (RegExp(r'METHOD\s*=\s*NONE', caseSensitive: false).hasMatch(t)) {
        continue;
      }
      out.add(_rewriteAttrUris(line, base, root, '/api/hls/key'));
      continue;
    }
    if (t.startsWith('#EXT-X-MAP')) {
      out.add(_rewriteAttrUris(line, base, root, '/api/hls/seg'));
      continue;
    }
    if (t.isNotEmpty && !t.startsWith('#')) {
      final abs = base.resolve(t).toString();
      out.add('$root/api/hls/seg?url=${Uri.encodeQueryComponent(abs)}');
      continue;
    }
    out.add(line);
  }
  return out.join('\n');
}

String? bestVariantUrl(String masterText, String masterUrl) {
  final base = Uri.parse(masterUrl);
  var bestBw = -1;
  String? bestUrl;
  var currentBw = 0;
  for (final line in masterText.split(RegExp(r'\r?\n'))) {
    final t = line.trim();
    if (t.startsWith('#EXT-X-STREAM-INF')) {
      final m = RegExp(r'BANDWIDTH=(\d+)').firstMatch(t);
      currentBw = m != null ? int.parse(m.group(1)!) : 0;
    } else if (t.isNotEmpty && !t.startsWith('#')) {
      if (currentBw >= bestBw) {
        bestBw = currentBw;
        bestUrl = base.resolve(t).toString();
      }
    }
  }
  return bestUrl;
}

String _proxyRoot(String proxyBase) => proxyBase.replaceAll(RegExp(r'/$'), '');

String _rewriteAttrUris(String line, Uri base, String root, String path) {
  var result = line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (m) {
    final abs = base.resolve(m.group(1)!).toString();
    return 'URI="$root$path?url=${Uri.encodeQueryComponent(abs)}"';
  });
  if (!result.contains('URI="') && result.contains('URI=')) {
    result = result.replaceAllMapped(RegExp(r'URI=([^,\s"]+)'), (m) {
      final abs = base.resolve(m.group(1)!).toString();
      return 'URI="$root$path?url=${Uri.encodeQueryComponent(abs)}"';
    });
  }
  return result;
}
