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
  int stage = 0;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    Timer.periodic(const Duration(milliseconds: 780), (timer) {
      if (!mounted) return timer.cancel();
      if (stage < 3) setState(() => stage++);
      if (stage == 3) timer.cancel();
    });
    transition = Timer(const Duration(milliseconds: 3900), () {
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
    final copy =
        [
          'More than an app.',
          'More than an app.',
          'Getting things ready for you…',
          'People. Products. Payments. In one place.',
        ][stage];
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF031E13), EazyColors.canvas, Color(0xFF020604)],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: controller,
            builder:
                (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 178,
                      height: 178,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.rotate(
                            angle: controller.value * math.pi * 2,
                            child: Container(
                              width: 166,
                              height: 166,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: EazyColors.green.withValues(
                                    alpha: .26,
                                  ),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: EazyColors.green.withValues(
                                      alpha: .14,
                                    ),
                                    blurRadius: 28,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Transform.scale(
                            scale:
                                .92 +
                                math.sin(controller.value * math.pi * 2) * .06,
                            child: Image.asset(
                              'assets/images/eazy_logo_mark.png',
                              width: 88,
                              height: 100,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Eazy',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -3,
                        color: EazyColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      child: Text(
                        copy,
                        key: ValueKey(copy),
                        style: const TextStyle(
                          color: EazyColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 170,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: (stage + 1) / 4,
                          minHeight: 4,
                          backgroundColor: EazyColors.border,
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
