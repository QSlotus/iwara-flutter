import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:signal_desk/core/theme/shell_theme.dart';
import 'package:signal_desk/features/iwara/app.dart';
import 'package:signal_desk/features/iwara/services/app_controller.dart';
import 'package:signal_desk/features/qinav/qinav_module.dart';
import 'package:signal_desk/features/qinav/services/qinav_controller.dart';
import 'package:signal_desk/shell/screens/shell_edge_screen.dart';
import 'package:signal_desk/shell/screens/shell_hub_screen.dart';
import 'package:signal_desk/shell/shell_controller.dart';

class SignalDeskApp extends StatelessWidget {
  const SignalDeskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ShellController>(
      builder: (context, shell, _) {
        switch (shell.phase) {
          case ShellPhase.booting:
            return MaterialApp(
              title: 'Signal Desk',
              debugShowCheckedModeBanner: false,
              theme: buildShellTheme(),
              home: const BootLoadingPage(
                title: 'Signal Desk',
                message: '正在初始化…',
              ),
            );
          case ShellPhase.edgeSetup:
            return MaterialApp(
              title: 'Signal Desk',
              debugShowCheckedModeBanner: false,
              theme: buildShellTheme(),
              home: const ShellEdgeScreen(),
            );
          case ShellPhase.picker:
            return MaterialApp(
              title: 'Signal Desk',
              debugShowCheckedModeBanner: false,
              theme: buildShellTheme(),
              home: const ShellHubScreen(),
            );
          case ShellPhase.module:
            if (shell.activeModule == DeskModule.iwara && shell.iwaraController != null) {
              return ChangeNotifierProvider<AppController>.value(
                value: shell.iwaraController!,
                child: IwaraModuleApp(onExitModule: shell.exitToPicker),
              );
            }
            if (shell.activeModule == DeskModule.qinav && shell.qinavController != null) {
              return ChangeNotifierProvider<QinavController>.value(
                value: shell.qinavController!,
                child: const QinavModuleApp(),
              );
            }
            return MaterialApp(
              title: 'Signal Desk',
              debugShowCheckedModeBanner: false,
              theme: buildShellTheme(),
              home: const ShellHubScreen(),
            );
        }
      },
    );
  }
}

class BootLoadingPage extends StatelessWidget {
  const BootLoadingPage({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
