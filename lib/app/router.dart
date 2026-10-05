import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/auth/auth_controller.dart';
import '../features/auth/auth_page.dart';
import '../features/assist/assist_page.dart';
import '../features/location/location_page.dart';
import '../features/translation/translation_page.dart';
import '../features/notifications/notifications_page.dart';
import '../features/settings/settings_page.dart';
import '../features/security/security_page.dart';
import '../features/home/home_shell.dart';
import '../features/marketplace/cart_page.dart';
import '../features/onboarding/profile_setup_page.dart';
import '../features/onboarding/welcome_page.dart';

GoRouter buildRouter(AuthController auth) => GoRouter(
  initialLocation: '/welcome',
  refreshListenable: auth,
  redirect: (context, state) {
    final path = state.uri.path;
    final signedIn = auth.isSignedIn;
    final onboarding = auth.needsOnboarding;

    if (auth.isRestoring) return null;

    if (!signedIn) {
      if (path == '/welcome' || path == '/auth') return null;
      return '/auth';
    }

    if (onboarding) {
      if (path == '/onboarding') return null;
      return '/onboarding';
    }

    if (path == '/welcome' || path == '/auth' || path == '/onboarding') {
      return '/home';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/welcome', builder: (_, __) => const WelcomePage()),
    GoRoute(path: '/auth', builder: (_, __) => AuthPage(auth: auth)),
    GoRoute(path: '/onboarding', builder: (_, __) => ProfileSetupPage(auth: auth)),
    GoRoute(path: '/cart', builder: (_, __) => const CartPage()),
    GoRoute(path: '/home', builder: (_, __) => HomeShell(auth: auth)),
    GoRoute(path: '/assist', builder: (_, __) => const AssistPage()),
    GoRoute(path: '/translation', builder: (_, __) => const TranslationPage()),
    GoRoute(path: '/location', builder: (_, __) => const LocationPage()),
    GoRoute(path: '/notifications', builder: (_, __) => const NotificationsPage()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
    GoRoute(path: '/security', builder: (_, __) => const SecurityPage()),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('This view is temporarily unavailable.\\n${state.error}'),
      ),
    ),
  ),
);
