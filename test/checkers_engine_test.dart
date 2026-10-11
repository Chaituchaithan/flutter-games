import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/checkers/checkers_engine.dart';

void main() {
  test('opening: 12 pieces each, Dark has 7 moves', () {
    final s = CheckersState.initial();
    expect(s.countOf(CheckerSide.dark), 12);
    expect(s.countOf(CheckerSide.light), 12);
    expect(s.turn, CheckerSide.dark);
    expect(s.legalMoves().length, 7);
  });

  test('capture is compulsory and multi-jumps are completed', () {
    final b = List<Checker?>.filled(64, null);
    b[7 * 8 + 0] = const Checker(CheckerSide.dark); // a man at row 7 col 0
    b[6 * 8 + 1] = const Checker(CheckerSide.light); // jumpable
    b[4 * 8 + 3] = const Checker(CheckerSide.light); // second jump
    b[7 * 8 + 6] = const Checker(CheckerSide.dark); // has a quiet move too
    final s = CheckersState(b, CheckerSide.dark);
    final moves = s.legalMoves();
    expect(moves.length, 1, reason: 'only the capture is legal');
    expect(moves.single.captures.length, 2, reason: 'double jump');
    expect(moves.single.path, [56, 42, 28]);
    final n = s.play(moves.single);
    expect(n.countOf(CheckerSide.light), 0);
    expect(n.isOver, isTrue);
    expect(n.winner, CheckerSide.dark);
  });

  test('reaching the far row crowns a king', () {
    final b = List<Checker?>.filled(64, null);
    b[1 * 8 + 2] = const Checker(CheckerSide.dark);
    b[7 * 8 + 0] = const Checker(CheckerSide.light);
    final s = CheckersState(b, CheckerSide.dark);
    final n = s.play(const CheckerMove([10, 1]));
    expect(n.board[1]!.king, isTrue);
  });

  test('computer vs computer games always end', () {
    for (final depth in [2, 4]) {
      var s = CheckersState.initial();
      final bot = CheckersBot(depth: depth);
      var guard = 0;
      while (!s.isOver && guard++ < 400) {
        s = s.play(bot.chooseMove(s)!);
      }
      expect(s.isOver, isTrue, reason: 'depth $depth');
    }
  });
}
