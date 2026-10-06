import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/auth/auth_controller.dart';
import 'core/network/api_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  final auth = AuthController(api: api, firebaseReady: false);
  runApp(EazyApp(auth: auth));
  unawaited(_bootstrap(auth));
}

Future<void> _bootstrap(AuthController auth) async {
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (_) {
    // Keep the onboarding UI available and surface a useful auth error if needed.
  }
  auth.setFirebaseReady(firebaseReady);
  await auth.restore();
}
