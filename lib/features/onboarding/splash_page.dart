import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _wordmarkOpacity;
  late final Animation<Offset> _wordmarkOffset;
  late final Animation<double> _taglineOpacity;
  Timer? _transition;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    _logoScale = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, .72, curve: Curves.easeOutBack),
    );
    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, .28, curve: Curves.easeOut),
    );
    _wordmarkOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(.38, .78, curve: Curves.easeOut),
    );
    _wordmarkOffset = Tween<Offset>(
      begin: const Offset(0, .22),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(.38, .82, curve: Curves.easeOutCubic),
      ),
    );
    _taglineOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(.68, 1, curve: Curves.easeOut),
    );
    _controller.forward();
    _transition = Timer(const Duration(milliseconds: 3100), () {
      if (mounted) context.go('/welcome');
    });
  }

  @override
  void dispose() {
    _transition?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark
        ? const [Color(0xFF031E13), Color(0xFF06100B), Color(0xFF020604)]
        : const [Color(0xFFE5F8EC), Color(0xFFFCFFFD), Color(0xFFDDF5E6)];

    return Scaffold(
      backgroundColor: colors.surface,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: background,
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 190,
                  height: 190,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.scale(
                        scale: .78 + (_logoScale.value * .22),
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.primary.withValues(alpha: .07),
                            boxShadow: [
                              BoxShadow(
                                color: colors.primary.withValues(
                                  alpha: .16 * _logoOpacity.value,
                                ),
                                blurRadius: 54,
                                spreadRadius: 12,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: Image.asset(
                            'assets/images/eazy_logo_mark.png',
                            width: 126,
                            height: 126,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                FadeTransition(
                  opacity: _wordmarkOpacity,
                  child: SlideTransition(
                    position: _wordmarkOffset,
                    child: Text(
                      'Eazy',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 43,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2.8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                FadeTransition(
                  opacity: _taglineOpacity,
                  child: Text(
                    'Your world, made easier.',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 14,
                      letterSpacing: .15,
                    ),
                  ),
                ),
                const SizedBox(height: 38),
                SizedBox(
                  width: 116,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => LinearProgressIndicator(
                        value: _controller.value,
                        minHeight: 3,
                        backgroundColor: colors.primary.withValues(alpha: .13),
                        color: colors.primary,
                      ),
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
