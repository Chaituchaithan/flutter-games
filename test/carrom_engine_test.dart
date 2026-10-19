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
      while (!g.isOver && shots++ < 400) {
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
}
