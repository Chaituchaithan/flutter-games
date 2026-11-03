import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'carrom_engine.dart';

/// A tournament board as it looks under a lamp: a polished rosewood frame
/// (7.6 cm rails round the 74 cm surface), birch plywood dusted with powder,
/// ICF markings in ink, pockets cut through the corners into their nets,
/// and lathe-turned wooden carrom men that turn as they slide and throw
/// their shadows away from the light.

/// "+1" / ♛ / FOUL rising from a pocket.
class CarromPop {
  CarromPop(this.kind, this.pocket, this.born);
  final CarromKind kind;
  final int pocket;
  final double born;
}

/// Where the lamp hangs over the board (board units): a little towards the
/// far side, so shadows lean towards you like a real table.
const _lamp = Offset(0.5, 0.42);

class CarromBoardPainter extends CustomPainter {
  CarromBoardPainter({
    required this.game,
    required this.aim,
    required this.power,
    required this.yourTurn,
    required this.pops,
    required this.time,
    super.repaint,
  });

  final CarromGame game;
  final (double, double)? aim;
  final double power;
  final bool yourTurn;
  final List<CarromPop> pops;

  /// Seconds since the game started (pops and the turn glow). Listenable, so
  /// the idle glow repaints this layer without rebuilding the screen.
  final ValueListenable<double> time;
  double get clock => time.value;

  /// Frame rail width as a share of the board's side (7.6 cm of 89 cm).
  static const frame = 0.082;

  /// Shadows on a unit circle: soft edges without a blur on every frame.
  static final Paint _castShadow = Paint()
    ..shader = ui.Gradient.radial(Offset.zero, 1, [
      Colors.black.withValues(alpha: 0.3),
      Colors.black.withValues(alpha: 0.24),
      Colors.black.withValues(alpha: 0),
    ], const [0, 0.7, 1]);
  static final Paint _contactShadow = Paint()
    ..shader = ui.Gradient.radial(Offset.zero, 1, [
      Colors.black.withValues(alpha: 0.42),
      Colors.black.withValues(alpha: 0.42),
      Colors.black.withValues(alpha: 0),
    ], const [0, 0.86, 1]);

  static const _ink = Color(0xFF231510);
  static const _red = Color(0xFFB3261E);

  /// Board position → canvas.
  static Offset Function(double, double) mapper(double side) {
    final f = side * frame;
    final s = side - 2 * f;
    return (x, y) => Offset(f + x * s, f + y * s);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width;
    final s = side - 2 * side * frame;
    final at = mapper(side);

    _turnGlow(canvas, at, s);

    // Coins dropping through the hole into the net.
    for (final k in game.sinking) {
      final (px, py) = CarromRules.pockets[k.pocket];
      final t = (k.t / 0.35).clamp(0.0, 1.0);
      final pc = at(px, py);
      final pos = Offset.lerp(at(k.x, k.y), pc, Curves.easeIn.transform(t))!;
      final r = (k.kind == CarromKind.striker ? CarromRules.strikerR : CarromRules.coinR) * s * (1 - 0.35 * t);
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: pc, radius: CarromRules.pocketR * s)));
      paintCarromDisc(canvas, pos, r, k.kind, shadow: false);
      // Falling into the dark under the board.
      canvas.drawCircle(pos, r * 1.05, Paint()..color = Colors.black.withValues(alpha: 0.2 + 0.75 * t));
      canvas.restore();
    }

    // A faint blur behind anything really flying.
    for (final d in game.discs) {
      final sp = d.speed;
      if (sp < 0.8) continue;
      final c = at(d.x, d.y);
      final tail = c - Offset(d.vx, d.vy) * (0.02 * s);
      canvas.drawLine(
        c,
        tail,
        Paint()
          ..strokeWidth = d.r * s * 1.9
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(c, tail, [
            _tone(d.kind).withValues(alpha: (0.18 * sp / 4).clamp(0.0, 0.18)),
            _tone(d.kind).withValues(alpha: 0),
          ]),
      );
    }

    // Shadows first (so no disc's shadow lies on top of its neighbour),
    // then the coins, then the striker on top.
    for (final d in game.discs) {
      _shadow(canvas, at(d.x, d.y), d.r * s, _lampDir(d.x, d.y));
    }
    for (final d in game.discs) {
      if (d.kind == CarromKind.striker) continue;
      paintCarromDisc(
        canvas,
        at(d.x, d.y),
        d.r * s,
        d.kind,
        angle: d.angle,
        shadow: false,
      );
    }
    final st = game.striker;
    if (game.discs.contains(st)) {
      final c = at(st.x, st.y);
      paintCarromDisc(
        canvas,
        c,
        st.r * s,
        CarromKind.striker,
        angle: st.angle,
        shadow: false,
      );
      if (!game.moving && !game.strikerClear) {
        canvas.drawCircle(
          c,
          st.r * s + 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = const Color(0xFFE5484D),
        );
      } else if (yourTurn && aim == null) {
        // Your shot: a soft breathing ring on the striker.
        final k = 0.5 + 0.5 * math.sin(clock * 3);
        canvas.drawCircle(
          c,
          st.r * s + 3 + k * 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = Colors.white.withValues(alpha: 0.35 + 0.35 * k),
        );
      }
    }

    _guide(canvas, at, s);
    _lampLight(canvas, size);
    _pops(canvas, at, s);
  }

  /// From the lamp towards (x, y): which way a disc's shadow falls, longer
  /// further from the light.
  static Offset _lampDir(double x, double y) => (Offset(x, y) - _lamp) * 1.6;

  static Color _tone(CarromKind k) => switch (k) {
    CarromKind.white => const Color(0xFFF0DDB4),
    CarromKind.black => const Color(0xFF2A221E),
    CarromKind.queen => const Color(0xFFC0202F),
    CarromKind.striker => const Color(0xFFF5F2EA),
  };

  void _shadow(Canvas canvas, Offset c, double r, Offset dir) {
    // Soft cast shadow away from the lamp, and a tight contact shadow.
    final cast = c + Offset(r * (0.12 + dir.dx * 0.5), r * (0.16 + dir.dy * 0.5));
    canvas
      ..save()
      ..translate(cast.dx, cast.dy)
      ..scale(r * 1.3)
      ..drawCircle(Offset.zero, 1, _castShadow)
      ..restore();
    final touch = c + Offset(r * 0.04, r * 0.06);
    canvas
      ..save()
      ..translate(touch.dx, touch.dy)
      ..scale(r * 1.08)
      ..drawCircle(Offset.zero, 1, _contactShadow)
      ..restore();
  }

  /// Whose turn: their base glows faintly, like light catching the lacquer.
  void _turnGlow(Canvas canvas, Offset Function(double, double) at, double s) {
    if (game.isOver || game.moving) return;
    final y = CarromRules.baseY(game.turn);
    final pulse = 0.55 + 0.45 * math.sin(clock * 3.2);
    final color = game.turn == 0 ? const Color(0xFFFFE2A8) : const Color(0xFFA8E8FF);
    final r = Rect.fromPoints(
      at(CarromRules.baseMin - 0.03, y - CarromRules.coinR * 1.8),
      at(CarromRules.baseMax + 0.03, y + CarromRules.coinR * 1.8),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(r.height / 2)),
      Paint()
        ..color = color.withValues(alpha: 0.16 * pulse)
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  /// The lamp: a warm pool in the middle falling off to the corners. Drawn
  /// over the coins too, so everything sits in the same light.
  void _lampLight(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final c = Offset(size.width * _lamp.dx, size.height * _lamp.dy);
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          size.width * 0.78,
          [const Color(0xFFFFE9C4).withValues(alpha: 0.07), Colors.transparent, Colors.black.withValues(alpha: 0.30)],
          [0, 0.5, 1],
        ),
    );
  }

  /// "+1" / ♛ / FOUL rising from the pocket.
  void _pops(Canvas canvas, Offset Function(double, double) at, double s) {
    for (final p in pops) {
      final t = ((clock - p.born) / 1.2).clamp(0.0, 1.0);
      final (px, py) = CarromRules.pockets[p.pocket];
      final c = at(px, py) + Offset(px < 0.5 ? s * 0.08 : -s * 0.08, (py < 0.5 ? s * 0.07 : -s * 0.07) - t * s * 0.08);
      final (text, color) = switch (p.kind) {
        CarromKind.white => ('+1', const Color(0xFFFFF4D6)),
        CarromKind.black => ('+1', const Color(0xFFBFEFFF)),
        CarromKind.queen => ('♛ +3', const Color(0xFFFF6B7A)),
        CarromKind.striker => ('FOUL', const Color(0xFFFF5A5F)),
      };
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color.withValues(alpha: 1 - t * t),
            fontSize: s * 0.05 * (1 + 0.25 * Curves.elasticOut.transform((t * 3).clamp(0.0, 1.0))),
            fontWeight: FontWeight.w900,
            shadows: [Shadow(color: Colors.black.withValues(alpha: 0.85 * (1 - t)), blurRadius: 5)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _guide(Canvas canvas, Offset Function(double, double) at, double s) {
    final a = aim;
    if (a == null || power < 0.02 || game.moving) return;
    final st = game.striker;
    final from = at(st.x, st.y);
    final g = carromAimGuide(game, a.$1, a.$2);
    final to = at(g.x, g.y);
    // A fine line to first contact.
    final dir = to - from;
    final len = dir.distance;
    if (len > 1) {
      final u = dir / len;
      final dot = Paint()..color = Colors.white.withValues(alpha: 0.8);
      for (var d = st.r * s + 5; d < len - st.r * s; d += 7) {
        canvas.drawCircle(from + u * d, 1.2, dot);
      }
    }
    // Ghost striker at contact.
    canvas.drawCircle(
      to,
      st.r * s,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.7),
    );
    canvas.drawCircle(to, st.r * s, Paint()..color = Colors.white.withValues(alpha: 0.10));
    // Where the coin goes.
    final hit = g.hit;
    if (hit != null) {
      final hc = at(hit.x, hit.y);
      final n = hc - to;
      final nl = n.distance;
      if (nl > 0) {
        final u = n / nl;
        final end = hc + u * s * 0.17;
        canvas.drawLine(
          hc,
          end,
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..shader = ui.Gradient.linear(hc, end, [const Color(0xFFFFE08A), const Color(0x00FFE08A)]),
        );
      }
    }
    // Power: an arc round the striker, green → red.
    final pc = Color.lerp(const Color(0xFF4ADE80), const Color(0xFFF05252), power)!;
    canvas.drawArc(
      Rect.fromCircle(center: from, radius: st.r * s + 6),
      -math.pi / 2,
      2 * math.pi * power,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = pc,
    );
    // The finger pulling back behind the striker.
    final la = math.sqrt(a.$1 * a.$1 + a.$2 * a.$2);
    if (la > 0) {
      final back = from - Offset(a.$1 / la, a.$2 / la) * (power * 0.24 * s);
      canvas.drawLine(
        from,
        back,
        Paint()
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(from, back, [pc.withValues(alpha: 0.1), pc.withValues(alpha: 0.6)]),
      );
      canvas.drawCircle(back, 4, Paint()..color = pc.withValues(alpha: 0.8));
    }
  }

  @override
  bool shouldRepaint(CarromBoardPainter old) => true;
}

/// The board itself: frame, plywood, markings and pockets. It never changes,
/// so it sits in its own layer and never repaints.
class CarromSurfacePainter extends CustomPainter {
  const CarromSurfacePainter();

  @override
  bool shouldRepaint(CarromSurfacePainter oldDelegate) => false;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width;
    final f = side * CarromBoardPainter.frame;
    _paintBoard(canvas, size, CarromBoardPainter.mapper(side), f, side - 2 * f);
  }

  void _paintBoard(Canvas canvas, Size size, Offset Function(double, double) at, double f, double s) {
    final side = size.width;
    final rng = math.Random(5);
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(side * 0.022));

    // The board stands on the table: a broad soft shadow under it.
    canvas.drawRRect(
      outer.shift(Offset(0, side * 0.012)).inflate(side * 0.004),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, side * 0.025),
    );

    _paintFrame(canvas, size, outer, f, rng);
    final play = Rect.fromLTWH(f, f, s, s);
    _paintPlywood(canvas, play, s, rng);
    _markings(canvas, at, s);
    _pockets(canvas, at, s);

    // The rails sit higher than the surface: a soft dark band where the
    // plywood meets them, a touch heavier on the far side.
    for (final (edge, k) in [
      (Rect.fromLTWH(f, f, s, s * 0.035), (Alignment.topCenter, Alignment.bottomCenter, 0.34)),
      (Rect.fromLTWH(f, f + s * 0.975, s, s * 0.025), (Alignment.bottomCenter, Alignment.topCenter, 0.22)),
      (Rect.fromLTWH(f, f, s * 0.03, s), (Alignment.centerLeft, Alignment.centerRight, 0.28)),
      (Rect.fromLTWH(f + s * 0.97, f, s * 0.03, s), (Alignment.centerRight, Alignment.centerLeft, 0.28)),
    ]) {
      canvas.drawRect(
        edge,
        Paint()
          ..shader = LinearGradient(
            begin: k.$1,
            end: k.$2,
            colors: [
              Colors.black.withValues(alpha: k.$3),
              Colors.transparent,
            ],
          ).createShader(edge),
      );
    }
    // The inside edge of the rails: a crisp dark seam and a lit lip.
    canvas.drawRect(
      play.inflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFF140703),
    );
    canvas.drawRect(
      play.inflate(2.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFE0A070).withValues(alpha: 0.22),
    );
  }

  void _paintFrame(Canvas canvas, Size size, RRect outer, double f, math.Random rng) {
    final side = size.width;
    canvas.save();
    canvas.clipRRect(outer);
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF3A170A));

    // Four mitred rails, each with its grain running along it and a
    // rounded top that catches the lamp along its middle.
    final rails = [
      (
        [Offset.zero, Offset(side, 0), Offset(side - f, f), Offset(f, f)],
        Alignment.topCenter,
        Alignment.bottomCenter,
        true,
      ),
      (
        [Offset(0, side), Offset(side, side), Offset(side - f, side - f), Offset(f, side - f)],
        Alignment.bottomCenter,
        Alignment.topCenter,
        true,
      ),
      (
        [Offset.zero, Offset(f, f), Offset(f, side - f), Offset(0, side)],
        Alignment.centerLeft,
        Alignment.centerRight,
        false,
      ),
      (
        [Offset(side, 0), Offset(side - f, f), Offset(side - f, side - f), Offset(side, side)],
        Alignment.centerRight,
        Alignment.centerLeft,
        false,
      ),
    ];
    for (var k = 0; k < 4; k++) {
      final (pts, from, to, across) = rails[k];
      final path = Path()..addPolygon(pts, true);
      final band = switch (k) {
        0 => Rect.fromLTWH(0, 0, side, f),
        1 => Rect.fromLTWH(0, side - f, side, f),
        2 => Rect.fromLTWH(0, 0, f, side),
        _ => Rect.fromLTWH(side - f, 0, f, side),
      };
      canvas.save();
      canvas.clipPath(path);
      // Rosewood, each rail cut from a slightly different plank.
      final tint = [
        const Color(0xFF6A2E15),
        const Color(0xFF5E2812),
        const Color(0xFF64301A),
        const Color(0xFF5A2711),
      ][k];
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            begin: from,
            end: to,
            colors: [
              const Color(0xFF2A0F05),
              tint,
              Color.lerp(tint, const Color(0xFF8A4A26), 0.35)!,
              tint,
              const Color(0xFF240C04),
            ],
            stops: const [0, 0.18, 0.45, 0.78, 1],
          ).createShader(band),
      );
      // Grain: long wavering lines, a few darker figure streaks.
      for (var i = 0; i < 46; i++) {
        final o = f * rng.nextDouble();
        final dark = rng.nextDouble() < 0.7;
        final w = 0.4 + rng.nextDouble() * (dark ? 1.4 : 0.8);
        final amp = 0.6 + rng.nextDouble() * 2.2, freq = 2 + rng.nextDouble() * 5, ph = rng.nextDouble() * 6;
        final p = Path();
        for (var t = 0; t <= 40; t++) {
          final u = side * t / 40;
          final v = o + math.sin(t / 40 * freq + ph) * amp;
          final pt = across ? Offset(u, k == 0 ? v : side - v) : Offset(k == 2 ? v : side - v, u);
          t == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
        }
        canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..color = (dark ? const Color(0xFF1A0702) : const Color(0xFFB0683A)).withValues(
              alpha: dark ? 0.10 + rng.nextDouble() * 0.22 : 0.06 + rng.nextDouble() * 0.10,
            ),
        );
      }
      // Varnish: a long soft highlight down the crown of the rail, brightest
      // on the rail facing the lamp.
      final shine = [0.30, 0.16, 0.20, 0.20][k];
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            begin: from,
            end: to,
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: shine),
              Colors.transparent,
            ],
            stops: const [0.22, 0.38, 0.58],
          ).createShader(band),
      );
      canvas.restore();
    }
    // Mitre joints: a fine dark seam with a lit edge.
    final seam = Paint()
      ..strokeWidth = 1.1
      ..color = Colors.black.withValues(alpha: 0.6);
    final lit = Paint()
      ..strokeWidth = 0.7
      ..color = Colors.white.withValues(alpha: 0.12);
    for (final (a, b) in [
      (Offset.zero, Offset(f, f)),
      (Offset(side, 0), Offset(side - f, f)),
      (Offset(0, side), Offset(f, side - f)),
      (Offset(side, side), Offset(side - f, side - f)),
    ]) {
      canvas.drawLine(a, b, seam);
      canvas.drawLine(a + const Offset(0.8, 0), b + const Offset(0.8, 0), lit);
    }
    canvas.restore();
    // The rounded outer edge: a bright rim on top, darkening round the side.
    canvas.drawRRect(
      outer.deflate(0.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x66FFD9B0), Color(0x22FFD9B0), Color(0x55000000)],
        ).createShader(Offset.zero & size),
    );
  }

  void _paintPlywood(Canvas canvas, Rect play, double s, math.Random rng) {
    canvas.save();
    canvas.clipRect(play);
    // Birch: pale honey, warmer and darker away from the lamp.
    canvas.drawRect(
      play,
      Paint()
        ..shader = ui.Gradient.radial(
          play.topLeft + Offset(_lamp.dx * s, _lamp.dy * s),
          s * 0.78,
          [const Color(0xFFF4DFB2), const Color(0xFFEACD94), const Color(0xFFD4AF72)],
          [0, 0.55, 1],
        ),
    );
    // Veneer grain: long, gently wandering lines across the board, in
    // bands of slightly different tone.
    for (var i = 0; i < 9; i++) {
      final y = play.top + s * rng.nextDouble();
      final h = s * (0.03 + rng.nextDouble() * 0.09);
      canvas.drawRect(
        Rect.fromLTWH(play.left, y, s, h),
        Paint()
          ..color = (rng.nextBool() ? const Color(0xFFFFF3D6) : const Color(0xFFC99B5C)).withValues(
            alpha: 0.05 + rng.nextDouble() * 0.05,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.4),
      );
    }
    for (var i = 0; i < 170; i++) {
      final y0 = play.top + s * rng.nextDouble();
      final w = 0.35 + rng.nextDouble() * 1.1;
      final amp = 0.5 + rng.nextDouble() * 3.5, freq = 1 + rng.nextDouble() * 3, ph = rng.nextDouble() * 6;
      final x0 = play.left + s * (rng.nextDouble() * 0.4 - 0.2);
      final len = s * (0.5 + rng.nextDouble() * 0.9);
      final p = Path();
      for (var t = 0; t <= 30; t++) {
        final x = x0 + len * t / 30;
        final y = y0 + math.sin(t / 30 * freq * math.pi + ph) * amp + t / 30 * amp * 0.6;
        t == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = const Color(0xFFB08048).withValues(alpha: 0.04 + rng.nextDouble() * 0.11),
      );
    }
    // A couple of the small pin knots birch is known for.
    for (var i = 0; i < 3; i++) {
      final c = play.topLeft + Offset(s * (0.1 + rng.nextDouble() * 0.8), s * (0.1 + rng.nextDouble() * 0.8));
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(2.6, 1);
      canvas.drawCircle(
        Offset.zero,
        s * 0.004,
        Paint()
          ..color = const Color(0xFF8A5A2A).withValues(alpha: 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.002),
      );
      canvas.restore();
    }
    // Boric powder: fine dust everywhere, swept into faint swirls where
    // the coins have been sliding.
    final dust = Paint();
    for (var i = 0; i < 700; i++) {
      final p = play.topLeft + Offset(s * rng.nextDouble(), s * rng.nextDouble());
      dust.color = Colors.white.withValues(alpha: 0.12 + rng.nextDouble() * 0.28);
      canvas.drawCircle(p, 0.3 + rng.nextDouble() * 0.6, dust);
    }
    for (var i = 0; i < 7; i++) {
      final c = play.topLeft + Offset(s * (0.2 + rng.nextDouble() * 0.6), s * (0.2 + rng.nextDouble() * 0.6));
      final r = s * (0.05 + rng.nextDouble() * 0.12);
      final a0 = rng.nextDouble() * math.pi * 2;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        a0,
        1 + rng.nextDouble() * 1.6,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.03
          ..color = Colors.white.withValues(alpha: 0.05)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.01),
      );
    }
    // Lacquer: the lamp's reflection, a broad soft sheen.
    final glare = play.topLeft + Offset(s * 0.47, s * 0.3);
    canvas.save();
    canvas.translate(glare.dx, glare.dy);
    canvas.scale(1.6, 1);
    canvas.drawCircle(
      Offset.zero,
      s * 0.18,
      Paint()
        ..shader = ui.Gradient.radial(Offset.zero, s * 0.18, [
          Colors.white.withValues(alpha: 0.13),
          Colors.transparent,
        ]),
    );
    canvas.restore();
    canvas.restore();
  }

  void _markings(Canvas canvas, Offset Function(double, double) at, double s) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, s * 0.0026)
      ..color = CarromBoardPainter._ink.withValues(alpha: 0.88);
    final fine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.7, s * 0.0016)
      ..color = CarromBoardPainter._ink.withValues(alpha: 0.8);
    // Four bases: two lines 3.18 cm apart, a red circle closing each end.
    final gap = CarromRules.coinR;
    for (var side = 0; side < 4; side++) {
      Offset pt(double along, double inset) => switch (side) {
        0 => at(along, 1 - inset),
        1 => at(along, inset),
        2 => at(inset, along),
        _ => at(1 - inset, along),
      };
      for (final off in [-gap, gap]) {
        canvas.drawLine(
          pt(CarromRules.baseMin, CarromRules.baseInset + off),
          pt(CarromRules.baseMax, CarromRules.baseInset + off),
          line,
        );
      }
      for (final end in [CarromRules.baseMin, CarromRules.baseMax]) {
        final c = pt(end, CarromRules.baseInset);
        final r = gap * s;
        canvas.drawCircle(c, r * 0.86, Paint()..shader = ui.Gradient.radial(c, r, [CarromBoardPainter._red, const Color(0xFF8E1A14)]));
        canvas.drawCircle(c, r, line);
      }
    }
    // Arrows: 26.7 cm diagonals pointing into each pocket, an arc at the tail.
    for (final (cx, cy) in CarromRules.pockets) {
      final dx = cx < 0.5 ? 1.0 : -1.0, dy = cy < 0.5 ? 1.0 : -1.0;
      final a = at(cx + dx * 0.072, cy + dy * 0.072), b = at(cx + dx * 0.33, cy + dy * 0.33);
      canvas.drawLine(a, b, line);
      final u = (a - b) / (a - b).distance;
      final n = Offset(-u.dy, u.dx);
      final h = s * 0.017;
      canvas.drawLine(a, a - u * h + n * h * 0.65, line);
      canvas.drawLine(a, a - u * h - n * h * 0.65, line);
      canvas.drawArc(Rect.fromCircle(center: b, radius: s * 0.043), math.atan2(u.dy, u.dx) - 2.2, 4.4, false, line);
    }
    // Centre: the 17 cm double ring, a rose of eight petals, the red spot.
    final c = at(0.5, 0.5);
    canvas.drawCircle(c, s * 0.115, line);
    canvas.drawCircle(c, s * 0.106, fine);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final tip = c + Offset(math.cos(a), math.sin(a)) * (s * 0.098);
      final l = c + Offset(math.cos(a - 0.32), math.sin(a - 0.32)) * (s * 0.045);
      final r = c + Offset(math.cos(a + 0.32), math.sin(a + 0.32)) * (s * 0.045);
      final petal = Path()
        ..moveTo(c.dx, c.dy)
        ..quadraticBezierTo(l.dx, l.dy, tip.dx, tip.dy)
        ..quadraticBezierTo(r.dx, r.dy, c.dx, c.dy)
        ..close();
      canvas.drawPath(petal, Paint()..color = (i.isEven ? CarromBoardPainter._red : CarromBoardPainter._ink).withValues(alpha: i.isEven ? 0.20 : 0.07));
      canvas.drawPath(petal, fine);
    }
    canvas.drawCircle(
      c,
      s * CarromRules.coinR,
      Paint()..shader = ui.Gradient.radial(c, s * CarromRules.coinR, [CarromBoardPainter._red, const Color(0xFF8E1A14)]),
    );
    canvas.drawCircle(c, s * CarromRules.coinR, line);
  }

  void _pockets(Canvas canvas, Offset Function(double, double) at, double s) {
    for (final (px, py) in CarromRules.pockets) {
      final c = at(px, py);
      final r = CarromRules.pocketR * s;
      // The cut edge: plywood layers showing round the hole.
      canvas.drawCircle(
        c,
        r + 1.6,
        Paint()..shader = ui.Gradient.radial(c, r + 1.6, [const Color(0xFFCFAE78), const Color(0xFF8C6A3C)], [0.9, 1]),
      );
      // Down into the net: dark, a little light reaching the far side.
      final towardLamp = (Offset(_lamp.dx - px, _lamp.dy - py)) * (r * 0.6);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            c + towardLamp,
            r * 1.2,
            [const Color(0xFF2A1D14), const Color(0xFF0E0906), Colors.black],
            [0, 0.55, 1],
          ),
      );
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.92)));
      // Netting: a sagging diamond mesh, lit on the lamp side.
      final net = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..shader = ui.Gradient.radial(c + towardLamp, r, [
          const Color(0xFFD8C8A8).withValues(alpha: 0.16),
          const Color(0xFFD8C8A8).withValues(alpha: 0.02),
        ]);
      for (var k = -5; k <= 5; k++) {
        final o = k * r / 3.2;
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - r, c.dy + o - r)
            ..quadraticBezierTo(c.dx, c.dy + o + r * 0.25, c.dx + r, c.dy + o + r),
          net,
        );
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - r, c.dy + o + r)
            ..quadraticBezierTo(c.dx, c.dy + o + r * 0.25, c.dx + r, c.dy + o - r),
          net,
        );
      }
      // The board's thickness: the rim casts the hole's near side into shadow.
      canvas.drawCircle(
        c - towardLamp * 0.5,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.35
          ..color = Colors.black.withValues(alpha: 0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12),
      );
      canvas.restore();
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF2A1A0E),
      );
    }
  }
}


// ── Carrom men ──

/// Polished face of each kind on a unit circle, reused for every disc.
final Map<CarromKind, Paint> _discFace = {
  for (final kind in CarromKind.values)
    kind: Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        radius: 1.05,
        colors: [_discColors(kind).$1, _discColors(kind).$2],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)),
};

(Color, Color, Color) _discColors(CarromKind kind) => switch (kind) {
  CarromKind.white => (const Color(0xFFFBF3E0), const Color(0xFFD9C79F), const Color(0xFFC2A878)),
  CarromKind.black => (const Color(0xFF3A3A40), const Color(0xFF16161A), const Color(0xFF66666E)),
  CarromKind.queen => (const Color(0xFFE53950), const Color(0xFF9E1028), const Color(0xFFFFA3B0)),
  CarromKind.striker => (const Color(0xFFFFFFFF), const Color(0xFFCFD6E4), const Color(0xFF3B5BDB)),
};

/// One carrom man (or the striker) at [c] with radius [r]: polished face,
/// turned grooves, rim and shine. [angle] turns the man's grain, or the
/// striker's star.
void paintCarromDisc(
  Canvas canvas,
  Offset c,
  double r,
  CarromKind kind, {
  double angle = 0,
  bool shadow = true,
}) {
  if (shadow) {
    canvas.drawCircle(
      c + Offset(r * 0.18, r * 0.26),
      r * 1.02,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.25),
    );
  }
  final (_, edge, ring) = _discColors(kind);
  canvas
    ..save()
    ..translate(c.dx, c.dy)
    ..scale(r)
    ..drawCircle(Offset.zero, 1, _discFace[kind]!)
    ..restore();
  final rp = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.8, r * 0.09)
    ..color = ring.withValues(alpha: 0.85);
  // Turned grooves: a dark cut with a lit edge just inside it.
  final lit = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.5, r * 0.04)
    ..color = Colors.white.withValues(alpha: kind == CarromKind.black ? 0.18 : 0.45);
  for (final k in const [0.8, 0.58, 0.34]) {
    canvas.drawCircle(c, r * k, rp..strokeWidth = math.max(0.6, r * 0.06));
    canvas.drawCircle(c + Offset(r * 0.02, r * 0.03), r * (k - 0.05), lit);
  }
  if (kind == CarromKind.striker) {
    // Striker emblem: a small star.
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final rr = (i.isEven ? 0.32 : 0.14) * r;
      final a = -math.pi / 2 + angle + i * math.pi / 5;
      final q = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(p..close(), Paint()..color = ring);
  }
  if (kind != CarromKind.striker) {
    // The grain: a darker figure and a fleck, off-centre, that turn with it.
    final figure = Rect.fromCircle(center: c, radius: r * 0.69);
    canvas.drawArc(
      figure,
      angle,
      1.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, r * 0.13)
        ..strokeCap = StrokeCap.round
        ..color = edge.withValues(alpha: 0.75),
    );
    canvas.drawCircle(
      c + Offset(math.cos(angle + math.pi), math.sin(angle + math.pi)) * (r * 0.46),
      math.max(0.6, r * 0.07),
      Paint()..color = ring.withValues(alpha: 0.9),
    );
  }
  // Rim and shine.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, r * 0.07)
      ..color = edge,
  );
  canvas.drawCircle(c + Offset(-r * 0.35, -r * 0.4), r * 0.22, Paint()..color = Colors.white.withValues(alpha: 0.35));
}

/// A player's pocketed coins in a small wooden tray (3 × 3), with the queen
/// beside them once covered.
class CarromTray extends StatelessWidget {
  const CarromTray({super.key, required this.count, required this.kind, required this.queen});
  final int count;
  final CarromKind kind;
  final bool queen;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 72, height: 72, child: CustomPaint(painter: _TrayPainter(count, kind, queen)));
}

class _TrayPainter extends CustomPainter {
  _TrayPainter(this.count, this.kind, this.queen);
  final int count;
  final CarromKind kind;
  final bool queen;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
    canvas.drawRRect(
      r.shift(const Offset(0, 3)),
      Paint()
        ..color = Colors.black54
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF7A3A1C), Color(0xFF4A1E0C), Color(0xFF2E1206)],
        ).createShader(Offset.zero & size),
    );
    // The felt-lined well.
    final well = RRect.fromRectAndRadius((Offset.zero & size).deflate(6), const Radius.circular(8));
    canvas.drawRRect(well, Paint()..color = const Color(0xFF1A2A20));
    canvas.drawRRect(
      well,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    final cell = well.width / 3;
    final cr = cell * 0.4;
    for (var i = 0; i < CarromRules.coinsEach; i++) {
      final c = Offset(well.left + cell * (i % 3 + 0.5), well.top + cell * (i ~/ 3 + 0.5));
      if (i < count) {
        paintCarromDisc(canvas, c, cr, kind, angle: i * 1.3);
      } else {
        canvas.drawCircle(c, cr, Paint()..color = Colors.black.withValues(alpha: 0.28));
        canvas.drawCircle(
          c,
          cr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.05),
        );
      }
    }
    if (queen) {
      final c = Offset(size.width - 4, 4);
      canvas.drawCircle(
        c,
        13,
        Paint()
          ..color = const Color(0x88E53950)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      paintCarromDisc(canvas, c, 10, CarromKind.queen);
    }
  }

  @override
  bool shouldRepaint(_TrayPainter old) => old.count != count || old.queen != queen || old.kind != kind;
}

/// The striker drawn as a slider thumb.
class CarromStrikerIcon extends StatelessWidget {
  const CarromStrikerIcon({super.key, required this.size, this.ring});
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _StrikerIconPainter(ring));
}

class _StrikerIconPainter extends CustomPainter {
  _StrikerIconPainter(this.ring);
  final Color? ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 3;
    paintCarromDisc(canvas, c, r, CarromKind.striker);
    if (ring != null) {
      canvas.drawCircle(
        c,
        r + 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = ring!,
      );
    }
  }

  @override
  bool shouldRepaint(_StrikerIconPainter old) => old.ring != ring;
}
