import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:signal_desk/core/theme/shell_theme.dart';
import 'package:signal_desk/features/qinav/screens/qinav_home_screen.dart';
import 'package:signal_desk/features/qinav/services/qinav_controller.dart';

class QinavModuleApp extends StatelessWidget {
  const QinavModuleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<QinavController>();
    return MaterialApp(
      title: 'Qinav',
      debugShowCheckedModeBanner: false,
      theme: buildShellTheme(),
      home: !controller.ready
          ? Scaffold(
              body: Center(
                child: controller.lastError == null
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(controller.lastError!, textAlign: TextAlign.center),
                      ),
              ),
            )
          : const QinavHomeScreen(),
    );
  }
}
