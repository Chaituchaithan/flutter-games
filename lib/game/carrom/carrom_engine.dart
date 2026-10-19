import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// What a piece on the board is.
enum CarromKind { white, black, queen, striker }

/// A disc on the board, in board units (the playing surface is 1 × 1, top
/// left = 0,0). Mutable for speed: the physics moves these every substep.
class CarromDisc {
  CarromDisc(this.id, this.kind, this.x, this.y);

  final int id;
  final CarromKind kind;
  double x, y;
  double vx = 0, vy = 0;

  double get r => kind == CarromKind.striker ? CarromRules.strikerR : CarromRules.coinR;
  double get mass => kind == CarromKind.striker ? CarromRules.strikerMass : 1;
  double get speed => math.sqrt(vx * vx + vy * vy);
  bool get moving => vx != 0 || vy != 0;

  CarromDisc copy() => CarromDisc(id, kind, x, y)
    ..vx = vx
    ..vy = vy;
}

/// A coin dropping into a pocket (drawn shrinking for a moment).
class CarromSink {
  CarromSink(this.kind, this.x, this.y, this.pocket);
  final CarromKind kind;
  final double x, y;
  final int pocket;
  double t = 0;
}

/// Board sizes and physics, in board units (74 cm play area = 1).
abstract final class CarromRules {
  static const coinR = 0.0215; // 3.18 cm coin
  static const strikerR = 0.028; // 4.13 cm striker
  static const strikerMass = 2.4; // 15 g vs ~5.5 g coins (softened a bit)
  static const pocketR = 0.031; // 4.45 cm pocket
  static const coinsEach = 9;

  /// Baselines: the striker's centre line, and how far along it may go.
  static const baseInset = 0.137;
  static const baseMin = 0.185, baseMax = 0.815;

  /// Hardest shot (board units / second).
  static const maxSpeed = 4.6;

  /// Sliding friction (constant + speed-proportional) and bounces.
  static const friction = 0.85, drag = 1.15;
  static const wallBounce = 0.72, discBounce = 0.93;

  static const pockets = [
    (pocketR, pocketR),
    (1 - pocketR, pocketR),
    (pocketR, 1 - pocketR),
    (1 - pocketR, 1 - pocketR),
  ];

  /// Striker centre y for player 0 (bottom) / 1 (top).
  static double baseY(int player) => player == 0 ? 1 - baseInset : baseInset;

  /// Points for the board: the loser's coins left, +3 if the winner covered the queen.
  static const queenPoints = 3;
}

/// What one shot did.
@immutable
class CarromShotResult {
  const CarromShotResult({
    required this.player,
    required this.own,
    required this.other,
    required this.queen,
    required this.strikerPocketed,
    required this.covered,
    required this.queenReturned,
    required this.returned,
    required this.again,
  });

  final int player;

  /// Coins of the shooter's / the other side's colour pocketed this shot.
  final int own, other;
  final bool queen;
  final bool strikerPocketed;

  /// The queen was covered (by this shot).
  final bool covered;

  /// The queen went back to the centre (not covered, or too early).
  final bool queenReturned;

  /// Coins put back on the board as a penalty.
  final int returned;

  /// The shooter plays again.
  final bool again;

  bool get foul => strikerPocketed;
}

/// Carrom for two: you (white, bottom) against the computer (black, top).
/// Pocket your coins, cover the queen with one of your own, and clear your
/// colour first. White breaks.
class CarromGame extends ChangeNotifier {
  CarromGame({math.Random? rng}) : _rng = rng ?? math.Random() {
    _rack();
    _placeStriker();
  }

  final math.Random _rng;

  /// Discs on the board (striker last).
  final List<CarromDisc> discs = [];
  late CarromDisc striker;
  final List<CarromSink> sinking = [];

  /// Pocketed coins per player colour (0 = white, 1 = black).
  final pocketed = [0, 0];

  /// Who covered the queen (null = still on the board / uncovered).
  int? queenOwner;

  /// Pocketed the queen last shot and must cover it now.
  int? queenPending;

  int turn = 0;

  /// Striker position along the baseline, 0..1.
  double strikerPos = 0.5;

  bool moving = false;
  int? winner;
  int shots = 0;
  CarromShotResult? last;

  /// Called when a disc drops (kind) — for haptics.
  void Function(CarromKind kind)? onPocket;

  // Shot bookkeeping.
  final List<CarromKind> _inShot = [];
  bool _strikerIn = false;

  bool get isOver => winner != null;
  CarromKind colorOf(int player) => player == 0 ? CarromKind.white : CarromKind.black;
  int coinsLeft(int player) => CarromRules.coinsEach - pocketed[player];
  bool get queenOnBoard => discs.any((d) => d.kind == CarromKind.queen);

  int _nextId = 0;

  void _rack() {
    final d = CarromRules.coinR * 2 + 0.0006;
    discs.add(CarromDisc(_nextId++, CarromKind.queen, 0.5, 0.5));
    // Hex rings around the queen: 6 inside, 12 outside, colours alternating.
    final spots = <(double, double)>[];
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 6 + i * math.pi / 3;
      spots.add((math.cos(a) * d, math.sin(a) * d));
    }
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 6 + i * math.pi / 3;
      spots.add((math.cos(a) * 2 * d, math.sin(a) * 2 * d));
      final b = a + math.pi / 6;
      spots.add((math.cos(b) * d * math.sqrt(3), math.sin(b) * d * math.sqrt(3)));
    }
    for (var i = 0; i < spots.length; i++) {
      final kind = i.isEven ? CarromKind.white : CarromKind.black;
      discs.add(CarromDisc(_nextId++, kind, 0.5 + spots[i].$1, 0.5 + spots[i].$2));
    }
  }

  double _baseX(double pos) => CarromRules.baseMin + (CarromRules.baseMax - CarromRules.baseMin) * pos.clamp(0.0, 1.0);

  void _placeStriker() {
    discs.removeWhere((d) => d.kind == CarromKind.striker);
    striker = CarromDisc(_nextId++, CarromKind.striker, _baseX(strikerPos), CarromRules.baseY(turn));
    discs.add(striker);
  }

  /// Slide the striker along your baseline (0..1).
  void placeStriker(double pos) {
    if (moving || isOver) return;
    strikerPos = pos.clamp(0.0, 1.0);
    striker
      ..x = _baseX(strikerPos)
      ..y = CarromRules.baseY(turn);
    notifyListeners();
  }

  /// The striker may not sit on a coin.
  bool get strikerClear => _clearAt(striker.x, striker.y, striker.r, except: striker);

  bool _clearAt(double x, double y, double r, {CarromDisc? except}) {
    for (final d in discs) {
      if (identical(d, except)) continue;
      final dx = d.x - x, dy = d.y - y, rr = d.r + r;
      if (dx * dx + dy * dy < rr * rr) return false;
    }
    return true;
  }

  /// Flick the striker: [dx], [dy] direction (any length), [power] 0..1.
  void shoot(double dx, double dy, double power) {
    if (moving || isOver || !strikerClear) return;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return;
    final v = CarromRules.maxSpeed * power.clamp(0.05, 1.0);
    striker
      ..vx = dx / len * v
      ..vy = dy / len * v;
    moving = true;
    _inShot.clear();
    _strikerIn = false;
    shots++;
    notifyListeners();
  }

  /// Advance the physics by [dt] seconds (call every frame while [moving]).
  void step(double dt) {
    for (final s in sinking) {
      s.t += dt;
    }
    sinking.removeWhere((s) => s.t > 0.35);
    if (!moving) {
      if (sinking.isNotEmpty) notifyListeners();
      return;
    }
    const sub = 1 / 480;
    var left = dt.clamp(0.0, 1 / 20);
    while (left > 0 && moving) {
      final h = math.min(sub, left);
      left -= h;
      if (!_physics(discs, h, _pocket)) _endShot();
    }
    notifyListeners();
  }

  void _pocket(CarromDisc d, int pocket) {
    discs.remove(d);
    sinking.add(CarromSink(d.kind, d.x, d.y, pocket));
    if (d.kind == CarromKind.striker) {
      _strikerIn = true;
    } else {
      _inShot.add(d.kind);
    }
    onPocket?.call(d.kind);
  }

  /// One physics substep for [list]. Returns false once everything stopped.
  static bool _physics(List<CarromDisc> list, double h, void Function(CarromDisc, int) pocket) {
    var any = false;
    // Move + friction.
    for (final d in list) {
      if (!d.moving) continue;
      d.x += d.vx * h;
      d.y += d.vy * h;
      final s = d.speed;
      final ns = s - (CarromRules.friction + CarromRules.drag * s) * h;
      if (ns <= 0.004) {
        d.vx = 0;
        d.vy = 0;
      } else {
        d.vx *= ns / s;
        d.vy *= ns / s;
        any = true;
      }
    }
    // Disc–disc collisions.
    for (var i = 0; i < list.length; i++) {
      final a = list[i];
      for (var j = i + 1; j < list.length; j++) {
        final b = list[j];
        final dx = b.x - a.x, dy = b.y - a.y;
        final rr = a.r + b.r;
        final dist2 = dx * dx + dy * dy;
        if (dist2 >= rr * rr || dist2 == 0) continue;
        final dist = math.sqrt(dist2);
        final nx = dx / dist, ny = dy / dist;
        // Push apart.
        final overlap = rr - dist;
        final ta = b.mass / (a.mass + b.mass), tb = a.mass / (a.mass + b.mass);
        a.x -= nx * overlap * ta;
        a.y -= ny * overlap * ta;
        b.x += nx * overlap * tb;
        b.y += ny * overlap * tb;
        final rel = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny;
        if (rel <= 0) continue;
        final j0 = (1 + CarromRules.discBounce) * rel / (1 / a.mass + 1 / b.mass);
        a.vx -= j0 / a.mass * nx;
        a.vy -= j0 / a.mass * ny;
        b.vx += j0 / b.mass * nx;
        b.vy += j0 / b.mass * ny;
        any = true;
      }
    }
    // Pockets, then the frame.
    for (final d in List.of(list)) {
      for (var p = 0; p < 4; p++) {
        final (px, py) = CarromRules.pockets[p];
        final dx = d.x - px, dy = d.y - py;
        if (dx * dx + dy * dy < CarromRules.pocketR * CarromRules.pocketR) {
          pocket(d, p);
          break;
        }
      }
    }
    for (final d in list) {
      final r = d.r;
      if (d.x < r) {
        d.x = r;
        if (d.vx < 0) d.vx = -d.vx * CarromRules.wallBounce;
      } else if (d.x > 1 - r) {
        d.x = 1 - r;
        if (d.vx > 0) d.vx = -d.vx * CarromRules.wallBounce;
      }
      if (d.y < r) {
        d.y = r;
        if (d.vy < 0) d.vy = -d.vy * CarromRules.wallBounce;
      } else if (d.y > 1 - r) {
        d.y = 1 - r;
        if (d.vy > 0) d.vy = -d.vy * CarromRules.wallBounce;
      }
    }
    return any;
  }

  /// Put a coin back near the centre (the nearest free spot).
  void _returnCoin(CarromKind kind) {
    final r = CarromRules.coinR;
    for (var ring = 0; ring < 40; ring++) {
      final steps = ring == 0 ? 1 : ring * 6;
      for (var k = 0; k < steps; k++) {
        final a = k / steps * 2 * math.pi;
        final x = 0.5 + math.cos(a) * ring * r * 1.2, y = 0.5 + math.sin(a) * ring * r * 1.2;
        if (_clearAt(x, y, r)) {
          discs.insert(0, CarromDisc(_nextId++, kind, x, y));
          return;
        }
      }
    }
  }

  /// Everything stopped: apply the rules and set up the next shot.
  void _endShot() {
    moving = false;
    for (final d in discs) {
      d.vx = 0;
      d.vy = 0;
    }
    final me = turn, other = 1 - turn;
    final mine = colorOf(me), theirs = colorOf(other);
    var own = _inShot.where((k) => k == mine).length;
    final opp = _inShot.where((k) => k == theirs).length;
    final queenIn = _inShot.contains(CarromKind.queen);
    var covered = false, queenBack = false, returned = 0;
    var again = false;

    pocketed[other] += opp;
    if (_strikerIn) {
      // Foul: your coins from this shot come back, plus one already won.
      returned = own + (pocketed[me] > 0 ? 1 : 0);
      pocketed[me] -= returned - own;
      own = 0;
      if (queenIn || queenPending == me) queenBack = true;
    } else {
      pocketed[me] += own;
      if (queenIn) {
        // The queen only counts once you've pocketed one of your own.
        if (pocketed[me] == 0) {
          queenBack = true;
        } else if (own > 0) {
          covered = true;
        } else {
          queenPending = me;
        }
      } else if (queenPending == me) {
        if (own > 0) {
          covered = true;
        } else {
          queenBack = true;
        }
      }
      again = own > 0 || (queenIn && queenPending == me && !covered);
    }
    if (covered) {
      queenOwner = me;
      queenPending = null;
    }
    if (queenBack) {
      queenPending = null;
      _returnCoin(CarromKind.queen);
    }
    for (var i = 0; i < returned; i++) {
      _returnCoin(mine);
    }
    // Last coin before the queen is covered: it comes back (a foul).
    for (final p in [me, other]) {
      if (pocketed[p] == CarromRules.coinsEach && queenOwner == null) {
        pocketed[p]--;
        _returnCoin(colorOf(p));
        if (p == me) again = false;
        returned++;
      }
    }
    last = CarromShotResult(
      player: me,
      own: own,
      other: opp,
      queen: queenIn,
      strikerPocketed: _strikerIn,
      covered: covered,
      queenReturned: queenBack,
      returned: returned,
      again: again,
    );
    for (final p in [me, other]) {
      if (pocketed[p] == CarromRules.coinsEach && queenOwner != null) {
        winner = p;
      }
    }
    if (!isOver && !again) turn = other;
    strikerPos = 0.5;
    _placeStriker();
    // Centre spot taken: slide along until the striker is clear.
    if (!strikerClear) {
      for (var k = 1; k <= 20 && !strikerClear; k++) {
        placeStriker(0.5 + (k.isOdd ? 1 : -1) * ((k + 1) ~/ 2) * 0.05);
      }
    }
  }

  /// Out of time: the turn passes (an uncovered queen goes back).
  void passTurn() {
    if (moving || isOver) return;
    if (queenPending == turn) {
      queenPending = null;
      _returnCoin(CarromKind.queen);
    }
    last = null;
    turn = 1 - turn;
    strikerPos = 0.5;
    _placeStriker();
    for (var k = 1; k <= 20 && !strikerClear; k++) {
      placeStriker(0.5 + (k.isOdd ? 1 : -1) * ((k + 1) ~/ 2) * 0.05);
    }
    notifyListeners();
  }

  /// Board points for the winner.
  int get boardPoints {
    final w = winner;
    if (w == null) return 0;
    return coinsLeft(1 - w) + (queenOwner == w ? CarromRules.queenPoints : 0);
  }

  // ── Computer ──

  /// Play a shot on a copy of the board; what it would pocket.
  ({List<CarromKind> inShot, bool striker}) simulate(double pos, double dx, double dy, double power) {
    final list = [for (final d in discs) d.copy()];
    final s = list.firstWhere((d) => d.kind == CarromKind.striker)
      ..x = _baseX(pos)
      ..y = CarromRules.baseY(turn);
    final len = math.sqrt(dx * dx + dy * dy);
    final v = CarromRules.maxSpeed * power;
    s
      ..vx = dx / len * v
      ..vy = dy / len * v;
    final got = <CarromKind>[];
    var strikerIn = false;
    for (var t = 0; t < 480 * 8; t++) {
      final go = _physics(list, 1 / 480, (d, _) {
        list.remove(d);
        if (d.kind == CarromKind.striker) {
          strikerIn = true;
        } else {
          got.add(d.kind);
        }
      });
      if (!go) break;
    }
    return (inShot: got, striker: strikerIn);
  }

  /// The computer's shot: striker position, direction and power. Tries
  /// cut shots of its coins (and the queen) into each pocket, simulates the
  /// best-looking ones, and keeps the best result. [difficulty] 1–3 sets
  /// how many it tries and how steady its aim is.
  ({double pos, double dx, double dy, double power}) botShot(int difficulty) {
    final me = turn;
    final mine = colorOf(me), theirs = colorOf(1 - me);
    final y = CarromRules.baseY(me);
    final targets = discs.where((d) => d.kind == mine || (d.kind == CarromKind.queen && pocketed[me] > 0)).toList();
    final cands = <(double, double, double, double, double)>[]; // geo score, pos, dx, dy, power
    for (var i = 0; i <= 12; i++) {
      final pos = i / 12;
      final sx = _baseX(pos);
      if (!_clearAt(sx, y, CarromRules.strikerR)) continue;
      for (final c in targets) {
        for (final (px, py) in CarromRules.pockets) {
          // Ghost-ball aim: where the striker must touch to send c to the pocket.
          var ex = px - c.x, ey = py - c.y;
          final el = math.sqrt(ex * ex + ey * ey);
          ex /= el;
          ey /= el;
          final rr = CarromRules.coinR + CarromRules.strikerR;
          final gx = c.x - ex * rr, gy = c.y - ey * rr;
          var ax = gx - sx, ay = gy - y;
          final al = math.sqrt(ax * ax + ay * ay);
          if (al < 0.01) continue;
          ax /= al;
          ay /= al;
          final cut = ax * ex + ay * ey; // 1 = straight, 0 = 90°
          if (cut < 0.25) continue;
          final score = cut * 2 - el - al * 0.4;
          final power = (0.28 + (el + al) * 0.32 / math.max(cut, 0.4)).clamp(0.25, 0.95);
          cands.add((score, pos, ax, ay, power));
        }
      }
    }
    cands.sort((a, b) => b.$1.compareTo(a.$1));
    final tries = switch (difficulty) {
      <= 1 => 6,
      2 => 14,
      _ => 26,
    };
    final noise = switch (difficulty) {
      <= 1 => 0.05,
      2 => 0.022,
      _ => 0.008,
    };
    ({double pos, double dx, double dy, double power})? best;
    var bestScore = -1e9;
    for (final c in cands.take(tries)) {
      for (final pm in const [1.0, 1.25]) {
        final power = (c.$5 * pm).clamp(0.2, 1.0);
        final r = simulate(c.$2, c.$3, c.$4, power);
        var s = 0.0;
        for (final k in r.inShot) {
          s += k == mine ? 10 : (k == theirs ? -9 : 6);
        }
        if (r.striker) s -= 18;
        s += c.$1;
        if (s > bestScore) {
          bestScore = s;
          best = (pos: c.$2, dx: c.$3, dy: c.$4, power: power);
        }
      }
    }
    // Nothing lined up: a firm shot into the centre to open things up.
    best ??= (() {
      var pos = 0.5;
      for (var k = 0; k <= 12; k++) {
        final p = 0.5 + (k.isOdd ? 1 : -1) * ((k + 1) ~/ 2) / 24;
        if (_clearAt(_baseX(p), y, CarromRules.strikerR)) {
          pos = p;
          break;
        }
      }
      return (pos: pos, dx: 0.5 - _baseX(pos), dy: 0.5 - y, power: 0.75);
    })();
    final a = math.atan2(best.dy, best.dx) + (_rng.nextDouble() * 2 - 1) * noise;
    return (pos: best.pos, dx: math.cos(a), dy: math.sin(a), power: best.power);
  }
}

/// Where a shot along ([dx], [dy]) from the striker first hits a disc:
/// the striker's centre at contact and the disc it meets (null = a wall
/// first, then the point is where the striker meets the frame).
({double x, double y, CarromDisc? hit}) carromAimGuide(CarromGame g, double dx, double dy) {
  final s = g.striker;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len == 0) return (x: s.x, y: s.y, hit: null);
  final ux = dx / len, uy = dy / len;
  var bestT = double.infinity;
  CarromDisc? hit;
  for (final d in g.discs) {
    if (identical(d, s)) continue;
    final rr = d.r + s.r;
    final ox = s.x - d.x, oy = s.y - d.y;
    final b = ox * ux + oy * uy;
    final c = ox * ox + oy * oy - rr * rr;
    final disc = b * b - c;
    if (disc < 0) continue;
    final t = -b - math.sqrt(disc);
    if (t > 0 && t < bestT) {
      bestT = t;
      hit = d;
    }
  }
  // The frame.
  final r = s.r;
  double wall(double p, double u, double lo, double hi) =>
      u > 0 ? (hi - p) / u : (u < 0 ? (lo - p) / u : double.infinity);
  final tw = math.min(wall(s.x, ux, r, 1 - r), wall(s.y, uy, r, 1 - r));
  if (tw < bestT) {
    bestT = tw;
    hit = null;
  }
  return (x: s.x + ux * bestT, y: s.y + uy * bestT, hit: hit);
}
