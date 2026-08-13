import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:signal_desk/core/edge/edge_models.dart';
import 'package:signal_desk/shell/shell_controller.dart';

class ShellEdgeScreen extends StatefulWidget {
  const ShellEdgeScreen({super.key});

  @override
  State<ShellEdgeScreen> createState() => _ShellEdgeScreenState();
}

class _ShellEdgeScreenState extends State<ShellEdgeScreen> {
  bool selecting = false;
  bool entering = false;

  Future<void> _select(String ip) async {
    setState(() => selecting = true);
    try {
      await context.read<ShellController>().selectEdgeIp(ip);
    } finally {
      if (mounted) setState(() => selecting = false);
    }
  }

  Future<void> _continue() async {
    setState(() => entering = true);
    try {
      await context.read<ShellController>().completeEdgeSetup();
    } finally {
      if (mounted) setState(() => entering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();
    final status = shell.edgeStatus;
    final probing = shell.edgeBusy || status.status == 'probing' || status.status == 'idle';
    final ready = status.status == 'ready' || status.status == 'error';
    final results = status.results;
    final selectedIp = status.selectedIp ?? status.activeIp;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 12),
                Text(
                  'Signal Desk',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '首次启动需要完成 Cloudflare 边缘测速并选择强制解析 IP。之后不会自动测速。',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (status.status == 'ready')
                          const Icon(Icons.check_circle, color: Colors.greenAccent)
                        else if (status.status == 'error' || shell.edgeError != null)
                          const Icon(Icons.warning_amber_rounded, color: Colors.amber)
                        else
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                status.status == 'ready'
                                    ? '测速完成'
                                    : status.status == 'error'
                                        ? '测速失败，可使用当前解析 IP 继续'
                                        : '正在测速 Cloudflare 边缘节点…',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                probing
                                    ? '请稍候，这可能需要几秒到十几秒。界面卡在这里是正常的。'
                                    : '当前 IP: ${status.activeIp}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 13,
                                ),
                              ),
                              if (!probing)
                                Text(
                                  '模式: ${status.selectionMode} · 状态: ${status.status}',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                                ),
                              if (status.warning != null) ...[
                                const SizedBox(height: 4),
                                Text(status.warning!, style: const TextStyle(color: Colors.amber, fontSize: 12)),
                              ],
                              if (shell.edgeError != null) ...[
                                const SizedBox(height: 4),
                                Text(shell.edgeError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (probing) ...[
                  const SizedBox(height: 24),
                  const Center(child: SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3))),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      '测速进行中',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.tonal(
                        onPressed: shell.edgeBusy ? null : () => shell.runEdgeProbe(force: true),
                        child: Text(shell.edgeBusy ? '测速中…' : '重新测速'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: (!ready || entering) ? null : _continue,
                        child: Text(entering ? '进入…' : '使用此 IP 继续'),
                      ),
                    ],
                  ),
                  if (results.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('可选节点', style: TextStyle(fontWeight: FontWeight.w600)),
                    ...results.map((EdgeProbeResult item) {
                      final selected = selectedIp == item.ip;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.ip, style: const TextStyle(fontFamily: 'monospace')),
                        subtitle: Text('${item.latencyMs.toStringAsFixed(1)} ms'),
                        trailing: selected
                            ? const Icon(Icons.check, color: Colors.greenAccent)
                            : const Text('使用'),
                        selected: selected,
                        onTap: (selecting || shell.edgeBusy) ? null : () => _select(item.ip),
                      );
                    }),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
