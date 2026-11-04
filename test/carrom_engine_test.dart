import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snakeladder/game/carrom/carrom_engine.dart';

void runShot(CarromGame g) {
  var t = 0;
  while (g.moving && t++ < 2000) {
    g.step(1 / 60);
  }
}

CarromDisc coin(CarromGame g, CarromKind k) => g.discs.firstWhere((d) => d.kind == k);

void main() {
  test('rack: queen in the middle, 9 white + 9 black, nothing overlapping', () {
    final g = CarromGame(rng: math.Random(1));
    expect(g.discs.where((d) => d.kind == CarromKind.white).length, 9);
    expect(g.discs.where((d) => d.kind == CarromKind.black).length, 9);
    final q = coin(g, CarromKind.queen);
    expect((q.x, q.y), (0.5, 0.5));
    for (var i = 0; i < g.discs.length; i++) {
      for (var j = i + 1; j < g.discs.length; j++) {
        final a = g.discs[i], b = g.discs[j];
        expect(math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)), greaterThanOrEqualTo(a.r + b.r - 1e-9));
      }
    }
    expect(g.striker.y, closeTo(1 - CarromRules.baseInset, 1e-9));
    expect(g.strikerClear, isTrue);
  });

  test('a break scatters the coins and everything comes to rest on the board', () {
    final g = CarromGame(rng: math.Random(2));
    g.shoot(0, -1, 1);
    expect(g.moving, isTrue);
    runShot(g);
    expect(g.moving, isFalse);
    for (final d in g.discs) {
      expect(d.x, inInclusiveRange(0, 1));
      expect(d.y, inInclusiveRange(0, 1));
    }
    expect(
      g.discs.where((d) => d.kind != CarromKind.striker).any((d) => (d.x - 0.5).abs() > 0.1 || (d.y - 0.5).abs() > 0.1),
      isTrue,
    );
  });

  /// Clear the board but [keep] and put [target] in front of the top-left pocket.
  CarromGame setUpPot(CarromKind target, {int pocketedWhite = 0}) {
    final g = CarromGame(rng: math.Random(3));
    g.discs.removeWhere((d) => d.kind != CarromKind.striker);
    g.discs.insert(0, CarromDisc(900, target, 0.15, 0.15));
    g.pocketed[0] = pocketedWhite;
    // Striker on the diagonal behind it.
    g.striker
      ..x = 0.4
      ..y = 0.4;
    return g;
  }

  test('pocketing your own coin: it counts and you go again', () {
    final g = setUpPot(CarromKind.white);
    g.shoot(-1, -1, 0.3);
    runShot(g);
    expect(g.pocketed[0], 1);
    expect(g.last!.again, isTrue);
    expect(g.turn, 0);
  });

  test('pocketing the other colour: it counts for them, turn passes', () {
    final g = setUpPot(CarromKind.black);
    g.shoot(-1, -1, 0.3);
    runShot(g);
    expect(g.pocketed[1], 1);
    expect(g.turn, 1);
  });

  test('queen before any of your coins goes back to the centre', () {
    final g = setUpPot(CarromKind.queen);
    g.shoot(-1, -1, 0.3);
    runShot(g);
    expect(g.queenOnBoard, isTrue);
    expect(g.last!.queenReturned, isTrue);
  });

  test('queen after one of yours: must cover next shot, else it returns', () {
    final g = setUpPot(CarromKind.queen, pocketedWhite: 2);
    g.shoot(-1, -1, 0.3);
    runShot(g);
    expect(g.queenPending, 0);
    expect(g.turn, 0, reason: 'you get a shot to cover it');
    // Miss the cover: shoot into nothing.
    g.shoot(1, 0, 0.2);
    runShot(g);
    expect(g.queenPending, isNull);
    expect(g.queenOnBoard, isTrue);
    expect(g.queenOwner, isNull);
  });

  test('striker in a pocket is a foul: lose a coin back and the turn', () {
    final g = setUpPot(CarromKind.white, pocketedWhite: 3);
    g.discs.removeWhere((d) => d.kind == CarromKind.white);
    g.shoot(-1, -1, 0.6);
    runShot(g);
    expect(g.last!.strikerPocketed, isTrue);
    expect(g.pocketed[0], 2);
    expect(g.discs.where((d) => d.kind == CarromKind.white).length, 1);
    expect(g.turn, 1);
  });

  test('aim guide finds the first coin in line', () {
    final g = setUpPot(CarromKind.white);
    final a = carromAimGuide(g, -1, -1);
    expect(a.hit?.kind, CarromKind.white);
    expect(carromAimGuide(g, 1, 0).hit, isNull);
  });

  test('computer vs computer: games finish with a winner and board points', () {
    for (var seed = 0; seed < 3; seed++) {
      final g = CarromGame(rng: math.Random(seed));
      var shots = 0;
      // Roomy: the last coin before the queen can go back again and again.
      while (!g.isOver && shots++ < 1000) {
        final s = g.botShot(3);
        g.placeStriker(s.pos);
        if (!g.strikerClear) g.placeStriker(0.5);
        g.shoot(s.dx, s.dy, s.power);
        runShot(g);
      }
      expect(g.isOver, isTrue, reason: 'seed $seed after $shots shots');
      expect(g.boardPoints, greaterThanOrEqualTo(0));
      expect(g.pocketed[g.winner!], CarromRules.coinsEach);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a disc sliding into a wall picks up spin the way rims rub', () {
    double spinOff(double x, double y, double vx, double vy) {
      final g = CarromGame(rng: math.Random(1));
      g.discs.removeWhere((d) => d.kind != CarromKind.striker);
      g.striker
        ..x = x
        ..y = y;
      g.shoot(vx, vy, 0.5);
      g.step(1 / 60);
      return g.striker.spin;
    }

    const r = CarromRules.strikerR;
    expect(spinOff(r + 0.001, 0.5, -1, 1), greaterThan(0), reason: 'left wall, moving +y');
    expect(spinOff(1 - r - 0.001, 0.5, 1, 1), lessThan(0), reason: 'right wall, moving +y');
    expect(spinOff(0.5, r + 0.001, 1, -1), lessThan(0), reason: 'top wall, moving +x');
    expect(spinOff(0.5, 1 - r - 0.001, 1, 1), greaterThan(0), reason: 'bottom wall, moving +x');
  });

  test('computer does not treat its own striker as blocking the baseline', () {
    final g = CarromGame(rng: math.Random(1));
    g.discs.removeWhere((d) => d.kind != CarromKind.striker);
    expect(g.botShot(1).pos, 0.5, reason: 'nothing to aim at: the centre fallback');
  });

  test('the computer plans on a copy: same shot, real board untouched', () {
    final g = CarromGame(rng: math.Random(4));
    g.shoot(0, -1, 0.9); // break, so the board isn't the plain rack
    runShot(g);
    final before = [for (final d in g.discs) (d.kind, d.x, d.y)];
    final a = planCarromShot((CarromGame.planningCopy(g, seed: 7), 3));
    final b = planCarromShot((CarromGame.planningCopy(g, seed: 7), 3));
    expect((a.pos, a.dx, a.dy, a.power), (b.pos, b.dx, b.dy, b.power));
    expect([for (final d in g.discs) (d.kind, d.x, d.y)], before);
    final copy = CarromGame.planningCopy(g);
    expect(copy.turn, g.turn);
    expect(copy.pocketed, g.pocketed);
    expect(copy.discs.length, g.discs.length);
    expect(identical(copy.striker, g.striker), isFalse);
    expect(copy.discs.contains(copy.striker), isTrue);
  });
}
