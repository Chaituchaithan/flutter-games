import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/aura.dart';
import '../../widgets/wallet_pill.dart';

/// One wheel wedge: an amount + unit, with gold/jackpot flags.
class _Seg {
  const _Seg(
    this.amount,
    this.unit,
    this.value, {
    this.gold = false,
    this.jackpot = false,
  });
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
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  /// Marquee bulbs around the rim: a slow blink at rest, a chase while spinning.
  late final AnimationController _lights;

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

  /// Hides the win message 3 s after the wheel stops.
  Timer? _hideResult;

  bool get _canSpin => _spinsLeft > 0 && !_controller.isAnimating;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 5200),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            // Normalise so the next spin starts from the resting angle.
            _fromAngle = _toAngle % (2 * math.pi);
            setState(() {});
          }
        });
    _lights = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _hideResult?.cancel();
    _lights.dispose();
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

    _hideResult?.cancel();
    setState(() {
      _spinsLeft -= 1;
      _result = null;
    });
    _controller.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() => _result = _segs[i]);
      _hideResult = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _result = null);
      });
    });
  }

  /// Pointer deflection for wheel [angle]: pegs sit on the wedge borders; one
  /// passing under the pointer pushes it aside, then it springs back.
  double _flapperAngle(double angle) {
    final sweep = 2 * math.pi / _segs.length;
    // How far the nearest border has travelled past the pointer (0 → sweep).
    final d = (angle - sweep / 2) % sweep;
    const kick = 0.32; // fraction of a wedge the pointer stays pushed
    if (d >= sweep * kick) return 0;
    final f = 1 - d / (sweep * kick);
    return -0.42 * f * f;
  }

  String get _resultText {
    final r = _result;
    if (r == null) return '';
    if (r.jackpot) return 'JACKPOT!  +${r.amount} Tokens';
    return 'You won  +${r.amount} ${r.gold ? 'Gold' : 'Tokens'}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Same insets as the Store tab, so the header pills line up.
      padding: const EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 0),
      child: Column(
        children: [
          const WalletTitleBar(title: 'Lucky Spin'),
          // Spins chip, wheel and result, centred in the space below the
          // header (scrolls only on very short screens).
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 12),
                      Center(child: _FreeSpinsChip(spinsLeft: _spinsLeft)),
                      const SizedBox(height: 28),
                      Center(
                        child: SizedBox(
                          width: 312,
                          height: 324,
                          child: AnimatedBuilder(
                            animation: Listenable.merge([_controller, _lights]),
                            builder: (context, _) {
                              // Long, natural slow-down (most of the time is spent easing in).
                              final t = Curves.easeOutQuart.transform(
                                _controller.value,
                              );
                              final angle =
                                  _fromAngle + (_toAngle - _fromAngle) * t;
                              return Stack(
                                alignment: Alignment.center,
                                clipBehavior: Clip.none,
                                children: [
                                  // Soft drop shadow under the whole wheel.
                                  Positioned(
                                    top: 12,
                                    child: Container(
                                      width: 300,
                                      height: 300,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.55,
                                            ),
                                            blurRadius: 28,
                                            offset: const Offset(0, 14),
                                          ),
                                          BoxShadow(
                                            color: AuraColors.accentGlow
                                                .withValues(alpha: 0.25),
                                            blurRadius: 40,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Gold rim + marquee bulbs (fixed).
                                  Positioned(
                                    top: 12,
                                    child: CustomPaint(
                                      size: const Size(300, 300),
                                      painter: _RimPainter(
                                        phase: _lights.value,
                                        spinning: _controller.isAnimating,
                                      ),
                                    ),
                                  ),
                                  // The wedges (rotating).
                                  Positioned(
                                    top: 12 + 22,
                                    child: Transform.rotate(
                                      angle: angle,
                                      child: CustomPaint(
                                        size: const Size(256, 256),
                                        painter: _WheelPainter(
                                          segs: _segs,
                                          colors: _segmentColors,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Centre hub: brass bezel around the SPIN button.
                                  Positioned(
                                    top: 12 + 150 - 50,
                                    child: _SpinButton(onTap: _spin, enabled: _canSpin, phase: _lights.value),
                                  ),
                                  // Flapper pointer: kicks back as each peg passes, then settles.
                                  Positioned(
                                    top: 0,
                                    child: Transform.rotate(
                                      angle: _flapperAngle(angle),
                                      alignment: const Alignment(0, -0.62),
                                      child: CustomPaint(
                                        size: const Size(34, 44),
                                        painter: _PointerPainter(),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      // Fixed height: the wheel stays put when the win shows.
                      SizedBox(
                        height: 46,
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            transitionBuilder: (c, a) => FadeTransition(
                              opacity: a,
                              child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: c),
                            ),
                            child: _result != null
                                ? _ResultBanner(key: ValueKey(_resultText), text: _resultText)
                                : Text(
                                    _spinsLeft > 0
                                        ? 'Land on a wedge to win tokens or gold'
                                        : 'No spins left — come back tomorrow',
                                    key: ValueKey(_spinsLeft > 0),
                                    style: AuraText.cardSub,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
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

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({super.key, required this.text});
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

/// Centre hub: a brass bezel with rivets around a casino-style jewel
/// button — deep red dome with a bevel and gloss, embossed gold SPIN, a
/// breathing glow and a shine sweep while a spin is available.
class _SpinButton extends StatefulWidget {
  const _SpinButton({required this.onTap, required this.enabled, required this.phase});
  final VoidCallback onTap;
  final bool enabled;

  /// 0 → 1, repeating (drives the glow and the shine).
  final double phase;

  @override
  State<_SpinButton> createState() => _SpinButtonState();
}

class _SpinButtonState extends State<_SpinButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    final breathe = 0.5 + 0.5 * math.sin(widget.phase * 2 * math.pi);
    return GestureDetector(
      onTapDown: on ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTapUp: on
          ? (_) {
              setState(() => _down = false);
              widget.onTap();
            }
          : null,
      child: SizedBox(
        width: 100,
        height: 100,
        child: CustomPaint(
          painter: _HubPainter(),
          child: Center(
            child: AnimatedScale(
              scale: _down ? 0.9 : 1,
              duration: const Duration(milliseconds: 90),
              child: SizedBox.square(
                dimension: 72,
                child: CustomPaint(
                  painter: _JewelPainter(on: on, pressed: _down, glow: on ? breathe : 0, shine: on ? widget.phase : -1),
                  child: Center(child: _SpinLabel(on: on)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Embossed gold "SPIN": a dark under-stroke, then the gold face.
class _SpinLabel extends StatelessWidget {
  const _SpinLabel({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: AuraText.displayFamily,
      fontSize: 18,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.5,
      height: 1,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        // Depth: a dark copy just below.
        Transform.translate(
          offset: const Offset(0, 1.6),
          child: Text('SPIN', style: style.copyWith(color: on ? const Color(0xFF5A0610) : Colors.black45)),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: on
                ? const [Color(0xFFFFF7D1), Color(0xFFFCD34D), Color(0xFFD97706)]
                : const [Color(0xFFE5E7EB), Color(0xFF9CA3AF), Color(0xFF6B7280)],
            stops: const [0, 0.5, 1],
          ).createShader(r),
          child: Text('SPIN', style: style.copyWith(color: Colors.white)),
        ),
      ],
    );
  }
}

/// The dome: outer glow, a bevelled rim (light top, dark bottom), the red
/// jewel with depth, a glossy crescent, and a shine that sweeps across.
class _JewelPainter extends CustomPainter {
  _JewelPainter({required this.on, required this.pressed, required this.glow, required this.shine});
  final bool on;
  final bool pressed;
  final double glow;

  /// Shine position 0 → 1 (−1 = none).
  final double shine;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final base = on ? const Color(0xFFDC2626) : const Color(0xFF6B7280);
    if (on) {
      canvas.drawCircle(
        c,
        r + 2,
        Paint()
          ..color = const Color(0xFFFBBF24).withValues(alpha: 0.25 + 0.35 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 6 * glow),
      );
    }
    // Bevelled rim.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: pressed
              ? [Color.lerp(base, Colors.black, 0.55)!, Color.lerp(base, Colors.white, 0.35)!]
              : [Color.lerp(base, Colors.white, 0.45)!, Color.lerp(base, Colors.black, 0.6)!],
        ).createShader(rect),
    );
    // The jewel.
    final jr = r - 4;
    canvas.drawCircle(
      c,
      jr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 0.95,
          colors: on
              ? [const Color(0xFFFF6B6B), base, const Color(0xFF7F1D1D), const Color(0xFF450A0A)]
              : [const Color(0xFFD1D5DB), base, const Color(0xFF374151), const Color(0xFF1F2937)],
          stops: const [0, 0.45, 0.85, 1],
        ).createShader(Rect.fromCircle(center: c, radius: jr)),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: jr)));
    // Shine sweep (a soft diagonal band crossing the dome).
    if (shine >= 0 && shine < 0.45) {
      final t = shine / 0.45;
      final x = c.dx - jr * 1.6 + t * jr * 3.2;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.32), Colors.white.withValues(alpha: 0)],
            stops: const [0.4, 0.5, 0.6],
          ).createShader(Rect.fromCenter(center: Offset(x, c.dy), width: jr * 2, height: jr * 2)),
      );
    }
    canvas.restore();
    // Glossy crescent on the top half.
    if (!pressed) {
      final gloss = Rect.fromCenter(center: c - Offset(0, jr * 0.45), width: jr * 1.4, height: jr * 0.8);
      canvas.drawOval(
        gloss,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withValues(alpha: on ? 0.55 : 0.35), Colors.white.withValues(alpha: 0)],
          ).createShader(gloss),
      );
      canvas.drawCircle(c + Offset(-jr * 0.42, -jr * 0.5), jr * 0.07, Paint()..color = Colors.white.withValues(alpha: 0.85));
    }
    // Thin dark ring between rim and jewel.
    canvas.drawCircle(
      c,
      jr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_JewelPainter old) =>
      old.on != on || old.pressed != pressed || old.glow != glow || old.shine != shine;
}

/// Brass bezel (metallic sweep) with eight rivets.
class _HubPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(c, r - 1, Paint()..shader = _brass.createShader(rect));
    // Inner groove.
    canvas.drawCircle(
      c,
      r - 12,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF7C4A03),
    );
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + math.pi / 8;
      final p = c + Offset(math.cos(a), math.sin(a)) * (r - 6.5);
      canvas.drawCircle(p, 2.6, Paint()..color = const Color(0xFF7C4A03));
      canvas.drawCircle(
        p - const Offset(0.6, 0.6),
        1.6,
        Paint()..color = const Color(0xFFFFF3C4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HubPainter oldDelegate) => false;
}

/// Polished brass: light/dark bands around the circle.
const _brass = SweepGradient(
  colors: [
    Color(0xFFFDE68A),
    Color(0xFFB45309),
    Color(0xFFFCD34D),
    Color(0xFF92400E),
    Color(0xFFFEF3C7),
    Color(0xFFB45309),
    Color(0xFFFDE68A),
  ],
);

/// The fixed outer rim: brass ring with 16 marquee bulbs.
class _RimPainter extends CustomPainter {
  _RimPainter({required this.phase, required this.spinning});

  /// 0 → 1, repeating.
  final double phase;
  final bool spinning;

  static const bulbs = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    // Brass ring and a dark inner lip the wedges sit in.
    canvas.drawCircle(c, r, Paint()..shader = _brass.createShader(rect));
    canvas.drawCircle(
      c,
      r - 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF78350F),
    );
    canvas.drawCircle(c, r - 19, Paint()..color = const Color(0xFF1A0B2E));
    canvas.drawCircle(
      c,
      r - 19,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF78350F),
    );

    // Bulbs: alternate blink at rest; a fast chase while the wheel turns.
    for (var i = 0; i < bulbs; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / bulbs;
      final p = c + Offset(math.cos(a), math.sin(a)) * (r - 11);
      final bool lit;
      if (spinning) {
        lit =
            (i - (phase * bulbs * 2).floor()) % 4 == 0 ||
            (i - (phase * bulbs * 2).floor()) % 4 == 1;
      } else {
        lit = (i.isEven) == (phase < 0.5);
      }
      if (lit) {
        canvas.drawCircle(
          p,
          7,
          Paint()
            ..color = const Color(0xFFFFF7D6).withValues(alpha: 0.55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
      canvas.drawCircle(p, 4.6, Paint()..color = const Color(0xFF78350F));
      canvas.drawCircle(
        p,
        3.6,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.35),
            colors: lit
                ? const [Colors.white, Color(0xFFFDE68A), Color(0xFFF59E0B)]
                : const [
                    Color(0xFF9A6B2F),
                    Color(0xFF6B4410),
                    Color(0xFF3F2A0A),
                  ],
          ).createShader(Rect.fromCircle(center: p, radius: 3.6)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RimPainter old) =>
      old.phase != phase || old.spinning != spinning;
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
      ..color = const Color(0xFFFCD34D).withValues(alpha: 0.55)
      ..strokeWidth = 1.6;

    for (var i = 0; i < segCount; i++) {
      final start = startBase + sweep * i;
      segPaint.color = colors[i % colors.length];
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(rect, start, sweep, false)
        ..close();
      canvas.drawPath(path, segPaint);
      // Light from the rim falling toward the hub.
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.black.withValues(alpha: 0.35),
              Colors.transparent,
              Colors.white.withValues(alpha: 0.10),
            ],
            stops: const [0.25, 0.7, 1],
          ).createShader(rect),
      );
      canvas.drawPath(path, borderPaint);

      _drawLabel(canvas, center, radius, start + sweep / 2, segs[i]);
    }
    // Pegs on the wedge borders (they flick the pointer as they pass).
    for (var i = 0; i < segCount; i++) {
      final a = startBase + sweep * i;
      final p = center + Offset(math.cos(a), math.sin(a)) * (radius - 7);
      canvas.drawCircle(
        p + const Offset(0.8, 1.2),
        4.2,
        Paint()..color = Colors.black.withValues(alpha: 0.45),
      );
      canvas.drawCircle(
        p,
        4,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.4, -0.4),
            colors: [Color(0xFFFFFBEB), Color(0xFFFBBF24), Color(0xFF92400E)],
          ).createShader(Rect.fromCircle(center: p, radius: 4)),
      );
    }
  }

  void _drawLabel(
    Canvas canvas,
    Offset center,
    double radius,
    double midAngle,
    _Seg seg,
  ) {
    final color = seg.jackpot ? const Color(0xFFFDE68A) : Colors.white;
    final amount = TextPainter(
      text: TextSpan(
        text: seg.amount,
        style: TextStyle(
          fontFamily: AuraText.displayFamily,
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    final unit = TextPainter(
      text: TextSpan(
        text: seg.unit,
        style: TextStyle(
          color: color.withValues(alpha: 0.75),
          fontSize: 9,
          height: 1,
        ),
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

/// Brass flapper pointer with a ruby inset and a pivot bolt.
class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = Path()
      ..moveTo(w / 2, h)
      ..cubicTo(w * 0.16, h * 0.55, 0, h * 0.34, 0, h * 0.2)
      ..arcToPoint(Offset(w, h * 0.2), radius: Radius.circular(w / 2))
      ..cubicTo(w, h * 0.34, w * 0.84, h * 0.55, w / 2, h)
      ..close();
    canvas.drawShadow(body, Colors.black, 4, false);
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFEF3C7), Color(0xFFF59E0B), Color(0xFF92400E)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF78350F),
    );
    // Ruby.
    final gem = Offset(w / 2, h * 0.42);
    canvas.drawCircle(
      gem,
      5,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.4),
          colors: [Color(0xFFFECACA), Color(0xFFDC2626), Color(0xFF7F1D1D)],
        ).createShader(Rect.fromCircle(center: gem, radius: 5)),
    );
    // Pivot bolt.
    final bolt = Offset(w / 2, h * 0.19);
    canvas.drawCircle(bolt, 4, Paint()..color = const Color(0xFF78350F));
    canvas.drawCircle(
      bolt - const Offset(0.7, 0.7),
      2.4,
      Paint()..color = const Color(0xFFFFFBEB),
    );
  }

  @override
  bool shouldRepaint(covariant _PointerPainter oldDelegate) => false;
}
