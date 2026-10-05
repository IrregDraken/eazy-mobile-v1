import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';
import '../../core/ui/eazy_artwork.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          children: [
            Row(
              children: [
                const _EazyLogo(),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: EazyColors.surface,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: EazyColors.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.public_rounded, size: 14, color: EazyColors.green),
                      SizedBox(width: 6),
                      Text('Everywhere', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const EazyArtwork(kind: EazyArtworkKind.welcome, height: 390),
            const SizedBox(height: 22),
            Text(
              'A global community\nfor people, products\nand possibilities.',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontSize: 34,
                height: 1.02,
                letterSpacing: -1.8,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Connect. Discover. Pay. Chat. Build your world in one social-first experience.',
              style: TextStyle(color: EazyColors.muted, fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 26),
            SizedBox(
              height: 58,
              child: FilledButton.icon(
                onPressed: () => context.go('/auth'),
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                label: const Text('Get started'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 54,
              child: OutlinedButton(
                onPressed: () => context.go('/auth'),
                child: const Text('Sign in'),
              ),
            ),
            const SizedBox(height: 18),
            const Center(
              child: Text(
                'People. Products. Payments. Everywhere.',
                style: TextStyle(color: EazyColors.muted, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EazyLogo extends StatelessWidget {
  const _EazyLogo();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: const TextSpan(
        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -2),
        children: [
          TextSpan(text: 'ea', style: TextStyle(color: EazyColors.ink)),
          TextSpan(text: 'zy', style: TextStyle(color: EazyColors.green)),
        ],
      ),
    );
  }
}
