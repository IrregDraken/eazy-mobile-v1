import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eazy_mobile_v1/app/theme/eazy_theme.dart';

void main() {
  group('Eazy theme', () {
    test('light theme is the white default surface', () {
      final theme = EazyTheme.light();

      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, Colors.white);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.colorScheme.surface, Colors.white);
      expect(theme.colorScheme.onPrimary, Colors.white);
    });

    test('dark theme remains available as an explicit preference', () {
      final theme = EazyTheme.dark();

      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, EazyColors.canvas);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });
  });
}
