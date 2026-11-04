import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'carrom_engine.dart';

/// A casual carrom board: warm polished wood framed by slim lacquered red
/// rails with gold corner caps, engraved baselines and centre ring, glossy
/// coins and a gold-rimmed striker. Aiming shows a red arrow ahead of the
/// striker and a dotted pull-back trail behind it.

/// "+1" / ♛ / FOUL rising from a pocket.
class CarromPop {
  CarromPop(this.kind, this.pocket, this.born);
  final CarromKind kind;
  final int pocket;
  final double born;
}

/// The shot being lined up: direction (board units, any length) and power
/// 0..1. The painter reads it when it paints, so dragging, or the computer
/// pulling back, repaints only the board.
class CarromAim extends ChangeNotifier {
  (double, double)? _dir;
  double _power = 0;

  (double, double)? get dir => _dir;
  double get power => _power;

  void set((double, double)? dir, double power) {
    if (dir == _dir && power == _power) return;
    _dir = dir;
    _power = power;
    notifyListeners();
  }

  void clear() => set(null, 0);
}

class CarromBoardPainter extends CustomPainter {
  CarromBoardPainter({
    required this.game,
    required this.aimState,
    required this.yourTurn,
    required this.pops,
    required this.time,
    super.repaint,
  });

  final CarromGame game;
  final CarromAim aimState;
  (double, double)? get aim => aimState.dir;
  double get power => aimState.power;
  final bool yourTurn;
  final List<CarromPop> pops;

  /// Seconds since the game started (pops and the turn halo). Listenable, so
  /// the idle halo repaints this layer without rebuilding the screen.
  final ValueListenable<double> time;
  double get clock => time.value;

  /// Frame width as a share of the board's side.
  static const frame = 0.028;

  /// A soft round shadow on a unit circle (scaled per disc).
  static final Paint _shadowPaint = Paint()
    ..shader = ui.Gradient.radial(Offset.zero, 1, [
      Colors.black.withValues(alpha: 0.45),
      Colors.black.withValues(alpha: 0.32),
      Colors.black.withValues(alpha: 0),
    ], const [0, 0.72, 1]);

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

    // Coins dropping into a pocket.
    for (final k in game.sinking) {
      final (px, py) = CarromRules.pockets[k.pocket];
      final t = (k.t / 0.35).clamp(0.0, 1.0);
      final pc = at(px, py);
      final pos = Offset.lerp(at(k.x, k.y), pc, Curves.easeIn.transform(t))!;
      final r = (k.kind == CarromKind.striker ? CarromRules.strikerR : CarromRules.coinR) * s * (1 - 0.35 * t);
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: pc, radius: CarromRules.pocketR * s)));
      paintCarromDisc(canvas, pos, r, k.kind, shadow: false);
      canvas.drawCircle(pos, r * 1.05, Paint()..color = Colors.black.withValues(alpha: 0.2 + 0.75 * t));
      canvas.restore();
    }

    // Your shot: a dark halo round the striker (under everything).
    final st = game.striker;
    final onBoard = game.discs.contains(st);
    if (onBoard && yourTurn && !game.moving && !game.isOver) {
      final c = at(st.x, st.y);
      final k = 0.5 + 0.5 * math.sin(clock * 3);
      final hr = st.r * s * (2.25 + 0.08 * k);
      canvas.drawCircle(
        c,
        hr,
        Paint()
          ..shader = ui.Gradient.radial(c, hr, [
            Colors.black.withValues(alpha: 0.22),
            Colors.black.withValues(alpha: 0.16),
            Colors.black.withValues(alpha: 0),
          ], const [0, 0.85, 1]),
      );
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
            _tone(d.kind).withValues(alpha: (0.2 * sp / 4).clamp(0.0, 0.2)),
            _tone(d.kind).withValues(alpha: 0),
          ]),
      );
    }

    // Shadows first, then the coins, then the striker on top.
    for (final d in game.discs) {
      final r = d.r * s;
      final c = at(d.x, d.y) + Offset(r * 0.1, r * 0.2);
      canvas
        ..save()
        ..translate(c.dx, c.dy)
        ..scale(r * 1.12)
        ..drawCircle(Offset.zero, 1, _shadowPaint)
        ..restore();
    }
    for (final d in game.discs) {
      if (d.kind == CarromKind.striker) continue;
      paintCarromDisc(canvas, at(d.x, d.y), d.r * s, d.kind, angle: d.angle, shadow: false);
    }
    if (onBoard) {
      final c = at(st.x, st.y);
      _guide(canvas, at, s, behind: true);
      paintCarromDisc(canvas, c, st.r * s, CarromKind.striker, angle: st.angle, shadow: false);
      if (!game.moving && !game.strikerClear) {
        // Can't shoot from here: overlapping a coin.
        canvas.drawCircle(
          c,
          st.r * s + 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const Color(0xFFE5484D),
        );
      }
    }

    _guide(canvas, at, s, behind: false);
    _pops(canvas, at, s);
  }

  static Color _tone(CarromKind k) => switch (k) {
    CarromKind.white => const Color(0xFFF7F3EC),
    CarromKind.black => const Color(0xFF222226),
    CarromKind.queen => const Color(0xFFD4202C),
    CarromKind.striker => const Color(0xFFF2C14E),
  };

  /// "+1" / ♛ / FOUL rising from the pocket.
  void _pops(Canvas canvas, Offset Function(double, double) at, double s) {
    for (final p in pops) {
      final t = ((clock - p.born) / 1.2).clamp(0.0, 1.0);
      final (px, py) = CarromRules.pockets[p.pocket];
      final c = at(px, py) + Offset(px < 0.5 ? s * 0.1 : -s * 0.1, (py < 0.5 ? s * 0.09 : -s * 0.09) - t * s * 0.08);
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

  /// Aiming. [behind] = the part drawn under the striker (the dotted
  /// pull-back trail); otherwise the arrow, the line to first contact and
  /// where the hit coin goes.
  void _guide(Canvas canvas, Offset Function(double, double) at, double s, {required bool behind}) {
    final a = aim;
    if (a == null || power < 0.02 || game.moving) return;
    final la = math.sqrt(a.$1 * a.$1 + a.$2 * a.$2);
    if (la == 0) return;
    final st = game.striker;
    final from = at(st.x, st.y);
    final r = st.r * s;
    final u = Offset(a.$1 / la, a.$2 / la); // shot direction

    if (behind) {
      // Yellow dots trailing back the way you pulled, more as you pull harder.
      final n = (2 + power * 5).round();
      final dot = Paint()..color = const Color(0xFFFFD54F);
      final rim = Paint()..color = const Color(0xFF8A5A00).withValues(alpha: 0.55);
      for (var i = 0; i < n; i++) {
        final p = from - u * (r * 1.45 + i * r * 0.78);
        final dr = r * (0.15 - i * 0.008).clamp(0.08, 0.15);
        canvas.drawCircle(p + const Offset(0, 0.8), dr, rim);
        canvas.drawCircle(p, dr, dot);
      }
      return;
    }

    // A fine line to first contact, a ghost striker there, and the coin's path.
    final g = carromAimGuide(game, a.$1, a.$2);
    final to = at(g.x, g.y);
    final dir = to - from;
    final len = dir.distance;
    final arrowLen = r * (1.4 + 2.4 * power);
    if (len > r * 2) {
      final line = Paint()..color = Colors.white.withValues(alpha: 0.6);
      for (var d = r + arrowLen + 6; d < len - r; d += 7) {
        canvas.drawCircle(from + u * d, 1.2, line);
      }
      canvas.drawCircle(
        to,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = Colors.white.withValues(alpha: 0.6),
      );
      final hit = g.hit;
      if (hit != null) {
        final hc = at(hit.x, hit.y);
        final nv = hc - to;
        final nl = nv.distance;
        if (nl > 0) {
          final end = hc + nv / nl * (s * 0.16);
          canvas.drawLine(
            hc,
            end,
            Paint()
              ..strokeWidth = 2.2
              ..strokeCap = StrokeCap.round
              ..shader = ui.Gradient.linear(hc, end, [const Color(0xFFFFE08A), const Color(0x00FFE08A)]),
          );
        }
      }
    }

    // The red arrow: longer with more power.
    final n = Offset(-u.dy, u.dx);
    final base = from + u * (r * 1.05);
    final head = r * 0.75;
    final tip = base + u * arrowLen;
    final neck = tip - u * head;
    final w = r * 0.2;
    final arrow = Path()
      ..moveTo(base.dx + n.dx * w, base.dy + n.dy * w)
      ..lineTo(neck.dx + n.dx * w, neck.dy + n.dy * w)
      ..lineTo(neck.dx + n.dx * head * 0.62, neck.dy + n.dy * head * 0.62)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(neck.dx - n.dx * head * 0.62, neck.dy - n.dy * head * 0.62)
      ..lineTo(neck.dx - n.dx * w, neck.dy - n.dy * w)
      ..lineTo(base.dx - n.dx * w, base.dy - n.dy * w)
      ..close();
    canvas.drawPath(
      arrow.shift(const Offset(1, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawPath(
      arrow,
      Paint()..shader = ui.Gradient.linear(base, tip, [const Color(0xFFB3141B), const Color(0xFFF0383E)]),
    );
    canvas.drawPath(
      arrow,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF6E0A0E),
    );
  }

  @override
  bool shouldRepaint(CarromBoardPainter old) => true;
}

/// The board itself: frame, wood, markings and pockets. It never changes,
/// so it sits in its own layer and never repaints.
class CarromSurfacePainter extends CustomPainter {
  const CarromSurfacePainter();

  @override
  bool shouldRepaint(CarromSurfacePainter oldDelegate) => false;

  static const _groove = Color(0xFF7A3E17);
  static const _grooveLight = Color(0xFFFFD2A0);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width;
    final f = side * CarromBoardPainter.frame;
    final s = side - 2 * f;
    final at = CarromBoardPainter.mapper(side);
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(side * 0.04));
    final play = Rect.fromLTWH(f, f, s, s);

    // The board stands on the table: a broad soft shadow under it.
    canvas.drawRRect(
      outer.shift(Offset(0, side * 0.014)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, side * 0.022),
    );
    _frame(canvas, size, outer, f);
    _wood(canvas, play, s);
    _markings(canvas, at, s);
    _pockets(canvas, at, s);

    // Where the wood meets the rails: a soft inner shadow and a dark seam.
    canvas.save();
    canvas.clipRect(play);
    canvas.drawRect(
      play.inflate(s * 0.02),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.05
        ..color = Colors.black.withValues(alpha: 0.32)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.012),
    );
    canvas.restore();
    canvas.drawRect(
      play,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF2A0604),
    );
  }

  /// Slim red lacquered rails with gold caps over the four corners.
  void _frame(Canvas canvas, Size size, RRect outer, double f) {
    final side = size.width;
    canvas.save();
    canvas.clipRRect(outer);
    // Lacquer: deep red, lighter along the crown of each rail.
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF5A0F0A));
    for (final (band, from, to) in [
      (Rect.fromLTWH(0, 0, side, f), Alignment.topCenter, Alignment.bottomCenter),
      (Rect.fromLTWH(0, side - f, side, f), Alignment.bottomCenter, Alignment.topCenter),
      (Rect.fromLTWH(0, 0, f, side), Alignment.centerLeft, Alignment.centerRight),
      (Rect.fromLTWH(side - f, 0, f, side), Alignment.centerRight, Alignment.centerLeft),
    ]) {
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            begin: from,
            end: to,
            colors: const [Color(0xFF3E0805), Color(0xFF8C1C14), Color(0xFFB4372B), Color(0xFF7E1710), Color(0xFF2E0503)],
            stops: const [0, 0.25, 0.45, 0.75, 1],
          ).createShader(band),
      );
    }
    // Gold corner caps: an L of polished brass round each corner.
    final cap = side * 0.1;
    for (final corner in [Offset.zero, Offset(side - cap, 0), Offset(0, side - cap), Offset(side - cap, side - cap)]) {
      final box = corner & Size.square(cap);
      canvas.save();
      canvas.clipRect(box);
      canvas.drawRRect(
        outer.deflate(f * 0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = f
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: const [Color(0xFFFFE7A3), Color(0xFFE2A33C), Color(0xFFB0701A), Color(0xFFF6CB6A)],
            stops: const [0, 0.4, 0.7, 1],
          ).createShader(box),
      );
      canvas.restore();
      // Where the cap ends on each rail: a crisp edge.
      final edge = Paint()
        ..strokeWidth = 1.4
        ..color = const Color(0xFF6B3A08);
      final x = corner.dx == 0 ? cap : side - cap;
      final y = corner.dy == 0 ? cap : side - cap;
      final ry = corner.dy == 0 ? 0.0 : side - f;
      final rx = corner.dx == 0 ? 0.0 : side - f;
      canvas.drawLine(Offset(x, ry), Offset(x, ry + f), edge);
      canvas.drawLine(Offset(rx, y), Offset(rx + f, y), edge);
    }
    canvas.restore();
    // A bright lip round the top edge, darkening at the bottom.
    canvas.drawRRect(
      outer.deflate(0.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x88FFD9B0), Color(0x22FFD9B0), Color(0x66000000)],
        ).createShader(Offset.zero & size),
    );
  }

  /// Warm polished wood: lighter in the middle, soft vertical grain.
  void _wood(Canvas canvas, Rect play, double s) {
    final rng = math.Random(7);
    canvas.save();
    canvas.clipRect(play);
    canvas.drawRect(
      play,
      Paint()
        ..shader = ui.Gradient.radial(
          play.center - Offset(0, s * 0.04),
          s * 0.75,
          [const Color(0xFFE9B47E), const Color(0xFFD69A5E), const Color(0xFFB5733F)],
          [0, 0.55, 1],
        ),
    );
    // Broad bands of slightly different tone, then fine grain lines.
    for (var i = 0; i < 10; i++) {
      final x = play.left + s * rng.nextDouble();
      final w = s * (0.02 + rng.nextDouble() * 0.07);
      canvas.drawRect(
        Rect.fromLTWH(x, play.top, w, s),
        Paint()
          ..color = (rng.nextBool() ? const Color(0xFFFFE0B8) : const Color(0xFFA9652F)).withValues(
            alpha: 0.05 + rng.nextDouble() * 0.06,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.5),
      );
    }
    for (var i = 0; i < 140; i++) {
      final x0 = play.left + s * rng.nextDouble();
      final amp = 0.6 + rng.nextDouble() * 3, freq = 1 + rng.nextDouble() * 2.5, ph = rng.nextDouble() * 6;
      final y0 = play.top + s * (rng.nextDouble() * 0.5 - 0.25);
      final len = s * (0.5 + rng.nextDouble() * 0.8);
      final p = Path();
      for (var t = 0; t <= 30; t++) {
        final y = y0 + len * t / 30;
        final x = x0 + math.sin(t / 30 * freq * math.pi + ph) * amp;
        t == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.4 + rng.nextDouble() * 1.0
          ..color = const Color(0xFF8E5226).withValues(alpha: 0.05 + rng.nextDouble() * 0.09),
      );
    }
    // Polish: a soft sheen across the upper middle.
    final glare = play.topLeft + Offset(s * 0.5, s * 0.32);
    canvas.save();
    canvas.translate(glare.dx, glare.dy);
    canvas.scale(1.7, 1);
    canvas.drawCircle(
      Offset.zero,
      s * 0.2,
      Paint()..shader = ui.Gradient.radial(Offset.zero, s * 0.2, [Colors.white.withValues(alpha: 0.10), Colors.transparent]),
    );
    canvas.restore();
    canvas.restore();
  }

  /// A line cut into the wood: dark in the groove, lit on its lower edge.
  void _engrave(Canvas canvas, Path p, double w) {
    canvas.drawPath(
      p.shift(Offset(0, w * 0.8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = _grooveLight.withValues(alpha: 0.45),
    );
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = _groove.withValues(alpha: 0.75),
    );
  }

  void _markings(Canvas canvas, Offset Function(double, double) at, double s) {
    final w = math.max(1.2, s * 0.0035);
    final g = CarromRules.coinR; // half the baseline's width
    for (var side = 0; side < 4; side++) {
      Offset pt(double along, double inset) => switch (side) {
        0 => at(along, 1 - inset),
        1 => at(along, inset),
        2 => at(inset, along),
        _ => at(1 - inset, along),
      };
      // The baseline: a long capsule, its ends rounded round the circles.
      final rect = Rect.fromPoints(
        pt(CarromRules.baseMin - g, CarromRules.baseInset - g),
        pt(CarromRules.baseMax + g, CarromRules.baseInset + g),
      );
      _engrave(canvas, Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(g * s))), w);
      // Its end circles, inlaid in orange.
      for (final end in [CarromRules.baseMin, CarromRules.baseMax]) {
        final c = pt(end, CarromRules.baseInset);
        final r = g * s * 0.8;
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = ui.Gradient.radial(c - Offset(r * 0.25, r * 0.3), r * 1.2, [
              const Color(0xFFF2A070),
              const Color(0xFFD9703E),
              const Color(0xFFB4532A),
            ], const [0, 0.6, 1]),
        );
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.8
            ..color = _groove.withValues(alpha: 0.6),
        );
      }
    }
    // Centre: one ring round the rack and a small red spot under the queen.
    final c = at(0.5, 0.5);
    _engrave(canvas, Path()..addOval(Rect.fromCircle(center: c, radius: s * CarromRules.coinR * 5.6)), w);
    canvas.drawCircle(
      c,
      s * CarromRules.coinR * 0.9,
      Paint()..shader = ui.Gradient.radial(c, s * CarromRules.coinR, [const Color(0xFFD9443A), const Color(0xFF8E1A14)]),
    );
  }

  void _pockets(Canvas canvas, Offset Function(double, double) at, double s) {
    for (final (px, py) in CarromRules.pockets) {
      final c = at(px, py);
      final r = CarromRules.pocketR * s;
      // A lighter worn ring of wood round the hole.
      canvas.drawCircle(
        c,
        r * 1.08,
        Paint()..shader = ui.Gradient.radial(c, r * 1.08, [const Color(0xFF6B3A1C), const Color(0xFF3A1A0A)], [0.85, 1]),
      );
      // The hole: dark, with a woven net at the bottom.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(c, r, [const Color(0xFF2E2016), const Color(0xFF16100B), const Color(0xFF070504)], [0, 0.65, 1]),
      );
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.9)));
      final net = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, r * 0.05)
        ..color = const Color(0xFF6E5A44).withValues(alpha: 0.35);
      final step = r / 3.2;
      for (var k = -4; k <= 4; k++) {
        final o = k * step;
        canvas.drawLine(c + Offset(o - r, -r), c + Offset(o + r, r), net);
        canvas.drawLine(c + Offset(o + r, -r), c + Offset(o - r, r), net);
      }
      // Depth: the rim shades the inside.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.45
          ..color = Colors.black.withValues(alpha: 0.6)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.15),
      );
      canvas.restore();
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFF1A0C05),
      );
    }
  }
}

// ── Coins and striker ──

/// (highlight, body, edge) of each coin.
(Color, Color, Color) _coinColors(CarromKind kind) => switch (kind) {
  CarromKind.white => (const Color(0xFFFFFFFF), const Color(0xFFF0ECE4), const Color(0xFFBDB5A8)),
  CarromKind.black => (const Color(0xFF5E5E66), const Color(0xFF1F1F23), const Color(0xFF060607)),
  CarromKind.queen => (const Color(0xFFFF7A7A), const Color(0xFFD21F2B), const Color(0xFF7E0B14)),
  CarromKind.striker => (const Color(0xFFFFF0B8), const Color(0xFFE2A83E), const Color(0xFF8E5A10)),
};

/// Cached unit-circle paints (drawn under a scale, so no shader per frame).
final Map<CarromKind, Paint> _coinBody = {
  for (final k in CarromKind.values)
    k: Paint()
      ..shader = ui.Gradient.radial(const Offset(-0.3, -0.38), 1.35, [
        _coinColors(k).$1,
        _coinColors(k).$2,
        _coinColors(k).$3,
      ], const [0, 0.55, 1]),
};

final Paint _gloss = Paint()
  ..shader = ui.Gradient.linear(const Offset(0, -1), const Offset(0, 0.1), [
    Colors.white.withValues(alpha: 0.55),
    Colors.white.withValues(alpha: 0),
  ]);

final Paint _rimBevel = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 0.1
  ..shader = ui.Gradient.linear(const Offset(0, -1), const Offset(0, 1), [
    Colors.white.withValues(alpha: 0.35),
    Colors.black.withValues(alpha: 0.35),
  ]);

final Paint _strikerGold = Paint()
  ..shader = ui.Gradient.linear(const Offset(-1, -1), const Offset(1, 1), const [
    Color(0xFFFFEDB0),
    Color(0xFFE6A93F),
    Color(0xFFA9680F),
    Color(0xFFF7CF6E),
  ], const [0, 0.4, 0.72, 1]);

final Paint _strikerFace = Paint()
  ..shader = ui.Gradient.radial(const Offset(-0.2, -0.25), 0.9, const [
    Color(0xFF8B5CF6),
    Color(0xFF5B2BD6),
    Color(0xFF2A1068),
  ], const [0, 0.55, 1]);

/// One coin (or the striker) at [c] with radius [r]: glossy body, a turned
/// groove, a bevelled rim and a shine. [angle] turns the coin's fleck or the
/// striker's star, so you can see them spin.
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
      c + Offset(r * 0.1, r * 0.22),
      r * 1.02,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22),
    );
  }
  canvas
    ..save()
    ..translate(c.dx, c.dy)
    ..scale(r);
  if (kind == CarromKind.striker) {
    _paintStriker(canvas, angle);
  } else {
    final (_, body, edge) = _coinColors(kind);
    canvas.drawCircle(Offset.zero, 1, _coinBody[kind]!);
    // A turned groove: dark cut, lit just below it.
    canvas.drawCircle(
      const Offset(0, 0.03),
      0.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.05
        ..color = Colors.white.withValues(alpha: kind == CarromKind.black ? 0.12 : 0.5),
    );
    canvas.drawCircle(
      Offset.zero,
      0.6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.06
        ..color = Color.lerp(body, edge, 0.75)!.withValues(alpha: 0.7),
    );
    // A small fleck that turns with the coin.
    canvas.drawCircle(
      Offset(math.cos(angle), math.sin(angle)) * 0.78,
      0.07,
      Paint()..color = (kind == CarromKind.black ? Colors.white : edge).withValues(alpha: 0.35),
    );
    canvas.drawCircle(Offset.zero, 0.95, _rimBevel);
    _shine(canvas);
  }
  canvas.restore();
}

void _paintStriker(Canvas canvas, double angle) {
  // Gold rim, a purple face and a gold star.
  canvas.drawCircle(Offset.zero, 1, _strikerGold);
  canvas.drawCircle(Offset.zero, 0.74, _strikerFace);
  canvas.drawCircle(
    Offset.zero,
    0.74,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.06
      ..color = const Color(0xFF6B3F08),
  );
  canvas.drawCircle(
    Offset.zero,
    0.6,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.035
      ..color = const Color(0xFFF2C14E).withValues(alpha: 0.6),
  );
  final star = Path();
  for (var i = 0; i < 10; i++) {
    final rr = i.isEven ? 0.46 : 0.2;
    final a = -math.pi / 2 + angle + i * math.pi / 5;
    final q = Offset(math.cos(a) * rr, math.sin(a) * rr);
    i == 0 ? star.moveTo(q.dx, q.dy) : star.lineTo(q.dx, q.dy);
  }
  star.close();
  canvas.drawPath(star.shift(const Offset(0, 0.04)), Paint()..color = Colors.black.withValues(alpha: 0.35));
  canvas.drawPath(star, _strikerGold);
  canvas.drawCircle(
    Offset.zero,
    0.97,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.06
      ..color = const Color(0xFF7A4A0C),
  );
  _shine(canvas);
}

/// A soft gloss over the top half of a unit disc.
void _shine(Canvas canvas) {
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 0.9)));
  canvas.drawOval(Rect.fromLTRB(-0.75, -0.92, 0.75, 0.05), _gloss);
  canvas.restore();
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
    // Red lacquer, like the board's rails.
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFA42A1E), Color(0xFF6E140D), Color(0xFF3E0805)],
        ).createShader(Offset.zero & size),
    );
    // The wooden well.
    final well = RRect.fromRectAndRadius((Offset.zero & size).deflate(6), const Radius.circular(8));
    canvas.drawRRect(
      well,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFD39258), Color(0xFFA9642F)],
        ).createShader(well.outerRect),
    );
    canvas.drawRRect(
      well,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    final cell = well.width / 3;
    final cr = cell * 0.4;
    for (var i = 0; i < CarromRules.coinsEach; i++) {
      final c = Offset(well.left + cell * (i % 3 + 0.5), well.top + cell * (i ~/ 3 + 0.5));
      if (i < count) {
        paintCarromDisc(canvas, c, cr, kind, angle: i * 1.3);
      } else {
        canvas.drawCircle(c, cr, Paint()..color = Colors.black.withValues(alpha: 0.18));
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
