import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/crash/crash_engine.dart';

void main() {
  test('crash points follow P(crash ≥ x) ≈ 0.99 / x', () {
    final rng = math.Random(7);
    const n = 200000;
    var atLeast2 = 0, atLeast10 = 0;
    for (var i = 0; i < n; i++) {
      final c = CrashRules.crashPointFrom(rng.nextDouble());
      expect(c, greaterThanOrEqualTo(1));
      if (c >= 2) atLeast2++;
      if (c >= 10) atLeast10++;
    }
    expect(atLeast2 / n, closeTo(0.495, 0.01));
    expect(atLeast10 / n, closeTo(0.099, 0.005));
  });

  test('multiplier grows: 2× ≈ 5.8 s, monotonic', () {
    expect(CrashRules.multiplierAt(0), 1);
    expect(CrashRules.secondsFor(2), closeTo(5.78, 0.01));
    expect(CrashRules.multiplierAt(10) > CrashRules.multiplierAt(5), isTrue);
  });

  test('a round: bet, auto cash-out pays, the crash loses the other bet', () {
    final g = CrashGame(rng: math.Random(3), balance: 1000);
    final t0 = DateTime.now();
    g.setAmount(0, 100);
    g.setAmount(1, 50);
    g.setAuto(0, 1.5);
    g.toggleBet(0);
    g.toggleBet(1);
    expect(g.balance, 850);
    // Force a known crash point after betting.
    g.tick(t0); // betting tick
    g.tick(t0.add(const Duration(seconds: 7))); // → flying
    g.crashPoint = 3.0;
    var t = t0.add(const Duration(seconds: 7));
    while (g.phase == CrashPhase.flying) {
      t = t.add(const Duration(milliseconds: 50));
      g.tick(t);
    }
    expect(g.bets[0].cashedAt, 1.5);
    expect(g.bets[1].cashedAt, isNull, reason: 'no manual cash-out → lost');
    expect(g.balance, 850 + 150);
    expect(g.history.first, 3.0);
  });
}
