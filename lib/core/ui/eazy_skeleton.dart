import 'package:flutter/material.dart';
import '../../app/theme/eazy_theme.dart';

/// Eazy-branded shimmer primitives for content that is still loading.
class EazySkeletonBox extends StatelessWidget {
  const EazySkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 10,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => _EazyShimmer(
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: EazyColors.surfaceRaised,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: EazyColors.border.withValues(alpha: .7)),
      ),
    ),
  );
}

class EazySkeletonCircle extends StatelessWidget {
  const EazySkeletonCircle({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => EazySkeletonBox(
    width: size,
    height: size,
    radius: size / 2,
  );
}

class EazyProfileGridSkeleton extends StatelessWidget {
  const EazyProfileGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.all(2),
    sliver: SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (context, index) => const EazySkeletonBox(radius: 4),
        childCount: 9,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 1,
      ),
    ),
  );
}

class _EazyShimmer extends StatefulWidget {
  const _EazyShimmer({required this.child});
  final Widget child;

  @override
  State<_EazyShimmer> createState() => _EazyShimmerState();
}

class _EazyShimmerState extends State<_EazyShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) => ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) {
        final progress = _controller.value;
        final start = -1.0 + (progress * 3);
        return LinearGradient(
          begin: Alignment(start - .7, 0),
          end: Alignment(start + .7, 0),
          colors: const [
            Color(0xFF102119),
            Color(0xFF1C3B2B),
            Color(0xFF48F59A),
            Color(0xFF1C3B2B),
            Color(0xFF102119),
          ],
          stops: const [0, .32, .5, .68, 1],
        ).createShader(bounds);
      },
      child: child,
    ),
  );
}
