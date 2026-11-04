import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snakeladder/game/snooker/snooker_engine.dart';

void runShot(SnookerGame g) {
  var t = 0;
  while (g.moving && t++ < 200000) {
    g.step(1 / 60);
  }
}

/// Only the cue ball at (x, y) plus [others].
SnookerGame table(double x, double y, List<(SnookerKind, double, double)> others) {
  final g = SnookerGame(rng: math.Random(1));
  g.balls.removeWhere((b) => b.kind != SnookerKind.cue);
  g.cue
    ..x = x
    ..y = y;
  g.inHand = false;
  var id = 100;
  for (final (k, bx, by) in others) {
    g.balls.insert(0, SnookerBall(id++, k, bx, by));
  }
  return g;
}

SnookerBall ball(SnookerGame g, SnookerKind k) => g.balls.firstWhere((b) => b.kind == k);
const w = SnookerRules.width, l = SnookerRules.length;

void main() {
  group('table', () {
    test('rack: 15 reds, 6 colours on their spots, nothing overlapping', () {
      final g = SnookerGame(rng: math.Random(1));
      expect(g.redsLeft, 15);
      SnookerRules.spots.forEach((k, s) => expect((ball(g, k).x, ball(g, k).y), s));
      for (var i = 0; i < g.balls.length; i++) {
        for (var j = i + 1; j < g.balls.length; j++) {
          final a = g.balls[i], b = g.balls[j];
          expect(math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)), greaterThanOrEqualTo(2 * SnookerRules.r));
        }
      }
      expect(SnookerRules.inD(g.cue.x, g.cue.y), isTrue);
      expect(g.target, SnookerKind.red);
    });

    test('real 2:1 table; a 52.5 mm ball drawn ballScale× bigger', () {
      expect(l / w, closeTo(2, 0.01));
      expect(SnookerRules.r * 2, closeTo(0.0525 * SnookerRules.ballScale, 1e-9));
      // The pockets grow with the balls: a ball still fits the middle mouth
      // with the same room as on a real table.
      expect(SnookerRules.midMouth * 2 / (SnookerRules.r * 2), closeTo(0.116 / 0.0525, 1e-9));
    });
  });

  group('physics', () {
    test('a stun shot slides, then rolls at 5/7 of its speed', () {
      final g = table(w / 2, l - 0.2, []);
      g.shoot(0, -1, SnookerRules.powerOf(3));
      var rolling = false;
      for (var i = 0; i < 120 && !rolling; i++) {
        g.step(1 / 60);
        final c = g.cue;
        rolling = (c.vy + SnookerRules.r * c.wx).abs() < 1e-6 && c.vy != 0;
      }
      expect(rolling, isTrue);
      expect(g.cue.vy.abs(), closeTo(3 * 5 / 7, 0.2));
    });

    test('screw comes back, follow runs through, a stun stops dead', () {
      double after(double top) {
        final g = table(w / 2, 2.0, [(SnookerKind.red, w / 2, 1.8)]);
        g.shoot(0, -1, SnookerRules.powerOf(2.5), top: top);
        runShot(g);
        return g.cue.y;
      }

      expect(after(-1), greaterThan(2.0), reason: 'screw');
      expect(after(1), lessThan(1.75), reason: 'follow');
      final stun = table(w / 2, 1.9, [(SnookerKind.red, w / 2, 1.8)]);
      stun.shoot(0, -1, SnookerRules.powerOf(0.6));
      runShot(stun);
      expect((stun.cue.y - 1.8525).abs(), lessThan(0.06));
    });

    test('right-hand side comes off the top cushion to the right', () {
      double exitX(double side) {
        final g = table(w / 2, 0.8, []);
        g.shoot(0, -1, SnookerRules.powerOf(2.5), side: side);
        for (var i = 0; i < 30 && g.cue.vy <= 0; i++) {
          g.step(1 / 60);
        }
        expect(g.cue.vy, greaterThan(0), reason: 'has bounced');
        return g.cue.vx;
      }

      expect(exitX(1), greaterThan(0.05));
      expect(exitX(-1), lessThan(-0.05));
      expect(exitX(0).abs(), lessThan(1e-6));
    });

    test('a cushion takes pace off a ball', () {
      final g = table(w / 2, 0.5, []);
      g.shoot(0, -1, SnookerRules.powerOf(2));
      var before = 0.0;
      for (var i = 0; i < 60 && g.cue.vy <= 0; i++) {
        before = g.cue.speed;
        g.step(1 / 60);
      }
      expect(g.cue.speed, lessThan(before));
    });

    test('a ball straight at a pocket drops; one hitting the jaw stays out', () {
      final inG = table(1.0, 1.0, [(SnookerKind.red, 0.4, 0.4)]);
      inG.shoot(-1, -1, SnookerRules.powerOf(3), top: -1);
      runShot(inG);
      expect(inG.redsLeft, 0);

      // Along the cushion, a ball's width out of line: it hits the far jaw.
      final out = table(0.6, 0.6, [(SnookerKind.red, 0.3, 0.27)]);
      out.shoot(-0.3, -0.33, SnookerRules.powerOf(0.9), top: -1);
      runShot(out);
      expect(out.balls.every((b) => b.x >= -0.06 && b.y >= -0.06), isTrue);
    });

    test('middle pocket accepts a ball across the table', () {
      final g = table(0.8, l / 2, [(SnookerKind.red, 0.4, l / 2)]);
      g.shoot(-1, 0, SnookerRules.powerOf(2.5), top: -1);
      runShot(g);
      expect(g.redsLeft, 0);
    });
  });

  group('rules', () {
    /// Cue 0.3 m behind a ball by the top-left pocket: a clean pot.
    SnookerGame potSetup(SnookerKind k, {List<(SnookerKind, double, double)> also = const []}) =>
        table(0.6, 0.6, [(k, 0.3, 0.3), ...also]);

    void pot(SnookerGame g) {
      g.shoot(-1, -1, SnookerRules.powerOf(2), top: -0.8);
      runShot(g);
    }

    test('red: +1, keeps the table, colour next', () {
      final g = potSetup(SnookerKind.red, also: [(SnookerKind.red, 1.5, 3), (SnookerKind.black, 0.9, 0.32)]);
      pot(g);
      expect(g.scores[0], 1);
      expect(g.turn, 0);
      expect(g.colourDue, isTrue);
      expect(g.target, isNull);
      expect(g.currentBreak, 1);
    });

    test('colour after a red scores its value and goes back on its spot', () {
      final g = potSetup(SnookerKind.black, also: [(SnookerKind.red, 1.5, 3)]);
      g.colourDue = true;
      pot(g);
      expect(g.scores[0], 7);
      final (sx, sy) = SnookerRules.spots[SnookerKind.black]!;
      expect((ball(g, SnookerKind.black).x, ball(g, SnookerKind.black).y), (sx, sy));
      expect(g.colourDue, isFalse);
      expect(g.target, SnookerKind.red);
    });

    test('potting a colour when on a red is a foul worth its value', () {
      final g = potSetup(SnookerKind.pink, also: [(SnookerKind.red, 1.5, 3)]);
      pot(g);
      expect(g.scores, [0, 6]);
      expect(g.turn, 1);
      expect(g.last!.foul, 6);
      expect(g.balls.any((b) => b.kind == SnookerKind.pink), isTrue);
    });

    test('missing everything gives away 4 at least', () {
      final g = table(0.6, 2, [(SnookerKind.red, 1.5, 3)]);
      g.shoot(-1, -0.2, 0.2);
      runShot(g);
      expect(g.scores, [0, 4]);
      expect(g.turn, 1);
    });

    test('in-off: foul, ball in hand for the other player', () {
      final g = table(0.3, 0.3, [(SnookerKind.red, 1.5, 3)]);
      g.shoot(-1, -1, SnookerRules.powerOf(2.5));
      runShot(g);
      expect(g.last!.inOff, isTrue);
      expect(g.scores[1], greaterThanOrEqualTo(4));
      expect(g.turn, 1);
      expect(g.inHand, isTrue);
      expect(SnookerRules.inD(g.cue.x, g.cue.y), isTrue);
      expect(g.balls.contains(g.cue), isTrue);
    });

    test('colours are cleared in order and stay down', () {
      final g = potSetup(SnookerKind.yellow, also: [(SnookerKind.green, 1.5, 3)]);
      expect(g.target, SnookerKind.yellow);
      pot(g);
      expect(g.scores[0], 2);
      expect(g.balls.any((b) => b.kind == SnookerKind.yellow), isFalse);
      expect(g.target, SnookerKind.green);
    });

    test('after the last red you may take any colour, and it comes back', () {
      final g = potSetup(SnookerKind.blue, also: [(SnookerKind.yellow, 1.5, 3)]);
      g.colourDue = true;
      pot(g);
      expect(g.scores[0], 5);
      expect(g.balls.any((b) => b.kind == SnookerKind.blue), isTrue);
      expect(g.target, SnookerKind.yellow);
    });

    test('a foul that leaves a snooker gives a free ball', () {
      // Cue tucked behind the brown with the only red straight beyond it.
      final g = table(0.6, 2, [(SnookerKind.red, 1.0, 1.0), (SnookerKind.brown, 0.8, 1.5)]);
      g.cue
        ..x = 0.6
        ..y = 2.0;
      g.turn = 0;
      g.shoot(-1, 0, 0.02);
      runShot(g);
      expect(g.last!.foul, greaterThan(0));
      expect(g.freeBall, isTrue);
      expect(g.ballsOn.map((b) => b.kind), containsAll([SnookerKind.red, SnookerKind.brown]));
    });

    test('free ball: a colour counts as a red, comes back, and a colour follows', () {
      final g = potSetup(SnookerKind.black, also: [(SnookerKind.red, 1.5, 3)]);
      g.freeBall = true;
      pot(g);
      expect(g.scores, [1, 0]);
      expect(g.balls.any((b) => b.kind == SnookerKind.black), isTrue);
      expect(g.colourDue, isTrue);
    });

    test('potting the last black ends the frame', () {
      final g = potSetup(SnookerKind.black);
      g.scores[1] = 3;
      pot(g);
      expect(g.isOver, isTrue);
      expect(g.winner, 0);
    });

    test('with only the black left, a foul gives 7 and ends the frame', () {
      final g = table(0.6, 2, [(SnookerKind.black, 1.5, 3)]);
      g.scores[0] = 3;
      g.scores[1] = 2;
      g.shoot(-1, 0, 0.02);
      runShot(g);
      expect(g.scores, [3, 9]);
      expect(g.winner, 1);
    });

    test('level on the last black: re-spotted, ball in hand, next score wins', () {
      final g = potSetup(SnookerKind.black);
      g.scores[1] = 7;
      pot(g);
      expect(g.isOver, isFalse);
      expect(g.blackGame, isTrue);
      expect(g.inHand, isTrue);
      final (sx, sy) = SnookerRules.spots[SnookerKind.black]!;
      expect((ball(g, SnookerKind.black).x, ball(g, SnookerKind.black).y), (sx, sy));
    });

    test('a colour whose spot is taken goes on the highest free spot', () {
      final (bx, by) = SnookerRules.spots[SnookerKind.black]!;
      final g = potSetup(SnookerKind.black, also: [(SnookerKind.red, bx, by), (SnookerKind.red, 1.5, 3)]);
      g.colourDue = true;
      pot(g);
      final (px, py) = SnookerRules.spots[SnookerKind.pink]!;
      expect((ball(g, SnookerKind.black).x, ball(g, SnookerKind.black).y), (px, py));
    });

    test('ball in hand stays inside the D and off other balls', () {
      final g = SnookerGame(rng: math.Random(1));
      g.placeCue(0.1, 0.1);
      expect(SnookerRules.inD(g.cue.x, g.cue.y + 1e-9), isTrue);
      final before = (g.cue.x, g.cue.y);
      final brown = ball(g, SnookerKind.brown);
      g.placeCue(brown.x, brown.y + 0.01);
      expect((g.cue.x, g.cue.y), before);
    });
  });

  test('aim guide: first ball in line, then the direction it leaves', () {
    final g = table(w / 2, 2, [(SnookerKind.red, w / 2, 1)]);
    final a = snookerAimGuide(g, 0, -1);
    expect(a.hit?.kind, SnookerKind.red);
    expect(a.objY, closeTo(-1, 1e-9));
    expect(snookerAimGuide(g, 1, 0).hit, isNull);
  });

  test('computer pots an easy ball at every difficulty it should', () {
    final g = table(0.7, 0.7, [(SnookerKind.red, 0.35, 0.35), (SnookerKind.black, 1.5, 3)]);
    final s = g.botShot(3);
    g.shoot(s.dx, s.dy, s.power, side: s.side, top: s.top);
    runShot(g);
    expect(g.scores[0], greaterThanOrEqualTo(1));
  });

  test('computer vs computer: frames finish with a winner and everything stays on the table', () {
    for (var seed = 0; seed < 2; seed++) {
      final g = SnookerGame(rng: math.Random(seed));
      var shots = 0;
      while (!g.isOver && shots++ < 700) {
        final s = g.botShot(3);
        g.placeCue(s.x, s.y);
        expect(g.shoot(s.dx, s.dy, s.power, side: s.side, top: s.top), isTrue);
        runShot(g);
        expect(g.moving, isFalse);
        for (final b in g.balls) {
          expect(b.x, inInclusiveRange(-0.06, w + 0.06));
          expect(b.y, inInclusiveRange(-0.06, l + 0.06));
        }
      }
      expect(g.isOver, isTrue, reason: 'seed $seed after $shots shots, scores ${g.scores}, reds ${g.redsLeft}');
      expect(g.scores[g.winner!], greaterThan(g.scores[1 - g.winner!]));
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
