import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:signal_desk/core/update/update_service.dart';
import 'package:signal_desk/core/update/update_ui.dart';
import 'package:signal_desk/shell/shell_controller.dart';

/// Post-edge shell home: project picker + app info (with update check).
class ShellHubScreen extends StatefulWidget {
  const ShellHubScreen({super.key});

  @override
  State<ShellHubScreen> createState() => _ShellHubScreenState();
}

class _ShellHubScreenState extends State<ShellHubScreen> {
  int tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: tabIndex,
        children: const [
          _ProjectsTab(),
          _AboutTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: (i) => setState(() => tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps),
            label: '项目',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info),
            label: '软件信息',
          ),
        ],
      ),
    );
  }
}

class _ProjectsTab extends StatelessWidget {
  const _ProjectsTab();

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();
    return SafeArea(
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
                subtitle: '列表 / 搜索 / 详情 / 本地 HLS 代理播放',
                icon: Icons.video_library_outlined,
                onTap: () => shell.openModule(DeskModule.qinav),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutTab extends StatefulWidget {
  const _AboutTab();

  @override
  State<_AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends State<_AboutTab> {
  final UpdateService updateService = UpdateService();
  String appName = 'Signal Desk';
  String version = '';
  String buildNumber = '';
  bool updateBusy = false;
  String? lastCheckSummary;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        appName = info.appName.isNotEmpty ? info.appName : 'Signal Desk';
        version = info.version;
        buildNumber = info.buildNumber;
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _checkUpdate() async {
    setState(() {
      updateBusy = true;
      lastCheckSummary = null;
    });
    try {
      final result = await updateService.checkForUpdate();
      if (!mounted) return;
      setState(() {
        if (result.error != null && !result.hasUpdate) {
          lastCheckSummary = result.error;
        } else if (result.hasUpdate) {
          lastCheckSummary = '发现新版本 ${result.displayLatest}';
        } else {
          lastCheckSummary = '已是最新版本 ${result.currentVersion}';
        }
      });
      await presentUpdateCheck(
        context,
        service: updateService,
        result: result,
        quietIfNoUpdate: false,
      );
    } finally {
      if (mounted) setState(() => updateBusy = false);
    }
  }

  Future<void> _openReleases() async {
    final uri = Uri.parse('https://github.com/QSlotus/iwara-flutter/releases');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开 GitHub Releases')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();
    final versionLabel = version.isEmpty
        ? '…'
        : (buildNumber.isEmpty ? version : '$version+$buildNumber');

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 12),
              Text(
                '软件信息',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '整包更新面向 Signal Desk 本体，不区分项目模块。',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(appName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('版本: $versionLabel', style: const TextStyle(fontFamily: 'monospace')),
                      const SizedBox(height: 4),
                      Text('仓库: QSlotus/iwara-flutter', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        '强制解析 IP: ${shell.activeIp}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('检查更新', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                        '通过 GitHub Releases 比对版本号。发现新版本可下载 APK。',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                      ),
                      if (lastCheckSummary != null) ...[
                        const SizedBox(height: 10),
                        Text(lastCheckSummary!),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: updateBusy ? null : _checkUpdate,
                            child: Text(updateBusy ? '检查中…' : '检查更新'),
                          ),
                          OutlinedButton(
                            onPressed: _openReleases,
                            child: const Text('打开 Releases'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '模块说明\n'
                    '· Iwara：原有功能保持不变\n'
                    '· Qinav：独立本地代理与播放链路\n'
                    '退出任一模块后会硬卸载，返回本页。',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.78), height: 1.45),
                  ),
                ),
              ),
            ],
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
