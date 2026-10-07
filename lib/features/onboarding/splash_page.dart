import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/eazy_theme.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  Timer? transition;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    transition = Timer(const Duration(milliseconds: 3000), () {
      if (mounted) context.go('/welcome');
    });
  }

  @override
  void dispose() {
    transition?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? EazyColors.canvas : const Color(0xFFF3FBF6);
    final foreground = dark ? EazyColors.ink : const Color(0xFF10231A);
    final muted = dark ? EazyColors.muted : const Color(0xFF5B6C63);

    return Scaffold(
      backgroundColor: background,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors:
                dark
                    ? const [
                      Color(0xFF031E13),
                      EazyColors.canvas,
                      Color(0xFF020604),
                    ]
                    : const [
                      Color(0xFFE1F8EA),
                      Color(0xFFF8FFFA),
                      Color(0xFFD5F4E2),
                    ],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: controller,
            builder:
                (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale:
                          .98 + math.sin(controller.value * math.pi * 2) * .025,
                      child: Container(
                        width: 116,
                        height: 116,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: dark ? const Color(0xFF031E13) : Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: EazyColors.green.withValues(alpha: .65),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: EazyColors.green.withValues(alpha: .25),
                              blurRadius: 28,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: Image.asset('assets/images/eazy_app_icon.png'),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Eazy',
                      style: TextStyle(
                        color: foreground,
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Your world, made easier.',
                      style: TextStyle(color: muted, fontSize: 14),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: 170,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: null,
                          minHeight: 4,
                          backgroundColor: EazyColors.green.withValues(
                            alpha: .16,
                          ),
                          color: EazyColors.green,
                        ),
                      ),
                    ),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}
