import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/api_client.dart';

class PushRegistrationService {
  PushRegistrationService._();

  static final PushRegistrationService instance = PushRegistrationService._();
  static const _deviceIdKey = 'eazy.push.deviceId';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  StreamSubscription<String>? _tokenRefreshSubscription;
  ApiClient? _api;

  Future<void> start(ApiClient api) async {
    _api = api;
    _tokenRefreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => unawaited(_registerToken(token)),
      onError: (_) {},
    );
    await registerIfAuthorized();
  }

  Future<void> registerIfAuthorized() async {
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) await _registerToken(token);
    } catch (_) {
      // Push registration is best-effort and must never delay sign-in or app startup.
    }
  }

  Future<void> _registerToken(String token) async {
    final api = _api;
    if (api == null || token.isEmpty) return;
    try {
      final response = await api.post(
        'notifications/devices',
        body: {'token': token, 'platform': Platform.isIOS ? 'ios' : 'android'},
        auth: true,
      );
      final deviceId = response['deviceId']?.toString();
      if (deviceId != null && deviceId.isNotEmpty) {
        await _storage.write(key: _deviceIdKey, value: deviceId);
      }
    } catch (_) {
      // A later token refresh, sign-in restore, or explicit opt-in retries registration.
    }
  }

  Future<void> unregister(ApiClient api) async {
    final deviceId = await _storage.read(key: _deviceIdKey);
    try {
      if (deviceId != null && deviceId.isNotEmpty) {
        await api
            .delete('notifications/devices/$deviceId', auth: true)
            .timeout(const Duration(seconds: 2));
      }
    } catch (_) {
      // Deleting the FCM token below also prevents this installation receiving new pushes.
    } finally {
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}
      await _storage.delete(key: _deviceIdKey);
      _api = null;
    }
  }
}
