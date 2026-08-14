import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../utils/helpers.dart';
import 'api_catalog.dart';
import 'package:signal_desk/core/edge/edge_probe.dart';
import 'package:signal_desk/core/edge/edge_store.dart';
import 'local_api_server.dart';
import 'upstream_client.dart';

class AppController extends ChangeNotifier {
  static const tokenKey = 'iwara.token';
  static const legacyTokenKey = 'iwara-signal-token';
  static const configuredIp = EdgeStore.configuredIp;

  late final ApiCatalog catalog;
  late final UpstreamClient upstream;
  late final LocalApiServer server;
  SharedPreferences? _prefs;

  bool ready = false;
  bool entered = false;
  bool edgeFirstDone = false;
  String token = '';
  String? lastError;
  VoidCallback? onExitModule;

  String _resolvedSource = '';
  String _resolvedAccess = '';

  String get baseUrl => server.baseUrl;
  EdgeStatus get edgeStatus => server.edgeStatus;
  String get activeIp => upstream.resolveIp;
  bool get isLoggedIn => token.trim().isNotEmpty;

  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final prefs = _prefs!;
      final edgeStore = EdgeStore(prefs);
      final modernToken = (prefs.getString(tokenKey) ?? '').trim();
      final legacyToken = (prefs.getString(legacyTokenKey) ?? '').trim();
      token = modernToken.isNotEmpty ? modernToken : legacyToken;
      edgeFirstDone = edgeStore.firstDone;
      final initialIp = edgeStore.activeIp;
      catalog = await ApiCatalog.load();
      upstream = UpstreamClient(resolveIp: initialIp);
      server = LocalApiServer(
        catalog: catalog,
        upstream: upstream,
        edgeProbe: EdgeProbeService(),
        configuredIp: configuredIp,
      );
      await server.start();
      if (edgeStore.selectedIp.isNotEmpty) {
        await server.applySavedIp(edgeStore.selectedIp, locked: true);
      }
      // Shell owns first-run edge; module always enters main UI.
      entered = true;
      ready = true;
      notifyListeners();
    } catch (error, stack) {
      lastError = '$error\n$stack';
      ready = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> refreshEdge() async {
    await server.runEdgeTest(force: true);
    final prefs = _prefs;
    if (prefs != null) {
      await EdgeStore(prefs).setSelectedIp(activeIp);
    }
    notifyListeners();
  }

  Future<void> selectEdgeIp(String ip) async {
    await server.selectIp(ip);
    final prefs = _prefs;
    if (prefs != null) {
      await EdgeStore(prefs).setSelectedIp(ip);
    }
    notifyListeners();
  }

  Future<void> completeFirstEdgeSetup() async {
    edgeFirstDone = true;
    final prefs = _prefs;
    if (prefs != null) {
      await EdgeStore(prefs).markFirstDone(ip: activeIp);
    }
    entered = true;
    notifyListeners();
  }

  void enterApp() {
    // Prefer completeFirstEdgeSetup() so the IP choice is persisted.
    entered = true;
    notifyListeners();
  }

  Future<void> disposeModule() async {
    try {
      await server.stop();
    } catch (_) {}
    ready = false;
    entered = false;
  }

  Future<Map<String, dynamic>?> fetchProfileByHandle(String handle) async {
    final payload = asRecord(await callApi('fetchProfile', args: {'t': handle}, tokenOverride: isLoggedIn ? null : ''));
    final nested = asRecord(payload['user']);
    if (nested.isNotEmpty) {
      return <String, dynamic>{...payload, ...nested, 'user': nested};
    }
    return unwrapUser(payload);
  }

  Future<void> toggleFollow({required String userId, required bool currentlyFollowed}) async {
    if (userId.trim().isEmpty) {
      throw Exception('缺少用户 id，无法关注');
    }
    await callApi(
      currentlyFollowed ? 'destroyFollow' : 'createFollow',
      args: {'t': userId.trim()},
    );
  }

  Future<void> setToken(String value) async {
    token = value.trim();
    _resolvedSource = '';
    _resolvedAccess = '';
    if (token.isEmpty) {
      await _prefs?.remove(tokenKey);
      await _prefs?.remove(legacyTokenKey);
    } else {
      await _prefs?.setString(tokenKey, token);
      await _prefs?.setString(legacyTokenKey, token);
    }
    notifyListeners();
  }

  String _normalizeCredential(String? value) {
    return (value ?? '').trim().replaceFirst(RegExp(r'^(?:bearer\s+)+', caseSensitive: false), '');
  }

  String _accessTokenFromPayload(dynamic payload) {
    final record = asRecord(payload);
    final nested = asRecord(record['data']);
    for (final candidate in [record['accessToken'], nested['accessToken'], record['token'], nested['token']]) {
      final value = _normalizeCredential('$candidate');
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// Login often returns an exchangeable credential. Prefer an access token like the web client.
  Future<String> resolveAccessToken({bool force = false}) async {
    final source = _normalizeCredential(token);
    if (source.isEmpty) return '';
    if (!force && _resolvedSource == source && _resolvedAccess.isNotEmpty) {
      return _resolvedAccess;
    }
    try {
      final payload = await _postCall(
        'fetchAccessToken',
        args: null,
        query: null,
        body: null,
        tokenValue: source,
        captcha: null,
      );
      final access = _accessTokenFromPayload(payload);
      if (access.isNotEmpty) {
        _resolvedSource = source;
        _resolvedAccess = access;
        return access;
      }
    } catch (_) {
      // Manual short-lived access tokens cannot always be exchanged.
    }
    _resolvedSource = source;
    _resolvedAccess = source;
    return source;
  }

  Future<dynamic> _postCall(
    String operation, {
    Map<String, dynamic>? args,
    Map<String, dynamic>? query,
    dynamic body,
    required String tokenValue,
    String? captcha,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/call/${Uri.encodeComponent(operation)}'),
      headers: {'content-type': 'application/json', 'accept': 'application/json'},
      body: jsonEncode({
        if (args != null) 'args': args,
        if (query != null) 'query': query,
        if (body != null) 'body': body,
        'token': tokenValue,
        if (captcha != null) 'captcha': captcha,
      }),
    );
    return _decode(response);
  }

  Future<dynamic> callApi(
    String operation, {
    Map<String, dynamic>? args,
    Map<String, dynamic>? query,
    dynamic body,
    String? tokenOverride,
    String? captcha,
  }) async {
    final String tokenValue;
    if (tokenOverride != null) {
      tokenValue = _normalizeCredential(tokenOverride);
    } else if (operation == 'fetchAccessToken') {
      tokenValue = _normalizeCredential(token);
    } else {
      tokenValue = await resolveAccessToken();
    }
    return _postCall(
      operation,
      args: args,
      query: query,
      body: body,
      tokenValue: tokenValue,
      captcha: captcha,
    );
  }

  Future<dynamic> callAux(
    String operation, {
    Map<String, dynamic>? args,
    Map<String, dynamic>? query,
    String? url,
    String? tokenOverride,
  }) async {
    final tokenValue = tokenOverride != null
        ? _normalizeCredential(tokenOverride)
        : await resolveAccessToken();
    final response = await http.post(
      Uri.parse('$baseUrl/api/aux/${Uri.encodeComponent(operation)}'),
      headers: {'content-type': 'application/json', 'accept': 'application/json'},
      body: jsonEncode({
        if (args != null) 'args': args,
        if (query != null) 'query': query,
        if (url != null) 'url': url,
        'token': tokenValue,
      }),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> fetchCurrentProfile() async {
    await resolveAccessToken();
    final payload = asRecord(await callApi('fetchCurrentUser'));
    // Match web account page: current.user || current, then resolve public profile by username.
    final current = unwrapUser(payload);
    final username = '${current['username'] ?? ''}'.trim();
    if (username.isNotEmpty) {
      try {
        final profilePayload = asRecord(await callApi('fetchProfile', args: {'t': username}, tokenOverride: ''));
        final nestedUser = asRecord(profilePayload['user']);
        final resolved = nestedUser.isNotEmpty ? nestedUser : unwrapUser(profilePayload);
        if (_userIdOf(resolved).isNotEmpty) {
          return <String, dynamic>{...current, ...resolved};
        }
      } catch (_) {
        // Keep /user payload.
      }
    }
    if (_userIdOf(current).isNotEmpty) return current;
    final nestedProfile = unwrapUser(payload['profile']);
    if (_userIdOf(nestedProfile).isNotEmpty) return nestedProfile;
    return current;
  }

  String _userIdOf(Map<String, dynamic> user) {
    for (final key in ['id', 'userId', 'uid']) {
      final value = '${user[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Map<String, dynamic> _relationshipUser(dynamic item) {
    final record = asRecord(item);
    // Prefer nested user objects over the relationship row itself.
    for (final key in ['user', 'following', 'follower', 'targetUser', 'sourceUser']) {
      final nested = asRecord(record[key]);
      if (_userIdOf(nested).isNotEmpty || '${nested['username'] ?? ''}'.trim().isNotEmpty) {
        return nested;
      }
    }
    return record;
  }

  Future<List<Map<String, dynamic>>> fetchFollowingPeople({
    required String userId,
    int limit = 50,
    int maxPages = 6,
  }) async {
    if (userId.isEmpty) return const [];

    Future<dynamic> pageRequest(int page, {required bool authed}) {
      return callApi(
        'fetchFollowing',
        tokenOverride: authed ? null : '',
        args: {'e': userId},
        query: {'limit': limit, 'page': page},
      );
    }

    dynamic first;
    Object? lastError;
    // Authenticated first (same as web account page), then public fallback (home feed style).
    try {
      first = await pageRequest(0, authed: true);
    } catch (e) {
      lastError = e;
      try {
        first = await pageRequest(0, authed: false);
      } catch (e2) {
        throw Exception('无法读取关注列表: $e2 (auth failed: $lastError)');
      }
    }

    // Some gateways treat page as 1-based. If page 0 is empty but count>0, retry page 1.
    var firstRecord = asRecord(first);
    var firstResults = listResults(first);
    final reportedCount = firstRecord['count'] is num ? (firstRecord['count'] as num).toInt() : 0;
    if (firstResults.isEmpty && reportedCount > 0) {
      try {
        first = await pageRequest(1, authed: true);
      } catch (_) {
        first = await pageRequest(1, authed: false);
      }
      firstRecord = asRecord(first);
      firstResults = listResults(first);
    }

    final pageSize = (firstRecord['limit'] is num ? (firstRecord['limit'] as num).toInt() : limit).clamp(1, 100);
    final count = firstRecord['count'] is num ? (firstRecord['count'] as num).toInt() : firstResults.length;
    final pageCount = count > 0 ? ((count + pageSize - 1) ~/ pageSize) : 1;

    final pages = <dynamic>[first];
    if (pageCount > 1) {
      final rest = await Future.wait([
        for (var page = 1; page < pageCount && page < maxPages; page++)
          pageRequest(page, authed: true).catchError((_) => pageRequest(page, authed: false).catchError((_) => null)),
      ]);
      pages.addAll(rest.where((item) => item != null));
    }

    final people = <Map<String, dynamic>>[];
    final seenPeople = <String>{};
    for (final page in pages) {
      for (final item in listResults(page)) {
        final person = Map<String, dynamic>.from(_relationshipUser(item));
        var id = _userIdOf(person);
        // Last resort: if only username exists, resolve public profile for UUID.
        if (id.isEmpty) {
          final username = '${person['username'] ?? ''}'.trim();
          if (username.isNotEmpty) {
            try {
              final profilePayload = asRecord(await callApi('fetchProfile', args: {'t': username}, tokenOverride: ''));
              final nestedUser = asRecord(profilePayload['user']);
              final resolved = nestedUser.isNotEmpty ? nestedUser : unwrapUser(profilePayload);
              id = _userIdOf(resolved);
              if (id.isNotEmpty) {
                person.addAll(resolved);
              }
            } catch (_) {}
          }
        }
        if (id.isEmpty || !seenPeople.add(id)) continue;
        person['id'] = id;
        people.add(person);
      }
    }
    // ignore: avoid_print
    print('[following] userId=$userId people=${people.length} count=$count');
    return people;
  }

  Future<List<Map<String, dynamic>>> loadFollowingVideos({int limit = 24}) async {
    final current = await fetchCurrentProfile();
    final currentId = _userIdOf(current);
    // ignore: avoid_print
    print('[following-feed] currentId=$currentId username=${current['username']} name=${current['name']}');
    if (currentId.isEmpty) {
      throw Exception('当前用户缺少 id，无法加载关注动态');
    }

    final people = await fetchFollowingPeople(userId: currentId);
    if (people.isEmpty) return const [];

    final batches = <List<String>>[];
    for (var i = 0; i < people.length; i += 30) {
      final end = (i + 30 > people.length) ? people.length : i + 30;
      batches.add(people.sublist(i, end).map(_userIdOf).where((id) => id.isNotEmpty).toList());
    }

    final videos = <Map<String, dynamic>>[];
    final seenVideos = <String>{};
    Object? lastError;
    var anySuccess = false;

    Future<dynamic> fetchForUsers(List<String> userIds, {required bool authed}) {
      return callApi(
        'fetchVideos',
        tokenOverride: authed ? null : '',
        query: {'user': userIds, 'limit': 12, 'page': 0, 'sort': 'date'},
      );
    }

    for (final userIds in batches) {
      if (userIds.isEmpty) continue;
      dynamic payload;
      try {
        // Public multi-user filter first (web home style).
        payload = await fetchForUsers(userIds, authed: false);
        anySuccess = true;
      } catch (e) {
        lastError = e;
        try {
          payload = await fetchForUsers(userIds, authed: true);
          anySuccess = true;
        } catch (e2) {
          lastError = e2;
          // Fallback: query each followed creator individually.
          for (final uid in userIds) {
            try {
              final one = await callApi(
                'fetchVideos',
                tokenOverride: '',
                query: {'user': uid, 'limit': 6, 'page': 0, 'sort': 'date'},
              );
              anySuccess = true;
              for (final video in listResults(one)) {
                final id = '${video['id'] ?? video['slug'] ?? ''}'.trim();
                if (id.isEmpty || !seenVideos.add(id)) continue;
                videos.add(video);
              }
            } catch (e3) {
              lastError = e3;
            }
          }
          continue;
        }
      }
      for (final video in listResults(payload)) {
        final id = '${video['id'] ?? video['slug'] ?? ''}'.trim();
        if (id.isEmpty || !seenVideos.add(id)) continue;
        videos.add(video);
      }
    }

    if (!anySuccess && lastError != null) {
      throw Exception('无法读取关注者内容: $lastError');
    }

    videos.sort((a, b) {
      final left = DateTime.tryParse('${a['createdAt'] ?? ''}')?.millisecondsSinceEpoch ?? 0;
      final right = DateTime.tryParse('${b['createdAt'] ?? ''}')?.millisecondsSinceEpoch ?? 0;
      return right.compareTo(left);
    });
    // ignore: avoid_print
    print('[following-feed] people=${people.length} videos=${videos.length}');
    return videos.take(limit).toList();
  }

  Future<EdgeStatus> fetchEdgeStatus() async {
    final response = await http.get(Uri.parse('$baseUrl/api/edge/status'));
    final data = _decode(response) as Map<String, dynamic>;
    final results = (data['results'] as List? ?? const [])
        .map((item) => EdgeProbeResult(
              ip: '${item['ip']}',
              latencyMs: (item['latencyMs'] as num?)?.toDouble() ?? 0,
              lossRate: (item['lossRate'] as num?)?.toDouble() ?? 0,
              sent: (item['sent'] as num?)?.toInt() ?? 0,
              received: (item['received'] as num?)?.toInt() ?? 0,
            ))
        .toList();
    return EdgeStatus(
      status: '${data['status'] ?? 'idle'}',
      activeIp: '${data['activeIp'] ?? configuredIp}',
      configuredIp: '${data['configuredIp'] ?? configuredIp}',
      fastestIp: data['fastestIp']?.toString(),
      selectedIp: data['selectedIp']?.toString(),
      selectionMode: '${data['selectionMode'] ?? 'configured'}',
      source: data['source']?.toString(),
      warning: data['warning']?.toString(),
      durationMs: (data['durationMs'] as num?)?.toInt(),
      results: results,
    );
  }

  Future<List<PlayableMediaSource>> mediaSources(String fileUrl) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/media/sources?url=${Uri.encodeComponent(fileUrl)}'),
      headers: {'accept': 'application/json'},
    );
    final data = _decode(response);
    if (data is! Map) return const [];
    final list = data['sources'];
    if (list is! List) return const [];
    return list.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final url = '${map['url'] ?? ''}';
      return PlayableMediaSource(
        label: '${map['label'] ?? 'Source'}',
        url: url.startsWith('http') ? url : '$baseUrl$url',
        downloadUrl: map['downloadUrl'] == null
            ? null
            : ('${map['downloadUrl']}'.startsWith('http') ? '${map['downloadUrl']}' : '$baseUrl${map['downloadUrl']}'),
      );
    }).toList();
  }

  String mediaProxyUrl(String absoluteUrl) {
    return '$baseUrl/api/media?url=${Uri.encodeComponent(absoluteUrl)}';
  }

  String? thumbnailUrl(Map<String, dynamic>? video) {
    if (video == null) return null;
    final custom = video['customThumbnail'];
    if (custom is Map && custom['id'] != null) {
      return mediaProxyUrl('https://i.iwara.tv/image/thumbnail/${custom['id']}/thumbnail-00.jpg');
    }
    final file = video['file'];
    if (file is Map && file['id'] != null) {
      final index = video['thumbnail'] is num ? (video['thumbnail'] as num).toInt() : 0;
      final name = 'thumbnail-${index.toString().padLeft(2, '0')}.jpg';
      return mediaProxyUrl('https://i.iwara.tv/image/thumbnail/${file['id']}/$name');
    }
    return null;
  }

  Future<Directory> resolveDownloadDirectory() async {
    final candidates = <Directory>[
      Directory('/storage/emulated/0/Download/IwaraSignal'),
      Directory('/sdcard/Download/IwaraSignal'),
      Directory('/storage/emulated/0/Movies/IwaraSignal'),
    ];
    for (final dir in candidates) {
      try {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final probe = File('${dir.path}${Platform.pathSeparator}.write_test');
        await probe.writeAsString('ok', flush: true);
        await probe.delete();
        return dir;
      } catch (_) {
        // try next candidate
      }
    }
    final fallback = Directory('/data/data/tv.iwara.iwara_signal_desk/files/downloads');
    await fallback.create(recursive: true);
    return fallback;
  }

  Future<File> downloadMedia({
    required String url,
    required String filename,
    void Function(int received, int? total)? onProgress,
  }) async {
    final dir = await resolveDownloadDirectory();
    final safeName = sanitizeFilename(filename);
    final file = File('${dir.path}${Platform.pathSeparator}$safeName');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      request.headers.set(HttpHeaders.userAgentHeader, 'iwara-signal-desk/0.1');
      final response = await request.close().timeout(const Duration(minutes: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('下载失败（${response.statusCode}）', uri: Uri.parse(url));
      }
      final total = response.contentLength >= 0 ? response.contentLength : null;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      return file;
    } finally {
      client.close(force: true);
    }
  }


  /// Official `/search` is currently returning `errors.serverError` (HTTP 500)
  /// from Iwara. Fall back to autocomplete + tag-filtered lists when that happens.
  Future<dynamic> searchResults({
    required String type,
    required String query,
    int limit = 24,
    int page = 0,
    String sort = 'newest',
  }) async {
    final q = query.trim();
    // Official site uses plural types: videos / users / images.
    // Singular (video/user/image) returns errors.serverError.
    final normalizedType = _normalizeSearchType(type);
    final normalizedSort = _normalizeSearchSort(sort);
    try {
      return await callApi('fetchSearchResults', query: {
        'type': normalizedType,
        'query': q,
        'limit': limit,
        'page': page,
        'sort': normalizedSort,
      });
    } catch (e) {
      if (!_isSearchUpstreamFailure(e)) rethrow;
      if (normalizedType == 'users') {
        return _fallbackSearchUsers(query: q, limit: limit, page: page);
      }
      return _fallbackSearchVideos(query: q, limit: limit, page: page, sort: sort);
    }
  }

  bool _isSearchUpstreamFailure(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('errors.servererror') ||
        msg.contains('servererror') ||
        msg.contains('请求失败（500') ||
        msg.contains('请求失败(500') ||
        msg.contains('statuscode: 500') ||
        msg.contains(' 500');
  }

  Future<Map<String, dynamic>> _fallbackSearchUsers({
    required String query,
    int limit = 12,
    int page = 0,
  }) async {
    final payload = await callApi(
      'fetchAutocompleteUsers',
      query: {
        'query': query,
        'limit': limit,
        'page': page,
      },
      tokenOverride: '',
    );
    final record = asRecord(payload);
    final results = listResults(payload).map(unwrapUser).toList();
    return <String, dynamic>{
      ...record,
      'results': results,
      'fallback': 'autocomplete-users',
    };
  }

  Future<Map<String, dynamic>> _fallbackSearchVideos({
    required String query,
    int limit = 24,
    int page = 0,
    String sort = 'newest',
  }) async {
    final tagPayload = await callApi(
      'fetchAutocompleteTags',
      query: {'query': query},
      tokenOverride: '',
    );
    final tagIds = <String>[];
    for (final tag in listResults(tagPayload)) {
      final id = '${tag['id'] ?? ''}'.trim();
      if (id.isEmpty || tagIds.contains(id)) continue;
      tagIds.add(id);
      if (tagIds.length >= 6) break;
    }

    // Also try the raw query as a tag id (common for exact tag searches).
    final raw = query.trim().toLowerCase().replaceAll(' ', '_');
    if (raw.isNotEmpty && !tagIds.contains(raw)) {
      tagIds.add(raw);
    }

    if (tagIds.isEmpty) {
      throw HttpException(
        '官方搜索暂不可用，且未找到可匹配的标签。可尝试更具体的英文标签，或粘贴视频 ID。',
      );
    }

    final videoSort = (sort == 'relevance' || sort == 'trending') ? 'date' : (sort == 'newest' ? 'date' : sort);
    Object? lastError;
    for (final tagId in tagIds) {
      try {
        final payload = await callApi(
          'fetchVideos',
          query: {
            'limit': limit,
            'page': page,
            'sort': videoSort,
            'tags': tagId,
          },
          tokenOverride: '',
        );
        final record = asRecord(payload);
        final results = listVideos(payload);
        // Accept empty first page (valid no-results) for exact tag match.
        return <String, dynamic>{
          ...record,
          'results': results,
          'fallback': 'videos-by-tag',
          'fallbackTag': tagId,
        };
      } catch (e) {
        lastError = e;
        // Try next candidate tag when this one 500s / rejects.
        continue;
      }
    }

    throw HttpException(
      '官方搜索暂不可用，标签兜底也失败了: ${lastError ?? 'unknown'}',
    );
  }

  dynamic _decode(http.Response response) {
    final text = response.body;
    dynamic payload;
    try {
      payload = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      payload = text;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = payload is Map && payload['message'] != null
          ? '${payload['message']}'
          : '请求失败（${response.statusCode}）';
      throw HttpException(message, uri: response.request?.url);
    }
    return payload;
  }
}

class HttpException implements Exception {
  HttpException(this.message, {this.uri});
  final String message;
  final Uri? uri;
  @override
  String toString() => message;
}
