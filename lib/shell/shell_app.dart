import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:signal_desk/core/theme/shell_theme.dart';
import 'package:signal_desk/features/iwara/app.dart';
import 'package:signal_desk/features/iwara/services/app_controller.dart';
import 'package:signal_desk/features/qinav/qinav_placeholder_page.dart';
import 'package:signal_desk/shell/screens/project_picker_screen.dart';
import 'package:signal_desk/shell/screens/shell_edge_screen.dart';
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
              home: const Scaffold(body: Center(child: CircularProgressIndicator())),
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
              home: const ProjectPickerScreen(),
            );
          case ShellPhase.module:
            if (shell.activeModule == DeskModule.iwara && shell.iwaraController != null) {
              return ChangeNotifierProvider<AppController>.value(
                value: shell.iwaraController!,
                child: IwaraModuleApp(onExitModule: shell.exitToPicker),
              );
            }
            if (shell.activeModule == DeskModule.qinav) {
              return MaterialApp(
                title: 'Signal Desk',
                debugShowCheckedModeBanner: false,
                theme: buildShellTheme(),
                home: QinavPlaceholderPage(
                  activeIp: shell.activeIp,
                  onExitModule: shell.exitToPicker,
                ),
              );
            }
            return MaterialApp(
              title: 'Signal Desk',
              debugShowCheckedModeBanner: false,
              theme: buildShellTheme(),
              home: const ProjectPickerScreen(),
            );
        }
      },
    );
  }
}
