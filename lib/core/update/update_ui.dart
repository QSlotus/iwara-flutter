import 'package:flutter/material.dart';

import 'update_service.dart';

Future<void> presentUpdateCheck(
  BuildContext context, {
  required UpdateService service,
  required UpdateCheckResult result,
  bool quietIfNoUpdate = false,
  bool markPromptedOnShow = false,
}) async {
  if (!context.mounted) return;

  if (result.error != null && !result.hasUpdate) {
    if (!quietIfNoUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error!)));
    }
    return;
  }

  if (!result.hasUpdate) {
    if (!quietIfNoUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已是最新版本 ${result.currentVersion}')),
      );
    }
    return;
  }

  if (markPromptedOnShow) {
    await service.markPrompted(result);
  }
  if (!context.mounted) return;

  final notes = (result.releaseNotes ?? '').trim();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('发现新版本'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('当前版本: ${result.currentVersion}'),
              Text('最新版本: ${result.displayLatest}'),
              if ((result.releaseName ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(result.releaseName!, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(notes),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () async {
              final opened = await service.openUpdate(result);
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('无法打开下载链接，请稍后在 GitHub Releases 手动下载')),
                );
              }
            },
            child: Text((result.apkDownloadUrl?.isNotEmpty ?? false) ? '下载 APK' : '查看 Release'),
          ),
        ],
      );
    },
  );
}