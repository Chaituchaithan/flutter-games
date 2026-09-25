import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../widgets/aura.dart';

/// Splash — Aura orb logo + tagline. Auto-advances to Language.
/// See docs/DESIGN_SPEC.md (v2 §Splash).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1400), _goNext);
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    // Only advance when Splash is actually the visible route — prevents a
    // Splash sitting at the bottom of a deep-linked stack from hijacking nav.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _navigated = true;
    Navigator.pushReplacementNamed(context, Routes.language);
  }

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      glowColor: AuraColors.accentGlow,
      glowAlignment: Alignment.center,
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _AuraOrb(size: 150),
                  const SizedBox(height: 34),
                  Text(
                    'Aura',
                    style: TextStyle(
                      fontFamily: AuraText.displayFamily,
                      color: Colors.white,
                      fontSize: 46,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Play. Win. Repeat.',
                    style: AuraText.body.copyWith(color: AuraColors.textSecondary, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
          // Loading bar.
          Padding(
            padding: const EdgeInsets.only(bottom: 48),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  width: 150,
                  height: 3,
                  color: Colors.white.withValues(alpha: 0.12),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.45,
                    child: Container(decoration: const BoxDecoration(gradient: AuraGradients.brand)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Large Aura orb: brand-gradient ring, near-black inner circle, glowing dot.
class _AuraOrb extends StatelessWidget {
  const _AuraOrb({required this.size});
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
        colors: [
          AuraColors.brandPurple,
          AuraColors.brandPink,
          AuraColors.brandOrange,
          AuraColors.brandPurple,
        ],
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
