import 'dart:math' as math;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme.dart';

/// An animated 3D die — a lit, perspective-projected cube.
///
/// Each time [rollId] changes the cube tumbles (2–3 random turns on every
/// axis), hops and bounces, and lands showing [value] on its front face. While
/// [enabled] (your turn to roll) it gently wobbles and glows to invite a tap.
class DiceView extends StatefulWidget {
  const DiceView({
    super.key,
    required this.value,
    required this.rollId,
    this.size = 64,
    this.enabled = false,
    this.onTap,
    this.color = const Color(0xFFF8F7FF),
    this.pipColor = const Color(0xFF1E1B2E),
    this.glow = AuraColors.accentGlow,
    this.onRolled,
  });

  /// Face to land on (1–6).
  final int value;

  /// Bump to play a roll (the cube lands on [value]).
  final int rollId;
  final double size;

  /// Your turn to roll: wobble + glow, taps go to [onTap].
  final bool enabled;
  final VoidCallback? onTap;
  final Color color;
  final Color pipColor;
  final Color glow;

  /// Called when a roll animation finishes.
  final VoidCallback? onRolled;

  /// Roll animation length.
  static const rollDuration = Duration(milliseconds: 900);

  @override
  State<DiceView> createState() => _DiceViewState();
}

class _DiceViewState extends State<DiceView> with TickerProviderStateMixin {
  // Starts "landed" (value 1); the listener is added afterwards so only a
  // real roll reports completion.
  late final AnimationController _roll = AnimationController(vsync: this, duration: DiceView.rollDuration, value: 1)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onRolled?.call();
    });
  late final AnimationController _idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  final _rng = math.Random();

  /// Extra spin (radians) unwound during the roll.
  double _sx = 0, _sy = 0, _sz = 0;

  @override
  void initState() {
    super.initState();
    _syncIdle();
  }

  @override
  void didUpdateWidget(DiceView old) {
    super.didUpdateWidget(old);
    if (widget.rollId != old.rollId) {
      final turns = 2 + _rng.nextInt(2);
      _sx = (turns + _rng.nextDouble()) * 2 * math.pi * (_rng.nextBool() ? 1 : -1);
      _sy = (turns + _rng.nextDouble()) * 2 * math.pi * (_rng.nextBool() ? 1 : -1);
      _sz = (_rng.nextDouble() - 0.5) * math.pi;
      _roll.forward(from: 0);
    }
    if (widget.enabled != old.enabled) _syncIdle();
  }

  void _syncIdle() {
    if (widget.enabled) {
      if (!_idle.isAnimating) _idle.repeat();
    } else {
      _idle.stop();
      _idle.value = 0;
    }
  }

  @override
  void dispose() {
    _roll.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: s * 1.5,
        height: s * 1.6,
        child: AnimatedBuilder(
          animation: Listenable.merge([_roll, _idle]),
          builder: (_, _) {
            final t = _roll.value;
            final e = Curves.easeOutCubic.transform(t);
            final rolling = _roll.isAnimating;
            // Spin unwinds to 0 so the target face ends up in front.
            final spin = 1 - e;
            // Hop: a high first arc then two small bounces.
            final hop = rolling ? _bounce(t) : 0.0;
            // Idle invite: a small rock + breathing glow.
            final idle = widget.enabled && !rolling ? math.sin(_idle.value * 2 * math.pi) : 0.0;
            final glow = widget.enabled && !rolling ? 0.45 + 0.25 * (0.5 + 0.5 * idle) : 0.0;
            return CustomPaint(
              painter: _DicePainter(
                value: widget.value.clamp(1, 6),
                ax: _sx * spin + idle * 0.06,
                ay: _sy * spin + idle * 0.08,
                az: _sz * spin,
                lift: hop * s * 0.45,
                size: s,
                color: widget.color,
                pipColor: widget.pipColor,
                glow: widget.glow.withValues(alpha: glow),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 0..1 height over the roll: one big arc, then two decaying bounces.
  static double _bounce(double t) {
    if (t < 0.55) return math.sin(t / 0.55 * math.pi);
    if (t < 0.8) return 0.28 * math.sin((t - 0.55) / 0.25 * math.pi);
    return 0.08 * math.sin((t - 0.8) / 0.2 * math.pi);
  }
}

// ── Cube projection ────────────────────────────────────────────────────────

class _V3 {
  const _V3(this.x, this.y, this.z);
  final double x, y, z;
  _V3 rotX(double a) {
    final c = math.cos(a), s = math.sin(a);
    return _V3(x, y * c - z * s, y * s + z * c);
  }

  _V3 rotY(double a) {
    final c = math.cos(a), s = math.sin(a);
    return _V3(x * c + z * s, y, -x * s + z * c);
  }

  _V3 rotZ(double a) {
    final c = math.cos(a), s = math.sin(a);
    return _V3(x * c - y * s, x * s + y * c, z);
  }
}

/// Face: outward normal, the two in-plane axes (u right, v up when facing
/// the viewer) and its pip count. Opposite faces sum to 7.
class _Face {
  const _Face(this.n, this.u, this.v, this.pips);
  final _V3 n, u, v;
  final int pips;
}

const _faces = [
  _Face(_V3(0, 0, 1), _V3(1, 0, 0), _V3(0, 1, 0), 1),
  _Face(_V3(0, 0, -1), _V3(-1, 0, 0), _V3(0, 1, 0), 6),
  _Face(_V3(1, 0, 0), _V3(0, 0, -1), _V3(0, 1, 0), 2),
  _Face(_V3(-1, 0, 0), _V3(0, 0, 1), _V3(0, 1, 0), 5),
  _Face(_V3(0, 1, 0), _V3(1, 0, 0), _V3(0, 0, -1), 3),
  _Face(_V3(0, -1, 0), _V3(1, 0, 0), _V3(0, 0, 1), 4),
];

/// Pip positions on a face, in face units (−1..1).
const _pipLayout = <int, List<(double, double)>>{
  1: [(0, 0)],
  2: [(-0.5, 0.5), (0.5, -0.5)],
  3: [(-0.5, 0.5), (0, 0), (0.5, -0.5)],
  4: [(-0.5, 0.5), (0.5, 0.5), (-0.5, -0.5), (0.5, -0.5)],
  5: [(-0.5, 0.5), (0.5, 0.5), (0, 0), (-0.5, -0.5), (0.5, -0.5)],
  6: [(-0.5, 0.55), (0.5, 0.55), (-0.5, 0), (0.5, 0), (-0.5, -0.55), (0.5, -0.55)],
};

class _DicePainter extends CustomPainter {
  _DicePainter({
    required this.value,
    required this.ax,
    required this.ay,
    required this.az,
    required this.lift,
    required this.size,
    required this.color,
    required this.pipColor,
    required this.glow,
  });

  final int value;
  final double ax, ay, az, lift, size;
  final Color color, pipColor, glow;

  /// Rotation that brings [value]'s face to the front (+z, toward the viewer).
  static (double, double) _base(int v) => switch (v) {
    1 => (0, 0),
    6 => (0, math.pi),
    2 => (0, -math.pi / 2),
    5 => (0, math.pi / 2),
    3 => (math.pi / 2, 0),
    _ => (-math.pi / 2, 0), // 4
  };

  /// Full rotation: land face → spin (unwinding) → fixed 3/4 display tilt.
  _V3 _rot(_V3 p) {
    final (bx, by) = _base(value);
    var q = p.rotX(bx).rotY(by);
    q = q.rotX(ax).rotY(ay).rotZ(az);
    return q.rotX(0.42).rotY(-0.5);
  }

  @override
  void paint(Canvas canvas, Size sz) {
    final half = size / 2;
    final center = Offset(sz.width / 2, sz.height * 0.56 - lift);
    const camera = 5.0; // in half-edge units

    Offset project(_V3 p) {
      final k = camera / (camera - p.z);
      return center + Offset(p.x * half * k, -p.y * half * k);
    }

    // Ground shadow (shrinks + fades as the die lifts).
    final shadowY = sz.height * 0.56 + half * 1.05;
    final lifted = (lift / (size * 0.45)).clamp(0.0, 1.0);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(sz.width / 2, shadowY), width: size * (1.1 - 0.4 * lifted), height: size * 0.28),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45 - 0.25 * lifted)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Invite glow.
    if (glow.a > 0) {
      canvas.drawCircle(
        center,
        size * 0.85,
        Paint()
          ..color = glow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
    }

    const light = _V3(-0.45, 0.6, 0.66);
    final faces = <(double, _Face, _V3, _V3, _V3, _V3)>[];
    for (final f in _faces) {
      final n = _rot(f.n);
      if (n.z <= 0.02) continue; // back-facing
      faces.add((n.z, f, n, _rot(f.u), _rot(f.v), _rot(f.n)));
    }
    faces.sort((a, b) => a.$1.compareTo(b.$1));

    for (final (_, face, n, u, v, c) in faces) {
      // Face corners: centre ± u ± v (rounded via a slightly inset quad).
      final corners = [
        for (final (su, sv) in const [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)])
          project(
            _V3(
              c.x + u.x * su * 0.96 + v.x * sv * 0.96,
              c.y + u.y * su * 0.96 + v.y * sv * 0.96,
              c.z + u.z * su * 0.96 + v.z * sv * 0.96,
            ),
          ),
      ];
      final path = _roundedQuad(corners, size * 0.09);
      final lum = (n.x * light.x + n.y * light.y + n.z * light.z).clamp(0.0, 1.0);
      final shade = Color.lerp(const Color(0xFF9C97B8), color, 0.35 + 0.65 * lum)!;
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(shade, Colors.white, 0.25)!, shade],
          ).createShader(path.getBounds()),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black.withValues(alpha: 0.12),
      );
      // Pips — drawn in face space via the face's affine frame.
      final o = project(c);
      final pu = project(_V3(c.x + u.x, c.y + u.y, c.z + u.z)) - o;
      final pv = project(_V3(c.x + v.x, c.y + v.y, c.z + v.z)) - o;
      canvas.save();
      canvas.transform(Float64List.fromList([pu.dx, pu.dy, 0, 0, -pv.dx, -pv.dy, 0, 0, 0, 0, 1, 0, o.dx, o.dy, 0, 1]));
      final pip = Paint()
        ..color = face.pips == 1 ? const Color(0xFFE11D48) : pipColor.withValues(alpha: 0.4 + 0.6 * lum);
      for (final (x, y) in _pipLayout[face.pips]!) {
        canvas.drawCircle(Offset(x, -y), face.pips == 1 ? 0.24 : 0.17, pip);
      }
      canvas.restore();
    }
  }

  /// A quad with softly rounded corners.
  static Path _roundedQuad(List<Offset> p, double r) {
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final a = p[i], b = p[(i + 1) % 4], prev = p[(i + 3) % 4];
      final inDir = (a - prev) / (a - prev).distance;
      final outDir = (b - a) / (b - a).distance;
      final p1 = a - inDir * r, p2 = a + outDir * r;
      if (i == 0) {
        path.moveTo(p1.dx, p1.dy);
      } else {
        path.lineTo(p1.dx, p1.dy);
      }
      path.quadraticBezierTo(a.dx, a.dy, p2.dx, p2.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_DicePainter o) =>
      o.value != value || o.ax != ax || o.ay != ay || o.az != az || o.lift != lift || o.glow != glow;
}
