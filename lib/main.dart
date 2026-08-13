import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:signal_desk/shell/shell_app.dart';
import 'package:signal_desk/shell/shell_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final shell = ShellController();
  // Show UI immediately; edge probe runs inside initialize() with visible progress.
  runApp(
    ChangeNotifierProvider.value(
      value: shell,
      child: const SignalDeskApp(),
    ),
  );
  // ignore: unawaited_futures
  shell.initialize();
}
