import 'dart:async';

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
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _rotation;
  late final Animation<double> _fade;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..forward();
    _scale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, .62, curve: Curves.easeOutBack),
    );
    _rotation = Tween<double>(begin: -.35, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, .7, curve: Curves.easeOutCubic),
      ),
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(.35, 1, curve: Curves.easeIn),
    );
    _timer = Timer(const Duration(milliseconds: 2300), () {
      if (mounted) context.go('/welcome');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF071B11), EazyColors.canvas, Color(0xFF020604)],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder:
                (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.rotate(
                      angle: _rotation.value,
                      child: Transform.scale(
                        scale: .72 + (_scale.value * .28),
                        child: const _SplashMark(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FadeTransition(
                      opacity: _fade,
                      child: const Text(
                        'eazy',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -3,
                          color: EazyColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FadeTransition(
                      opacity: _fade,
                      child: const Text(
                        'Your life, made easier.',
                        style: TextStyle(
                          color: EazyColors.muted,
                          fontSize: 13,
                          letterSpacing: .2,
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

class _SplashMark extends StatelessWidget {
  const _SplashMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [EazyColors.mint, EazyColors.green, EazyColors.greenDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: EazyColors.green.withValues(alpha: .42),
            blurRadius: 34,
            spreadRadius: 6,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 62,
          height: 62,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: EazyColors.canvas,
          ),
          child: const Center(
            child: Text(
              'e',
              style: TextStyle(
                fontSize: 42,
                height: .9,
                fontWeight: FontWeight.w900,
                color: EazyColors.green,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
