import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
    this.releaseName,
    this.releaseNotes,
    this.releasePageUrl,
    this.apkDownloadUrl,
    this.error,
  });

  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final String? releaseName;
  final String? releaseNotes;
  final String? releasePageUrl;
  final String? apkDownloadUrl;
  final String? error;

  String get displayLatest => latestVersion.isEmpty ? currentVersion : latestVersion;
}

/// Checks GitHub Releases for a newer app version.
class UpdateService {
  UpdateService({
    this.owner = 'QSlotus',
    this.repo = 'iwara-flutter',
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const dismissedVersionKey = 'update-dismissed-version';
  static const lastPromptAtKey = 'update-last-prompt-at';

  final String owner;
  final String repo;
  final http.Client _client;

  static final RegExp _versionToken = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?');

  Future<UpdateCheckResult> checkForUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final current = info.version.trim();

    try {
      final uri = Uri.https('api.github.com', '/repos/$owner/$repo/releases/latest');
      final response = await _client
          .get(
            uri,
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'iwara-signal-desk/$current',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 404) {
        return UpdateCheckResult(
          currentVersion: current,
          latestVersion: current,
          hasUpdate: false,
          error: '暂无 GitHub Release',
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return UpdateCheckResult(
          currentVersion: current,
          latestVersion: current,
          hasUpdate: false,
          error: '检查更新失败 (HTTP ${response.statusCode})',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return UpdateCheckResult(
          currentVersion: current,
          latestVersion: current,
          hasUpdate: false,
          error: 'Release 数据格式无效',
        );
      }

      final map = Map<String, dynamic>.from(decoded);
      final tag = '${map['tag_name'] ?? ''}'.trim();
      final latest = normalizeVersion(tag);
      if (latest.isEmpty) {
        return UpdateCheckResult(
          currentVersion: current,
          latestVersion: current,
          hasUpdate: false,
          error: 'Release 缺少有效版本号',
        );
      }

      String? apkUrl;
      final assets = map['assets'];
      if (assets is List) {
        for (final asset in assets) {
          if (asset is! Map) continue;
          final name = '${asset['name'] ?? ''}'.toLowerCase();
          final url = '${asset['browser_download_url'] ?? ''}'.trim();
          if (!name.endsWith('.apk') || url.isEmpty) continue;
          apkUrl = url;
          if (name.contains('release')) break;
        }
      }

      return UpdateCheckResult(
        currentVersion: current,
        latestVersion: latest,
        hasUpdate: compareVersions(latest, current) > 0,
        releaseName: '${map['name'] ?? tag}'.trim(),
        releaseNotes: '${map['body'] ?? ''}'.trim(),
        releasePageUrl: '${map['html_url'] ?? ''}'.trim(),
        apkDownloadUrl: apkUrl,
      );
    } catch (error) {
      return UpdateCheckResult(
        currentVersion: current,
        latestVersion: current,
        hasUpdate: false,
        error: '检查更新失败: $error',
      );
    }
  }

  Future<bool> shouldAutoPrompt(UpdateCheckResult result) async {
    if (!result.hasUpdate) return false;
    final prefs = await SharedPreferences.getInstance();
    final dismissed = (prefs.getString(dismissedVersionKey) ?? '').trim();
    if (dismissed.isNotEmpty && compareVersions(dismissed, result.latestVersion) >= 0) {
      return false;
    }
    final lastPrompt = prefs.getInt(lastPromptAtKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Avoid prompting more than once every 12 hours.
    if (lastPrompt > 0 && now - lastPrompt < const Duration(hours: 12).inMilliseconds) {
      return false;
    }
    return true;
  }

  Future<void> markPrompted(UpdateCheckResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(lastPromptAtKey, DateTime.now().millisecondsSinceEpoch);
    await prefs.setString(dismissedVersionKey, result.latestVersion);
  }

  Future<bool> openUpdate(UpdateCheckResult result) async {
    final raw = (result.apkDownloadUrl?.isNotEmpty ?? false)
        ? result.apkDownloadUrl!
        : (result.releasePageUrl ?? '');
    if (raw.trim().isEmpty) return false;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static String normalizeVersion(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return '';
    final withoutPrefix =
        (cleaned.startsWith('v') || cleaned.startsWith('V')) ? cleaned.substring(1) : cleaned;
    final match = _versionToken.firstMatch(withoutPrefix);
    if (match == null) return withoutPrefix.split(RegExp(r'[-+]')).first;
    final major = match.group(1) ?? '0';
    final minor = match.group(2) ?? '0';
    final patch = match.group(3) ?? '0';
    return '$major.$minor.$patch';
  }

  /// >0 if [a] is newer than [b].
  static int compareVersions(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    for (var i = 0; i < 3; i++) {
      final delta = pa[i] - pb[i];
      if (delta != 0) return delta;
    }
    return 0;
  }

  static List<int> _parts(String version) {
    final normalized = normalizeVersion(version);
    final bits = normalized.split('.');
    int at(int index) {
      if (index >= bits.length) return 0;
      return int.tryParse(bits[index]) ?? 0;
    }

    return [at(0), at(1), at(2)];
  }
}