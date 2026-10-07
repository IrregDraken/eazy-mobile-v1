import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/eazy_theme.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/eazy_welcome_hero.png', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Color(0x2206100B),
                  Color(0x8806100B),
                  Color(0xE806100B),
                  EazyColors.canvas,
                ],
                stops: [.12, .42, .72, 1],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _EazyLogo(),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: EazyColors.canvas.withValues(alpha: .58),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .16),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.public_rounded,
                              size: 14,
                              color: EazyColors.green,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Everywhere',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const Text(
                    'Your Life,\nMade Easier',
                    style: TextStyle(
                      fontSize: 42,
                      height: .98,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -2.3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Connect with people, discover what matters, and make everyday life feel simpler in one beautifully connected place.',
                    style: TextStyle(
                      color: EazyColors.muted,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton.icon(
                      onPressed: () => context.go('/auth?mode=register'),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                      label: const Text('Get Started'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton(
                      onPressed: () => context.go('/auth?mode=login'),
                      child: const Text('I Already Have An Account'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Center(
                    child: Text(
                      'People. Products. Possibilities.',
                      style: TextStyle(
                        color: EazyColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
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

class _EazyLogo extends StatelessWidget {
  const _EazyLogo();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset('assets/images/eazy_logo_mark.png', width: 28, height: 32),
      const SizedBox(width: 7),
      const Text(
        'Eazy',
        style: TextStyle(
          fontSize: 29,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.8,
          color: EazyColors.ink,
        ),
      ),
    ],
  );
}
