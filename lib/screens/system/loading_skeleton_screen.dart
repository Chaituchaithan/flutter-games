import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Animated shimmer skeleton block. Drop into any loading state to stand in for
/// content that hasn't arrived yet (mockup `loading`). Presentation-only.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
    this.shape = BoxShape.rectangle,
  });

  final double? width;
  final double height;
  final double radius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final t = _ShimmerScope.of(context);
    // Sweep a bright band across a dim base using the ancestor's phase [0,1].
    return SizedBox(
      width: shape == BoxShape.circle ? height : width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: shape,
          borderRadius: shape == BoxShape.circle ? null : BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment(-1 + 2 * t - 0.6, 0),
            end: Alignment(-1 + 2 * t + 0.6, 0),
            colors: const [
              Color(0x14FFFFFF),
              Color(0x2EFFFFFF),
              Color(0x14FFFFFF),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Wrap a subtree so every [SkeletonBox] inside shimmers in sync.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400)) // mockup auraShimmer 1.4s
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => _ShimmerScope(phase: _c.value, child: widget.child),
    );
  }
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({required this.phase, required super.child});
  final double phase;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.phase ?? 0.5;

  @override
  bool updateShouldNotify(_ShimmerScope oldWidget) => oldWidget.phase != phase;
}

/// A full loading screen: a Home-shaped skeleton under the shimmer.
class LoadingSkeletonScreen extends StatelessWidget {
  const LoadingSkeletonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      body: Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            // HUD row: avatar + name lines + currency pills.
            Row(
              children: [
                const SkeletonBox(height: 46, shape: BoxShape.circle),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(width: 120, height: 14),
                    SizedBox(height: 8),
                    SkeletonBox(width: 80, height: 11),
                  ],
                ),
                const Spacer(),
                const SkeletonBox(width: 58, height: 30, radius: 14),
                const SizedBox(width: 8),
                const SkeletonBox(width: 58, height: 30, radius: 14),
              ],
            ),
            const SizedBox(height: 22),
            // Hero banner.
            const SkeletonBox(height: 150, radius: 24),
            const SizedBox(height: 22),
            const SkeletonBox(width: 140, height: 14),
            const SizedBox(height: 14),
            // 3-column game tiles.
            Row(
              children: const [
                Expanded(child: SkeletonBox(height: 96, radius: 18)),
                SizedBox(width: 12),
                Expanded(child: SkeletonBox(height: 96, radius: 18)),
                SizedBox(width: 12),
                Expanded(child: SkeletonBox(height: 96, radius: 18)),
              ],
            ),
            const SizedBox(height: 22),
            const SkeletonBox(width: 120, height: 14),
            const SizedBox(height: 14),
            for (var i = 0; i < 3; i++) ...[
              const _SkeletonRow(),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AuraGlass.decoration(radius: 16),
      child: Row(
        children: [
          const SkeletonBox(height: 40, shape: BoxShape.circle),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SkeletonBox(width: 130, height: 13),
              SizedBox(height: 8),
              SkeletonBox(width: 90, height: 10),
            ],
          ),
          const Spacer(),
          const SkeletonBox(width: 46, height: 22, radius: 11),
        ],
      ),
    );
  }
}
