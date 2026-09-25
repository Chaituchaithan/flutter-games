import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/aura_widgets.dart';

/// ── Slide 1: "Find your people" ──────────────────────────────────────────
/// A central "You" avatar surrounded by two dashed orbit rings and five
/// letter avatars scattered around them.
class FindYourPeopleArt extends StatelessWidget {
  const FindYourPeopleArt({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Dashed orbit rings.
          CustomPaint(
            size: const Size(280, 280),
            painter: _DashedRingsPainter(radii: const [78, 128]),
          ),
          // Central "You".
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AuraGradients.orb,
              boxShadow: [
                BoxShadow(
                  color: AuraColors.brandPink.withValues(alpha: 0.55),
                  blurRadius: 34,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'You',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          // Satellite avatars, placed by angle/radius around the centre.
          ..._satellites.map(
            (s) => Transform.translate(
              offset: Offset(
                s.radius * math.cos(s.angle),
                s.radius * math.sin(s.angle),
              ),
              child: LetterAvatar(
                letter: s.letter,
                color: s.color,
                size: s.size,
                glow: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Satellite {
  const _Satellite(this.letter, this.color, this.angle, this.radius, this.size);
  final String letter;
  final Color color;
  final double angle; // radians, 0 = right, clockwise
  final double radius;
  final double size;
}

const _satellites = <_Satellite>[
  _Satellite('K', AuraColors.avatarBlue, -math.pi / 2, 110, 46),
  _Satellite('M', AuraColors.avatarOrange, -0.35, 118, 46),
  _Satellite('J', AuraColors.avatarGreen, 0.7, 118, 46),
  _Satellite('R', AuraColors.avatarPurple, math.pi - 0.75, 118, 42),
  _Satellite('A', AuraColors.avatarPink, math.pi + 0.55, 112, 40),
];

/// Paints one or more dashed circles centred in the given size.
class _DashedRingsPainter extends CustomPainter {
  _DashedRingsPainter({required this.radii});

  final List<double> radii;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.14);

    const dash = 4.0;
    const gap = 7.0;
    for (final r in radii) {
      final step = (dash + gap) / r; // angular step per dash
      final sweep = dash / r;
      for (double a = 0; a < 2 * math.pi; a += step) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r),
          a,
          sweep,
          false,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingsPainter oldDelegate) =>
      oldDelegate.radii != radii;
}

/// ── Slide 2: "Share your moment" ─────────────────────────────────────────
/// A floating post card: avatar + skeleton lines, a gradient image block and
/// a like / comment chip row.
class ShareYourMomentArt extends StatelessWidget {
  const ShareYourMomentArt({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AuraColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AuraColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: avatar + two skeleton lines.
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AuraGradients.orb,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _skeleton(width: 92),
                  const SizedBox(height: 6),
                  _skeleton(width: 56, opacity: 0.06),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Image block.
          Container(
            height: 118,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF6D5B8C), Color(0xFF8C5B72), Color(0xFF6D5B8C)],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Reaction chips.
          Row(
            children: [
              _reactionChip(
                icon: Icons.favorite,
                label: '2.4k',
                gradient: AuraGradients.brand,
              ),
              const SizedBox(width: 10),
              _reactionChip(
                icon: Icons.mode_comment_outlined,
                label: '312',
                gradient: null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _skeleton({required double width, double opacity = 0.12}) {
    return Container(
      width: width,
      height: 8,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  static Widget _reactionChip({
    required IconData icon,
    required String label,
    required LinearGradient? gradient,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? AuraColors.chipDark : null,
        borderRadius: BorderRadius.circular(20),
        border: gradient == null
            ? Border.all(color: Colors.white.withValues(alpha: 0.10))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// ── Slide 3: "Always in sync" ────────────────────────────────────────────
/// A glowing gradient orb inside faint concentric rings, a "Live" chip and
/// two small satellite dots.
class AlwaysInSyncArt extends StatelessWidget {
  const AlwaysInSyncArt({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(280, 280),
            painter: _SolidRingsPainter(radii: const [72, 108, 132]),
          ),
          // Central glowing orb.
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AuraGradients.orb,
              boxShadow: [
                BoxShadow(
                  color: AuraColors.brandPink.withValues(alpha: 0.6),
                  blurRadius: 44,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          // "Live" chip, upper-left.
          Positioned(
            left: 34,
            top: 30,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AuraColors.chipDark,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Dot(color: AuraColors.avatarGreen, size: 7),
                  SizedBox(width: 6),
                  Text(
                    'Live',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Satellite dots riding the rings.
          const Positioned(left: 44, bottom: 96, child: _Dot(color: AuraColors.avatarGreen, size: 22, glow: true)),
          const Positioned(right: 60, bottom: 70, child: _Dot(color: AuraColors.avatarBlue, size: 22, glow: true)),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size, this.glow = false});

  final Color color;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: glow
            ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 14, spreadRadius: -1)]
            : null,
      ),
    );
  }
}

/// Faint solid concentric rings.
class _SolidRingsPainter extends CustomPainter {
  _SolidRingsPainter({required this.radii});

  final List<double> radii;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < radii.length; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Colors.white.withValues(alpha: 0.06 + i * 0.02);
      canvas.drawCircle(center, radii[i], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SolidRingsPainter oldDelegate) =>
      oldDelegate.radii != radii;
}
