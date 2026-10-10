import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Large Aura orb: brand-gradient ring, near-black inner circle, glowing dot.
class AuraOrb extends StatelessWidget {
  const AuraOrb({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _AuraOrbPainter()),
    );
  }
}

class _AuraOrbPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final ringWidth = size.width * 0.09;
    final ringRadius = (size.width - ringWidth) / 2;

    // Brand-gradient ring stroke (full circle, swept gradient).
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..shader = const SweepGradient(
        colors: [AuraColors.brandPurple, AuraColors.brandPink, AuraColors.brandOrange, AuraColors.brandPurple],
        startAngle: 0,
        endAngle: math.pi * 2,
      ).createShader(rect);
    canvas.drawCircle(center, ringRadius, ringPaint);

    // Near-black inner circle.
    final innerRadius = ringRadius - ringWidth * 0.75;
    final innerPaint = Paint()..color = const Color(0xFF0A0812);
    canvas.drawCircle(center, innerRadius, innerPaint);

    // Glowing pink dot in the centre.
    final glowPaint = Paint()
      ..color = AuraColors.brandPink.withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, size.width * 0.12, glowPaint);

    final dotPaint = Paint()..color = AuraColors.brandPink;
    canvas.drawCircle(center, size.width * 0.075, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
