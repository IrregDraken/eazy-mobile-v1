import 'package:flutter/material.dart';

abstract final class EazyColors {
  static const ink = Color(0xFFF5F7F5);
  static const muted = Color(0xFFA4AEA8);
  static const canvas = Color(0xFF07100C);
  static const surface = Color(0xFF0E1813);
  static const surfaceRaised = Color(0xFF14221A);
  static const border = Color(0xFF22372B);
  static const green = Color(0xFF48F59A);
  static const greenDeep = Color(0xFF18B96C);
  static const mint = Color(0xFFB9FFD9);
  static const red = Color(0xFFFF746E);
  static const amber = Color(0xFFFFC96B);
  static const blue = Color(0xFF75B9FF);
}

abstract final class EazyRadius {
  static const sm = 12.0;
  static const md = 18.0;
  static const lg = 26.0;
  static const xl = 34.0;
}

abstract final class EazyTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: EazyColors.green,
      brightness: Brightness.dark,
      surface: EazyColors.surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme.copyWith(
        primary: EazyColors.green,
        onPrimary: EazyColors.canvas,
        surface: EazyColors.surface,
        onSurface: EazyColors.ink,
      ),
      scaffoldBackgroundColor: EazyColors.canvas,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: EazyColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EazyRadius.md),
          borderSide: const BorderSide(color: EazyColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EazyRadius.md),
          borderSide: const BorderSide(color: EazyColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EazyRadius.md),
          borderSide: const BorderSide(color: EazyColors.green, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      ),
      cardTheme: CardThemeData(
        color: EazyColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EazyRadius.lg),
          side: const BorderSide(color: EazyColors.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: EazyColors.surface.withValues(alpha: .96),
        indicatorColor: EazyColors.green.withValues(alpha: .14),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: EazyColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static ThemeData light() => dark();
}
