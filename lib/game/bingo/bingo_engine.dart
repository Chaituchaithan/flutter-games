import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Winning patterns.
enum BingoPattern { line, corners, fullHouse }

/// 75-ball bingo: column letter of a number.
String bingoLetter(int n) => 'BINGO'[(n - 1) ~/ 15];

/// A 5×5 card: B 1–15, I 16–30, N 31–45 (centre FREE = 0), G 46–60,
/// O 61–75. Cells are indexed row × 5 + col.
@immutable
class BingoCard {
  const BingoCard(this.cells);
  final List<int> cells;

  static const free = 12;

  factory BingoCard.random(math.Random rng) {
    final cols = [
      for (var c = 0; c < 5; c++) (List.generate(15, (i) => c * 15 + i + 1)..shuffle(rng)).take(5).toList(),
    ];
    return BingoCard([
      for (var r = 0; r < 5; r++)
        for (var c = 0; c < 5; c++) r * 5 + c == free ? 0 : cols[c][r],
    ]);
  }

  int indexOf(int number) => cells.indexOf(number);
}

/// The cell groups that win [p] (any one complete group wins).
List<List<int>> patternGroups(BingoPattern p) => switch (p) {
  BingoPattern.line => [
    for (var r = 0; r < 5; r++) [for (var c = 0; c < 5; c++) r * 5 + c],
    for (var c = 0; c < 5; c++) [for (var r = 0; r < 5; r++) r * 5 + c],
    [0, 6, 12, 18, 24],
    [4, 8, 12, 16, 20],
  ],
  BingoPattern.corners => [
    [0, 4, 20, 24],
  ],
  BingoPattern.fullHouse => [List.generate(25, (i) => i)],
};

/// Fewest unmarked cells left to complete [p] (0 = bingo).
int cellsNeeded(Set<int> marked, BingoPattern p) =>
    patternGroups(p).map((g) => g.where((i) => !marked.contains(i)).length).reduce(math.min);

/// The completed group for [p] (the winning cells), or null.
List<int>? winningGroup(Set<int> marked, BingoPattern p) {
  for (final g in patternGroups(p)) {
    if (g.every(marked.contains)) return g;
  }
  return null;
}

/// Cells that would each complete a group on their own ("1 to go").
Set<int> oneToGo(Set<int> marked, BingoPattern p) => {
  for (final g in patternGroups(p))
    if (g.where((i) => !marked.contains(i)).length == 1) g.firstWhere((i) => !marked.contains(i)),
};

/// One seat: the card and what's daubed (the FREE centre always is).
class BingoSeat {
  BingoSeat(this.card) : marked = {BingoCard.free};
  final BingoCard card;
  final Set<int> marked;

  int needed(BingoPattern p) => cellsNeeded(marked, p);
}

/// A game: the caller, the seats (0 = you), daubing and claims. The first
/// valid claim wins; a false claim locks that player's claims briefly.
class BingoGame extends ChangeNotifier {
  BingoGame({required int players, required this.pattern, math.Random? rng}) : _rng = rng ?? math.Random() {
    _balls = List.generate(75, (i) => i + 1)..shuffle(_rng);
    seats = [for (var i = 0; i < players; i++) BingoSeat(BingoCard.random(_rng))];
  }

  final math.Random _rng;
  final BingoPattern pattern;
  late final List<int> _balls;
  late final List<BingoSeat> seats;

  /// Numbers called so far, oldest first.
  final List<int> called = [];
  int? winner;

  /// The final number when the bag ran out with no winner.
  bool get exhausted => called.length >= 75;
  bool get over => winner != null || exhausted;
  int? get current => called.isEmpty ? null : called.last;

  /// Call the next ball.
  int? callNext() {
    if (over) return null;
    final n = _balls[called.length];
    called.add(n);
    notifyListeners();
    return n;
  }

  /// Daub [cell] on [seat]'s card — only numbers already called.
  bool daub(int seat, int cell) {
    final s = seats[seat];
    final n = s.card.cells[cell];
    if (over || n == 0 || !called.contains(n) || s.marked.contains(cell)) return false;
    s.marked.add(cell);
    notifyListeners();
    return true;
  }

  /// Daub every called number on [seat] (auto-daub / computer players).
  void daubAll(int seat) {
    final s = seats[seat];
    var changed = false;
    for (var i = 0; i < 25; i++) {
      final n = s.card.cells[i];
      if (n != 0 && called.contains(n) && s.marked.add(i)) changed = true;
    }
    if (changed) notifyListeners();
  }

  /// [seat] calls "Bingo!": wins when their daubs complete the pattern.
  bool claim(int seat) {
    if (over) return false;
    if (seats[seat].needed(pattern) != 0) return false;
    winner = seat;
    notifyListeners();
    return true;
  }
}
