import 'package:flutter_test/flutter_test.dart';
import 'package:eazy_mobile_v1/features/wallet/wallet_amount_input.dart';

void main() {
  group('normalizeWalletAmountInput', () {
    test('accepts whole naira amounts and formats two decimal places', () {
      expect(normalizeWalletAmountInput('500'), '500.00');
      expect(normalizeWalletAmountInput('5000'), '5000.00');
      expect(normalizeWalletAmountInput('10,000'), '10000.00');
    });

    test('preserves valid fractional amounts and pads one decimal place', () {
      expect(normalizeWalletAmountInput('5000.5'), '5000.50');
      expect(normalizeWalletAmountInput('5000.55'), '5000.55');
    });

    test('converts naira to integer kobo without floating point', () {
      expect(walletAmountToMinorUnits('500'), BigInt.from(50000));
      expect(walletAmountToMinorUnits('1,000.5'), BigInt.from(100050));
      expect(walletAmountToMinorUnits('0.01'), BigInt.one);
      expect(walletAmountToMinorUnits('1000.999'), isNull);
      expect(walletAmountToMinorUnits('not money'), isNull);
    });

    test('rejects zero, excessive precision and malformed amounts', () {
      expect(normalizeWalletAmountInput('0'), isNull);
      expect(normalizeWalletAmountInput('0.00'), isNull);
      expect(normalizeWalletAmountInput('5000.555'), isNull);
      expect(normalizeWalletAmountInput('-5000'), isNull);
      expect(normalizeWalletAmountInput('five thousand'), isNull);
      expect(normalizeWalletAmountInput(''), isNull);
    });
  });
}
