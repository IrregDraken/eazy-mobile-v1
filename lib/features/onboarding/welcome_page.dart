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
          Image.asset(
            'assets/images/eazy_welcome_hero.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x18030B07),
                  Color(0x12030B07),
                  Color(0x44030B07),
                  Color(0xE8030B07),
                  Color(0xFF030B07),
                ],
                stops: [0, .28, .55, .78, 1],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .24),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .22),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.eco_rounded,
                            size: 15,
                            color: EazyColors.green,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Eco Live',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                    decoration: BoxDecoration(
                      color: const Color(0xD906100B),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .14),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 30,
                          offset: Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: EazyColors.green,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'A living ecosystem\nfor everyday life.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 35,
                            height: .99,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.7,
                          ),
                        ),
                        const SizedBox(height: 13),
                        const Text(
                          'Connect with people, discover what matters, and make everyday life feel simpler in one beautifully connected place.',
                          style: TextStyle(
                            color: Color(0xC9D4E0D9),
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: () => context.go('/auth?mode=register'),
                            icon: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 20,
                            ),
                            label: const Text('Get Started'),
                          ),
                        ),
                        const SizedBox(height: 9),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            onPressed: () => context.go('/auth?mode=login'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: .28),
                              ),
                            ),
                            child: const Text('I Already Have An Account'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Center(
                          child: Text(
                            'People · Products · Possibilities',
                            style: TextStyle(
                              color: Color(0xA8D4E0D9),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .2,
                            ),
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
