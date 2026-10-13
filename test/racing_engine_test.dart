import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/racing/racing_engine.dart';

void main() {
  test('chances add up; top-3 chances add up to 3', () {
    final s = [1.0, 2.0, 0.5, 3.0, 1.2, 0.8];
    expect(RacingGame.winChances(s).fold(0.0, (a, b) => a + b), closeTo(1, 1e-9));
    expect(RacingGame.top3Chances(s).fold(0.0, (a, b) => a + b), closeTo(3, 1e-9));
  });

  test('cars never roll backwards and finish in the drawn order', () {
    for (var seed = 0; seed < 30; seed++) {
      final g = RacingGame(rng: math.Random(seed), balance: 1000)..start();
      for (final run in g.runs) {
        var last = 0.0;
        for (var t = 0.0; t <= run.finishAt; t += 0.02) {
          final x = run.at(t);
          expect(x, greaterThanOrEqualTo(last - 1e-9));
          last = x;
        }
        expect(run.at(run.finishAt), closeTo(1, 1e-9));
      }
      final end = g.runs.map((r) => r.finishAt).reduce(math.max) + 0.1;
      expect(g.standings(end), g.order);
    }
  });

  test('win and top-3 bets pay at the quoted odds', () {
    final g = RacingGame(rng: math.Random(3), balance: 1000);
    g
      ..placeBet(0, RaceBetKind.win, 100)
      ..placeBet(0, RaceBetKind.top3, 100)
      ..start()
      ..finish();
    final winner = g.order.first == 0;
    final podium = g.order.take(3).contains(0);
    final expected = (winner ? (100 * g.winOdds[0]).floor() : 0) + (podium ? (100 * g.top3Odds[0]).floor() : 0);
    expect(g.lastReturn, expected);
    expect(g.balance, 800 + expected);
  });

  test('odds carry the margin (pay less than fair)', () {
    final g = RacingGame(rng: math.Random(1));
    final p = RacingGame.winChances(g.strength);
    for (var i = 0; i < p.length; i++) {
      expect(g.winOdds[i] * p[i], lessThanOrEqualTo(RacingGame.margin + 0.0001));
    }
  });
}
