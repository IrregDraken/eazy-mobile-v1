import 'package:flutter/material.dart';

/// Brand and semantic colors used by screens that haven't migrated to
/// context-aware ColorScheme tokens yet. These values are optimized for the
/// default light interface so fixed-color labels remain legible on white.
abstract final class EazyColors {
  static const ink = Color(0xFF153B27);
  static const muted = Color(0xFF587365);
  static const canvas = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceRaised = Color(0xFFF0F8F2);
  static const border = Color(0xFFD7E8DC);
  static const green = Color(0xFF16864C);
  static const greenDeep = Color(0xFF147A43);
  static const mint = Color(0xFFD9F5E3);
  static const red = Color(0xFFB42318);
  static const amber = Color(0xFF8A5200);
  static const blue = Color(0xFF155EEF);
}

abstract final class _DarkColors {
  static const ink = Color(0xFFF4F8F5);
  static const canvas = Color(0xFF06100B);
  static const surface = Color(0xFF0C1711);
  static const surfaceRaised = Color(0xFF122119);
  static const border = Color(0xFF20352A);
  static const green = Color(0xFF48F59A);
  static const red = Color(0xFFFF746E);
}

abstract final class EazyRadius {
  static const sm = 12.0, md = 18.0, lg = 26.0, xl = 34.0;
}

abstract final class EazyTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _DarkColors.green,
      brightness: Brightness.dark,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme.copyWith(
        primary: _DarkColors.green,
        onPrimary: _DarkColors.canvas,
        surface: _DarkColors.surface,
        onSurface: _DarkColors.ink,
        surfaceContainerHighest: _DarkColors.surfaceRaised,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: _DarkColors.canvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: _DarkColors.ink,
      ),
      textTheme: base.textTheme
          .apply(bodyColor: _DarkColors.ink, displayColor: _DarkColors.ink)
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
        fillColor: _DarkColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EazyRadius.md),
          borderSide: const BorderSide(color: _DarkColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EazyRadius.md),
          borderSide: const BorderSide(color: _DarkColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EazyRadius.md),
          borderSide: const BorderSide(color: _DarkColors.green, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EazyRadius.md),
          borderSide: const BorderSide(color: _DarkColors.red),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
      ),
      cardTheme: CardThemeData(
        color: _DarkColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EazyRadius.lg),
          side: const BorderSide(color: _DarkColors.border),
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
            BorderSide(color: _DarkColors.border),
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
        backgroundColor: _DarkColors.surface.withValues(alpha: .97),
        indicatorColor: _DarkColors.green.withValues(alpha: .14),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _DarkColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: const DividerThemeData(color: _DarkColors.border),
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
        surface: Colors.white,
        onSurface: const Color(0xFF176B42),
        surfaceContainerHighest: const Color(0xFFEAF6EE),
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: Color(0xFF176B42),
      ),
      textTheme: base.textTheme
          .apply(
            bodyColor: const Color(0xFF176B42),
            displayColor: const Color(0xFF176B42),
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
          borderSide: const BorderSide(color: Color(0xFFCFE5D7)),
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
            BorderSide(color: Color(0xFFB7DCC4)),
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
