import 'package:flutter/material.dart';

ThemeData buildShellTheme() {
  const seed = Color(0xFF5B8CFF);
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: seed,
  );
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFF0E1116),
    appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0),
    cardTheme: CardThemeData(
      color: const Color(0xFF171B22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
