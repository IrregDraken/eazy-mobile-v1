import 'package:flutter/material.dart';

/// Brand and semantic colors used by screens that haven't migrated to
/// context-aware ColorScheme tokens yet. These values are optimized for the
/// default light interface so fixed-color labels remain legible on white.
abstract final class EazyColors {
  static const ink = Color(0xFF102019);
  static const muted = Color(0xFF4F6258);
  static const canvas = Color(0xFFF7FBF8);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceRaised = Color(0xFFFFFFFF);
  static const border = Color(0xFFD9E7DE);
  static const green = Color(0xFF087A45);
  static const greenDeep = Color(0xFF087A45);
  static const mint = Color(0xFFDDF5E6);
  static const red = Color(0xFFB42318);
  static const amber = Color(0xFF946200);
  static const blue = Color(0xFF155EEF);
}

@immutable
class EazySemanticColors extends ThemeExtension<EazySemanticColors> {
  const EazySemanticColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.border,
    required this.primary,
    required this.primaryPressed,
    required this.onPrimary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.error,
    required this.warning,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color border;
  final Color primary;
  final Color primaryPressed;
  final Color onPrimary;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color error;
  final Color warning;

  static const light = EazySemanticColors(
    background: Color(0xFFF7FBF8),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    border: Color(0xFFD9E7DE),
    primary: Color(0xFF087A45),
    primaryPressed: Color(0xFF055A33),
    onPrimary: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF102019),
    textSecondary: Color(0xFF4F6258),
    textDisabled: Color(0xFF7A8B82),
    error: Color(0xFFB42318),
    warning: Color(0xFF946200),
  );

  static const dark = EazySemanticColors(
    background: Color(0xFF06150F),
    surface: Color(0xFF0B2118),
    surfaceElevated: Color(0xFF102D21),
    border: Color(0x2E87FFBE),
    primary: Color(0xFF36F28A),
    primaryPressed: Color(0xFF19C970),
    onPrimary: Color(0xFF06150F),
    textPrimary: Color(0xFFF4FFF8),
    textSecondary: Color(0xFFA8BDB1),
    textDisabled: Color(0xFF6E8377),
    error: Color(0xFFFF7A7A),
    warning: Color(0xFFF2C66D),
  );

  @override
  EazySemanticColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? border,
    Color? primary,
    Color? primaryPressed,
    Color? onPrimary,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? error,
    Color? warning,
  }) => EazySemanticColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceElevated: surfaceElevated ?? this.surfaceElevated,
    border: border ?? this.border,
    primary: primary ?? this.primary,
    primaryPressed: primaryPressed ?? this.primaryPressed,
    onPrimary: onPrimary ?? this.onPrimary,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textDisabled: textDisabled ?? this.textDisabled,
    error: error ?? this.error,
    warning: warning ?? this.warning,
  );

  @override
  EazySemanticColors lerp(
    covariant ThemeExtension<EazySemanticColors>? other,
    double t,
  ) {
    if (other is! EazySemanticColors) return this;
    return EazySemanticColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryPressed: Color.lerp(primaryPressed, other.primaryPressed, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      error: Color.lerp(error, other.error, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

abstract final class _DarkColors {
  static const ink = Color(0xFFF4FFF8);
  static const canvas = Color(0xFF06150F);
  static const surface = Color(0xFF0B2118);
  static const surfaceRaised = Color(0xFF102D21);
  static const border = Color(0x2E87FFBE);
  static const green = Color(0xFF36F28A);
  static const red = Color(0xFFFF7A7A);
}

abstract final class EazyRadius {
  static const sm = 12.0, md = 18.0, lg = 26.0, xl = 34.0;
}

abstract final class EazySpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 40.0;
}

abstract final class EazyTypography {
  static const metadata = 12.0;
  static const body = 14.0;
  static const control = 16.0;
  static const section = 20.0;
  static const heading = 24.0;
  static const display = 32.0;
}

abstract final class EazyIconSize {
  static const sm = 16.0;
  static const md = 20.0;
  static const lg = 24.0;
  static const xl = 28.0;
}

abstract final class EazyTouchTarget {
  static const minimum = 48.0;
}

abstract final class EazyMotion {
  static const fast = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 180);
  static const slow = Duration(milliseconds: 280);
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
        onSurfaceVariant: EazySemanticColors.dark.textSecondary,
        outlineVariant: EazySemanticColors.dark.border,
        error: EazySemanticColors.dark.error,
        primaryContainer: EazySemanticColors.dark.primaryPressed,
        onPrimaryContainer: EazySemanticColors.dark.onPrimary,
      ),
      extensions: const [EazySemanticColors.dark],
    );
    return base.copyWith(
      scaffoldBackgroundColor: EazySemanticColors.dark.background,
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
      dialogTheme: DialogThemeData(
        backgroundColor: _DarkColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EazyRadius.lg),
          side: const BorderSide(color: _DarkColors.border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: _DarkColors.surface,
        modalBackgroundColor: _DarkColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(EazyRadius.lg),
          ),
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
        contentTextStyle: const TextStyle(color: _DarkColors.ink),
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
        onSurface: EazySemanticColors.light.textPrimary,
        onSurfaceVariant: EazySemanticColors.light.textSecondary,
        outlineVariant: EazySemanticColors.light.border,
        error: EazySemanticColors.light.error,
        surfaceContainerHighest: const Color(0xFFEAF6EE),
        primaryContainer: EazySemanticColors.light.primaryPressed,
        onPrimaryContainer: EazySemanticColors.light.onPrimary,
      ),
      extensions: const [EazySemanticColors.light],
    );
    return base.copyWith(
      scaffoldBackgroundColor: EazySemanticColors.light.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: Color(0xFF176B42),
      ),
      textTheme: base.textTheme
          .apply(
            bodyColor: EazySemanticColors.light.textPrimary,
            displayColor: EazySemanticColors.light.textPrimary,
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
        fillColor: EazySemanticColors.light.surface,
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
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EazyRadius.lg),
          side: const BorderSide(color: Color(0xFFDDEBE2)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(EazyRadius.lg),
          ),
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
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFDDEBE2)),
    );
  }
}

extension EazyThemeTokens on BuildContext {
  Color get eazyAccent =>
      Theme.of(this).brightness == Brightness.dark
          ? _DarkColors.green
          : EazyColors.greenDeep;
  Color get eazyText => Theme.of(this).colorScheme.onSurface;
  Color get eazyMuted => Theme.of(this).colorScheme.onSurfaceVariant;
  Color get eazyBorder => Theme.of(this).colorScheme.outlineVariant;
  Color get eazySurfaceRaised =>
      Theme.of(this).colorScheme.surfaceContainerHighest;
  Color get eazyOnAccent => Theme.of(this).colorScheme.onPrimary;
  Color get eazyDisabled =>
      Theme.of(this).extension<EazySemanticColors>()?.textDisabled ??
      EazyColors.muted;
  Color get eazyError =>
      Theme.of(this).extension<EazySemanticColors>()?.error ??
      EazyColors.red;
  Color get eazyWarning =>
      Theme.of(this).extension<EazySemanticColors>()?.warning ??
      EazyColors.amber;
}
