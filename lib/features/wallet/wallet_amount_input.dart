/// Normalizes user-entered major currency units to the API's two-decimal format.
String? normalizeWalletAmountInput(String input) {
  final value = input.replaceAll(',', '').trim();
  if (!RegExp(r'^(?:0|[1-9][0-9]{0,17})(?:\.[0-9]{1,2})?$').hasMatch(value)) {
    return null;
  }
  final parts = value.split('.');
  final fraction = parts.length == 2 ? parts[1].padRight(2, '0') : '00';
  final normalized = '${parts[0]}.$fraction';
  if (!RegExp(r'^(?:0|[1-9][0-9]{0,17})\.[0-9]{2}$').hasMatch(normalized)) {
    return null;
  }
  if (normalized == '0.00') return null;
  return normalized;
}
