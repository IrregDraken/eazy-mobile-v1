import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/auth/auth_controller.dart';
import '../features/auth/auth_page.dart';
import '../features/assist/assist_page.dart';
import '../features/location/location_page.dart';
import '../features/translation/translation_page.dart';
import '../features/notifications/notifications_page.dart';
import '../features/posts/post_detail_page.dart';
import '../features/settings/settings_page.dart';
import '../features/security/security_page.dart';
import '../features/settings/account_settings_page.dart';
import '../features/support/support_page.dart';
import '../features/security/blocks_page.dart';
import '../features/home/home_shell.dart';
import '../features/profile/profile_page.dart';
import '../features/marketplace/cart_page.dart';
import '../features/marketplace/checkout_page.dart';
import '../features/marketplace/orders_page.dart';
import '../features/marketplace/seller_orders_page.dart';
import '../features/marketplace/seller_payables_page.dart';
import '../features/marketplace/seller_reviews_page.dart';
import '../features/marketplace/seller_storefront_page.dart';
import '../features/marketplace/seller_products_page.dart';
import '../features/marketplace/marketplace_search_page.dart';
import '../features/marketplace/product_route_page.dart';
import '../features/marketplace/seller_setup_page.dart';
import '../features/onboarding/profile_setup_page.dart';
import '../features/onboarding/discovery_page.dart';
import '../features/onboarding/splash_page.dart';
import '../features/onboarding/welcome_page.dart';

GoRouter buildRouter(
  AuthController auth, {
  List<NavigatorObserver> observers = const [],
}) => GoRouter(
  observers: observers,
  initialLocation: '/splash',
  refreshListenable: auth,
  redirect: (context, state) {
    final path = state.uri.path;
    final signedIn = auth.isSignedIn;
    final onboarding = auth.needsOnboarding;

    if (auth.state == EazyAuthState.fatalStartupError) {
      return path == '/startup-error' ? null : '/startup-error';
    }
    if (path == '/startup-error') {
      return auth.isRestoring
          ? '/splash'
          : signedIn
              ? (onboarding ? '/onboarding' : '/home')
              : '/auth';
    }
    // While session restoration is pending, keep the branded splash visible.
    // Never allow a welcome/login route to flash before backend validation.
    if (auth.isRestoring) {
      return path == '/splash' ? null : '/splash';
    }

    if (!signedIn) {
      if (path == '/splash') return '/welcome';
      if (path == '/welcome' || path == '/auth') return null;
      return '/welcome';
    }

    if (onboarding) {
      if (path == '/onboarding') return null;
      return '/onboarding';
    }

    if (path == '/splash' ||
        path == '/welcome' ||
        path == '/auth' ||
        path == '/onboarding') {
      return '/home';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/splash', builder: (_, _) => const SplashPage()),
    GoRoute(
      path: '/startup-error',
      builder: (_, _) => _StartupErrorPage(auth: auth),
    ),
    GoRoute(path: '/welcome', builder: (_, _) => const WelcomePage()),
    GoRoute(
      path: '/auth',
      builder:
          (_, state) => AuthPage(
            auth: auth,
            initialRegister: state.uri.queryParameters['mode'] == 'register',
          ),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (_, _) => ProfileSetupPage(auth: auth),
    ),
    GoRoute(path: '/discovery', builder: (_, _) => const DiscoveryPage()),
    GoRoute(path: '/cart', builder: (_, _) => const CartPage()),
    GoRoute(path: '/checkout', builder: (_, _) => const CheckoutPage()),
    GoRoute(path: '/orders', builder: (_, _) => const OrdersPage()),
    GoRoute(path: '/seller/orders', builder: (_, _) => const SellerOrdersPage()),
    GoRoute(path: '/seller/payables', builder: (_, _) => const SellerPayablesPage()),
    GoRoute(path: '/seller/products', builder: (_, _) => const SellerProductsPage()),
    GoRoute(path: '/seller-reviews/:username', builder: (_, state) => SellerReviewsPage(username: state.pathParameters['username']!)),
    GoRoute(path: '/store/:slug', builder: (_, state) => SellerStorefrontPage(slug: state.pathParameters['slug']!)),
    GoRoute(path: '/marketplace/search', builder: (_, state) => MarketplaceSearchPage(query: state.uri.queryParameters['q'] ?? '')),
    GoRoute(path: '/orders/:id', builder: (_, state) => OrderDetailPage(orderId: state.pathParameters['id']!)),
    GoRoute(path: '/product/:id', builder: (_, state) => ProductRoutePage(productId: state.pathParameters['id']!)),
    GoRoute(path: '/p/:id', builder: (_, state) => PostDetailPage(postId: state.pathParameters['id']!)),
    GoRoute(path: '/seller', builder: (_, _) => const SellerSetupPage()),
    GoRoute(
      path: '/home',
      builder:
          (_, state) => HomeShell(
            auth: auth,
            initialTab: state.uri.queryParameters['tab'],
            initialAction: state.uri.queryParameters['action'],
            initialUsername: state.uri.queryParameters['username'],
            initialConversationId: state.uri.queryParameters['conversationId'],
          ),
    ),
    GoRoute(
      path: '/u/:username',
      builder: (_, state) => ProfilePage(
        auth: auth,
        username: state.pathParameters['username'],
      ),
    ),
    GoRoute(
      path: '/profile/:username',
      builder:
          (_, state) => ProfilePage(
            auth: auth,
            username: state.pathParameters['username'],
          ),
    ),
    GoRoute(path: '/assist', builder: (_, _) => const AssistPage()),
    GoRoute(path: '/translation', builder: (_, _) => const TranslationPage()),
    GoRoute(path: '/location', builder: (_, _) => const LocationPage()),
    GoRoute(
      path: '/notifications',
      builder: (_, state) => NotificationsPage(initialDeepLink: state.uri.queryParameters['deepLink']),
    ),
    GoRoute(path: '/settings', builder: (_, _) => SettingsPage(auth: auth)),
    GoRoute(path: '/account-settings', builder: (_, _) => AccountSettingsPage(auth: auth)),
    GoRoute(path: '/security', builder: (_, _) => SecurityPage(auth: auth)),
    GoRoute(path: '/support', builder: (_, _) => const SupportPage()),
    GoRoute(path: '/blocks', builder: (_, _) => const BlocksPage()),
  ],
  errorBuilder:
      (context, state) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'This view is temporarily unavailable.\\n${state.error}',
            ),
          ),
        ),
      ),
);


class _StartupErrorPage extends StatelessWidget {
  const _StartupErrorPage({required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_clock_outlined,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Eazy couldn't finish starting",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    auth.startupError ??
                        'Your session could not be verified. Please try again.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: auth.isRestoring ? null : auth.retryStartup,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
