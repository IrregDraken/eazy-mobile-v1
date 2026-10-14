import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final ValueNotifier<ThemeMode> eazyThemeMode = ValueNotifier<ThemeMode>(
  ThemeMode.light,
);

const _themeStorage = FlutterSecureStorage();
const _themeStorageKey = 'eazy.theme.mode';

Future<void> restoreEazyThemeMode() async {
  try {
    final saved = await _themeStorage.read(key: _themeStorageKey);
    if (saved == 'dark') eazyThemeMode.value = ThemeMode.dark;
  } catch (_) {
    // Keep the safe white default if local storage is unavailable.
  }
}

Future<void> setEazyThemeMode(ThemeMode mode) async {
  final normalized = mode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
  eazyThemeMode.value = normalized;
  try {
    await _themeStorage.write(
      key: _themeStorageKey,
      value: normalized == ThemeMode.dark ? 'dark' : 'light',
    );
  } catch (_) {
    // The in-memory choice still applies for this session.
  }
}
