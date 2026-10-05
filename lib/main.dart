import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/auth/auth_controller.dart';
import 'core/network/api_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (_) {
    // UI remains launchable until native Firebase configuration is supplied.
  }

  final api = ApiClient();
  final auth = AuthController(api: api, firebaseReady: firebaseReady);
  await auth.restore();

  runApp(EazyApp(auth: auth));
}
