import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/chess/chess_controller.dart';
import 'package:snakeladder/game/chess/chess_engine.dart';

void main() {
  group('ChessEngine', () {
    test('initial position has 20 legal moves', () {
      final s = ChessState.initial();
      expect(s.legalMoves().length, 20);
      expect(s.turn, PieceColor.white);
      expect(s.status(), GameStatus.ongoing);
    });

    test('FEN round-trips', () {
      const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      expect(ChessState.fromFen(fen).toFen(), fen);
    });

    test('e4 produces an en-passant target and flips the turn', () {
      final s = ChessState.initial();
      final e2 = squareFromName('e2')!, e4 = squareFromName('e4')!;
      final next = s.applyMove(Move(from: e2, to: e4));
      expect(next.turn, PieceColor.black);
      expect(next.enPassant, squareFromName('e3'));
      expect(next.pieceAt(e4)?.type, PieceType.pawn);
      expect(next.pieceAt(e2), isNull);
    });

    test("Fool's mate is detected as checkmate", () {
      var s = ChessState.initial();
      // 1. f3 e5 2. g4 Qh4#
      s = s.applyMove(Move(from: squareFromName('f2')!, to: squareFromName('f3')!));
      s = s.applyMove(Move(from: squareFromName('e7')!, to: squareFromName('e5')!));
      s = s.applyMove(Move(from: squareFromName('g2')!, to: squareFromName('g4')!));
      s = s.applyMove(Move(from: squareFromName('d8')!, to: squareFromName('h4')!));
      expect(s.inCheck, isTrue);
      expect(s.status(), GameStatus.checkmate);
      expect(s.legalMoves(), isEmpty);
    });

    test('stalemate is detected (not checkmate)', () {
      // Classic K+Q vs K stalemate: black king a8, white queen c7, white king...
      // Black to move, not in check, no legal moves.
      final s = ChessState.fromFen('k7/2Q5/1K6/8/8/8/8/8 b - - 0 1');
      expect(s.inCheck, isFalse);
      expect(s.status(), GameStatus.stalemate);
    });

    test('white king-side castling is legal from a clear position', () {
      final s = ChessState.fromFen('r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1');
      final e1 = squareFromName('e1')!;
      final castles = s.legalMovesFrom(e1).where((m) => m.isCastle).toList();
      expect(castles.length, 2); // both sides available
      final next = s.applyMove(castles.firstWhere((m) => fileOf(m.to) == 6));
      expect(next.pieceAt(squareFromName('g1')!)?.type, PieceType.king);
      expect(next.pieceAt(squareFromName('f1')!)?.type, PieceType.rook);
    });

    test('a pinned piece cannot expose the king', () {
      // White king e1, white bishop e2, black rook e8 → bishop is pinned.
      final s = ChessState.fromFen('4r3/8/8/8/8/8/4B3/4K3 w - - 0 1');
      final bishop = squareFromName('e2')!;
      // The bishop has no legal move that leaves the e-file (all expose the king).
      expect(s.legalMovesFrom(bishop), isEmpty);
    });

    test('promotion to queen on the last rank', () {
      final s = ChessState.fromFen('8/P7/8/8/8/8/8/k6K w - - 0 1');
      final a7 = squareFromName('a7')!, a8 = squareFromName('a8')!;
      final promos = s.legalMovesFrom(a7);
      expect(promos.map((m) => m.promotion).whereType<PieceType>().toSet(),
          {PieceType.queen, PieceType.rook, PieceType.bishop, PieceType.knight});
      final next = s.applyMove(Move(from: a7, to: a8, promotion: PieceType.queen));
      expect(next.pieceAt(a8), const Piece(PieceColor.white, PieceType.queen));
    });
  });

  group('draw rules', () {
    test('insufficient material', () {
      bool draw(String fen) => ChessState.fromFen(fen).insufficientMaterial;
      expect(draw('8/8/8/4k3/8/8/8/4K3 w - - 0 1'), isTrue, reason: 'bare kings');
      expect(draw('8/8/8/4k3/8/8/8/2N1K3 w - - 0 1'), isTrue, reason: 'lone knight');
      expect(draw('8/8/8/4k3/8/8/8/2B1K3 w - - 0 1'), isTrue, reason: 'lone bishop');
      expect(draw('5b2/8/8/4k3/8/8/8/2B1K3 w - - 0 1'), isFalse, reason: 'f8 and c1: opposite colours');
      expect(draw('2b5/8/8/4k3/8/8/8/2B1K3 w - - 0 1'), isTrue, reason: 'c8 and c1: same colour');
      expect(draw('8/8/8/4k3/8/8/4P3/4K3 w - - 0 1'), isFalse, reason: 'a pawn can promote');
      expect(draw('8/8/8/4k3/8/8/8/1NN1K3 w - - 0 1'), isFalse);
    });

    test('fifty moves come from the halfmove clock', () {
      expect(ChessState.fromFen('8/8/8/4k3/8/8/4R3/4K3 w - - 99 80').fiftyMoveDraw, isFalse);
      expect(ChessState.fromFen('8/8/8/4k3/8/8/4R3/4K3 w - - 100 80').fiftyMoveDraw, isTrue);
    });

    group('controller', () {
      void shuffle(ChessController c) {
        int sq(String n) => squareFromName(n)!;
        c.applyExternalCoords(sq('g1'), sq('f3'));
        c.applyExternalCoords(sq('g8'), sq('f6'));
        c.applyExternalCoords(sq('f3'), sq('g1'));
        c.applyExternalCoords(sq('f6'), sq('g8'));
      }

      test('three repeats draw, undo takes it back', () {
        final c = ChessController(drawRules: true, undoEnabled: true);
        shuffle(c);
        expect(c.status, GameStatus.ongoing, reason: 'twice is not enough');
        shuffle(c);
        expect(c.status, GameStatus.draw);
        expect(c.isOver, isTrue);
        expect(c.drawReason, contains('three times'));
        c.undo();
        expect(c.status, GameStatus.ongoing);
      });

      test('online games leave draws to the server', () {
        final c = ChessController();
        shuffle(c);
        shuffle(c);
        expect(c.status, GameStatus.ongoing);
        final bare = ChessController(initial: ChessState.fromFen('8/8/8/4k3/8/8/8/4K3 w - - 0 1'));
        expect(bare.drawReason, isNull);
      });

      test('bare kings end at once; checkmate beats the fifty-move rule', () {
        final bare = ChessController(drawRules: true, initial: ChessState.fromFen('8/8/8/4k3/8/8/8/4K3 w - - 0 1'));
        expect(bare.status, GameStatus.draw);
        final mate = ChessController(drawRules: true, initial: ChessState.fromFen('7k/6Q1/5K2/8/8/8/8/8 b - - 100 80'));
        expect(mate.status, GameStatus.checkmate);
      });
    });
  });
}
