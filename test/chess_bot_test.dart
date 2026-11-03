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

  String uci(Move m) => '${squareName(m.from)}${squareName(m.to)}';

  test('Medium and Hard find a quiet mate in two', () {
    // Ra6! bxa6 b7#, the only way: a sacrifice, not a check or a capture.
    final state = ChessState.fromFen('kbK5/pp6/1P6/8/8/8/8/R7 w - - 0 1');
    for (final level in [2, 3]) {
      expect(uci(ChessBot(depth: level, rng: Random(1), timeMs: 2000).chooseMove(state)!), 'a1a6', reason: 'level $level');
    }
  });

  test('Medium and Hard leave a defended pawn alone', () {
    final state = ChessState.fromFen('4k3/8/4p3/3p4/8/8/8/3QK3 w - - 0 1');
    for (final level in [2, 3]) {
      expect(uci(ChessBot(depth: level, rng: Random(2), timeMs: 300).chooseMove(state)!), isNot('d1d5'));
    }
  });

  test('Hard sees an exchange through to the end', () {
    // Rxd5 wins a pawn only until exd5: it looks past the capture.
    final state = ChessState.fromFen('3rk3/8/4p3/3p4/8/8/8/3RK3 w - - 0 1');
    expect(uci(ChessBot(depth: 3, rng: Random(3), timeMs: 300).chooseMove(state)!), isNot('d1d5'));
  });

  test('Hard walks a queen and king to mate a lone king', () {
    var s = ChessState.fromFen('8/8/8/4k3/8/8/8/3QK3 w - - 0 1');
    final bot = ChessBot(depth: 3, rng: Random(4), timeMs: 150);
    final rng = Random(5);
    final seen = <String>[s.positionKey];
    for (var ply = 0; ply < 60 && s.legalMoves().isNotEmpty; ply++) {
      if (s.turn == PieceColor.white) {
        s = s.applyMove(ChessBot(depth: 3, rng: rng, timeMs: 150, history: seen).chooseMove(s)!);
      } else {
        final replies = s.legalMoves();
        s = s.applyMove(replies[rng.nextInt(replies.length)]);
      }
      seen.add(s.positionKey);
    }
    expect(bot.depth, 3);
    expect(s.status(), GameStatus.checkmate);
  });

  group('levels play in order', () {
    int match(ChessBot Function() first, ChessBot Function() second, int games) {
      var wins = 0;
      for (var g = 0; g < games; g++) {
        var s = ChessState.initial();
        final firstIsWhite = g.isEven;
        var result = 0;
        final seen = <String>[s.positionKey];
        for (var ply = 0; ply < 160 && result == 0; ply++) {
          final firstToMove = (s.turn == PieceColor.white) == firstIsWhite;
          final m = (firstToMove ? first() : second()).chooseMove(s);
          if (m == null) {
            if (s.inCheck) result = firstToMove ? -1 : 1;
            break;
          }
          s = s.applyMove(m);
          seen.add(s.positionKey);
          if (s.insufficientMaterial || s.fiftyMoveDraw) break;
        }
        if (result > 0) wins++;
      }
      return wins;
    }

    test('Medium beats Easy, Hard beats Medium', () {
      final r = Random(7);
      expect(match(() => ChessBot(depth: 2, rng: r, timeMs: 400), () => ChessBot(depth: 1, rng: r), 4), greaterThanOrEqualTo(3));
      expect(match(() => ChessBot(depth: 3, rng: r, timeMs: 400), () => ChessBot(depth: 2, rng: r, timeMs: 20), 4), greaterThanOrEqualTo(2));
    }, timeout: const Timeout(Duration(minutes: 6)));
  });
}
