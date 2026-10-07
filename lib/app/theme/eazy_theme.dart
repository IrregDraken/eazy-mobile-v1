import 'package:flutter/material.dart';

abstract final class EazyColors {
  static const ink = Color(0xFFF4F8F5);
  static const muted = Color(0xFF9AA79F);
  static const canvas = Color(0xFF06100B);
  static const surface = Color(0xFF0C1711);
  static const surfaceRaised = Color(0xFF122119);
  static const border = Color(0xFF20352A);
  static const green = Color(0xFF48F59A);
  static const greenDeep = Color(0xFF18B96C);
  static const mint = Color(0xFFB9FFD9);
  static const red = Color(0xFFFF746E);
  static const amber = Color(0xFFFFC96B);
  static const blue = Color(0xFF75B9FF);
}

abstract final class EazyRadius {
  static const sm = 12.0, md = 18.0, lg = 26.0, xl = 34.0;
}

abstract final class EazyTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: EazyColors.green,
      brightness: Brightness.dark,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme.copyWith(
        primary: EazyColors.green,
        onPrimary: EazyColors.canvas,
        surface: EazyColors.surface,
        onSurface: EazyColors.ink,
        surfaceContainerHighest: EazyColors.surfaceRaised,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: EazyColors.canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: EazyColors.ink,
      ),
      textTheme: base.textTheme
          .apply(bodyColor: EazyColors.ink, displayColor: EazyColors.ink)
          .copyWith(
            headlineLarge: const TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: -1.8,
            ),
            headlineMedium: const TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
            ),
            titleLarge: const TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: -.4,
            ),
            titleMedium: const TextStyle(fontWeight: FontWeight.w800),
          ),
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EazyRadius.md),
          borderSide: const BorderSide(color: EazyColors.red),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
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
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(54)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(EazyRadius.md),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(54)),
          side: const WidgetStatePropertyAll(
            BorderSide(color: EazyColors.border),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(EazyRadius.md),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: EazyColors.surface.withValues(alpha: .97),
        indicatorColor: EazyColors.green.withValues(alpha: .14),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: EazyColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: const DividerThemeData(color: EazyColors.border),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: EazyColors.greenDeep,
      brightness: Brightness.light,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme.copyWith(
        primary: EazyColors.greenDeep,
        onPrimary: Colors.white,
        surface: const Color(0xFFF8FCF9),
        onSurface: const Color(0xFF10231A),
        surfaceContainerHighest: const Color(0xFFE8F3EC),
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF5FAF7),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: Color(0xFF10231A),
      ),
      textTheme: base.textTheme
          .apply(
            bodyColor: const Color(0xFF10231A),
            displayColor: const Color(0xFF10231A),
          )
          .copyWith(
            headlineLarge: const TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: -1.8,
            ),
            headlineMedium: const TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
            ),
            titleLarge: const TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: -.4,
            ),
            titleMedium: const TextStyle(fontWeight: FontWeight.w800),
          ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EazyRadius.md),
          borderSide: const BorderSide(color: Color(0xFFD3E4D9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EazyRadius.md),
          borderSide: const BorderSide(color: Color(0xFFD3E4D9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EazyRadius.md),
          borderSide: const BorderSide(color: EazyColors.greenDeep, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EazyRadius.lg),
          side: const BorderSide(color: Color(0xFFDDEBE2)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(54)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(EazyRadius.md),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(54)),
          side: const WidgetStatePropertyAll(
            BorderSide(color: Color(0xFFBFD8C9)),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(EazyRadius.md),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: Colors.white.withValues(alpha: .97),
        indicatorColor: EazyColors.greenDeep.withValues(alpha: .14),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF173D29),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFDDEBE2)),
    );
  }
}
