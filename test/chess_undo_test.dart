import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/chess/chess_controller.dart';
import 'package:snakeladder/game/chess/chess_engine.dart';

void main() {
  void move(ChessController c, String from, String to) {
    int sq(String n) => squareOf(n.codeUnitAt(0) - 97, int.parse(n[1]) - 1);
    expect(c.applyExternalCoords(sq(from), sq(to)), isTrue);
  }

  test('undo takes back moves: position, turn, history and last move', () {
    final c = ChessController(undoEnabled: true);
    move(c, 'e2', 'e4');
    final afterE4 = c.lastMove;
    move(c, 'e7', 'e5');
    move(c, 'g1', 'f3');
    expect(c.undoable, 3);

    expect(c.undo(2), 2);
    expect(c.history, ['e4']);
    expect(c.state.turn, PieceColor.black);
    expect(identical(c.lastMove, afterE4), isTrue);
    expect(c.state.pieceAt(squareOf(4, 6))?.type, PieceType.pawn, reason: 'e7 pawn is back');
    expect(c.state.pieceAt(squareOf(6, 0))?.type, PieceType.knight, reason: 'g1 knight is back');

    expect(c.undo(5), 1, reason: 'only one move left to take back');
    expect(c.history, isEmpty);
    expect(c.lastMove, isNull);
    expect(c.undo(), 0);
  });

  test('a capture taken back restores the captured piece', () {
    final c = ChessController(undoEnabled: true);
    move(c, 'e2', 'e4');
    move(c, 'd7', 'd5');
    move(c, 'e4', 'd5');
    expect(c.capturesBy(PieceColor.white), 1);
    c.undo();
    expect(c.capturesBy(PieceColor.white), 0);
    expect(c.state.pieceAt(squareOf(3, 4))?.color, PieceColor.black);
  });

  test('undo bumps undoSerial (the board jumps instead of animating)', () {
    final c = ChessController(undoEnabled: true);
    move(c, 'e2', 'e4');
    final before = c.undoSerial;
    c.undo();
    expect(c.undoSerial, before + 1);
  });

  test('undo is off unless asked for: an online game keeps no history to desync', () {
    final c = ChessController();
    move(c, 'e2', 'e4');
    expect(c.undoable, 0);
    expect(c.undo(), 0);
    expect(c.history, ['e4']);
  });
}
