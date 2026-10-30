import 'dart:math' show pow;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eazy_mobile_v1/app/theme/theme_controller.dart';

import 'package:eazy_mobile_v1/app/theme/eazy_theme.dart';

void main() {
  group('Eazy theme', () {
    test('light theme is the white default surface', () {
      eazyThemeMode.value = ThemeMode.light;
      addTearDown(() => eazyThemeMode.value = ThemeMode.light);
      final theme = EazyTheme.light();

      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, Colors.white);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.colorScheme.surface, Colors.white);
      expect(theme.colorScheme.onPrimary, Colors.white);
      expect(_contrastRatio(theme.colorScheme.primary, theme.colorScheme.surface), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(theme.colorScheme.onSurface, theme.colorScheme.surface), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(theme.colorScheme.onSurfaceVariant, theme.colorScheme.surface), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(EazyColors.red, theme.colorScheme.surface), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(EazyColors.amber, theme.colorScheme.surface), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(EazyColors.greenForeground, theme.colorScheme.surface), greaterThanOrEqualTo(4.5));
    });

    test('dark theme remains available as an explicit preference', () {
      eazyThemeMode.value = ThemeMode.dark;
      addTearDown(() => eazyThemeMode.value = ThemeMode.light);
      final theme = EazyTheme.dark();

      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, EazyColors.canvas);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(_contrastRatio(EazyColors.muted, theme.colorScheme.surface), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(EazyColors.red, theme.colorScheme.surface), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(EazyColors.amber, theme.colorScheme.surface), greaterThanOrEqualTo(4.5));
    });
  });
}

double _contrastRatio(Color foreground, Color background) {
  double linearize(int channel) {
    final value = channel / 255;
    return value <= 0.04045
        ? value / 12.92
        : pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  final foregroundLuminance = 0.2126 * linearize(foreground.red) +
      0.7152 * linearize(foreground.green) +
      0.0722 * linearize(foreground.blue);
  final backgroundLuminance = 0.2126 * linearize(background.red) +
      0.7152 * linearize(background.green) +
      0.0722 * linearize(background.blue);
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
