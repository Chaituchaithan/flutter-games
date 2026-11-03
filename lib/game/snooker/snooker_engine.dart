import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// What a ball on the table is, with its value.
enum SnookerKind {
  cue(0),
  red(1),
  yellow(2),
  green(3),
  brown(4),
  blue(5),
  pink(6),
  black(7);

  const SnookerKind(this.value);
  final int value;

  bool get isColour => value >= 2;
}

/// A ball, in metres (x across the table, y from the black end down to baulk).
/// Mutable for speed: the physics moves these every substep. The spin is a
/// full 3D vector, so sliding, screw, follow and side all come from friction.
class SnookerBall {
  SnookerBall(this.id, this.kind, this.x, this.y);

  final int id;
  final SnookerKind kind;
  double x, y;
  double vx = 0, vy = 0;
  double wx = 0, wy = 0, wz = 0;

  /// Which way the ball is turned (a quaternion), for drawing it rolling.
  double qw = 1, qx = 0, qy = 0, qz = 0;

  double get speed => math.sqrt(vx * vx + vy * vy);
  bool get moving => vx != 0 || vy != 0 || wx != 0 || wy != 0;

  SnookerBall copy() => SnookerBall(id, kind, x, y)
    ..vx = vx
    ..vy = vy
    ..wx = wx
    ..wy = wy
    ..wz = wz;

  /// Turn the drawn ball by its spin over [dt] seconds.
  void turn(double dt) {
    final w = math.sqrt(wx * wx + wy * wy + wz * wz);
    if (w == 0) return;
    final half = w * dt / 2, s = math.sin(half) / w;
    final dw = math.cos(half), dx = wx * s, dy = wy * s, dz = wz * s;
    final nw = dw * qw - dx * qx - dy * qy - dz * qz;
    final nx = dw * qx + dx * qw + dy * qz - dz * qy;
    final ny = dw * qy - dx * qz + dy * qw + dz * qx;
    final nz = dw * qz + dx * qy - dy * qx + dz * qw;
    final len = math.sqrt(nw * nw + nx * nx + ny * ny + nz * nz);
    qw = nw / len;
    qx = nx / len;
    qy = ny / len;
    qz = nz / len;
  }

  /// A point on the ball's surface (unit vector) as it is turned now.
  (double, double, double) surface(double x, double y, double z) {
    final tx = 2 * (qy * z - qz * y), ty = 2 * (qz * x - qx * z), tz = 2 * (qx * y - qy * x);
    return (x + qw * tx + qy * tz - qz * ty, y + qw * ty + qz * tx - qx * tz, z + qw * tz + qx * ty - qy * tx);
  }
}

/// A ball dropping into a pocket (drawn shrinking for a moment).
class SnookerSink {
  SnookerSink(this.kind, this.x, this.y, this.pocket);
  final SnookerKind kind;
  final double x, y;
  final int pocket;
  double t = 0;
}

/// A cushion nose or pocket jaw: a line the balls bounce off.
class SnookerRail {
  const SnookerRail(this.x1, this.y1, this.x2, this.y2, {this.jaw = false});
  final double x1, y1, x2, y2;
  final bool jaw;
}

/// The 12 ft table and its physics, in metres and seconds.
abstract final class SnookerRules {
  static const width = 1.778, length = 3.569;
  static const r = 0.02625;

  static const baulkY = length - 0.737;
  static const dRadius = 0.292;

  /// Half the middle pocket's mouth, and how far the corner mouth runs along
  /// each cushion from the corner.
  static const midMouth = 0.058, cornerMouth = 0.0675;

  /// Hardest shot.
  static const maxSpeed = 6.5;

  /// Cloth: sliding and rolling friction (× g), plus a little air and nap.
  static const g = 9.81, slideFriction = 0.2, rollFriction = 0.012, drag = 0.06;
  static const pivotDecay = 11.0; // side spin dying away, rad/s²

  /// Balls: restitution and how much they grip when they meet.
  static const ballBounce = 0.96, ballGrip = 0.05;

  /// Cushions: how much they grip the ball.
  static const railGrip = 0.2;

  /// Furthest the tip may land from the ball's centre (× radius).
  static const maxTip = 0.6;

  /// Colour spots: yellow on the right of the D, seen from baulk.
  static const spots = {
    SnookerKind.yellow: (width / 2 + dRadius, baulkY),
    SnookerKind.green: (width / 2 - dRadius, baulkY),
    SnookerKind.brown: (width / 2, baulkY),
    SnookerKind.blue: (width / 2, length / 2),
    SnookerKind.pink: (width / 2, length / 4),
    SnookerKind.black: (width / 2, 0.324),
  };

  /// Where a ball aims to fall: TL, TR, BL, BR, middle left, middle right.
  static const pockets = [
    (0.015, 0.015),
    (width - 0.015, 0.015),
    (0.015, length - 0.015),
    (width - 0.015, length - 0.015),
    (-0.015, length / 2),
    (width + 0.015, length / 2),
  ];

  /// Every cushion nose and jaw.
  static final List<SnookerRail> rails = _buildRails();

  static List<SnookerRail> _buildRails() {
    const w = width, l = length, c = cornerMouth, m = midMouth, mid = length / 2;
    SnookerRail jaw(double x1, double y1, double x2, double y2) => SnookerRail(x1, y1, x2, y2, jaw: true);
    return [
      const SnookerRail(c, 0, w - c, 0),
      const SnookerRail(c, l, w - c, l),
      const SnookerRail(0, c, 0, mid - m),
      const SnookerRail(0, mid + m, 0, l - c),
      const SnookerRail(w, c, w, mid - m),
      const SnookerRail(w, mid + m, w, l - c),
      // Corners.
      jaw(c, 0, 0.035, -0.05),
      jaw(0, c, -0.05, 0.035),
      jaw(w - c, 0, w - 0.035, -0.05),
      jaw(w, c, w + 0.05, 0.035),
      jaw(c, l, 0.035, l + 0.05),
      jaw(0, l - c, -0.05, l - 0.035),
      jaw(w - c, l, w - 0.035, l + 0.05),
      jaw(w, l - c, w + 0.05, l - 0.035),
      // Middles.
      jaw(0, mid - m, -0.05, mid - m * 0.9),
      jaw(0, mid + m, -0.05, mid + m * 0.9),
      jaw(w, mid - m, w + 0.05, mid - m * 0.9),
      jaw(w, mid + m, w + 0.05, mid + m * 0.9),
    ];
  }

  /// The pocket a ball at (x, y) has fallen into, if any.
  static int? fallen(double x, double y) {
    const fall = 0.025;
    if (x + y < fall) return 0;
    if (width - x + y < fall) return 1;
    if (x + length - y < fall) return 2;
    if (width - x + length - y < fall) return 3;
    if ((y - length / 2).abs() < 0.12) {
      if (x < -0.012) return 4;
      if (x > width + 0.012) return 5;
    }
    // Rattled clean out of a jaw: it can only have gone down the nearest hole.
    if (x < -0.06 || x > width + 0.06 || y < -0.06 || y > length + 0.06) {
      if ((y - length / 2).abs() < length / 4) return x < width / 2 ? 4 : 5;
      return (x < width / 2 ? 0 : 1) + (y < length / 2 ? 0 : 2);
    }
    return null;
  }

  /// Is (x, y) inside the D?
  static bool inD(double x, double y) {
    final dx = x - width / 2, dy = y - baulkY;
    return dy >= 0 && dx * dx + dy * dy <= dRadius * dRadius;
  }

  /// Shot strength 0..1 ↔ cue ball speed: finer control on soft shots.
  static double speedOf(double power) => maxSpeed * math.pow(power.clamp(0.0, 1.0), 1.35).toDouble();
  static double powerOf(double speed) => math.pow((speed / maxSpeed).clamp(0.0, 1.0), 1 / 1.35).toDouble();
}

/// One shot's verdict.
@immutable
class SnookerShotResult {
  const SnookerShotResult({
    required this.player,
    required this.points,
    required this.foul,
    required this.potted,
    required this.inOff,
    required this.again,
  });

  final int player;

  /// Scored by the shooter, or (a foul) given to the other player.
  final int points, foul;
  final List<SnookerKind> potted;
  final bool inOff;
  final bool again;
}

/// A frame of snooker: you against the computer, you break. Reds and colours
/// alternate, the colours come back to their spots until the reds are gone,
/// then they're cleared in order. Fouls give away 4–7. After a foul that
/// leaves the next player snookered they have a free ball. Level on the last
/// black: it's re-spotted and the next score wins.
///
/// There's no calling of a colour: the first colour you hit is the one you
/// nominated. The miss rule and asking the offender to play again aren't used.
class SnookerGame extends ChangeNotifier {
  SnookerGame({math.Random? rng}) : _rng = rng ?? math.Random() {
    _rack();
  }

  final math.Random _rng;

  final List<SnookerBall> balls = [];
  late SnookerBall cue;
  final List<SnookerSink> sinking = [];

  final scores = [0, 0];

  /// Highest break of the frame per player.
  final highBreak = [0, 0];
  int currentBreak = 0;

  int turn = 0;
  bool moving = false;
  int? winner;

  /// A red has gone down: the next ball is a colour.
  bool colourDue = false;

  /// The player's cue ball goes anywhere in the D.
  bool inHand = true;

  /// Snookered after a foul: any ball may be played as the ball on.
  bool freeBall = false;

  /// Level on the last black: it was re-spotted and the next score wins.
  bool blackGame = false;
  SnookerShotResult? last;

  /// Called when a ball drops — for haptics.
  void Function(SnookerKind kind)? onPocket;

  /// Called once a frame with the hardest knock in it — for haptics.
  void Function(double speed)? onImpact;

  // Shot bookkeeping.
  SnookerKind? _first;
  SnookerKind? _shotOn; // the ball on when the shot was struck
  final List<SnookerKind> _inShot = [];
  bool _cueIn = false;
  int _nextId = 0;

  bool get isOver => winner != null;
  int get redsLeft => balls.where((b) => b.kind == SnookerKind.red).length;
  bool get _onlyBlack => !colourDue && balls.every((b) => b.kind == SnookerKind.cue || b.kind == SnookerKind.black);

  /// The ball on: a kind, or null for "any colour".
  SnookerKind? get target {
    if (colourDue) return null;
    if (redsLeft > 0) return SnookerKind.red;
    return _lowestColour;
  }

  SnookerKind? get _lowestColour {
    SnookerKind? low;
    for (final b in balls) {
      if (b.kind.isColour && (low == null || b.kind.value < low.value)) low = b.kind;
    }
    return low;
  }

  /// What may be hit first this shot.
  List<SnookerBall> get ballsOn {
    final on = target;
    return [
      for (final b in balls)
        if (b.kind != SnookerKind.cue && (freeBall || (on == null ? b.kind.isColour : b.kind == on))) b,
    ];
  }

  void _rack() {
    const w = SnookerRules.width, r = SnookerRules.r;
    SnookerRules.spots.forEach((kind, spot) => balls.add(SnookerBall(_nextId++, kind, spot.$1, spot.$2)));
    // The triangle: apex just behind pink, rows growing towards the top.
    const gap = r * 2 + 0.0004;
    final rowStep = gap * math.sqrt(3) / 2;
    final apex = SnookerRules.length / 4 - gap;
    for (var row = 0; row < 5; row++) {
      for (var i = 0; i <= row; i++) {
        balls.add(SnookerBall(_nextId++, SnookerKind.red, w / 2 + (i - row / 2) * gap, apex - row * rowStep));
      }
    }
    _placeCueDefault();
  }

  void _placeCueDefault() {
    cue = SnookerBall(_nextId++, SnookerKind.cue, SnookerRules.width / 2, SnookerRules.baulkY);
    balls.add(cue);
    // A hand's width towards the yellow (or wherever's free in the D).
    const spots = [0.12, -0.12, 0.2, -0.2, 0.06, -0.06, 0.26, -0.26];
    for (final dy in const [0.03, 0.12, 0.2]) {
      for (final dx in spots) {
        final x = SnookerRules.width / 2 + dx, y = SnookerRules.baulkY + dy;
        if (SnookerRules.inD(x, y) && _clearAt(x, y, except: cue)) {
          cue
            ..x = x
            ..y = y;
          return;
        }
      }
    }
  }

  bool _clearAt(double x, double y, {SnookerBall? except}) {
    const min = SnookerRules.r * 2;
    for (final b in balls) {
      if (identical(b, except)) continue;
      final dx = b.x - x, dy = b.y - y;
      if (dx * dx + dy * dy < min * min) return false;
    }
    return true;
  }

  /// Ball in hand: put the cue ball at (x, y) — pulled back into the D, and
  /// ignored if another ball is in the way.
  void placeCue(double x, double y) {
    if (!inHand || moving || isOver) return;
    const cx = SnookerRules.width / 2, by = SnookerRules.baulkY, dr = SnookerRules.dRadius;
    var px = x, py = math.max(y, by);
    final dx = px - cx, dy = py - by, d = math.sqrt(dx * dx + dy * dy);
    if (d > dr) {
      px = cx + dx / d * dr;
      py = by + dy / d * dr;
    }
    if (!_clearAt(px, py, except: cue)) return;
    cue
      ..x = px
      ..y = py;
    notifyListeners();
  }

  /// Strike the cue ball: [dx], [dy] direction (any length), [power] 0..1,
  /// and where the tip lands — [side] (+ right) and [top] (+ top spin, − screw),
  /// each −1..1 of the reach. Returns false if a shot can't be played now.
  bool shoot(double dx, double dy, double power, {double side = 0, double top = 0}) {
    if (moving || isOver) return false;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return false;
    _strike(cue, dx / len, dy / len, SnookerRules.speedOf(math.max(power, 0.02)), side, top);
    moving = true;
    inHand = false;
    _shotOn = target;
    _first = null;
    _inShot.clear();
    _cueIn = false;
    notifyListeners();
    return true;
  }

  static void _strike(SnookerBall c, double ux, double uy, double v, double side, double top) {
    const r = SnookerRules.r, reach = SnookerRules.maxTip * r;
    final a = side.clamp(-1.0, 1.0) * reach, b = top.clamp(-1.0, 1.0) * reach;
    final k = 5 * v / (2 * r * r);
    c
      ..vx = ux * v
      ..vy = uy * v
      ..wx = -b * uy * k
      ..wy = b * ux * k
      ..wz = -a * k;
  }

  /// Advance the physics by [dt] seconds (call every frame).
  void step(double dt) {
    for (final s in sinking) {
      s.t += dt;
    }
    final hadSinks = sinking.isNotEmpty;
    sinking.removeWhere((s) => s.t > 0.3);
    if (!moving) {
      if (hadSinks) notifyListeners();
      return;
    }
    var left = dt.clamp(0.0, 1 / 20);
    var knock = 0.0;
    final frame = left;
    while (left > 0 && moving) {
      final h = math.min(_substep, left);
      left -= h;
      final any = _physics(balls, h, _pocket, (a, b, v) {
        knock = math.max(knock, v);
        if (identical(a, cue)) {
          _first ??= b.kind;
        } else if (identical(b, cue)) {
          _first ??= a.kind;
        }
      }, (v) => knock = math.max(knock, v));
      if (!any) _endShot();
    }
    for (final b in balls) {
      b.turn(frame);
    }
    if (knock > 0) onImpact?.call(knock);
    notifyListeners();
  }

  static const _substep = 1 / 360;

  void _pocket(SnookerBall b, int pocket) {
    balls.remove(b);
    sinking.add(SnookerSink(b.kind, b.x, b.y, pocket));
    if (b.kind == SnookerKind.cue) {
      _cueIn = true;
    } else {
      _inShot.add(b.kind);
    }
    onPocket?.call(b.kind);
  }

  /// One physics substep for [list]. Returns false once everything stopped.
  static bool _physics(
    List<SnookerBall> list,
    double h,
    void Function(SnookerBall, int) pocket,
    void Function(SnookerBall, SnookerBall, double) contact, [
    void Function(double)? railHit,
  ]) {
    var any = false;
    for (final b in list) {
      if (!b.moving) continue;
      _cloth(b, h);
      if (b.moving) any = true;
    }
    for (var i = 0; i < list.length; i++) {
      final a = list[i];
      for (var j = i + 1; j < list.length; j++) {
        final b = list[j];
        if (!a.moving && !b.moving) continue;
        if (_collide(a, b, contact)) any = true;
      }
    }
    for (final b in List.of(list)) {
      if (!b.moving) continue;
      if (_nearEdge(b)) {
        for (final rail in SnookerRules.rails) {
          _bounce(b, rail, railHit);
        }
        final p = SnookerRules.fallen(b.x, b.y);
        if (p != null) pocket(b, p);
      }
    }
    return any;
  }

  static bool _nearEdge(SnookerBall b) {
    const m = SnookerRules.r + 0.015;
    return b.x < m || b.x > SnookerRules.width - m || b.y < m || b.y > SnookerRules.length - m;
  }

  /// The cloth: slide until the ball's surface matches the table, then roll.
  static void _cloth(SnookerBall b, double h) {
    const r = SnookerRules.r;
    final ux = b.vx - r * b.wy, uy = b.vy + r * b.wx;
    final slip = math.sqrt(ux * ux + uy * uy);
    final slide = SnookerRules.slideFriction * SnookerRules.g * h;
    if (slip > 3.5 * slide) {
      final ax = -ux / slip * slide, ay = -uy / slip * slide;
      b.vx += ax;
      b.vy += ay;
      b.wx += 2.5 / r * ay;
      b.wy -= 2.5 / r * ax;
    } else {
      // Slip is gone: settle onto a clean roll that conserves the momentum.
      b.vx -= ux / 3.5;
      b.vy -= uy / 3.5;
      final s = b.speed;
      if (s > 0) {
        final ns = s - (SnookerRules.rollFriction * SnookerRules.g + SnookerRules.drag * s) * h;
        if (ns <= 0.004) {
          b.vx = 0;
          b.vy = 0;
        } else {
          b.vx *= ns / s;
          b.vy *= ns / s;
        }
      }
      b.wy = b.vx / r;
      b.wx = -b.vy / r;
    }
    final piv = SnookerRules.pivotDecay * h;
    b.wz = b.wz.abs() <= piv ? 0 : b.wz - piv * b.wz.sign;
    if (b.vx == 0 && b.vy == 0 && b.wx == 0 && b.wy == 0) {
      b.wz = 0;
      return;
    }
    b.x += b.vx * h;
    b.y += b.vy * h;
  }

  static bool _collide(SnookerBall a, SnookerBall b, void Function(SnookerBall, SnookerBall, double) contact) {
    const r = SnookerRules.r, rr = 2 * r;
    final dx = b.x - a.x, dy = b.y - a.y;
    final dist2 = dx * dx + dy * dy;
    if (dist2 >= rr * rr || dist2 == 0) return false;
    final dist = math.sqrt(dist2);
    final nx = dx / dist, ny = dy / dist;
    final push = (rr - dist) / 2;
    a.x -= nx * push;
    a.y -= ny * push;
    b.x += nx * push;
    b.y += ny * push;
    final rel = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny;
    if (rel <= 0) return false;
    contact(a, b, rel);
    final jn = (1 + SnookerRules.ballBounce) / 2 * rel;
    a.vx -= jn * nx;
    a.vy -= jn * ny;
    b.vx += jn * nx;
    b.vy += jn * ny;
    // Surfaces rubbing where they touch: throw on the object ball, and spin
    // handed from one ball to the other.
    final swx = a.wx + b.wx, swy = a.wy + b.wy, swz = a.wz + b.wz;
    var gx = a.vx - b.vx - r * swz * ny, gy = a.vy - b.vy + r * swz * nx;
    final gz = r * (swx * ny - swy * nx);
    final gn = gx * nx + gy * ny;
    gx -= gn * nx;
    gy -= gn * ny;
    final g = math.sqrt(gx * gx + gy * gy + gz * gz);
    if (g > 1e-6) {
      final j = math.min(SnookerRules.ballGrip * jn, g / 7);
      final jx = -gx / g * j, jy = -gy / g * j, jz = -gz / g * j;
      a.vx += jx;
      a.vy += jy;
      b.vx -= jx;
      b.vy -= jy;
      const k = 2.5 / r;
      final dwx = k * ny * jz, dwy = -k * nx * jz, dwz = k * (nx * jy - ny * jx);
      a.wx += dwx;
      a.wy += dwy;
      a.wz += dwz;
      b.wx += dwx;
      b.wy += dwy;
      b.wz += dwz;
    }
    return true;
  }

  static void _bounce(SnookerBall b, SnookerRail rail, void Function(double)? railHit) {
    const r = SnookerRules.r;
    final ex = rail.x2 - rail.x1, ey = rail.y2 - rail.y1;
    final t = (((b.x - rail.x1) * ex + (b.y - rail.y1) * ey) / (ex * ex + ey * ey)).clamp(0.0, 1.0);
    final qx = rail.x1 + ex * t - b.x, qy = rail.y1 + ey * t - b.y;
    final d2 = qx * qx + qy * qy;
    if (d2 >= r * r || d2 == 0) return;
    final d = math.sqrt(d2);
    final nx = qx / d, ny = qy / d; // towards the cushion
    b.x -= nx * (r - d);
    b.y -= ny * (r - d);
    final vn = b.vx * nx + b.vy * ny;
    if (vn <= 0) return;
    railHit?.call(vn);
    // Hard hits sink into the rubber and lose more.
    var e = (0.9 - 0.06 * vn).clamp(0.55, 0.88);
    if (rail.jaw) e *= 0.7;
    final tx = b.vx - vn * nx, ty = b.vy - vn * ny;
    final sx = tx - b.wz * r * ny, sy = ty + b.wz * r * nx;
    final slip = math.sqrt(sx * sx + sy * sy);
    b.vx -= (1 + e) * vn * nx;
    b.vy -= (1 + e) * vn * ny;
    if (slip > 1e-6) {
      final j = math.min(SnookerRules.railGrip * (1 + e) * vn, slip / 3.5);
      final jx = -sx / slip * j, jy = -sy / slip * j;
      b.vx += jx;
      b.vy += jy;
      b.wz += 2.5 / r * (nx * jy - ny * jx);
    }
    // The nap and rubber take some of the roll.
    b.wx *= 0.6;
    b.wy *= 0.6;
  }

  /// The referee: how a shot with this outcome is scored right now.
  ({int points, int foul}) _judge(SnookerKind? on, SnookerKind? first, List<SnookerKind> pots, bool cueIn) {
    final bool hitOk;
    if (first == null) {
      hitOk = false;
    } else if (freeBall) {
      hitOk = true;
    } else {
      hitOk = on == null ? first.isColour : first == on;
    }
    final nominated = freeBall && first != on ? first : null;
    final potsOk = pots.every((p) => p == on || p == nominated || (on == null && p == first));
    if (!hitOk || !potsOk || cueIn) {
      var worst = math.max(4, math.max(on?.value ?? 0, first?.value ?? 0));
      for (final p in pots) {
        worst = math.max(worst, p.value);
      }
      return (points: 0, foul: worst);
    }
    if (pots.isEmpty) return (points: 0, foul: 0);
    if (on == SnookerKind.red) {
      final reds = pots.where((p) => p == SnookerKind.red).length;
      return (points: reds == 0 ? 1 : reds, foul: 0);
    }
    return (points: on?.value ?? first!.value, foul: 0);
  }

  /// Everything stopped: apply the rules and set up the next shot.
  void _endShot() {
    moving = false;
    for (final b in balls) {
      b
        ..vx = 0
        ..vy = 0
        ..wx = 0
        ..wy = 0
        ..wz = 0;
    }
    final me = turn, other = 1 - turn;
    final on = _shotOn, wasFree = freeBall;
    final j = _judge(on, _first, _inShot, _cueIn);
    final foul = j.foul > 0;
    final pots = List.of(_inShot);
    freeBall = false;
    var again = false;
    if (foul) {
      scores[other] += j.foul;
      currentBreak = 0;
      colourDue = false;
    } else if (pots.isNotEmpty) {
      scores[me] += j.points;
      currentBreak += j.points;
      highBreak[me] = math.max(highBreak[me], currentBreak);
      again = true;
      // A red, or a free ball played as a red, earns a colour.
      if (on == SnookerKind.red) {
        colourDue = true;
      } else if (on == null) {
        colourDue = false;
      }
    } else {
      currentBreak = 0;
      colourDue = false;
    }
    // Colours come back, unless it's the one being cleared, potted fairly.
    for (final p in pots) {
      if (!p.isColour) continue;
      if (!foul && p == on && on != null) continue;
      _respot(p);
    }
    if (!again) {
      turn = other;
      currentBreak = 0;
    }
    if (_cueIn) {
      inHand = true;
      _placeCueDefault();
    }
    last = SnookerShotResult(
      player: me,
      points: j.points,
      foul: j.foul,
      potted: pots,
      inOff: _cueIn,
      again: again,
    );
    _checkEnd(foul, wasBlackOnly: on == SnookerKind.black && !wasFree);
    if (!isOver && foul && !inHand) freeBall = snookered;
  }

  /// With only the black left, the first score or foul ends the frame.
  void _checkEnd(bool foul, {required bool wasBlackOnly}) {
    final cleared = !colourDue && balls.every((b) => b.kind == SnookerKind.cue);
    if (!cleared && !(wasBlackOnly && foul && _onlyBlack)) return;
    if (scores[0] == scores[1]) {
      if (balls.every((b) => b.kind != SnookerKind.black)) _respot(SnookerKind.black);
      blackGame = true;
      turn = _rng.nextInt(2);
      currentBreak = 0;
      inHand = true;
      balls.remove(cue);
      _placeCueDefault();
      return;
    }
    winner = scores[0] > scores[1] ? 0 : 1;
  }

  /// A colour back on its spot, or the highest free spot, or the nearest
  /// free point straight up the table from its own.
  void _respot(SnookerKind kind) {
    final own = SnookerRules.spots[kind]!;
    final order = [own, for (final k in SnookerKind.values.reversed) if (k.isColour) SnookerRules.spots[k]!];
    for (final (x, y) in order) {
      if (_clearAt(x, y)) {
        balls.insert(0, SnookerBall(_nextId++, kind, x, y));
        return;
      }
    }
    for (var d = 0.001; d < SnookerRules.length; d += 0.002) {
      for (final y in [own.$2 - d, own.$2 + d]) {
        if (y > SnookerRules.r && y < SnookerRules.length - SnookerRules.r && _clearAt(own.$1, y)) {
          balls.insert(0, SnookerBall(_nextId++, kind, own.$1, y));
          return;
        }
      }
    }
  }

  /// Out of time: the turn passes (ball in hand stays in hand).
  void passTurn() {
    if (moving || isOver) return;
    last = null;
    colourDue = false;
    freeBall = false;
    currentBreak = 0;
    turn = 1 - turn;
    notifyListeners();
  }

  /// No ball on can be hit on both its edges in a straight line.
  bool get snookered {
    final on = target;
    final list = [
      for (final b in balls)
        if (b.kind != SnookerKind.cue && (on == null ? b.kind.isColour : b.kind == on)) b,
    ];
    if (list.isEmpty) return false;
    for (final t in list) {
      if (_edgeClear(t, 1) && _edgeClear(t, -1)) return false;
    }
    return true;
  }

  bool _edgeClear(SnookerBall t, int sign) {
    final dx = t.x - cue.x, dy = t.y - cue.y, len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return false;
    const off = SnookerRules.r * 2 * 0.98;
    final ex = t.x - dy / len * off * sign, ey = t.y + dx / len * off * sign;
    return _pathClear(balls, cue.x, cue.y, ex, ey, cue, t);
  }

  static bool _pathClear(List<SnookerBall> list, double x1, double y1, double x2, double y2, SnookerBall? skipA, SnookerBall? skipB) {
    final ex = x2 - x1, ey = y2 - y1, len2 = ex * ex + ey * ey;
    if (len2 == 0) return true;
    const min = SnookerRules.r * 2 - 0.0005;
    for (final b in list) {
      if (identical(b, skipA) || identical(b, skipB) || b.id == skipA?.id || b.id == skipB?.id) continue;
      final t = (((b.x - x1) * ex + (b.y - y1) * ey) / len2).clamp(0.0, 1.0);
      final qx = x1 + ex * t - b.x, qy = y1 + ey * t - b.y;
      if (qx * qx + qy * qy < min * min) return false;
    }
    return true;
  }

  // ── Computer ──

  /// Play a shot on a copy of the table and see how it comes out.
  ({int points, int foul, double cueX, double cueY, bool cueIn}) simulate(
    double x,
    double y,
    double dx,
    double dy,
    double speed, {
    double side = 0,
    double top = 0,
  }) {
    final on = target;
    final list = [for (final b in balls) b.copy()];
    final c = list.firstWhere((b) => b.kind == SnookerKind.cue)
      ..x = x
      ..y = y;
    final len = math.sqrt(dx * dx + dy * dy);
    _strike(c, dx / len, dy / len, speed, side, top);
    SnookerKind? first;
    final pots = <SnookerKind>[];
    var cueIn = false;
    for (var t = 0; t < 360 * 12; t++) {
      final go = _physics(list, _substep, (b, _) {
        list.remove(b);
        if (b.kind == SnookerKind.cue) {
          cueIn = true;
        } else {
          pots.add(b.kind);
        }
      }, (a, b, _) {
        if (identical(a, c)) {
          first ??= b.kind;
        } else if (identical(b, c)) {
          first ??= a.kind;
        }
      });
      if (!go) break;
    }
    final j = _judge(on, first, pots, cueIn);
    return (points: j.points, foul: j.foul, cueX: c.x, cueY: c.y, cueIn: cueIn);
  }

  /// The computer's shot: where to put the cue ball (if in hand), direction,
  /// power and spin. Lines up pots from the balls on into each pocket,
  /// simulates the best-looking ones and keeps the best outcome; with nothing
  /// on, plays safe or escapes a snooker. [difficulty] 1–3 sets how many it
  /// tries and how steady its cue arm is.
  ({double x, double y, double dx, double dy, double power, double side, double top}) botShot(int difficulty) {
    final tries = switch (difficulty) {
      <= 1 => 5,
      2 => 12,
      _ => 22,
    };
    final noise = switch (difficulty) {
      <= 1 => 0.016,
      2 => 0.006,
      _ => 0.0015,
    };
    final targets = ballsOn;
    const decel = SnookerRules.rollFriction * SnookerRules.g + 0.05;
    final starts = inHand
        ? [
            for (final (dx, dy) in const [(0.0, 0.25), (0.14, 0.05), (-0.14, 0.05), (0.2, 0.12), (-0.2, 0.12)])
              if (_clearAt(SnookerRules.width / 2 + dx, SnookerRules.baulkY + dy, except: cue))
                (SnookerRules.width / 2 + dx, SnookerRules.baulkY + dy),
          ]
        : [(cue.x, cue.y)];
    if (starts.isEmpty) starts.add((cue.x, cue.y));

    final cands = <({double geo, double x, double y, double ax, double ay, double speed})>[];
    for (final (sx, sy) in starts) {
      for (final t in targets) {
        for (var p = 0; p < 6; p++) {
          final (px, py) = SnookerRules.pockets[p];
          var ex = px - t.x, ey = py - t.y;
          final el = math.sqrt(ex * ex + ey * ey);
          ex /= el;
          ey /= el;
          // The middle pockets only take balls coming across the table.
          if (p >= 4 && ex.abs() < 0.5) continue;
          final gx = t.x - ex * 2 * SnookerRules.r, gy = t.y - ey * 2 * SnookerRules.r;
          var ax = gx - sx, ay = gy - sy;
          final al = math.sqrt(ax * ax + ay * ay);
          if (al < 0.001) continue;
          ax /= al;
          ay /= al;
          final cut = ax * ex + ay * ey;
          if (cut < 0.3) continue;
          if (!_pathClear(balls, sx, sy, gx, gy, cue, t)) continue;
          if (!_pathClear(balls, t.x, t.y, px, py, cue, t)) continue;
          final vObj = math.sqrt(2 * decel * el + 0.25);
          final vHit = vObj / cut * 1.05;
          final speed = math.sqrt(vHit * vHit + 2 * decel * al * 1.25);
          cands.add((
            geo: cut * 1.5 - el * 0.6 - al * 0.3 + t.kind.value * 0.25,
            x: sx,
            y: sy,
            ax: ax,
            ay: ay,
            speed: speed,
          ));
        }
      }
    }
    cands.sort((a, b) => b.geo.compareTo(a.geo));

    double rate(({int points, int foul, double cueX, double cueY, bool cueIn}) r) {
      if (r.foul > 0) return -8.0 * r.foul - (r.cueIn ? 4 : 0);
      var nearest = 9.0;
      for (final t in targets) {
        final d = math.sqrt(math.pow(t.x - r.cueX, 2) + math.pow(t.y - r.cueY, 2));
        nearest = math.min(nearest, d);
      }
      // Potting: stay close for the next one. Not potting: leave it far away.
      return r.points > 0 ? r.points * 12 - nearest * 0.8 : nearest * 1.2;
    }

    var best = (x: cue.x, y: cue.y, dx: 0.0, dy: -1.0, speed: 2.0, side: 0.0, top: 0.0);
    var bestScore = -1e9;
    void consider(double x, double y, double ax, double ay, double speed, double top, double bonus) {
      final s = rate(simulate(x, y, ax, ay, speed, top: top)) + bonus;
      if (s > bestScore) {
        bestScore = s;
        best = (x: x, y: y, dx: ax, dy: ay, speed: speed, side: 0.0, top: top);
      }
    }

    for (final c in cands.take(tries)) {
      consider(c.x, c.y, c.ax, c.ay, c.speed, 0, c.geo * 0.1);
      if (difficulty >= 2) consider(c.x, c.y, c.ax, c.ay, c.speed * 1.3, -0.4, c.geo * 0.1);
      if (difficulty >= 3) consider(c.x, c.y, c.ax, c.ay, c.speed * 1.1, 0.5, c.geo * 0.1);
    }
    // No pot worth playing: roll up safely, thin off a ball on.
    if (bestScore < 6) {
      final (sx, sy) = starts.first;
      final near = List.of(targets)
        ..sort((a, b) => _dist(a, sx, sy).compareTo(_dist(b, sx, sy)));
      for (final t in near.take(4)) {
        final dx = t.x - sx, dy = t.y - sy, len = math.sqrt(dx * dx + dy * dy);
        if (len == 0) continue;
        for (final off in const [-1.7, 1.7, 0.0]) {
          final ax = dx + -dy / len * off * SnookerRules.r, ay = dy + dx / len * off * SnookerRules.r;
          for (final v in const [1.2, 2.0, 3.2]) {
            consider(sx, sy, ax, ay, v, 0, 0);
          }
        }
      }
      // Snookered (or every safety fouls): look all round for a way out.
      if (bestScore < 0) {
        for (var i = 0; i < 36; i++) {
          final a = i / 36 * 2 * math.pi;
          consider(sx, sy, math.cos(a), math.sin(a), 3.6, 0, 0);
        }
      }
    }
    final a = math.atan2(best.dy, best.dx) + (_rng.nextDouble() * 2 - 1) * noise;
    return (
      x: best.x,
      y: best.y,
      dx: math.cos(a),
      dy: math.sin(a),
      power: SnookerRules.powerOf(best.speed),
      side: best.side,
      top: best.top,
    );
  }

  static double _dist(SnookerBall b, double x, double y) => math.sqrt(math.pow(b.x - x, 2) + math.pow(b.y - y, 2));
}

/// Where a shot along ([dx], [dy]) first meets something: the cue ball's
/// centre at contact, the ball it hits (null = a cushion) and where that ball
/// and the cue ball head off.
({double x, double y, SnookerBall? hit, double objX, double objY, double cueX, double cueY}) snookerAimGuide(
  SnookerGame g,
  double dx,
  double dy,
) {
  final c = g.cue;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len == 0) return (x: c.x, y: c.y, hit: null, objX: 0, objY: 0, cueX: 0, cueY: 0);
  final ux = dx / len, uy = dy / len;
  var bestT = double.infinity;
  SnookerBall? hit;
  const rr = SnookerRules.r * 2;
  for (final b in g.balls) {
    if (identical(b, c)) continue;
    final ox = c.x - b.x, oy = c.y - b.y;
    final q = ox * ux + oy * uy;
    final disc = q * q - (ox * ox + oy * oy - rr * rr);
    if (disc < 0) continue;
    final t = -q - math.sqrt(disc);
    if (t > 0 && t < bestT) {
      bestT = t;
      hit = b;
    }
  }
  const r = SnookerRules.r;
  double wall(double p, double u, double hi) => u > 0 ? (hi - r - p) / u : (u < 0 ? (r - p) / u : double.infinity);
  final tw = math.min(wall(c.x, ux, SnookerRules.width), wall(c.y, uy, SnookerRules.length));
  if (tw < bestT) {
    bestT = tw;
    hit = null;
  }
  final x = c.x + ux * bestT, y = c.y + uy * bestT;
  final h = hit;
  if (h == null) return (x: x, y: y, hit: null, objX: 0, objY: 0, cueX: 0, cueY: 0);
  final nx = (h.x - x) / rr, ny = (h.y - y) / rr;
  final along = ux * nx + uy * ny;
  return (x: x, y: y, hit: h, objX: nx * along, objY: ny * along, cueX: ux - nx * along, cueY: uy - ny * along);
}
