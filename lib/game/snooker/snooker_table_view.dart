import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'snooker_engine.dart';

/// A bright club table: orange wood rails with white diamond sights, green
/// cloth, cushions that follow the real noses and jaws the balls bounce off,
/// chrome-capped pockets, the baulk line, the D and the spots. The table and
/// the balls are separate layers: the table is painted once and only the
/// balls repaint.
///
/// [SnookerLayout] maps the table to the canvas upright (portrait) or on its
/// side (landscape, baulk on the left); everything is drawn through it.

/// Table → canvas: margins around the 3569 × 1778 mm playing area.
class SnookerLayout {
  const SnookerLayout(this.size, {this.landscape = false});
  final Size size;

  /// On its side: the length runs left to right, baulk on the left.
  final bool landscape;

  static const pad = 0.24;

  /// Width / height of the whole table, upright.
  static const aspect = (SnookerRules.width + 2 * pad) / (SnookerRules.length + 2 * pad);

  /// Width / height of the whole table as drawn.
  static double aspectFor({required bool landscape}) => landscape ? 1 / aspect : aspect;

  double get scale => (landscape ? size.height : size.width) / (SnookerRules.width + 2 * pad);

  /// A point on the table (metres) → canvas.
  Offset at(double x, double y) => landscape
      ? Offset((SnookerRules.length - y + pad) * scale, (x + pad) * scale)
      : Offset((x + pad) * scale, (y + pad) * scale);

  /// A direction on the table → canvas (a quarter turn when on its side).
  Offset vec(double dx, double dy) => landscape ? Offset(-dy, dx) : Offset(dx, dy);

  /// How far table angles turn on the canvas.
  double get turn => landscape ? math.pi / 2 : 0;

  /// Canvas → a point on the table.
  (double, double) toTable(Offset p) => landscape
      ? (p.dy / scale - pad, SnookerRules.length + pad - p.dx / scale)
      : (p.dx / scale - pad, p.dy / scale - pad);
}

/// The table itself: never changes, so it never repaints.
class SnookerTablePainter extends CustomPainter {
  const SnookerTablePainter({this.landscape = false});
  final bool landscape;

  static const _cloth = Color(0xFF26903C);

  /// Where the cloth ends and the wood begins, past the cushion noses.
  static const _clothEdge = 0.06 * SnookerRules.ballScale;

  @override
  bool shouldRepaint(SnookerTablePainter oldDelegate) => oldDelegate.landscape != landscape;

  @override
  void paint(Canvas canvas, Size size) {
    final l = SnookerLayout(size, landscape: landscape);
    final s = l.scale;
    const w = SnookerRules.width, h = SnookerRules.length, e = _clothEdge;
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.06));
    final cloth = Rect.fromPoints(l.at(-e, -e), l.at(w + e, h + e));

    // The table stands on the floor: a soft shadow under it.
    canvas.drawRRect(
      outer.shift(Offset(0, s * 0.02)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03),
    );
    _rails(canvas, size, outer, cloth, l);
    _clothPaint(canvas, cloth, l);
    _markings(canvas, l);
    _cushions(canvas, l);
    _pockets(canvas, outer, l);
    _diamonds(canvas, l);
  }

  /// Polished wood rails, each cut from its own plank: grain along the rail,
  /// a rounded top that catches the lamps in a long lacquer highlight, darker
  /// edges falling away, mitred at the corners.
  void _rails(Canvas canvas, Size size, RRect outer, Rect cloth, SnookerLayout l) {
    final s = l.scale;
    final W = size.width, H = size.height;
    canvas.save();
    canvas.clipRRect(outer);
    // (mitred outline, outer edge point, inner edge point, runs across?)
    final rails = [
      ([Offset.zero, Offset(W, 0), cloth.topRight, cloth.topLeft], Offset(0, 0), Offset(0, cloth.top), true),
      ([Offset(0, H), Offset(W, H), cloth.bottomRight, cloth.bottomLeft], Offset(0, H), Offset(0, cloth.bottom), true),
      ([Offset.zero, cloth.topLeft, cloth.bottomLeft, Offset(0, H)], Offset.zero, Offset(cloth.left, 0), false),
      ([Offset(W, 0), cloth.topRight, cloth.bottomRight, Offset(W, H)], Offset(W, 0), Offset(cloth.right, 0), false),
    ];
    final rng = math.Random(3);
    for (var k = 0; k < rails.length; k++) {
      final (pts, from, to, across) = rails[k];
      canvas.save();
      canvas.clipPath(Path()..addPolygon(pts, true));
      // Each plank a slightly different tone.
      final tone = [const Color(0xFFD7853D), const Color(0xFFCF7D36), const Color(0xFFD48240), const Color(0xFFCC7A34)][k];
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.linear(from, to, [
            const Color(0xFF7A3610),
            Color.lerp(tone, Colors.black, 0.12)!,
            Color.lerp(tone, Colors.white, 0.28)!,
            tone,
            Color.lerp(tone, Colors.black, 0.35)!,
          ], const [0, 0.14, 0.42, 0.72, 1]),
      );
      // Figure: broad soft streaks, then fine grain lines.
      final depth = (to - from).distance;
      Offset at(double along, double off) =>
          across ? Offset(along, from.dy + (to.dy - from.dy) * off) : Offset(from.dx + (to.dx - from.dx) * off, along);
      final length = across ? W : H;
      for (var i = 0; i < 6; i++) {
        final off = rng.nextDouble();
        canvas.drawLine(
          at(0, off),
          at(length, off + (rng.nextDouble() - 0.5) * 0.2),
          Paint()
            ..strokeWidth = depth * (0.08 + rng.nextDouble() * 0.18)
            ..color = (rng.nextBool() ? const Color(0xFF6E2E0A) : const Color(0xFFFFC98A)).withValues(alpha: 0.08)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, depth * 0.08),
        );
      }
      for (var i = 0; i < 46; i++) {
        final off = rng.nextDouble();
        final amp = depth * (0.01 + rng.nextDouble() * 0.04), freq = 1 + rng.nextDouble() * 4, ph = rng.nextDouble() * 6;
        final path = Path();
        for (var t = 0; t <= 48; t++) {
          final along = length * t / 48;
          final o = off + amp / depth * math.sin(t / 48 * freq * math.pi + ph);
          final q = at(along, o);
          t == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
        }
        final dark = rng.nextDouble() < 0.7;
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(0.5, s * (0.001 + rng.nextDouble() * 0.0025))
            ..color = (dark ? const Color(0xFF5E2508) : const Color(0xFFFFD9A8)).withValues(
              alpha: dark ? 0.05 + rng.nextDouble() * 0.08 : 0.03 + rng.nextDouble() * 0.05,
            ),
        );
      }
      // Lacquer: the lamps reflected in a long soft line along the crown.
      canvas.drawLine(
        at(0, 0.38),
        at(length, 0.38),
        Paint()
          ..strokeWidth = depth * 0.12
          ..color = Colors.white.withValues(alpha: 0.22)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, depth * 0.06),
      );
      canvas.drawLine(
        at(0, 0.36),
        at(length, 0.36),
        Paint()
          ..strokeWidth = math.max(0.6, depth * 0.02)
          ..color = Colors.white.withValues(alpha: 0.35),
      );
      canvas.restore();
    }
    // Mitre joints at the corners.
    for (final (a, b) in [
      (Offset.zero, cloth.topLeft),
      (Offset(W, 0), cloth.topRight),
      (Offset(0, H), cloth.bottomLeft),
      (Offset(W, H), cloth.bottomRight),
    ]) {
      canvas.drawLine(
        a,
        b,
        Paint()
          ..strokeWidth = 1
          ..color = Colors.black.withValues(alpha: 0.45),
      );
    }
    canvas.restore();
    // Rounded outer edge: lit on top, dark below.
    canvas.drawRRect(
      outer.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, s * 0.008)
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, H), const [
          Color(0xAAFFE2B8),
          Color(0x22FFE2B8),
          Color(0x88401A05),
        ], const [0, 0.5, 1]),
    );
    // A dark groove where the wood meets the cushions, its lower lip lit.
    canvas.drawRect(
      cloth.inflate(s * 0.006),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.012
        ..color = const Color(0xFF3E1A06),
    );
    canvas.drawRect(
      cloth.inflate(s * 0.013),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, s * 0.002)
        ..color = const Color(0x55FFD9A8),
    );
  }

  /// Match baize under a three-lamp canopy: a pool of light under each lamp
  /// along the table, falling off to the cushions, with a fine woven texture.
  void _clothPaint(Canvas canvas, Rect cloth, SnookerLayout l) {
    final s = l.scale;
    const w = SnookerRules.width, h = SnookerRules.length;
    canvas.save();
    canvas.clipRect(cloth);
    canvas.drawRect(cloth, Paint()..color = _cloth);
    for (final t in const [0.2, 0.5, 0.8]) {
      final c = l.at(w / 2, h * t);
      final along = h * 0.24 * s, acrossR = w * 0.62 * s;
      canvas
        ..save()
        ..translate(c.dx, c.dy)
        ..scale(l.landscape ? along / acrossR : 1, l.landscape ? 1 : along / acrossR)
        ..drawCircle(
          Offset.zero,
          acrossR,
          Paint()
            ..shader = ui.Gradient.radial(Offset.zero, acrossR, [
              const Color(0xFFE8FFD8).withValues(alpha: 0.13),
              const Color(0xFFE8FFD8).withValues(alpha: 0.05),
              Colors.transparent,
            ], const [0, 0.5, 1]),
        )
        ..restore();
    }
    // Darker towards the cushions, where the lamps don't reach.
    final fall = s * 0.22;
    for (final (rect, begin) in [
      (Rect.fromLTWH(cloth.left, cloth.top, cloth.width, fall), Alignment.topCenter),
      (Rect.fromLTWH(cloth.left, cloth.bottom - fall, cloth.width, fall), Alignment.bottomCenter),
      (Rect.fromLTWH(cloth.left, cloth.top, fall, cloth.height), Alignment.centerLeft),
      (Rect.fromLTWH(cloth.right - fall, cloth.top, fall, cloth.height), Alignment.centerRight),
    ]) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: begin,
            end: -begin,
            colors: [Colors.black.withValues(alpha: 0.26), Colors.transparent],
          ).createShader(rect),
      );
    }
    // The weave: thousands of fibres catching or losing the light, and a nap
    // brushed along the table.
    final rng = math.Random(7);
    final light = <Offset>[], dark = <Offset>[];
    for (var i = 0; i < 9000; i++) {
      final p = Offset(cloth.left + rng.nextDouble() * cloth.width, cloth.top + rng.nextDouble() * cloth.height);
      (i.isEven ? light : dark).add(p);
    }
    canvas.drawPoints(
      ui.PointMode.points,
      light,
      Paint()
        ..strokeWidth = math.max(0.8, s * 0.003)
        ..color = const Color(0xFFCCFFCC).withValues(alpha: 0.05),
    );
    canvas.drawPoints(
      ui.PointMode.points,
      dark,
      Paint()
        ..strokeWidth = math.max(0.8, s * 0.003)
        ..color = Colors.black.withValues(alpha: 0.06),
    );
    final nap = Paint()..strokeWidth = math.max(0.5, s * 0.0016);
    final along = l.vec(0, s * 0.014);
    for (var i = 0; i < 700; i++) {
      final p = Offset(cloth.left + rng.nextDouble() * cloth.width, cloth.top + rng.nextDouble() * cloth.height);
      nap.color = (i.isEven ? Colors.white : Colors.black).withValues(alpha: 0.02 + rng.nextDouble() * 0.025);
      canvas.drawLine(p, p + along, nap);
    }
    canvas.restore();
  }

  void _markings(Canvas canvas, SnookerLayout l) {
    final s = l.scale;
    const w = SnookerRules.width, by = SnookerRules.baulkY, dr = SnookerRules.dRadius;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, s * 0.004)
      ..color = const Color(0xFFB8F0C0).withValues(alpha: 0.45);
    canvas.drawLine(l.at(0, by), l.at(w, by), line);
    canvas.drawArc(Rect.fromCircle(center: l.at(w / 2, by), radius: dr * s), l.turn, math.pi, false, line);
    final spot = Paint()..color = Colors.white.withValues(alpha: 0.55);
    for (final (x, y) in SnookerRules.spots.values) {
      canvas.drawCircle(l.at(x, y), math.max(0.9, s * 0.006), spot);
    }
  }

  /// Black drops, each set in a chrome cap on the rail: an L that wraps the
  /// corner at the corner pockets, a wide bridge across the rail at the
  /// middle ones. The caps sit on the wood only; the cushions and cloth
  /// stay green.
  void _pockets(Canvas canvas, RRect outer, SnookerLayout l) {
    final s = l.scale;
    const w = SnookerRules.width, h = SnookerRules.length;
    // Corner and middle drops (centre, radius), sized for the balls.
    const k = SnookerRules.ballScale, co = 0.012 * k, cr = 0.052 * k, mo = 0.03 * k, mr = 0.054 * k;
    final holes = [
      (-co, -co, cr, true),
      (w + co, -co, cr, true),
      (-co, h + co, cr, true),
      (w + co, h + co, cr, true),
      (-mo, h / 2, mr, false),
      (w + mo, h / 2, mr, false),
    ];
    // The bed of the table, inside the cushion noses: plates never cover it.
    final bed = Rect.fromPoints(l.at(0, 0), l.at(w, h));
    final far = SnookerLayout.pad * 2 * s; // past the table's edge (clipped)

    // The plates: over the rail and the cushion ends, curving round the hole.
    canvas.save();
    canvas.clipRRect(outer);
    canvas.clipRect(bed, clipOp: ui.ClipOp.difference);
    for (final (x, y, r, corner) in holes) {
      final c = l.at(x, y);
      final rr = r * s;
      // Which way is out (on the canvas: each part −1, 0 or 1).
      final out = l.vec(x < w / 2 ? -1 : 1, corner ? (y < h / 2 ? -1 : 1) : 0);
      // A plate is a ring round the hole joined to the table's edge, so it
      // ends in a curve along the rail: out to the corner at a corner pocket,
      // straight out to the edge at a middle one.
      final reach = rr + s * (corner ? 0.028 : 0.032);
      final ring = Path()..addOval(Rect.fromCircle(center: c, radius: reach));
      final RRect toEdge;
      if (corner) {
        // Its inner corner rounds about the hole's centre, inside the ring.
        toEdge = RRect.fromRectAndRadius(Rect.fromPoints(c + out * far, c - out * (reach * 0.9)), Radius.circular(reach * 0.9));
      } else {
        final along = Offset(out.dy.abs(), out.dx.abs()); // along the rail
        toEdge = RRect.fromRectAndRadius(
          Rect.fromPoints(c - along * (reach * 0.92), c + out * far + along * (reach * 0.92)),
          Radius.circular(reach * 0.5),
        );
      }
      final cap = Path.combine(PathOperation.union, ring, Path()..addRRect(toEdge));
      final box = cap.getBounds();
      canvas.drawPath(
        cap.shift(Offset(0, s * 0.008)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.4)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.012),
      );
      // Polished chrome: the room's light in hard bands, and a soft round
      // highlight where the plate curves.
      canvas.drawPath(
        cap,
        Paint()
          ..shader = ui.Gradient.linear(box.topLeft, box.bottomRight, const [
            Color(0xFFFFFFFF),
            Color(0xFFD5DADF),
            Color(0xFF9AA2AA),
            Color(0xFFEEF1F4),
            Color(0xFFB7BEC6),
            Color(0xFF7F8891),
          ], const [0, 0.28, 0.45, 0.6, 0.82, 1]),
      );
      canvas.drawPath(
        cap,
        Paint()
          ..shader = ui.Gradient.radial(c - Offset(rr * 0.6, rr * 0.9), rr * 1.6, [
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0),
          ]),
      );
      // Its rolled edge: lit on top, darker underneath.
      canvas.drawPath(
        cap,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, s * 0.006)
          ..shader = ui.Gradient.linear(box.topCenter, box.bottomCenter, const [Color(0xFFFFFFFF), Color(0xFF5F6770)]),
      );
    }
    canvas.restore();

    // The drops: a leather-lined rim, then down into the dark, the net just
    // showing at the bottom.
    canvas.save();
    canvas.clipRRect(outer);
    for (final (x, y, r, _) in holes) {
      final c = l.at(x, y);
      final rr = r * s;
      canvas.drawCircle(
        c,
        rr,
        Paint()
          ..shader = ui.Gradient.radial(c, rr, const [Color(0xFF060403), Color(0xFF120B07), Color(0xFF3A2416)], const [
            0,
            0.78,
            1,
          ]),
      );
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: rr * 0.8)));
      final net = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.5, rr * 0.03)
        ..color = const Color(0xFF8C7A64).withValues(alpha: 0.12);
      for (var k = -4; k <= 4; k++) {
        final o = k * rr / 3;
        canvas.drawLine(c + Offset(o - rr, -rr), c + Offset(o + rr, rr), net);
        canvas.drawLine(c + Offset(o + rr, -rr), c + Offset(o - rr, rr), net);
      }
      // The lip throws the near side of the hole into deeper shadow.
      canvas.drawCircle(
        c - Offset(0, rr * 0.25),
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rr * 0.5
          ..color = Colors.black.withValues(alpha: 0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, rr * 0.15),
      );
      canvas.restore();
      // The leather lining's edge, lit on the far side.
      canvas.drawCircle(
        c,
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, rr * 0.1)
          ..shader = ui.Gradient.linear(c - Offset(0, rr), c + Offset(0, rr), const [Color(0xFF1A0F08), Color(0xFF5A3A24)]),
      );
    }
    canvas.restore();
  }

  void _cushions(Canvas canvas, SnookerLayout l) {
    const w = SnookerRules.width, h = SnookerRules.length, c = SnookerRules.cornerMouth, m = SnookerRules.midMouth;
    // The cushions run back to the wood (no strip of bare cloth behind them).
    const mid = h / 2, o = -_clothEdge, a = SnookerRules.jawAlong;
    // Each cushion: from jaw end, along the nose, to the other jaw end.
    final strips = <List<(double, double)>>[
      [(a, o), (c, 0), (w - c, 0), (w - a, o)],
      [(a, h - o), (c, h), (w - c, h), (w - a, h - o)],
      [(o, a), (0, c), (0, mid - m), (o, mid - m * 0.9)],
      [(o, mid + m * 0.9), (0, mid + m), (0, h - c), (o, h - a)],
      [(w - o, a), (w, c), (w, mid - m), (w - o, mid - m * 0.9)],
      [(w - o, mid + m * 0.9), (w, mid + m), (w, h - c), (w - o, h - a)],
    ];
    // Out from the table, per strip (on the canvas).
    final outs = [l.vec(0, -1), l.vec(0, 1), l.vec(-1, 0), l.vec(-1, 0), l.vec(1, 0), l.vec(1, 0)];
    final depth = -o * l.scale;
    for (var k = 0; k < strips.length; k++) {
      final pts = strips[k];
      final out = outs[k];
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final p = l.at(pts[i].$1, pts[i].$2);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      final nose = Path.from(path);
      path.close();
      final n0 = l.at(pts[1].$1, pts[1].$2);
      // Its shadow on the bed of the table, just inside the nose.
      canvas.drawPath(
        nose.shift(-out * (depth * 0.1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = depth * 0.3
          ..color = Colors.black.withValues(alpha: 0.32)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, depth * 0.16),
      );
      // Rubber under cloth, seen from above: the nose rolls away, the top
      // catches the lamps, and it sinks into shadow under the wooden rail.
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(n0, n0 + out * depth, const [
            Color(0xFF1F7A35),
            Color(0xFF2E9A45),
            Color(0xFF28903F),
            Color(0xFF16592A),
            Color(0xFF0C3D1A),
          ], const [0, 0.22, 0.55, 0.88, 1]),
      );
    }
  }

  /// White diamond sights set into the rails: three on each half of the
  /// long rails, three on the short ones.
  void _diamonds(Canvas canvas, SnookerLayout l) {
    final s = l.scale;
    const w = SnookerRules.width, h = SnookerRules.length;
    const inRail = -(SnookerLayout.pad + _clothEdge) / 2;
    // (centre, on a long rail?)
    final spots = <(Offset, bool)>[
      for (final k in [1, 2, 3, 5, 6, 7]) ...[(l.at(inRail, h * k / 8), true), (l.at(w - inRail, h * k / 8), true)],
      for (final k in [1, 2, 3]) ...[(l.at(w * k / 4, inRail), false), (l.at(w * k / 4, h - inRail), false)],
    ];
    final long = s * 0.016, short = s * 0.011;
    for (final (c, onLongRail) in spots) {
      // The oval lies along its rail: long rails run the table's length,
      // which is across the screen when the table is on its side.
      final wide = onLongRail == l.landscape;
      final rect = Rect.fromCenter(center: c, width: 2 * (wide ? long : short), height: 2 * (wide ? short : long));
      // Mother-of-pearl, set flush: a dark seat, the pearl's shifting
      // sheen, and a glint.
      canvas.drawOval(rect.inflate(0.8), Paint()..color = const Color(0x995A2508));
      canvas.drawOval(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, const [
            Color(0xFFFFFFFF),
            Color(0xFFE8F0F4),
            Color(0xFFF4E6EE),
            Color(0xFFD6D0C4),
          ], const [0, 0.35, 0.65, 1]),
      );
      canvas.drawCircle(rect.center - Offset(rect.width * 0.18, rect.height * 0.18), rect.shortestSide * 0.18, Paint()..color = Colors.white);
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
    this.landscape = false,
    super.repaint,
  });

  final SnookerGame game;

  /// The table on its side (see [SnookerLayout]).
  final bool landscape;

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

  /// One shading per kind, on a unit circle, reused for every ball and frame:
  /// lit from the lamps above, rolling off to a dark edge.
  static final Map<SnookerKind, Paint> _shade = {
    for (final e in _tones.entries)
      e.key: Paint()
        ..shader = ui.Gradient.radial(const Offset(-0.22, -0.3), 1.3, [
          Color.lerp(e.value, Colors.white, e.key == SnookerKind.black ? 0.22 : 0.3)!,
          e.value,
          Color.lerp(e.value, Colors.black, 0.45)!,
          Color.lerp(e.value, Colors.black, 0.75)!,
        ], const [0, 0.38, 0.86, 1]),
  };

  /// The green cloth reflected along the bottom of every ball.
  static final Paint _clothLight = Paint()
    ..shader = ui.Gradient.radial(const Offset(0, -0.4), 1.4, const [
      Color(0x0034B050),
      Color(0x0034B050),
      Color(0x6634B050),
    ], const [0, 0.72, 1]);

  /// The lamp: a broad sheen and a hard hot spot, plus the next lamp's
  /// smaller glint.
  static final Paint _sheen = Paint()
    ..shader = ui.Gradient.radial(const Offset(-0.26, -0.36), 0.62, [
      Colors.white.withValues(alpha: 0.32),
      Colors.white.withValues(alpha: 0),
    ]);
  static final Paint _gloss = Paint()
    ..shader = ui.Gradient.radial(const Offset(-0.3, -0.4), 0.2, [
      Colors.white,
      Colors.white.withValues(alpha: 0.85),
      Colors.white.withValues(alpha: 0),
    ], const [0, 0.45, 1]);
  static final Paint _glint = Paint()
    ..shader = ui.Gradient.radial(const Offset(0.3, -0.5), 0.09, [
      Colors.white.withValues(alpha: 0.7),
      Colors.white.withValues(alpha: 0),
    ]);
  static final Paint _castShadow = Paint()
    ..shader = ui.Gradient.radial(Offset.zero, 1, [
      Colors.black.withValues(alpha: 0.4),
      Colors.black.withValues(alpha: 0.22),
      Colors.black.withValues(alpha: 0),
    ], const [0, 0.6, 1]);

  /// Where the ball touches the cloth: a small, hard, dark shadow.
  static final Paint _contactShadow = Paint()
    ..shader = ui.Gradient.radial(Offset.zero, 1, [
      Colors.black.withValues(alpha: 0.7),
      Colors.black.withValues(alpha: 0.45),
      Colors.black.withValues(alpha: 0),
    ], const [0, 0.55, 1]);

  /// The ball's body (unit circle): colour, then the cloth's light.
  static void paintBody(Canvas canvas, SnookerKind kind) {
    canvas
      ..drawCircle(Offset.zero, 1, _shade[kind]!)
      ..drawCircle(Offset.zero, 1, _clothLight);
  }

  /// The lamps' reflections on top (unit circle).
  static void paintShine(Canvas canvas) {
    canvas
      ..drawCircle(Offset.zero, 1, _sheen)
      ..drawCircle(Offset.zero, 1, _gloss)
      ..drawCircle(Offset.zero, 1, _glint);
  }

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
      old.aim != aim ||
      old.power != power ||
      old.showGuide != showGuide ||
      old.inHandRing != inHandRing ||
      old.landscape != landscape;

  @override
  void paint(Canvas canvas, Size size) {
    final l = SnookerLayout(size, landscape: landscape);
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
      final c = l.at(b.x, b.y) + l.vec(dx, dy) * (rPx * 1.2) + Offset(rPx * 0.08, rPx * 0.12);
      canvas
        ..save()
        ..translate(c.dx, c.dy)
        ..scale(rPx * 1.3)
        ..drawCircle(Offset.zero, 1, _castShadow)
        ..restore();
      final touch = l.at(b.x, b.y) + Offset(0, rPx * 0.12);
      canvas
        ..save()
        ..translate(touch.dx, touch.dy)
        ..scale(rPx * 0.95)
        ..drawCircle(Offset.zero, 1, _contactShadow)
        ..restore();
    }

    final dir = aim;
    if (dir != null && showGuide) _guide(canvas, l, dir);
    for (final b in game.balls) {
      _ball(canvas, l.at(b.x, b.y), rPx, b.kind, ball: b, layout: l);
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

  void _ball(Canvas canvas, Offset c, double r, SnookerKind kind, {SnookerBall? ball, SnookerLayout? layout}) {
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..scale(r);
    paintBody(canvas, kind);
    if (ball != null) {
      final mark = Paint()
        ..color = kind == SnookerKind.cue
            ? const Color(0xFFC92A2A)
            : (kind == SnookerKind.black ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.07));
      for (final (x, y, z) in _marks) {
        final (px, py, pz) = ball.surface(x, y, z);
        if (pz <= 0.05) continue;
        canvas.drawOval(
          Rect.fromCenter(center: layout?.vec(px, py) ?? Offset(px, py), width: 0.3 * (0.35 + 0.65 * pz), height: 0.3 * (0.35 + 0.65 * pz)),
          mark,
        );
      }
    }
    paintShine(canvas);
    canvas.restore();
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
      hit + l.vec(g.objX, g.objY) * len,
      Paint()
        ..strokeWidth = 1.6
        ..color = const Color(0xCCFFE082),
    );
    canvas.drawLine(
      to,
      to + l.vec(g.cueX, g.cueY) * (len * 0.5),
      Paint()
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.3),
    );
  }

  /// A tapered ash cue, drawn back with the power.
  void _cue(Canvas canvas, SnookerLayout l, (double, double) dir) {
    final s = l.scale;
    final c = l.at(game.cue.x, game.cue.y);
    final angle = math.atan2(dir.$2, dir.$1) + l.turn;
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
      ..scale(r);
    SnookerBallsPainter.paintBody(canvas, kind);
    SnookerBallsPainter.paintShine(canvas);
    canvas.restore();
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
