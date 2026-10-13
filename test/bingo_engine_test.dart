import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/bingo/bingo_engine.dart';

void main() {
  test('cards: right ranges per column, unique, free centre', () {
    final card = BingoCard.random(math.Random(1));
    expect(card.cells[BingoCard.free], 0);
    for (var i = 0; i < 25; i++) {
      if (i == BingoCard.free) continue;
      final col = i % 5;
      expect(card.cells[i], inInclusiveRange(col * 15 + 1, col * 15 + 15));
    }
    expect(card.cells.where((n) => n != 0).toSet().length, 24);
  });

  test('pattern progress and completion', () {
    final marked = {12};
    expect(cellsNeeded(marked, BingoPattern.line), 4, reason: 'a line through the free centre');
    marked.addAll([10, 11, 13]);
    expect(cellsNeeded(marked, BingoPattern.line), 1);
    marked.add(14);
    expect(cellsNeeded(marked, BingoPattern.line), 0);
    expect(cellsNeeded({0, 4, 20, 24}, BingoPattern.corners), 0);
    expect(cellsNeeded({12}, BingoPattern.fullHouse), 24);
  });

  test('only called numbers can be daubed; false claims fail; a full game finds a winner', () {
    final g = BingoGame(players: 3, pattern: BingoPattern.line, rng: math.Random(5));
    final first = g.seats[0].card.cells[0];
    expect(g.daub(0, 0), first == 0 ? false : g.called.contains(first));
    expect(g.claim(0), isFalse, reason: 'nothing complete yet');
    while (!g.over) {
      g.callNext();
      for (var s = 0; s < 3; s++) {
        g.daubAll(s);
        if (g.seats[s].needed(g.pattern) == 0 && g.claim(s)) break;
      }
    }
    expect(g.winner, isNotNull);
    expect(g.called.length, lessThan(75));
  });

  test('winning group and "1 to go" cells', () {
    final marked = {12, 10, 11, 13}; // row 2 minus cell 14
    expect(winningGroup(marked, BingoPattern.line), isNull);
    expect(oneToGo(marked, BingoPattern.line), contains(14));
    marked.add(14);
    expect(winningGroup(marked, BingoPattern.line), [10, 11, 12, 13, 14]);
    expect(oneToGo({0, 4, 20}, BingoPattern.corners), {24});
  });
}
