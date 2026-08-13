import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:signal_desk/core/theme/shell_theme.dart';
import 'package:signal_desk/features/xmav/screens/xmav_home_screen.dart';
import 'package:signal_desk/features/xmav/services/xmav_controller.dart';

class XmavModuleApp extends StatelessWidget {
  const XmavModuleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<XmavController>();
    return MaterialApp(
      title: 'Xmav',
      debugShowCheckedModeBanner: false,
      theme: buildShellTheme(),
      home: !controller.ready
          ? Scaffold(
              appBar: AppBar(
                title: const Text('Xmav'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => controller.onExitModule?.call(),
                ),
              ),
              body: Center(
                child: controller.resolvingBase && controller.lastError == null
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('正在解析内容线路…'),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              controller.lastError ?? '线路未就绪',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: controller.resolvingBase
                                  ? null
                                  : () => controller.refreshBase(force: true),
                              child: Text(controller.resolvingBase ? '重试中…' : '重试解析'),
                            ),
                          ],
                        ),
                      ),
              ),
            )
          : const XmavHomeScreen(),
    );
  }
}
