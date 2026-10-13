import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// European roulette (single zero, 37 pockets).
abstract final class RouletteRules {
  /// Pockets clockwise around the wheel, starting at 0.
  static const wheel = [
    0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, //
    5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26,
  ];

  static const red = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36};

  static bool isRed(int n) => red.contains(n);
  static bool isBlack(int n) => n != 0 && !red.contains(n);

  /// Table position of [n] (1–36): row 0–11 top to bottom, column 0–2.
  static (int, int) cellOf(int n) => ((n - 1) ~/ 3, (n - 1) % 3);
}

enum BetKind { straight, split, street, corner, red, black, odd, even, low, high, dozen, column }

/// One bet spot on the table: its kind, the numbers it covers and how it
/// pays (winnings per chip, stake returned on top).
@immutable
class BetSpot {
  const BetSpot(this.kind, this.numbers, {this.index = 0});

  final BetKind kind;
  final Set<int> numbers;

  /// Dozen / column number (0–2) — part of the identity for those bets.
  final int index;

  factory BetSpot.straight(int n) => BetSpot(BetKind.straight, {n}, index: n);
  factory BetSpot.split(int a, int b) => BetSpot(BetKind.split, {a, b}, index: math.min(a, b) * 100 + math.max(a, b));
  factory BetSpot.street(int row) => BetSpot(BetKind.street, {row * 3 + 1, row * 3 + 2, row * 3 + 3}, index: row);
  factory BetSpot.corner(int topLeft) =>
      BetSpot(BetKind.corner, {topLeft, topLeft + 1, topLeft + 3, topLeft + 4}, index: topLeft);
  static final redBet = BetSpot(BetKind.red, RouletteRules.red);
  static final blackBet = BetSpot(BetKind.black, {for (var n = 1; n <= 36; n++) if (!RouletteRules.isRed(n)) n});
  static final oddBet = BetSpot(BetKind.odd, {for (var n = 1; n <= 36; n += 2) n});
  static final evenBet = BetSpot(BetKind.even, {for (var n = 2; n <= 36; n += 2) n});
  static final lowBet = BetSpot(BetKind.low, {for (var n = 1; n <= 18; n++) n});
  static final highBet = BetSpot(BetKind.high, {for (var n = 19; n <= 36; n++) n});
  factory BetSpot.dozen(int d) => BetSpot(BetKind.dozen, {for (var n = d * 12 + 1; n <= d * 12 + 12; n++) n}, index: d);
  factory BetSpot.column(int c) => BetSpot(BetKind.column, {for (var n = c + 1; n <= 36; n += 3) n}, index: c);

  /// Winnings per unit staked (35:1, 17:1, …); the stake is returned too.
  int get payout => switch (kind) {
    BetKind.straight => 35,
    BetKind.split => 17,
    BetKind.street => 11,
    BetKind.corner => 8,
    BetKind.dozen || BetKind.column => 2,
    _ => 1,
  };

  bool wins(int result) => numbers.contains(result);

  @override
  bool operator ==(Object other) => other is BetSpot && other.kind == kind && other.index == index;

  @override
  int get hashCode => Object.hash(kind, index);
}

enum RoulettePhase { betting, spinning, result }

/// A practice roulette table: chips on spots, spin, settle.
class RouletteGame extends ChangeNotifier {
  RouletteGame({math.Random? rng, int? balance}) : _rng = rng ?? math.Random(), balance = balance ?? savedBalance;

  /// Practice balance kept for this app run (not real currency).
  static int savedBalance = 5000;
  static const startingBalance = 5000;
  static const maxTotalBet = 10000;

  final math.Random _rng;
  int balance;
  RoulettePhase phase = RoulettePhase.betting;

  /// Chips on the table this round (spot → amount).
  final Map<BetSpot, int> bets = {};

  /// Chips placed, in order (undo).
  final List<(BetSpot, int)> _history = [];

  /// The previous round's bets (Repeat).
  Map<BetSpot, int> _lastBets = {};

  /// Results, newest first.
  final List<int> results = [];
  int? result;

  /// What the last spin paid back (stake + winnings) and the winning spots.
  int lastReturn = 0;
  int lastStake = 0;
  Set<BetSpot> winningSpots = {};

  int get totalBet => bets.values.fold(0, (a, b) => a + b);
  bool get canRepeat => _lastBets.isNotEmpty && bets.isEmpty;

  void _setBalance(int v) {
    balance = v;
    savedBalance = v;
  }

  /// Put [amount] on [spot] (if the balance and table limit allow).
  bool place(BetSpot spot, int amount) {
    if (phase != RoulettePhase.betting) return false;
    if (amount > balance || totalBet + amount > maxTotalBet) return false;
    bets[spot] = (bets[spot] ?? 0) + amount;
    _history.add((spot, amount));
    _setBalance(balance - amount);
    notifyListeners();
    return true;
  }

  void undo() {
    if (phase != RoulettePhase.betting || _history.isEmpty) return;
    final (spot, amount) = _history.removeLast();
    final left = (bets[spot] ?? 0) - amount;
    left <= 0 ? bets.remove(spot) : bets[spot] = left;
    _setBalance(balance + amount);
    notifyListeners();
  }

  void clear() {
    if (phase != RoulettePhase.betting) return;
    _setBalance(balance + totalBet);
    bets.clear();
    _history.clear();
    notifyListeners();
  }

  /// Double every bet on the table.
  bool double() {
    if (phase != RoulettePhase.betting || bets.isEmpty) return false;
    final extra = totalBet;
    if (extra > balance || totalBet + extra > maxTotalBet) return false;
    for (final e in bets.entries.toList()) {
      bets[e.key] = e.value * 2;
      _history.add((e.key, e.value));
    }
    _setBalance(balance - extra);
    notifyListeners();
    return true;
  }

  /// Place last round's bets again.
  bool repeat() {
    if (!canRepeat) return false;
    final total = _lastBets.values.fold(0, (a, b) => a + b);
    if (total > balance) return false;
    for (final e in _lastBets.entries) {
      place(e.key, e.value);
    }
    return true;
  }

  /// Start the spin: the winning pocket is drawn now (uniform over 37);
  /// the screen animates the wheel to it and then calls [settle].
  int spin() {
    assert(phase == RoulettePhase.betting && bets.isNotEmpty);
    result = RouletteRules.wheel[_rng.nextInt(37)];
    phase = RoulettePhase.spinning;
    notifyListeners();
    return result!;
  }

  /// Pay out: winning spots return stake × (payout + 1).
  void settle() {
    final r = result!;
    winningSpots = {for (final s in bets.keys) if (s.wins(r)) s};
    lastStake = totalBet;
    lastReturn = 0;
    for (final s in winningSpots) {
      lastReturn += bets[s]! * (s.payout + 1);
    }
    _setBalance(balance + lastReturn);
    results.insert(0, r);
    if (results.length > 40) results.removeLast();
    phase = RoulettePhase.result;
    notifyListeners();
  }

  /// Clear the table for the next round (bets remembered for Repeat).
  void nextRound() {
    _lastBets = Map.of(bets);
    bets.clear();
    _history.clear();
    winningSpots = {};
    phase = RoulettePhase.betting;
    notifyListeners();
  }

  void refill() {
    _setBalance(startingBalance);
    notifyListeners();
  }
}
