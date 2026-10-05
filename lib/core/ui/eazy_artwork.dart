import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';

enum EazyArtworkKind { welcome, signIn, createAccount, verify }

class EazyArtwork extends StatelessWidget {
  const EazyArtwork({super.key, required this.kind, this.height = 250});
  final EazyArtworkKind kind;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(EazyRadius.xl),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: EazyColors.surface,
          border: Border.all(color: EazyColors.border),
          borderRadius: BorderRadius.circular(EazyRadius.xl),
        ),
        child: CustomPaint(
          painter: _EazyArtworkPainter(kind),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: _ArtworkCaption(kind: kind),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtworkCaption extends StatelessWidget {
  const _ArtworkCaption({required this.kind});
  final EazyArtworkKind kind;

  @override
  Widget build(BuildContext context) {
    final data = switch (kind) {
      EazyArtworkKind.welcome => ('More than just an app', 'Connect, shop, pay and explore.'),
      EazyArtworkKind.signIn => ('Welcome back', 'Everything you need, one Eazy.'),
      EazyArtworkKind.createAccount => ('Create your Eazy', 'One account. Every possibility.'),
      EazyArtworkKind.verify => ('Verify your account', 'A small step before everything opens up.'),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EazyColors.canvas.withValues(alpha: .68),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EazyColors.border.withValues(alpha: .72)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data.$1, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -.5)),
          const SizedBox(height: 4),
          Text(data.$2, style: const TextStyle(color: EazyColors.muted, fontSize: 12, height: 1.35)),
        ],
      ),
    );
  }
}

class _EazyArtworkPainter extends CustomPainter {
  _EazyArtworkPainter(this.kind);
  final EazyArtworkKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()..shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF07150E), Color(0xFF10271A), Color(0xFF020704)],
    ).createShader(rect);
    canvas.drawRect(rect, bg);

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          EazyColors.green.withValues(alpha: .48),
          EazyColors.greenDeep.withValues(alpha: .16),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * .78, size.height * .24),
        radius: size.width * .62,
      ));
    canvas.drawCircle(
      Offset(size.width * .78, size.height * .24),
      size.width * .62,
      glow,
    );

    final globe = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.25, -.3),
        radius: 1,
        colors: [EazyColors.mint, EazyColors.greenDeep, const Color(0xFF07130C)],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * .68, size.height * .40),
        radius: size.width * .30,
      ));
    canvas.drawCircle(
      Offset(size.width * .68, size.height * .40),
      size.width * .30,
      globe,
    );

    final ring = Paint()
      ..color = EazyColors.green.withValues(alpha: .48)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    for (var i = 0; i < 3; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * .68, size.height * .40),
          width: size.width * (.48 + i * .08),
          height: size.width * (.18 + i * .03),
        ),
        ring,
      );
    }

    final seed = switch (kind) {
      EazyArtworkKind.welcome => 1,
      EazyArtworkKind.signIn => 2,
      EazyArtworkKind.createAccount => 3,
      EazyArtworkKind.verify => 4,
    };
    final random = math.Random(seed);
    for (var i = 0; i < 9; i++) {
      final x = size.width * (.08 + random.nextDouble() * .84);
      final y = size.height * (.08 + random.nextDouble() * .52);
      final r = 3 + random.nextDouble() * 8;
      final p = Paint()..color = EazyColors.green.withValues(alpha: .12 + random.nextDouble() * .18);
      canvas.drawCircle(Offset(x, y), r, p);
    }

    _glassCard(canvas, Offset(size.width * .09, size.height * .16), const Size(76, 58), Icons.people_alt_rounded);
    _glassCard(canvas, Offset(size.width * .62, size.height * .10), const Size(78, 58), switch (kind) {
      EazyArtworkKind.verify => Icons.verified_rounded,
      EazyArtworkKind.signIn => Icons.lock_rounded,
      _ => Icons.shopping_bag_rounded,
    });
    _glassCard(canvas, Offset(size.width * .78, size.height * .52), const Size(70, 54), switch (kind) {
      EazyArtworkKind.createAccount => Icons.wallet_rounded,
      EazyArtworkKind.verify => Icons.mark_email_read_rounded,
      _ => Icons.chat_bubble_rounded,
    });
  }

  void _glassCard(Canvas canvas, Offset offset, Size size, IconData icon) {
    final r = RRect.fromRectAndRadius(offset & size, const Radius.circular(17));
    final fill = Paint()..color = EazyColors.surfaceRaised.withValues(alpha: .72);
    canvas.drawRRect(r, fill);
    final border = Paint()
      ..color = EazyColors.green.withValues(alpha: .30)
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(r, border);
    final tp = TextPainter(
      text: TextSpan(text: String.fromCharCode(icon.codePoint), style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: EazyColors.green,
        fontSize: 25,
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset + Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(covariant _EazyArtworkPainter oldDelegate) => oldDelegate.kind != kind;
}
