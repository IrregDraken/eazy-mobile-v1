import 'package:flutter_test/flutter_test.dart';
import 'package:eazy_mobile_v1/core/formatters/money_formatter.dart';

void main() {
  group('formatEazyMoney', () {
    test('formats naira with grouping and exactly two decimals', () {
      expect(formatEazyMoney('0'), '₦0.00');
      expect(formatEazyMoney('1000'), '₦1,000.00');
      expect(formatEazyMoney('1234567.5'), '₦1,234,567.50');
    });

    test('formats non-NGN currencies with their currency code', () {
      expect(formatEazyMoney('12.5', currency: 'USD'), 'USD 12.50');
    });

    test('does not invent an amount for invalid values', () {
      expect(formatEazyMoney(null), '—');
      expect(formatEazyMoney('not a number'), '—');
    });
  });
}
