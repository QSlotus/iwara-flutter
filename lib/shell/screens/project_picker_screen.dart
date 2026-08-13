import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:signal_desk/shell/shell_controller.dart';

class ProjectPickerScreen extends StatelessWidget {
  const ProjectPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();

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
                  '选择要进入的项目。模块之间数据与会话互相隔离。',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 8),
                Text(
                  '强制解析 IP: ${shell.activeIp}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 20),
                _ProjectCard(
                  title: 'Iwara',
                  subtitle: 'Iwara Signal Desk · 本地强制 IP 代理客户端',
                  icon: Icons.play_circle_outline,
                  onTap: () => shell.openModule(DeskModule.iwara),
                ),
                const SizedBox(height: 12),
                _ProjectCard(
                  title: 'Qinav',
                  subtitle: 'P2：列表 / 搜索 / 详情 / HLS 播放（当前为占位）',
                  icon: Icons.video_library_outlined,
                  onTap: () => shell.openModule(DeskModule.qinav),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
