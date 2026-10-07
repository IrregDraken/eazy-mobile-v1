import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/eazy_theme.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? Colors.white : const Color(0xFF10231A);
    final muted = dark ? const Color(0xFFD0DDD5) : const Color(0xFF4D6256);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/eazy_onboarding_hero.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors:
                    dark
                        ? const [
                          Color(0x00030B07),
                          Color(0x10030B07),
                          Color(0xB8071D12),
                          Color(0xF504110B),
                        ]
                        : const [
                          Color(0x00030B07),
                          Color(0x12030B07),
                          Color(0xB8DFF4E8),
                          Color(0xF3F3FBF6),
                        ],
                stops: const [0, .35, .70, 1],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _BrandLockup(dark: dark),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your world, made easier.',
                          style: TextStyle(
                            color: foreground,
                            fontSize: 32,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.3,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          'Connect with people, discover what matters, and move through everyday life with Eazy.',
                          style: TextStyle(
                            color: muted,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Center(child: _PageDots()),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: () => context.go('/auth?mode=register'),
                            icon: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 19,
                            ),
                            label: const Text('GET STARTED'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: TextButton(
                            onPressed: () => context.go('/auth?mode=login'),
                            style: TextButton.styleFrom(
                              foregroundColor:
                                  dark ? Colors.white : EazyColors.greenDeep,
                            ),
                            child: const Text('I ALREADY HAVE AN ACCOUNT'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          'assets/images/eazy_app_icon.png',
          width: 30,
          height: 30,
        ),
      ),
      const SizedBox(width: 8),
      Text(
        'Eazy',
        style: TextStyle(
          color: dark ? Colors.white : const Color(0xFF10231A),
          fontSize: 24,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.2,
        ),
      ),
    ],
  );
}

class _PageDots extends StatelessWidget {
  const _PageDots();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 22,
        height: 5,
        decoration: BoxDecoration(
          color: EazyColors.green,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      const SizedBox(width: 5),
      ...List.generate(
        2,
        (_) => Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: EazyColors.green.withValues(alpha: .38),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    ],
  );
}
