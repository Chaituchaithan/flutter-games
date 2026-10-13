import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/roulette/roulette_engine.dart';

/// Always lands on the given wheel index.
class _Fixed implements math.Random {
  _Fixed(this.index);
  final int index;
  @override
  int nextInt(int max) => index;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

RouletteGame _game(int result) =>
    RouletteGame(rng: _Fixed(RouletteRules.wheel.indexOf(result)), balance: 1000);

void main() {
  test('wheel has all 37 numbers once; 18 red, 18 black', () {
    expect(RouletteRules.wheel.toSet().length, 37);
    expect(RouletteRules.wheel.toSet(), {for (var n = 0; n <= 36; n++) n});
    expect(RouletteRules.red.length, 18);
    expect([for (var n = 1; n <= 36; n++) n].where(RouletteRules.isBlack).length, 18);
  });

  test('bet coverage and payouts', () {
    expect(BetSpot.straight(17).payout, 35);
    expect(BetSpot.split(17, 20).numbers, {17, 20});
    expect(BetSpot.street(0).numbers, {1, 2, 3});
    expect(BetSpot.corner(1).numbers, {1, 2, 4, 5});
    expect(BetSpot.corner(1).payout, 8);
    expect(BetSpot.dozen(2).numbers.length, 12);
    expect(BetSpot.column(0).numbers, contains(34));
    expect(BetSpot.redBet.wins(0), isFalse, reason: 'zero loses outside bets');
  });

  test('straight win pays 35:1 plus the stake; losers lose', () {
    final g = _game(17)..place(BetSpot.straight(17), 10)..place(BetSpot.redBet, 50);
    expect(g.balance, 940);
    g
      ..spin()
      ..settle();
    expect(g.result, 17);
    expect(g.lastReturn, 360, reason: '10 × 36; 17 is black so red loses');
    expect(g.balance, 1300);
  });

  test('undo, clear, double and repeat', () {
    final g = _game(0)..place(BetSpot.oddBet, 100)..place(BetSpot.straight(5), 25);
    g.undo();
    expect(g.totalBet, 100);
    expect(g.double(), isTrue);
    expect(g.totalBet, 200);
    g
      ..spin()
      ..settle()
      ..nextRound();
    expect(g.bets, isEmpty);
    expect(g.canRepeat, isTrue);
    expect(g.repeat(), isTrue);
    expect(g.totalBet, 200);
    g.clear();
    expect(g.balance, 800, reason: '200 lost on zero; cleared chips returned');
  });

  test('cannot bet more than the balance', () {
    final g = _game(1);
    expect(g.place(BetSpot.highBet, 5000), isFalse);
  });
}
