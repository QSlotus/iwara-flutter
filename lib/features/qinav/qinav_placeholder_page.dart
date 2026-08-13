import 'package:flutter/material.dart';

class QinavPlaceholderPage extends StatelessWidget {
  const QinavPlaceholderPage({super.key, this.onExitModule, this.activeIp = ''});

  final VoidCallback? onExitModule;
  final String activeIp;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Qinav'),
        actions: [
          if (onExitModule != null)
            TextButton(onPressed: onExitModule, child: const Text('退出项目')),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.construction, size: 48),
                const SizedBox(height: 16),
                Text('Qinav 模块开发中', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'P2 将提供列表 / 搜索 / 详情 / 本地 HLS 代理播放。\n'
                  '已共用 Signal Desk 的 Cloudflare 强制解析'
                  '${activeIp.isEmpty ? '' : '（当前 IP: $activeIp）'}。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
