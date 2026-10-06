import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import 'router.dart';
import 'theme/eazy_theme.dart';

class EazyApp extends StatefulWidget {
  const EazyApp({super.key, required this.auth});

  final AuthController auth;

  @override
  State<EazyApp> createState() => _EazyAppState();
}

class _EazyAppState extends State<EazyApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = buildRouter(widget.auth);
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Eazy',
      debugShowCheckedModeBanner: false,
      theme: EazyTheme.light(),
      darkTheme: EazyTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: _router,
    );
  }
}
