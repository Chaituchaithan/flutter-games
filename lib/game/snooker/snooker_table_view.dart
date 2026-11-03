import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'snooker_engine.dart';

/// A match table under its long lamp: a mahogany frame, napped green baize
/// lit down the middle, cushions that follow the real noses and jaws the
/// balls bounce off, leather-lined pockets, the baulk line, the D and the
/// spots. The table and the balls are separate layers: the table is painted
/// once and only the balls repaint.

/// Table → canvas: margins around the 3569 × 1778 mm playing area.
class SnookerLayout {
  const SnookerLayout(this.size);
  final Size size;

  static const pad = 0.15;
  static const aspect = (SnookerRules.width + 2 * pad) / (SnookerRules.length + 2 * pad);

  double get scale => size.width / (SnookerRules.width + 2 * pad);
  Offset at(double x, double y) => Offset((x + pad) * scale, (y + pad) * scale);
  (double, double) toTable(Offset p) => (p.dx / scale - pad, p.dy / scale - pad);
}

/// The table itself: never changes, so it never repaints.
class SnookerTablePainter extends CustomPainter {
  const SnookerTablePainter();

  static const _baize = Color(0xFF0F7A41);

  @override
  bool shouldRepaint(SnookerTablePainter oldDelegate) => false;

  @override
  void paint(Canvas canvas, Size size) {
    final l = SnookerLayout(size);
    final s = l.scale;
    const w = SnookerRules.width, h = SnookerRules.length;
    _frame(canvas, size, s);

    // Baize, running out under the cushions to the wood.
    final cloth = Rect.fromPoints(l.at(-0.06, -0.06), l.at(w + 0.06, h + 0.06));
    canvas.drawRect(cloth, Paint()..color = _baize);
    final rng = math.Random(7);
    final nap = Paint()..strokeWidth = math.max(0.5, s * 0.0016);
    for (var i = 0; i < 1400; i++) {
      final x = cloth.left + rng.nextDouble() * cloth.width, y = cloth.top + rng.nextDouble() * cloth.height;
      nap.color = (i.isEven ? Colors.white : Colors.black).withValues(alpha: 0.025 + rng.nextDouble() * 0.03);
      canvas.drawLine(Offset(x, y), Offset(x, y + s * 0.012), nap);
    }
    // The light falls off towards the corners; the nap brushed to the black.
    canvas
      ..save()
      ..clipRect(cloth)
      ..translate(cloth.center.dx, cloth.center.dy)
      ..scale(0.62, 1)
      ..drawCircle(
        Offset.zero,
        cloth.height,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, cloth.height * 0.62, [
            Colors.white.withValues(alpha: 0.13),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.34),
          ], const [0, 0.48, 1]),
      )
      ..restore();

    _markings(canvas, l);
    _pockets(canvas, l);
    _cushions(canvas, l);
  }

  void _frame(Canvas canvas, Size size, double s) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.05));
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, const [
          Color(0xFF5E2C14),
          Color(0xFF3A170A),
          Color(0xFF5A2912),
          Color(0xFF2E1107),
        ], const [0, 0.35, 0.68, 1]),
    );
    canvas.save();
    canvas.clipRRect(rr);
    final rng = math.Random(3);
    final grain = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, s * 0.002);
    for (var i = 0; i < 90; i++) {
      final x = rng.nextDouble() * size.width;
      grain.color = Colors.black.withValues(alpha: 0.06 + rng.nextDouble() * 0.12);
      canvas.drawPath(
        Path()
          ..moveTo(x, 0)
          ..cubicTo(x + 6, size.height * 0.3, x - 6, size.height * 0.7, x + 2, size.height),
        grain,
      );
    }
    canvas.restore();
    canvas.drawRRect(
      rr.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x40FFD9B0),
    );
  }

  void _markings(Canvas canvas, SnookerLayout l) {
    final s = l.scale;
    const w = SnookerRules.width, by = SnookerRules.baulkY, dr = SnookerRules.dRadius;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, s * 0.004)
      ..color = Colors.white.withValues(alpha: 0.55);
    canvas.drawLine(l.at(0, by), l.at(w, by), line);
    canvas.drawArc(
      Rect.fromCircle(center: l.at(w / 2, by), radius: dr * s),
      0,
      math.pi,
      false,
      line,
    );
    final spot = Paint()..color = Colors.white.withValues(alpha: 0.6);
    for (final (x, y) in SnookerRules.spots.values) {
      canvas.drawCircle(l.at(x, y), math.max(0.9, s * 0.006), spot);
    }
  }

  void _pockets(Canvas canvas, SnookerLayout l) {
    final s = l.scale;
    const w = SnookerRules.width, h = SnookerRules.length;
    final holes = [
      (-0.018, -0.018, 0.064),
      (w + 0.018, -0.018, 0.064),
      (-0.018, h + 0.018, 0.064),
      (w + 0.018, h + 0.018, 0.064),
      (-0.034, h / 2, 0.066),
      (w + 0.034, h / 2, 0.066),
    ];
    for (final (x, y, r) in holes) {
      final c = l.at(x, y);
      // Leather and brass round the drop, then the dark inside it.
      canvas.drawCircle(c, (r + 0.02) * s, Paint()..color = const Color(0xFF17100B));
      canvas.drawCircle(
        c,
        (r + 0.02) * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, s * 0.008)
          ..color = const Color(0xFF8A6A36),
      );
      canvas.drawCircle(
        c,
        r * s,
        Paint()
          ..shader = ui.Gradient.radial(c, r * s, const [Colors.black, Color(0xFF0B0705)], const [0.6, 1]),
      );
    }
  }

  void _cushions(Canvas canvas, SnookerLayout l) {
    const w = SnookerRules.width, h = SnookerRules.length, c = SnookerRules.cornerMouth, m = SnookerRules.midMouth;
    const mid = h / 2, o = -0.052;
    // Each cushion: from jaw end, along the nose, to the other jaw end.
    final strips = <List<(double, double)>>[
      [(0.035, o), (c, 0), (w - c, 0), (w - 0.035, o)],
      [(0.035, h - o), (c, h), (w - c, h), (w - 0.035, h - o)],
      [(o, 0.035), (0, c), (0, mid - m), (o, mid - m * 0.9)],
      [(o, mid + m * 0.9), (0, mid + m), (0, h - c), (o, h - 0.035)],
      [(w - o, 0.035), (w, c), (w, mid - m), (w - o, mid - m * 0.9)],
      [(w - o, mid + m * 0.9), (w, mid + m), (w, h - c), (w - o, h - 0.035)],
    ];
    for (final pts in strips) {
      final path = Path()..moveTo(l.at(pts[0].$1, pts[0].$2).dx, l.at(pts[0].$1, pts[0].$2).dy);
      for (final (x, y) in pts.skip(1)) {
        final p = l.at(x, y);
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = const Color(0xFF0B5E32));
      // Lit nose, and the soft shadow it lays on the bed of the table.
      final nose = Path();
      for (var i = 0; i < pts.length; i++) {
        final p = l.at(pts[i].$1, pts[i].$2);
        i == 0 ? nose.moveTo(p.dx, p.dy) : nose.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        nose,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, l.scale * 0.009)
          ..color = Colors.black.withValues(alpha: 0.28),
      );
      canvas.drawPath(
        nose,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.7, l.scale * 0.003)
          ..color = const Color(0x6FA8E8BE),
      );
    }
  }
}

/// The balls, the cue and the aiming guide. Repaints with the game.
class SnookerBallsPainter extends CustomPainter {
  SnookerBallsPainter({
    required this.game,
    required this.aim,
    required this.power,
    required this.showGuide,
    required this.inHandRing,
    super.repaint,
  });

  final SnookerGame game;

  /// Direction the cue is pointing (null = no cue on the table).
  final (double, double)? aim;
  final double power;
  final bool showGuide;
  final bool inHandRing;

  static const _tones = {
    SnookerKind.cue: Color(0xFFF7F3E6),
    SnookerKind.red: Color(0xFFC3141F),
    SnookerKind.yellow: Color(0xFFF3C614),
    SnookerKind.green: Color(0xFF1F9C4F),
    SnookerKind.brown: Color(0xFF7A4318),
    SnookerKind.blue: Color(0xFF1656C4),
    SnookerKind.pink: Color(0xFFF184A9),
    SnookerKind.black: Color(0xFF17171B),
  };

  /// One shading per kind, on a unit circle, reused for every ball and frame.
  static final Map<SnookerKind, Paint> _shade = {
    for (final e in _tones.entries)
      e.key: Paint()
        ..shader = ui.Gradient.radial(const Offset(-0.32, -0.38), 1.45, [
          Color.lerp(e.value, Colors.white, 0.28)!,
          e.value,
          Color.lerp(e.value, Colors.black, 0.62)!,
        ], const [0, 0.42, 1]),
  };
  static final Paint _gloss = Paint()
    ..shader = ui.Gradient.radial(const Offset(-0.36, -0.42), 0.3, [
      Colors.white.withValues(alpha: 0.95),
      Colors.white.withValues(alpha: 0),
    ]);
  static final Paint _bounceLight = Paint()
    ..shader = ui.Gradient.radial(const Offset(0.34, 0.5), 0.5, [
      Colors.white.withValues(alpha: 0.16),
      Colors.white.withValues(alpha: 0),
    ]);
  static final Paint _castShadow = Paint()
    ..shader = ui.Gradient.radial(Offset.zero, 1, [
      Colors.black.withValues(alpha: 0.55),
      Colors.black.withValues(alpha: 0.32),
      Colors.black.withValues(alpha: 0),
    ], const [0, 0.65, 1]);

  /// Marks on the surface that show the ball rolling: the red spots of a
  /// practice cue ball, and faint flecks in the phenolic of the others.
  static const _marks = [
    (0.0, 0.0, 1.0),
    (0.0, 0.0, -1.0),
    (1.0, 0.0, 0.0),
    (-1.0, 0.0, 0.0),
    (0.0, 1.0, 0.0),
    (0.0, -1.0, 0.0),
  ];

  @override
  bool shouldRepaint(SnookerBallsPainter old) =>
      old.aim != aim || old.power != power || old.showGuide != showGuide || old.inHandRing != inHandRing;

  @override
  void paint(Canvas canvas, Size size) {
    final l = SnookerLayout(size);
    final s = l.scale;
    const r = SnookerRules.r;
    final rPx = r * s;

    for (final k in game.sinking) {
      final (px, py) = SnookerRules.pockets[k.pocket];
      final t = (k.t / 0.3).clamp(0.0, 1.0);
      final pos = Offset.lerp(l.at(k.x, k.y), l.at(px, py), Curves.easeIn.transform(t))!;
      _ball(canvas, pos, rPx * (1 - 0.3 * t), k.kind);
      canvas.drawCircle(pos, rPx * (1 - 0.3 * t) + 0.5, Paint()..color = Colors.black.withValues(alpha: t));
    }
    // The lamp hangs over the middle: shadows lean away from it, and lie
    // under every ball before any ball is drawn.
    for (final b in game.balls) {
      final dy = (b.y - SnookerRules.length / 2) / SnookerRules.length;
      final dx = (b.x - SnookerRules.width / 2) / SnookerRules.width;
      final c = l.at(b.x, b.y) + Offset(dx * rPx * 1.2 + rPx * 0.08, dy * rPx * 1.2 + rPx * 0.12);
      canvas
        ..save()
        ..translate(c.dx, c.dy)
        ..scale(rPx * 1.32)
        ..drawCircle(Offset.zero, 1, _castShadow)
        ..restore();
    }

    final dir = aim;
    if (dir != null && showGuide) _guide(canvas, l, dir);
    for (final b in game.balls) {
      _ball(canvas, l.at(b.x, b.y), rPx, b.kind, ball: b);
    }
    if (inHandRing && game.balls.contains(game.cue)) {
      canvas.drawCircle(
        l.at(game.cue.x, game.cue.y),
        rPx + 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withValues(alpha: 0.7),
      );
    }
    // The cue stays over the table, not over the controls under it.
    if (dir != null) {
      canvas
        ..save()
        ..clipRect(Offset.zero & size);
      _cue(canvas, l, dir);
      canvas.restore();
    }
  }

  void _ball(Canvas canvas, Offset c, double r, SnookerKind kind, {SnookerBall? ball}) {
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..scale(r)
      ..drawCircle(Offset.zero, 1, _shade[kind]!);
    if (ball != null) {
      final mark = Paint()
        ..color = kind == SnookerKind.cue
            ? const Color(0xFFC92A2A)
            : (kind == SnookerKind.black ? Colors.white.withValues(alpha: 0.16) : Colors.black.withValues(alpha: 0.2));
      for (final (x, y, z) in _marks) {
        final (px, py, pz) = ball.surface(x, y, z);
        if (pz <= 0.05) continue;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(px, py), width: 0.3 * (0.35 + 0.65 * pz), height: 0.3 * (0.35 + 0.65 * pz)),
          mark,
        );
      }
    }
    canvas
      ..drawCircle(Offset.zero, 1, _bounceLight)
      ..drawCircle(Offset.zero, 1, _gloss)
      ..restore();
  }

  void _guide(Canvas canvas, SnookerLayout l, (double, double) dir) {
    final s = l.scale;
    final g = snookerAimGuide(game, dir.$1, dir.$2);
    final from = l.at(game.cue.x, game.cue.y), to = l.at(g.x, g.y);
    final line = Paint()
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.62);
    canvas.drawLine(from, to, line);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.75);
    canvas.drawCircle(to, SnookerRules.r * s, ring);
    if (g.hit == null) return;
    // Where the object ball goes, and the tangent the cue ball leaves on.
    final hit = l.at(g.hit!.x, g.hit!.y);
    final len = 0.5 * s;
    canvas.drawLine(
      hit,
      hit + Offset(g.objX, g.objY) * len,
      Paint()
        ..strokeWidth = 1.6
        ..color = const Color(0xCCFFE082),
    );
    canvas.drawLine(
      to,
      to + Offset(g.cueX, g.cueY) * (len * 0.5),
      Paint()
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.3),
    );
  }

  /// A tapered ash cue, drawn back with the power.
  void _cue(Canvas canvas, SnookerLayout l, (double, double) dir) {
    final s = l.scale;
    final c = l.at(game.cue.x, game.cue.y);
    final angle = math.atan2(dir.$2, dir.$1);
    final gap = (SnookerRules.r + 0.012 + power * 0.26) * s;
    final len = 1.47 * s;
    final tip = math.max(1.4, s * 0.0105), butt = math.max(3.2, s * 0.024);
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(angle + math.pi);
    Path piece(double a, double b) {
      double half(double t) => tip + (butt - tip) * (t / len);
      return Path()
        ..moveTo(gap + a, -half(a))
        ..lineTo(gap + b, -half(b))
        ..lineTo(gap + b, half(b))
        ..lineTo(gap + a, half(a))
        ..close();
    }

    canvas.drawPath(
      piece(0, len).shift(const Offset(2, 3)),
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );
    canvas.drawPath(
      piece(0, len * 0.66),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, -butt), Offset(0, butt), const [
          Color(0xFFD9B77C),
          Color(0xFFF2DDAE),
          Color(0xFFB08A4F),
        ], const [0, 0.42, 1]),
    );
    canvas.drawPath(
      piece(len * 0.66, len),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, -butt), Offset(0, butt), const [
          Color(0xFF2A1408),
          Color(0xFF53301A),
          Color(0xFF190B04),
        ], const [0, 0.42, 1]),
    );
    canvas.drawPath(piece(0, s * 0.012), Paint()..color = const Color(0xFF3A6EA5)); // chalked tip
    canvas.drawPath(piece(s * 0.012, s * 0.03), Paint()..color = const Color(0xFFF2EEE0)); // ferrule
    canvas.restore();
  }
}

/// A snooker ball for the UI (trays, the spin pad).
class SnookerBallIcon extends StatelessWidget {
  const SnookerBallIcon({super.key, required this.kind, required this.size, this.tip});
  final SnookerKind kind;
  final double size;

  /// Where the cue tip lands, −1..1 each way (the spin pad).
  final Offset? tip;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _BallIconPainter(kind, tip));
}

class _BallIconPainter extends CustomPainter {
  const _BallIconPainter(this.kind, this.tip);
  final SnookerKind kind;
  final Offset? tip;

  @override
  bool shouldRepaint(_BallIconPainter old) => old.kind != kind || old.tip != tip;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    canvas
      ..save()
      ..translate(r, r)
      ..scale(r)
      ..drawCircle(Offset.zero, 1, SnookerBallsPainter._shade[kind]!)
      ..drawCircle(Offset.zero, 1, SnookerBallsPainter._gloss)
      ..restore();
    final t = tip;
    if (t == null) return;
    final c = Offset(r, r);
    final hair = Paint()
      ..strokeWidth = 0.8
      ..color = Colors.black.withValues(alpha: 0.2);
    canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), hair);
    canvas.drawLine(c - Offset(0, r), c + Offset(0, r), hair);
    canvas.drawCircle(c + t * r * 0.8, r * 0.17, Paint()..color = const Color(0xFF2F6FB0));
    canvas.drawCircle(
      c + t * r * 0.8,
      r * 0.17,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white,
    );
  }
}
