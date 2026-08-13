import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const seed = Color(0xFF8B5CF6);
  final base = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
  return ThemeData(
    useMaterial3: true,
    colorScheme: base.copyWith(surface: const Color(0xFF12101A), primary: seed),
    scaffoldBackgroundColor: const Color(0xFF0B0A13),
    cardTheme: CardThemeData(
      color: const Color(0xFF171523),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0B0A13), foregroundColor: Colors.white, elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1B1828),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
