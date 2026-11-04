import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import 'router.dart';
import 'theme/eazy_theme.dart';
import 'theme/theme_controller.dart';

class EazyApp extends StatefulWidget {
  const EazyApp({super.key, required this.auth});

  final AuthController auth;

  @override
  State<EazyApp> createState() => _EazyAppState();
}

class _EazyAppState extends State<EazyApp> {
  late final GoRouter _router;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<RemoteMessage>? _foregroundMessages;
  StreamSubscription<RemoteMessage>? _openedMessages;

  @override
  void initState() {
    super.initState();
    restoreEazyThemeMode();
    _router = buildRouter(
      widget.auth,
      observers: [
        _SnackBarNavigationObserver(
          () => _messengerKey.currentState?.removeCurrentSnackBar(),
        ),
      ],
    );
    widget.auth.addListener(_attachMessagingListeners);
    _attachMessagingListeners();
  }

  void _attachMessagingListeners() {
    if (!widget.auth.firebaseReady || _foregroundMessages != null) return;
    _foregroundMessages = FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title ?? 'Eazy notification';
      final body = message.notification?.body ?? 'You have a new update.';
      _messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => _openNotificationMessage(message),
            ),
          ),
        );
    });
    _openedMessages = FirebaseMessaging.onMessageOpenedApp.listen(_openNotificationMessage);
    unawaited(
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null) _openNotificationMessage(message);
      }).catchError((_) {}),
    );
  }

  void _openNotificationMessage(RemoteMessage message) {
    final deepLink = message.data['deepLink']?.toString();
    if (deepLink != null && deepLink.isNotEmpty) {
      _router.go('/notifications?deepLink=${Uri.encodeQueryComponent(deepLink)}');
    } else {
      _router.push('/notifications');
    }
  }

  @override
  void dispose() {
    widget.auth.removeListener(_attachMessagingListeners);
    unawaited(_foregroundMessages?.cancel());
    unawaited(_openedMessages?.cancel());
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: eazyThemeMode,
      builder:
          (context, mode, _) => MaterialApp.router(
            title: 'Eazy',
            debugShowCheckedModeBanner: false,
            theme: EazyTheme.light(),
            darkTheme: EazyTheme.dark(),
            themeMode: mode,
            routerConfig: _router,
            scaffoldMessengerKey: _messengerKey,
            builder: (context, child) {
              final brightness = Theme.of(context).brightness;
              final dark = brightness == Brightness.dark;
              final semantic = Theme.of(context).extension<EazySemanticColors>()!;
              final overlayStyle = SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness:
                    dark ? Brightness.light : Brightness.dark,
                statusBarBrightness:
                    dark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: semantic.background,
                systemNavigationBarIconBrightness:
                    dark ? Brightness.light : Brightness.dark,
                systemNavigationBarDividerColor: semantic.border,
                systemStatusBarContrastEnforced: false,
                systemNavigationBarContrastEnforced: false,
              );
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: overlayStyle,
                child: child ?? const SizedBox.shrink(),
              );
            },
          ),
    );
  }
}

class _SnackBarNavigationObserver extends NavigatorObserver {
  _SnackBarNavigationObserver(this.onNavigation);

  final VoidCallback onNavigation;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    onNavigation();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    onNavigation();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    onNavigation();
  }
}
