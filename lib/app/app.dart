import 'package:flutter/material.dart';

import '../core/auth/auth_controller.dart';
import 'router.dart';
import 'theme/eazy_theme.dart';

class EazyApp extends StatelessWidget {
  const EazyApp({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) => MaterialApp.router(
        title: 'Eazy',
        debugShowCheckedModeBanner: false,
        theme: EazyTheme.light(),
        darkTheme: EazyTheme.dark(),
        themeMode: ThemeMode.dark,
        routerConfig: buildRouter(auth),
      ),
    );
  }
}
