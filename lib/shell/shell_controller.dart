import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:signal_desk/core/edge/edge_models.dart';
import 'package:signal_desk/core/edge/edge_probe.dart';
import 'package:signal_desk/core/edge/edge_store.dart';
import 'package:signal_desk/features/iwara/services/app_controller.dart';
import 'package:signal_desk/features/qinav/services/qinav_controller.dart';
import 'package:signal_desk/features/xmav/services/xmav_controller.dart';

enum DeskModule { iwara, qinav, xmav }

enum ShellPhase { booting, edgeSetup, picker, module }

class ShellController extends ChangeNotifier {
  final EdgeProbeService _probe = EdgeProbeService();

  SharedPreferences? _prefs;
  EdgeStore? _edgeStore;

  ShellPhase phase = ShellPhase.booting;
  DeskModule? activeModule;
  AppController? iwaraController;
  QinavController? qinavController;
  XmavController? xmavController;

  bool edgeBusy = false;
  String? edgeError;
  EdgeStatus edgeStatus = EdgeStatus(
    status: 'idle',
    activeIp: EdgeStore.configuredIp,
    configuredIp: EdgeStore.configuredIp,
  );

  String get activeIp => _edgeStore?.activeIp ?? EdgeStore.configuredIp;
  bool get edgeReady => _edgeStore?.firstDone == true && activeIp.isNotEmpty;

  Future<void> initialize() async {
    phase = ShellPhase.booting;
    notifyListeners();
    // Let first frame render loading UI before prefs/IO.
    await Future<void>.delayed(Duration.zero);

    _prefs = await SharedPreferences.getInstance();
    _edgeStore = EdgeStore(_prefs!);

    final saved = _edgeStore!.selectedIp;
    if (_edgeStore!.firstDone && saved.isNotEmpty) {
      edgeStatus = EdgeStatus(
        status: 'ready',
        activeIp: saved,
        configuredIp: EdgeStore.configuredIp,
        selectedIp: saved,
        selectionMode: 'manual',
        source: 'saved',
      );
      phase = ShellPhase.picker;
      notifyListeners();
      return;
    }

    // Show edge screen with spinner/text before probe starts.
    phase = ShellPhase.edgeSetup;
    edgeStatus = EdgeStatus(
      status: 'probing',
      activeIp: EdgeStore.configuredIp,
      configuredIp: EdgeStore.configuredIp,
      selectionMode: 'automatic',
      source: 'probe',
    );
    notifyListeners();
    await Future<void>.delayed(Duration.zero);
    await runEdgeProbe();
  }

  Future<void> runEdgeProbe({bool force = false}) async {
    if (edgeBusy) return;
    edgeBusy = true;
    edgeError = null;
    edgeStatus = EdgeStatus(
      status: 'probing',
      activeIp: activeIp,
      configuredIp: EdgeStore.configuredIp,
      selectedIp: _edgeStore?.selectedIp,
      selectionMode: 'automatic',
      source: 'probe',
    );
    notifyListeners();

    try {
      final sw = Stopwatch()..start();
      final results = await _probe.run(configuredIp: EdgeStore.configuredIp, limit: 10);
      sw.stop();
      final fastest = results.isNotEmpty ? results.first.ip : EdgeStore.configuredIp;
      final selected = (_edgeStore?.selectedIp.isNotEmpty ?? false) ? _edgeStore!.selectedIp : fastest;
      if (_edgeStore != null && _edgeStore!.selectedIp.isEmpty) {
        await _edgeStore!.setSelectedIp(selected);
      }
      edgeStatus = EdgeStatus(
        status: results.isEmpty ? 'error' : 'ready',
        activeIp: selected,
        configuredIp: EdgeStore.configuredIp,
        fastestIp: fastest,
        selectedIp: selected,
        selectionMode: 'automatic',
        source: 'probe',
        warning: results.isEmpty ? 'No Cloudflare edge responded to the latency probe.' : null,
        durationMs: sw.elapsedMilliseconds,
        results: results,
      );
    } catch (e) {
      edgeError = e.toString();
      edgeStatus = EdgeStatus(
        status: 'error',
        activeIp: EdgeStore.configuredIp,
        configuredIp: EdgeStore.configuredIp,
        selectionMode: 'configured',
        source: 'probe',
        warning: e.toString(),
      );
    } finally {
      edgeBusy = false;
      notifyListeners();
    }
  }

  Future<void> selectEdgeIp(String ip) async {
    final value = ip.trim();
    if (value.isEmpty || _edgeStore == null) return;
    await _edgeStore!.setSelectedIp(value);
    edgeStatus = EdgeStatus(
      status: edgeStatus.status == 'idle' ? 'ready' : edgeStatus.status,
      activeIp: value,
      configuredIp: EdgeStore.configuredIp,
      fastestIp: edgeStatus.fastestIp,
      selectedIp: value,
      selectionMode: 'manual',
      source: edgeStatus.source ?? 'manual',
      warning: edgeStatus.warning,
      durationMs: edgeStatus.durationMs,
      results: edgeStatus.results,
    );
    notifyListeners();
  }

  Future<void> completeEdgeSetup() async {
    if (_edgeStore == null) return;
    final ip = activeIp;
    await _edgeStore!.markFirstDone(ip: ip);
    phase = ShellPhase.picker;
    notifyListeners();
  }

  Future<void> openModule(DeskModule module) async {
    await closeModule(notify: false);
    activeModule = module;
    if (module == DeskModule.iwara) {
      final controller = AppController();
      controller.onExitModule = exitToPicker;
      await controller.initialize();
      iwaraController = controller;
    } else if (module == DeskModule.qinav) {
      final controller = QinavController(resolveIp: activeIp, onExitModule: exitToPicker);
      await controller.initialize();
      qinavController = controller;
    } else if (module == DeskModule.xmav) {
      final controller = XmavController(onExitModule: exitToPicker);
      await controller.initialize();
      xmavController = controller;
    }
    phase = ShellPhase.module;
    notifyListeners();
  }

  Future<void> exitToPicker() async {
    await closeModule(notify: false);
    phase = ShellPhase.picker;
    notifyListeners();
  }

  Future<void> closeModule({bool notify = true}) async {
    final iwara = iwaraController;
    final qinav = qinavController;
    final xmav = xmavController;
    iwaraController = null;
    qinavController = null;
    xmavController = null;
    activeModule = null;
    if (iwara != null) {
      try {
        await iwara.disposeModule();
      } catch (_) {}
      iwara.dispose();
    }
    if (qinav != null) {
      try {
        await qinav.disposeModule();
      } catch (_) {}
      qinav.dispose();
    }
    if (xmav != null) {
      try {
        await xmav.disposeModule();
      } catch (_) {}
      xmav.dispose();
    }
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    final iwara = iwaraController;
    final qinav = qinavController;
    final xmav = xmavController;
    iwaraController = null;
    qinavController = null;
    xmavController = null;
    iwara?.dispose();
    qinav?.dispose();
    xmav?.dispose();
    super.dispose();
  }
}
