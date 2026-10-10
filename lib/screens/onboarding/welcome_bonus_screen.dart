import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../widgets/aura.dart';

/// Welcome bonus — starter pack. See docs/DESIGN_SPEC.md.
class WelcomeBonusScreen extends StatelessWidget {
  const WelcomeBonusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      scroll: false,
      glowColor: AuraColors.amber,
      glowAlignment: const Alignment(0, -0.6),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'WELCOME GIFT',
                    style: TextStyle(
                      color: AuraColors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Center(child: _StarBadge(size: 150)),
                const SizedBox(height: 28),
                Text("You're all set!",
                    textAlign: TextAlign.center,
                    style: AuraText.headline.copyWith(fontSize: 31)),
                const SizedBox(height: 10),
                Text(
                  "Here's your starter pack to jump straight into the action.",
                  textAlign: TextAlign.center,
                  style: AuraText.body.copyWith(color: AuraColors.textSecondary),
                ),
                const SizedBox(height: 28),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Expanded(
                      child: _RewardTile(
                        glyph: CurrencyGlyph(kind: Currency.gems, size: 26),
                        amount: '+5,000',
                        label: 'Tokens',
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _RewardTile(
                        glyph: CurrencyGlyph(kind: Currency.gold, size: 26),
                        amount: '+1,000',
                        label: 'Gold',
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _RewardTile(
                        glyph: Icon(Icons.refresh, color: AuraColors.accentGlow, size: 26),
                        amount: '+3',
                        label: 'Spins',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                GradientButton(
                  label: 'Claim & Play',
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                      context, Routes.home, (r) => false),
                ),
                const SizedBox(height: 24),
              ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RewardTile extends StatelessWidget {
  const _RewardTile({
    required this.glyph,
    required this.amount,
    required this.label,
  });

  final Widget glyph;
  final String amount;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 26, child: Center(child: glyph)),
          const SizedBox(height: 8),
          Text(
            amount,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: AuraText.caption),
        ],
      ),
    );
  }
}

/// Celebratory badge: sparkle rays behind a rotated gradient rounded-square
/// containing an upright white star.
class _StarBadge extends StatelessWidget {
  const _StarBadge({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final tileSize = size * 0.62;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Faint sparkle rays behind.
          SizedBox(
            width: size,
            height: size,
            child: CustomPaint(painter: _SparklePainter()),
          ),
          // Rotated rounded-square with brand gradient.
          Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: tileSize,
              height: tileSize,
              decoration: BoxDecoration(
                gradient: AuraGradients.brand,
                // Softer corners than a circle so the diamond points read (mockup).
                borderRadius: BorderRadius.circular(tileSize * 0.3),
                boxShadow: [
                  BoxShadow(
                    color: AuraColors.brandPink.withValues(alpha: 0.4),
                    blurRadius: 32,
                    spreadRadius: -4,
                  ),
                ],
              ),
            ),
          ),
          // Upright star.
          Icon(Icons.star, color: Colors.white, size: tileSize * 0.5),
          // Small diamond accent.
          Positioned(
            right: size * 0.06,
            top: size * 0.12,
            child: Icon(Icons.diamond, color: AuraColors.gems, size: size * 0.12),
          ),
          // Small coin accent.
          Positioned(
            left: size * 0.08,
            bottom: size * 0.14,
            child: Icon(Icons.monetization_on,
                color: AuraColors.gold, size: size * 0.11),
          ),
        ],
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = AuraColors.amber.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const rays = 8;
    final inner = size.width * 0.42;
    final outer = size.width * 0.5;
    for (var i = 0; i < rays; i++) {
      final angle = (math.pi * 2 / rays) * i + math.pi / 8;
      final p1 = center + Offset(math.cos(angle), math.sin(angle)) * inner;
      final p2 = center + Offset(math.cos(angle), math.sin(angle)) * outer;
      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
