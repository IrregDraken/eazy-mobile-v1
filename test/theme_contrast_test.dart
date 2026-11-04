import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eazy_mobile_v1/app/theme/eazy_theme.dart';

double _contrastRatio(Color foreground, Color background) {
  final luminances = [
    foreground.computeLuminance(),
    background.computeLuminance(),
  ]..sort((a, b) => b.compareTo(a));
  return (luminances.first + 0.05) / (luminances.last + 0.05);
}

void main() {
  test('light semantic theme keeps primary, secondary, disabled and status text legible', () {
    final theme = EazyTheme.light();
    final tokens = theme.extension<EazySemanticColors>()!;

    expect(_contrastRatio(tokens.textPrimary, tokens.background), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.textSecondary, tokens.surface), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.textDisabled, tokens.background), greaterThanOrEqualTo(3.0));
    expect(_contrastRatio(tokens.onPrimary, tokens.primary), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.error, tokens.surface), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.warning, tokens.surface), greaterThanOrEqualTo(4.5));
    expect(theme.colorScheme.onSurface, tokens.textPrimary);
    expect(theme.colorScheme.onSurfaceVariant, tokens.textSecondary);
  });

  test('dark semantic theme keeps primary, secondary, disabled and status text legible', () {
    final theme = EazyTheme.dark();
    final tokens = theme.extension<EazySemanticColors>()!;

    expect(_contrastRatio(tokens.textPrimary, tokens.background), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.textSecondary, tokens.surface), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.textDisabled, tokens.background), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.onPrimary, tokens.primary), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.error, tokens.surface), greaterThanOrEqualTo(4.5));
    expect(_contrastRatio(tokens.warning, tokens.surface), greaterThanOrEqualTo(4.5));
    expect(theme.colorScheme.onSurface, tokens.textPrimary);
    expect(theme.colorScheme.onSurfaceVariant, tokens.textSecondary);
  });
}
