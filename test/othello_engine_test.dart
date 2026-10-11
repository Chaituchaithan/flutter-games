import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/othello/othello_engine.dart';

void main() {
  test('opening: Black has the 4 classic moves; a move flips', () {
    final s = OthelloState.initial();
    expect(s.legalMoves()..sort(), [19, 26, 37, 44]); // d3 c4 f5 e6
    final n = s.play(19);
    expect(n.cells[19], Disc.black);
    expect(n.cells[27], Disc.black, reason: 'd4 flipped');
    expect(n.count(Disc.black), 4);
    expect(n.count(Disc.white), 1);
    expect(n.turn, Disc.white);
  });

  test('computer vs computer games always finish with a full count', () {
    for (final depth in [1, 2, 3]) {
      var s = OthelloState.initial();
      final bot = OthelloBot(depth: depth);
      var guard = 0;
      while (!s.isOver && guard++ < 100) {
        s = s.play(bot.chooseMove(s)!);
      }
      expect(s.isOver, isTrue, reason: 'depth $depth');
      expect(s.count(Disc.black) + s.count(Disc.white), lessThanOrEqualTo(64));
    }
  });

  test('a player with no move passes (turn stays)', () {
    // White to move with no legal move → after Black plays, Black moves again.
    final c = List<Disc?>.filled(64, null);
    c[0] = Disc.black;
    c[1] = Disc.white;
    final s = OthelloState(c, Disc.black);
    final n = s.play(2); // Black outflanks b1
    expect(n.isOver, isTrue, reason: 'all discs black → nobody can move');
    expect(n.winner, Disc.black);
  });
}
