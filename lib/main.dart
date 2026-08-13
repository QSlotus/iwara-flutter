import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:signal_desk/shell/shell_app.dart';
import 'package:signal_desk/shell/shell_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final shell = ShellController();
  await shell.initialize();
  runApp(
    ChangeNotifierProvider.value(
      value: shell,
      child: const SignalDeskApp(),
    ),
  );
}
