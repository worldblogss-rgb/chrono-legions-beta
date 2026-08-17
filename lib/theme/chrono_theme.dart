import 'package:flutter/material.dart';

class ChronoPalette {
  const ChronoPalette._();

  static const background = Color(0xFF0B0E0D);
  static const battlefield = Color(0xFF141813);
  static const panel = Color(0xFF201C17);
  static const panelRaised = Color(0xFF2B251D);
  static const parchment = Color(0xFFE7D2AD);
  static const parchmentMuted = Color(0xFFB7A486);
  static const gold = Color(0xFFC59A4D);
  static const bronze = Color(0xFF765236);
  static const rome = Color(0xFF8A2D2B);
  static const carthage = Color(0xFF245A55);
  static const valid = Color(0xFF68C77B);
  static const damage = Color(0xFFD75445);
  static const warning = Color(0xFFE3AF50);
  static const order = Color(0xFFD5A2E8);
  static const text = Color(0xFFF4EAD7);
  static const muted = Color(0xFF9B9181);
}

class ChronoTheme {
  const ChronoTheme._();

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ChronoPalette.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: ChronoPalette.gold,
        brightness: Brightness.dark,
      ),
      cardColor: ChronoPalette.panelRaised,
      dividerColor: ChronoPalette.gold.withAlpha(70),
      appBarTheme: const AppBarTheme(
        backgroundColor: ChronoPalette.background,
        foregroundColor: ChronoPalette.text,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ChronoPalette.panelRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: ChronoPalette.text, fontWeight: FontWeight.w800),
        titleMedium: TextStyle(color: ChronoPalette.text, fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(color: ChronoPalette.text),
        bodySmall: TextStyle(color: ChronoPalette.parchmentMuted),
      ),
    );
  }
}
