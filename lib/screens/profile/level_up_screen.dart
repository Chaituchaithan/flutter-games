import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:snakeladder/widgets/aura.dart';

/// Show the level-up celebration as a full-screen tap-to-dismiss overlay
/// (mockup `levelUp`). Levels are per game (08-progress-and-history.md):
/// [gameName] names the game. [onReward] adds a "Claim your level reward"
/// button (the `level_up` bonus game, 07-rewards.md §5); the overlay closes
/// first, then it runs.
Future<void> showLevelUp(BuildContext context, {int level = 8, String? gameName, String? rewardLabel, VoidCallback? onReward}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Level up',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => _LevelUpOverlay(
      level: level,
      gameName: gameName,
      rewardLabel: rewardLabel,
      onReward: onReward == null
          ? null
          : () {
              Navigator.of(ctx).maybePop();
              onReward();
            },
    ),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: Transform.scale(scale: 0.96 + 0.04 * anim.value, child: child),
    ),
  );
}

class _LevelUpOverlay extends StatelessWidget {
  const _LevelUpOverlay({required this.level, this.gameName, this.rewardLabel, this.onReward});
  final int level;
  final String? gameName;
  final String? rewardLabel;
  final VoidCallback? onReward;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.2),
              radius: 0.9,
              colors: [Color(0x8C8B5CF6), Color(0xEB05040C)],
              stops: [0.0, 0.7],
            ),
          ),
          child: Center(
            child: _LevelUpContent(level: level, gameName: gameName, rewardLabel: rewardLabel, onReward: onReward),
          ),
        ),
      ),
    );
  }
}

/// Level-up celebration content. Routed fallback wraps this in [LevelUpScreen].
class _LevelUpContent extends StatelessWidget {
  const _LevelUpContent({this.level = 8, this.gameName, this.rewardLabel, this.onReward});
  final int level;
  final String? gameName;
  final String? rewardLabel;
  final VoidCallback? onReward;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'LEVEL UP',
              style: TextStyle(
                color: AuraColors.goldLight,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 20),
            _LevelBadge(level: level, size: 160),
            const SizedBox(height: 26),
            Text('Level $level reached',
                style: AuraText.headline.copyWith(fontSize: 32), textAlign: TextAlign.center),
            if (gameName != null) ...[
              const SizedBox(height: 8),
              Text(
                'in $gameName',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14.5),
              ),
            ],
            if (onReward != null) ...[
              const SizedBox(height: 24),
              _RewardTile(
                glyph: const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 24),
                amount: rewardLabel ?? 'Level reward',
                label: 'A free bonus game',
              ),
              const SizedBox(height: 14),
              GradientButton(label: 'Claim your level reward', onPressed: onReward!),
            ],
            const SizedBox(height: 26),
            Text(
              'Tap anywhere to continue',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Routed fallback (kept for tests / deep-links).
class LevelUpScreen extends StatelessWidget {
  const LevelUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: const Center(child: _LevelUpContent()),
      ),
    );
  }
}

/// A glowing dark disc with the level number and a brand-gradient ring + rays.
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, required this.size});
  final int level;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size(size, size), painter: _RaysPainter()),
          // Gradient ring.
          Container(
            width: size * 0.72,
            height: size * 0.72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AuraGradients.brand,
              boxShadow: [
                BoxShadow(
                  color: AuraColors.brandPink.withValues(alpha: 0.55),
                  blurRadius: 40,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          // Dark inner disc.
          Container(
            width: size * 0.60,
            height: size * 0.60,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF0A0812),
            ),
            alignment: Alignment.center,
            child: Text(
              '$level',
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: Colors.white,
                fontSize: size * 0.30,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RaysPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..color = AuraColors.brandPurple.withValues(alpha: 0.18)
      ..strokeWidth = 2;
    const rays = 12;
    for (var i = 0; i < rays; i++) {
      final a = (math.pi * 2 / rays) * i;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * (size.width * 0.40),
        c + Offset(math.cos(a), math.sin(a)) * (size.width * 0.50),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({required this.glyph, required this.amount, required this.label});
  final Widget glyph;
  final String amount;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 24, child: Center(child: glyph)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 10.5)),
        ],
      ),
    );
  }
}
