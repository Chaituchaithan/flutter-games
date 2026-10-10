import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// One wheel wedge: an amount + unit, with gold/jackpot flags.
class _Seg {
  const _Seg(this.amount, this.unit, this.value, {this.gold = false, this.jackpot = false});
  final String amount;
  final String unit;
  final int value;
  final bool gold;
  final bool jackpot;
}

/// Wheel tab — "Lucky Spin". Scrollable body only (shell provides chrome).
/// Spins land on a wedge, reveal the win, and consume a free spin. See
/// docs/DESIGN_SPEC.md.
class WheelScreen extends StatefulWidget {
  const WheelScreen({super.key});

  @override
  State<WheelScreen> createState() => _WheelScreenState();
}

class _WheelScreenState extends State<WheelScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Segments clockwise from the top wedge (index 0 sits under the pointer).
  static const _segs = <_Seg>[
    _Seg('500', 'Tokens', 500),
    _Seg('200', 'Gold', 200, gold: true),
    _Seg('1,000', 'Tokens', 1000),
    _Seg('50', 'Gold', 50, gold: true),
    _Seg('500', 'Gold', 500, gold: true),
    _Seg('2,000', 'Tokens', 2000),
    _Seg('5,000', 'JACKPOT', 5000, jackpot: true),
    _Seg('100', 'Tokens', 100),
  ];

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

  int _spinsLeft = 3;
  double _fromAngle = 0;
  double _toAngle = 0;
  _Seg? _result;

  bool get _canSpin => _spinsLeft > 0 && !_controller.isAnimating;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          // Normalise so the next spin starts from the resting angle.
          _fromAngle = _toAngle % (2 * math.pi);
          setState(() {});
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _spin() {
    if (!_canSpin) return;
    final sweep = 2 * math.pi / _segs.length;
    final i = math.Random().nextInt(_segs.length);
    // Rotation that brings segment i under the top pointer: a ≡ -i*sweep.
    final current = _fromAngle % (2 * math.pi);
    final target = (-i * sweep) % (2 * math.pi);
    final delta = (target - current + 2 * math.pi) % (2 * math.pi);
    _fromAngle = current;
    _toAngle = current + 2 * math.pi * 5 + delta; // 5 full turns + align

    setState(() {
      _spinsLeft -= 1;
      _result = null;
    });
    _controller.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() => _result = _segs[i]);
    });
  }

  String get _resultText {
    final r = _result;
    if (r == null) return '';
    if (r.jackpot) return 'JACKPOT!  +${r.amount} Tokens';
    return 'You won  +${r.amount} ${r.gold ? 'Gold' : 'Tokens'}';
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
                CurrencyPill(kind: Currency.gems, amount: '10,000', showPlus: false),
                SizedBox(width: 6),
                CurrencyPill(kind: Currency.gold, amount: '3,000', showPlus: false),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        Center(child: _FreeSpinsChip(spinsLeft: _spinsLeft)),
        const SizedBox(height: 28),
        Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Outer purple glow ring + white rim.
                Container(
                  width: 286,
                  height: 286,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 8),
                    boxShadow: [
                      BoxShadow(
                        color: AuraColors.accentGlow.withValues(alpha: 0.22),
                        spreadRadius: 5,
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final t = Curves.easeOutCubic.transform(_controller.value);
                      final angle = _fromAngle + (_toAngle - _fromAngle) * t;
                      return Transform.rotate(angle: angle, child: child);
                    },
                    child: CustomPaint(
                      painter: _WheelPainter(segs: _segs, colors: _segmentColors),
                    ),
                  ),
                ),
                // Inner dark vignette (inset shadow stand-in).
                IgnorePointer(
                  child: Container(
                    width: 270,
                    height: 270,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
                        stops: const [0.72, 1.0],
                      ),
                    ),
                  ),
                ),
                // Top pointer (fixed).
                Positioned(
                  top: -6,
                  child: CustomPaint(
                    size: const Size(28, 26),
                    painter: _PointerPainter(),
                  ),
                ),
                // Center hub (SPIN).
                _SpinButton(onTap: _spin, enabled: _canSpin),
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),
        if (_result != null)
          Center(child: _ResultBanner(text: _resultText))
        else
          Center(
            child: Text(
              _spinsLeft > 0
                  ? 'Land on a wedge to win tokens or gold'
                  : 'No spins left — come back tomorrow',
              style: AuraText.cardSub,
            ),
          ),
      ],
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AuraColors.green.withValues(alpha: 0.18),
            AuraColors.amber.withValues(alpha: 0.14),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AuraColors.green.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AuraText.displayFamily,
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FreeSpinsChip extends StatelessWidget {
  const _FreeSpinsChip({required this.spinsLeft});
  final int spinsLeft;

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
            '$spinsLeft free spins left',
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
  const _SpinButton({required this.onTap, required this.enabled});
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: enabled
              ? AuraGradients.brand
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4B5563), Color(0xFF374151)],
                ),
          border: Border.all(color: AuraColors.background, width: 4),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AuraColors.brandPink.withValues(alpha: 0.6),
                    blurRadius: 26,
                    spreadRadius: -2,
                  ),
                ]
              : null,
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
  _WheelPainter({required this.segs, required this.colors});

  final List<_Seg> segs;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final segCount = segs.length;
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

      _drawLabel(canvas, center, radius, start + sweep / 2, segs[i]);
    }
  }

  void _drawLabel(Canvas canvas, Offset center, double radius, double midAngle, _Seg seg) {
    final color = seg.jackpot ? const Color(0xFFFDE68A) : Colors.white;
    final amount = TextPainter(
      text: TextSpan(
        text: seg.amount,
        style: TextStyle(fontFamily: AuraText.displayFamily, color: color, fontSize: 14, fontWeight: FontWeight.w700, height: 1),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    final unit = TextPainter(
      text: TextSpan(
        text: seg.unit,
        style: TextStyle(color: color.withValues(alpha: 0.75), fontSize: 9, height: 1),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(midAngle);
    canvas.translate(radius * 0.62, 0);
    canvas.rotate(math.pi / 2); // text reads outward from centre
    amount.paint(canvas, Offset(-amount.width / 2, -amount.height - 1));
    unit.paint(canvas, Offset(-unit.width / 2, 1));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => false;
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFBBF24)
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
