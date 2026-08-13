String rewriteMaster(String text, String baseUrl) {
  final base = Uri.parse(baseUrl);
  return text.split(RegExp(r'\r?\n')).map((line) {
    final t = line.trim();
    if (t.isNotEmpty && !t.startsWith('#')) {
      final abs = base.resolve(t).toString();
      return '/api/hls/variant?url=${Uri.encodeQueryComponent(abs)}';
    }
    return line;
  }).join('\n');
}

String rewriteVariant(String text, String baseUrl) {
  final base = Uri.parse(baseUrl);
  return text.split(RegExp(r'\r?\n')).map((line) {
    final t = line.trim();
    if (t.startsWith('#EXT-X-KEY')) {
      return line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (m) {
        final abs = base.resolve(m.group(1)!).toString();
        return 'URI="/api/hls/key?url=${Uri.encodeQueryComponent(abs)}"';
      });
    }
    if (t.isNotEmpty && !t.startsWith('#')) {
      final abs = base.resolve(t).toString();
      return '/api/hls/seg?url=${Uri.encodeQueryComponent(abs)}';
    }
    return line;
  }).join('\n');
}
