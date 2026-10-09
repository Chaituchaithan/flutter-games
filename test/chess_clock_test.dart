import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/chess/chess_clock.dart';
import 'package:snakeladder/game/chess/chess_controller.dart';
import 'package:snakeladder/game/chess/chess_engine.dart';

// ChessClock reads wall time (DateTime.now), so these use short real waits.
Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('per-move clock resets for the next mover after each move', () async {
    final game = ChessController();
    // Generous margins: the clock reads wall time, and the full suite runs
    // tests in parallel, so ticks can be late under load.
    final clock = ChessClock(game, initialMs: 5000, perMove: true);
    await _wait(900);
    expect(clock.msFor(PieceColor.white), lessThan(4800));

    game.applyExternalCoords(squareFromName('e2')!, squareFromName('e4')!);
    await _wait(250);
    // Black starts its move with (almost) the full allowance, not White's
    // leftover budget.
    expect(clock.msFor(PieceColor.black), greaterThan(4400));
    clock.dispose();
  });

  test('per-move clock flags the mover who exceeds the limit', () async {
    PieceColor? flagged;
    final game = ChessController();
    final clock = ChessClock(game, initialMs: 500, perMove: true, onFlag: (c) => flagged = c);
    await _wait(900);
    expect(flagged, PieceColor.white);
    clock.dispose();
  });

  test('game clock (default) keeps a running budget across moves', () async {
    final game = ChessController();
    final clock = ChessClock(game, initialMs: 1500);
    await _wait(500);
    game.applyExternalCoords(squareFromName('e2')!, squareFromName('e4')!);
    game.applyExternalCoords(squareFromName('e7')!, squareFromName('e5')!);
    await _wait(250);
    // White's earlier spend is NOT refunded in game-clock mode.
    expect(clock.msFor(PieceColor.white), lessThan(1200));
    clock.dispose();
  });

  test('lastMoveText names the mover and flags captures; capturesBy counts', () {
    final game = ChessController();
    String name(PieceColor c) => c == PieceColor.white ? 'You' : 'Computer';
    expect(game.lastMoveText(name), 'Match started · Chess');

    game.applyExternalCoords(squareFromName('e2')!, squareFromName('e4')!);
    expect(game.lastMoveText(name), 'You played e4');
    game.applyExternalCoords(squareFromName('d7')!, squareFromName('d5')!);
    expect(game.lastMoveText(name), 'Computer played d5');
    game.applyExternalCoords(squareFromName('e4')!, squareFromName('d5')!);
    expect(game.lastMoveText(name), 'You played exd5 · capture');
    expect(game.capturesBy(PieceColor.white), 1);
    expect(game.capturesBy(PieceColor.black), 0);
  });

  test('hand-over buffer holds the new mover\'s clock after a move', () async {
    final game = ChessController();
    final clock = ChessClock(game, initialMs: 3000, perMove: true, handoverMs: 600);
    await _wait(250);
    game.applyExternalCoords(squareFromName('e2')!, squareFromName('e4')!);
    await _wait(450); // inside the 600ms buffer
    expect(clock.msFor(PieceColor.black), 3000);
    await _wait(700); // buffer over → counting down
    expect(clock.msFor(PieceColor.black), lessThan(3000));
    clock.dispose();
  });
}
