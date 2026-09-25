import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Wheel tab — "Lucky Spin". Scrollable body only (shell provides chrome).
/// See docs/DESIGN_SPEC.md §5.
class WheelScreen extends StatefulWidget {
  const WheelScreen({super.key});

  @override
  State<WheelScreen> createState() => _WheelScreenState();
}

class _WheelScreenState extends State<WheelScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _turns = 0;

  // Segment labels clockwise from top.
  static const _labels = <String>[
    '500 Tokens',
    '200 Gold',
    '1,000 Tokens',
    '50 Gold',
    '500 Gold',
    '2,000 Tokens',
    'JACKPOT 5,000',
    '100 Tokens',
  ];

  // Alternating deep purple / magenta, with the JACKPOT wedge in amber
  // (matches the mockup's conic wheel).
  static const _segmentColors = <Color>[
    Color(0xFF6D28D9),
    Color(0xFF9D174D),
    Color(0xFF6D28D9),
    Color(0xFF9D174D),
    Color(0xFF6D28D9),
    Color(0xFF9D174D),
    Color(0xFFB45309), // JACKPOT
    Color(0xFF9D174D),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _spin() {
    if (_controller.isAnimating) return;
    setState(() => _turns += 4 + math.Random().nextDouble() * 2);
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text('Lucky Spin', style: AuraText.headline.copyWith(fontSize: 22)),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CurrencyPill(
                    kind: Currency.gems, amount: '10,000', showPlus: false),
                SizedBox(width: 6),
                CurrencyPill(
                    kind: Currency.gold, amount: '3,000', showPlus: false),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Center(child: _FreeSpinsChip()),
        const SizedBox(height: 28),
        Center(
          child: SizedBox(
            width: 280,
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Rotating wheel.
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final t = Curves.easeOutCubic.transform(_controller.value);
                    return Transform.rotate(
                      angle: _turns * 2 * math.pi * t,
                      child: child,
                    );
                  },
                  child: CustomPaint(
                    size: const Size(280, 280),
                    painter: _WheelPainter(
                      labels: _labels,
                      colors: _segmentColors,
                    ),
                  ),
                ),
                // Top pointer (does not rotate).
                Positioned(
                  top: -2,
                  child: CustomPaint(
                    size: const Size(26, 20),
                    painter: _PointerPainter(),
                  ),
                ),
                // Center SPIN button.
                _SpinButton(onTap: _spin),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: Text(
            'Land on a wedge to win tokens or gold',
            style: AuraText.cardSub,
          ),
        ),
      ],
    );
  }
}

class _FreeSpinsChip extends StatelessWidget {
  const _FreeSpinsChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: AuraGlass.decoration(radius: 99, shadow: false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.refresh, size: 15, color: AuraColors.accentGlow),
          const SizedBox(width: 7),
          Text(
            '3 free spins left',
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: AuraColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpinButton extends StatelessWidget {
  const _SpinButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AuraGradients.brand,
          border: Border.all(color: AuraColors.background, width: 5),
          boxShadow: [
            BoxShadow(
              color: AuraColors.brandPink.withValues(alpha: 0.5),
              blurRadius: 24,
              spreadRadius: -2,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Text(
          'SPIN',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.labels, required this.colors});

  final List<String> labels;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final segCount = labels.length;
    final sweep = 2 * math.pi / segCount;

    // Segment 0 is centered at the top pointer.
    final startBase = -math.pi / 2 - sweep / 2;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final segPaint = Paint()..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 2;

    for (var i = 0; i < segCount; i++) {
      final start = startBase + sweep * i;
      segPaint.color = colors[i % colors.length];
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(rect, start, sweep, false)
        ..close();
      canvas.drawPath(path, segPaint);
      canvas.drawPath(path, borderPaint);

      _drawLabel(canvas, center, radius, start + sweep / 2, labels[i]);
    }

    // Outer rim.
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 3,
    );
  }

  void _drawLabel(
    Canvas canvas,
    Offset center,
    double radius,
    double midAngle,
    String text,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
    )..layout(maxWidth: radius * 0.72);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(midAngle);
    // Move outward along the radius, then draw text upright-ish along the spoke.
    final labelRadius = radius * 0.60;
    canvas.translate(labelRadius, 0);
    // Rotate so text reads outward from center.
    canvas.rotate(math.pi / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => false;
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AuraColors.amber
      ..style = PaintingStyle.fill;
    // Downward triangle.
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PointerPainter oldDelegate) => false;
}
