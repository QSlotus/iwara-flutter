List<Map<String, dynamic>> listResults(dynamic payload) {
  if (payload is List) {
    return payload.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
  if (payload is Map) {
    for (final key in ['results', 'items', 'data']) {
      final value = payload[key];
      if (value is List) {
        return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
  }
  return const [];
}

Map<String, dynamic> asRecord(dynamic payload) {
  if (payload is Map<String, dynamic>) return payload;
  if (payload is Map) return Map<String, dynamic>.from(payload);
  return <String, dynamic>{};
}

/// Relationship endpoints return `{ user: User }` / `{ follower: User }` wrappers.
Map<String, dynamic> unwrapUser(dynamic value) {
  final record = asRecord(value);
  for (final key in ['user', 'follower', 'following', 'targetUser', 'sourceUser']) {
    final nested = asRecord(record[key]);
    if (nested.isNotEmpty) return nested;
  }
  return record;
}

String displayName(Map<String, dynamic>? user, {String fallback = '未知用户'}) {
  if (user == null || user.isEmpty) return fallback;
  final unwrapped = unwrapUser(user);
  final name = '${unwrapped['name'] ?? unwrapped['username'] ?? unwrapped['title'] ?? unwrapped['id'] ?? fallback}'.trim();
  return name.isEmpty ? fallback : name;
}

String formatCount(dynamic value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}M';
  if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}K';
  return number.toStringAsFixed(0);
}

String sanitizeFilename(String value) {
  final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  if (cleaned.isEmpty) return 'iwara-video';
  return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
}


Map<String, dynamic> unwrapVideo(dynamic value) {
  final record = asRecord(value);
  for (final key in ['video', 'media', 'content', 'item']) {
    final nested = asRecord(record[key]);
    if (nested.isNotEmpty && (nested['id'] != null || nested['title'] != null || nested['slug'] != null)) {
      return nested;
    }
  }
  return record;
}

List<Map<String, dynamic>> listVideos(dynamic payload) {
  return listResults(payload).map(unwrapVideo).where((item) {
    final id = '${item['id'] ?? item['slug'] ?? ''}'.trim();
    return id.isNotEmpty;
  }).toList();
}
