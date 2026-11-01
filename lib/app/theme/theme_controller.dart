import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final ValueNotifier<ThemeMode> eazyThemeMode = ValueNotifier<ThemeMode>(
  ThemeMode.system,
);

const _themeStorage = FlutterSecureStorage();
const _themeStorageKey = 'eazy.theme.mode';

Future<void> restoreEazyThemeMode() async {
  try {
    final saved = await _themeStorage.read(key: _themeStorageKey);
    eazyThemeMode.value = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  } catch (_) {
    // Keep the safe white default if local storage is unavailable.
  }
}

Future<void> setEazyThemeMode(ThemeMode mode) async {
  final normalized = mode;
  eazyThemeMode.value = normalized;
  try {
    await _themeStorage.write(
      key: _themeStorageKey,
      value: switch (normalized) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        _ => 'system',
      },
    );
  } catch (_) {
    // The in-memory choice still applies for this session.
  }
}
