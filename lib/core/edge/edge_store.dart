import 'package:shared_preferences/shared_preferences.dart';

/// Shared CF edge IP preferences (shell-owned).
class EdgeStore {
  static const configuredIp = '104.25.243.202';

  static const firstDoneKey = 'shell.edge.first-done';
  static const selectedIpKey = 'shell.edge.selected-ip';

  // Legacy keys from pre-shell Iwara app.
  static const legacyFirstDoneKey = 'iwara-edge-first-done';
  static const legacySelectedIpKey = 'iwara-edge-selected-ip';

  final SharedPreferences prefs;

  EdgeStore(this.prefs);

  bool get firstDone {
    if (prefs.containsKey(firstDoneKey)) {
      return prefs.getBool(firstDoneKey) ?? false;
    }
    return prefs.getBool(legacyFirstDoneKey) ?? false;
  }

  String get selectedIp {
    final modern = (prefs.getString(selectedIpKey) ?? '').trim();
    if (modern.isNotEmpty) return modern;
    return (prefs.getString(legacySelectedIpKey) ?? '').trim();
  }

  String get activeIp {
    final ip = selectedIp;
    return ip.isNotEmpty ? ip : configuredIp;
  }

  Future<void> setSelectedIp(String ip) async {
    final value = ip.trim();
    await prefs.setString(selectedIpKey, value);
    await prefs.setString(legacySelectedIpKey, value);
  }

  Future<void> markFirstDone({String? ip}) async {
    await prefs.setBool(firstDoneKey, true);
    await prefs.setBool(legacyFirstDoneKey, true);
    if (ip != null && ip.trim().isNotEmpty) {
      await setSelectedIp(ip);
    }
  }
}