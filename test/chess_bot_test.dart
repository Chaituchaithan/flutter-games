import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/chess/chess_bot.dart';
import 'package:snakeladder/game/chess/chess_engine.dart';

void main() {
  test('bot returns a legal move from the opening position', () {
    final bot = ChessBot(depth: 2, rng: Random(1));
    final state = ChessState.initial();
    final m = bot.chooseMove(state);
    expect(m, isNotNull);
    expect(state.legalMoves().any((x) => x.from == m!.from && x.to == m.to), isTrue);
  });

  test('bot grabs a free hanging queen', () {
    // White queen on d5 can be captured by the black pawn on e6? No — set up a
    // clean free capture: black to move, white queen hangs on d5, black pawn e6.
    // FEN: black queen on d8 removed; simplest is a crafted position.
    // Position: black to move; white queen on e5 is attacked by black pawn d6.
    final state = ChessState.fromFen('4k3/8/3p4/4Q3/8/8/8/4K3 b - - 0 1');
    final bot = ChessBot(depth: 2, rng: Random(1));
    final m = bot.chooseMove(state)!;
    // d6xe5 captures the queen.
    expect(squareName(m.from), 'd6');
    expect(squareName(m.to), 'e5');
  });

  test('bot finds mate in one', () {
    // Black king h8, white queen g6, white king f6: Qg7# is mate. White to move.
    final state = ChessState.fromFen('7k/8/5KQ1/8/8/8/8/8 w - - 0 1');
    final bot = ChessBot(depth: 2, rng: Random(1));
    final m = bot.chooseMove(state)!;
    final after = state.applyMove(m);
    expect(after.status(), GameStatus.checkmate);
  });
}
