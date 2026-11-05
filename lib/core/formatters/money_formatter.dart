import 'package:intl/intl.dart';

/// Formats Eazy money values consistently in major currency units.
String formatEazyMoney(Object? value, {String currency = 'NGN'}) {
  final normalized = value?.toString().replaceAll(',', '').trim() ?? '';
  final amount = num.tryParse(normalized);
  if (amount == null || !amount.isFinite) return '—';
  final code = currency.toUpperCase();
  final symbol = code == 'NGN' ? '₦' : '$code ';
  return NumberFormat.currency(
    locale: 'en_NG',
    symbol: symbol,
    decimalDigits: 2,
  ).format(amount);
}
