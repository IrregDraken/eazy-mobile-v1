import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/eazy_theme.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Stack(
        children: [
          const Positioned.fill(child: _WelcomeBackdrop()),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _BrandMark(),
                const Spacer(),
                Text('Everything\nyou need.\nOne Eazy.', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, height: .98, letterSpacing: -1.5)),
                const SizedBox(height: 18),
                const Text('Connect. Discover. Pay. Chat.\nBuilt into one social-first experience.', style: TextStyle(color: EazyColors.muted, fontSize: 16, height: 1.5)),
                const SizedBox(height: 30),
                SizedBox(width: double.infinity, height: 58, child: FilledButton(onPressed: () => context.go('/auth'), child: const Text('Get started', style: TextStyle(fontWeight: FontWeight.w800)))),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, height: 56, child: OutlinedButton(onPressed: () => context.go('/auth'), child: const Text('I already have an account'))),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 42, height: 42, decoration: BoxDecoration(color: EazyColors.green, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.bolt_rounded, color: EazyColors.canvas)),
    const SizedBox(width: 12),
    const Text('eazy', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -1)),
  ]);
}

class _WelcomeBackdrop extends StatelessWidget {
  const _WelcomeBackdrop();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _BackdropPainter());
}

class _BackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()..shader = RadialGradient(colors: [EazyColors.green.withValues(alpha: .22), Colors.transparent]).createShader(Rect.fromCircle(center: Offset(size.width * .75, size.height * .18), radius: size.width * .72));
    canvas.drawCircle(Offset(size.width * .75, size.height * .18), size.width * .72, glow);
    final line = Paint()..color = EazyColors.border.withValues(alpha: .55)..style = PaintingStyle.stroke..strokeWidth = 1;
    for (var i = -2; i < 8; i++) {
      final path = Path()..moveTo(size.width * .45 + i * 58, 0)..quadraticBezierTo(size.width * .15, size.height * .38, size.width * .9, size.height * .72)..quadraticBezierTo(size.width * .65, size.height * .9, size.width * .2, size.height);
      canvas.drawPath(path, line);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
