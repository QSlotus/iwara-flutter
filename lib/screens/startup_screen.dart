import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_controller.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  EdgeStatus? status;
  bool selecting = false;
  bool entering = false;
  bool probing = false;
  String? error;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final api = context.read<AppController>();
      // First launch only: start edge probe once.
      setState(() => probing = true);
      try {
        await api.refreshEdge();
      } catch (e) {
        if (mounted) setState(() => error = e.toString());
      } finally {
        if (mounted) setState(() => probing = false);
      }
      await _refresh();
    });
    timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    final controller = context.read<AppController>();
    try {
      final next = await controller.fetchEdgeStatus();
      if (!mounted) return;
      setState(() {
        status = next;
        error = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() => error = e.toString());
    }
  }

  Future<void> _select(String ip) async {
    setState(() => selecting = true);
    try {
      await context.read<AppController>().selectEdgeIp(ip);
      await _refresh();
    } finally {
      if (mounted) setState(() => selecting = false);
    }
  }

  Future<void> _continue() async {
    setState(() => entering = true);
    await context.read<AppController>().completeFirstEdgeSetup();
  }

  @override
  Widget build(BuildContext context) {
    final ready = status?.status == 'ready' || status?.status == 'error';
    final results = status?.results ?? const <EdgeProbeResult>[];
    final selectedIp = status?.selectedIp ?? status?.activeIp;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 12),
                Text('Iwara Signal Desk', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  '首次启动需要完成 Cloudflare 边缘测速并选择强制解析 IP。之后不会自动测速，可在账户页重新测速/换 IP。',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        if (status?.status == 'ready')
                          const Icon(Icons.check_circle, color: Colors.greenAccent)
                        else if (status?.status == 'error' || error != null)
                          const Icon(Icons.warning_amber_rounded, color: Colors.amber)
                        else
                          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(status?.status == 'ready'
                                  ? '测速完成'
                                  : status?.status == 'error'
                                      ? '测速失败，可使用当前解析'
                                      : probing
                                          ? '正在测速…'
                                          : '等待测速…'),
                              Text(
                                '当前 IP: ${status?.activeIp ?? '-'} · 来源: ${status?.source ?? '-'}',
                                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.65)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: selecting || entering || probing
                              ? null
                              : () async {
                                  setState(() => probing = true);
                                  try {
                                    await context.read<AppController>().refreshEdge();
                                    await _refresh();
                                  } finally {
                                    if (mounted) setState(() => probing = false);
                                  }
                                },
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < results.length; i++)
                        ListTile(
                          leading: Text('${(i + 1).toString().padLeft(2, '0')}'),
                          title: Text(results[i].ip, style: const TextStyle(fontFamily: 'monospace')),
                          subtitle: Text('${results[i].latencyMs.toStringAsFixed(1)} ms'),
                          trailing: selectedIp == results[i].ip
                              ? const Icon(Icons.check, color: Colors.greenAccent)
                              : const Text('选择'),
                          selected: selectedIp == results[i].ip,
                          onTap: selecting || entering ? null : () => _select(results[i].ip),
                        ),
                      if (results.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('等待测速结果…'),
                        ),
                    ],
                  ),
                ),
                if (status?.warning != null) ...[
                  const SizedBox(height: 12),
                  Text(status!.warning!, style: const TextStyle(color: Colors.amberAccent)),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: Colors.redAccent)),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: !ready || selecting || entering ? null : _continue,
                  icon: entering
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.arrow_forward),
                  label: Text(status?.status == 'error' ? '使用当前解析进入' : '使用所选节点进入'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
