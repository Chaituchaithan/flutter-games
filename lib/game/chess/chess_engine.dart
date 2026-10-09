/// A self-contained chess rules engine (pure Dart, no Flutter deps).
///
/// Generates fully legal moves (including castling, en passant and promotion),
/// detects check / checkmate / stalemate, applies moves immutably, and can
/// import/export FEN so game state can be synced over the socket later.
///
/// Board indexing: squares are 0..63 where `index = rank * 8 + file`,
/// file 0 = a-file, rank 0 = rank 1 (white's home rank). So a1 = 0, h1 = 7,
/// a8 = 56, h8 = 63.
library;

enum PieceColor { white, black }

extension PieceColorX on PieceColor {
  PieceColor get opposite => this == PieceColor.white ? PieceColor.black : PieceColor.white;
}

enum PieceType { pawn, knight, bishop, rook, queen, king }

class Piece {
  const Piece(this.color, this.type);
  final PieceColor color;
  final PieceType type;

  /// FEN letter (upper = white, lower = black).
  String get fenChar {
    const map = {
      PieceType.pawn: 'p',
      PieceType.knight: 'n',
      PieceType.bishop: 'b',
      PieceType.rook: 'r',
      PieceType.queen: 'q',
      PieceType.king: 'k',
    };
    final c = map[type]!;
    return color == PieceColor.white ? c.toUpperCase() : c;
  }

  static Piece fromFenChar(String ch) {
    final color = ch == ch.toUpperCase() ? PieceColor.white : PieceColor.black;
    const map = {
      'p': PieceType.pawn,
      'n': PieceType.knight,
      'b': PieceType.bishop,
      'r': PieceType.rook,
      'q': PieceType.queen,
      'k': PieceType.king,
    };
    return Piece(color, map[ch.toLowerCase()]!);
  }

  @override
  bool operator ==(Object other) => other is Piece && other.color == color && other.type == type;
  @override
  int get hashCode => Object.hash(color, type);
}

/// Square helpers (file 0..7, rank 0..7).
int fileOf(int sq) => sq % 8;
int rankOf(int sq) => sq ~/ 8;
int squareOf(int file, int rank) => rank * 8 + file;
bool onBoard(int file, int rank) => file >= 0 && file < 8 && rank >= 0 && rank < 8;

/// Algebraic coordinate like "e4".
String squareName(int sq) => '${String.fromCharCode(97 + fileOf(sq))}${rankOf(sq) + 1}';

int? squareFromName(String name) {
  if (name.length != 2) return null;
  final file = name.codeUnitAt(0) - 97;
  final rank = name.codeUnitAt(1) - 49;
  if (!onBoard(file, rank)) return null;
  return squareOf(file, rank);
}

class Move {
  const Move({
    required this.from,
    required this.to,
    this.promotion,
    this.isEnPassant = false,
    this.isCastle = false,
  });

  final int from;
  final int to;

  /// Promotion target type (queen/rook/bishop/knight) when a pawn reaches the
  /// last rank; null otherwise.
  final PieceType? promotion;
  final bool isEnPassant;
  final bool isCastle;

  /// UCI-style string, e.g. "e2e4" or "e7e8q" — the move format the server
  /// will most likely expect for `game.action`.
  String get uci {
    final base = '${squareName(from)}${squareName(to)}';
    if (promotion == null) return base;
    const m = {PieceType.queen: 'q', PieceType.rook: 'r', PieceType.bishop: 'b', PieceType.knight: 'n'};
    return '$base${m[promotion]}';
  }

  @override
  bool operator ==(Object other) =>
      other is Move && other.from == from && other.to == to && other.promotion == promotion;
  @override
  int get hashCode => Object.hash(from, to, promotion);
}

enum GameStatus { ongoing, check, checkmate, stalemate, draw }

/// Immutable chess position. Use [applyMove] to get the next state.
class ChessState {
  ChessState({
    required this.board,
    required this.turn,
    required this.castling,
    required this.enPassant,
    required this.halfmoveClock,
    required this.fullmoveNumber,
  });

  /// 64 squares, index = rank*8+file; null = empty.
  final List<Piece?> board;
  final PieceColor turn;

  /// Castling availability: {'K','Q','k','q'} present when allowed.
  final Set<String> castling;

  /// En-passant target square (the square behind a pawn that just moved two),
  /// or null.
  final int? enPassant;
  final int halfmoveClock;
  final int fullmoveNumber;

  Piece? pieceAt(int sq) => board[sq];

  /// Standard starting position.
  factory ChessState.initial() => ChessState.fromFen(
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      );

  factory ChessState.fromFen(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    final rows = parts[0].split('/'); // rank 8 first
    final board = List<Piece?>.filled(64, null);
    for (var r = 0; r < 8; r++) {
      final rank = 7 - r; // rows[0] is rank 8
      var file = 0;
      for (final ch in rows[r].split('')) {
        final n = int.tryParse(ch);
        if (n != null) {
          file += n;
        } else {
          board[squareOf(file, rank)] = Piece.fromFenChar(ch);
          file++;
        }
      }
    }
    final turn = (parts.length > 1 && parts[1] == 'b') ? PieceColor.black : PieceColor.white;
    final castling = <String>{};
    if (parts.length > 2 && parts[2] != '-') {
      for (final c in parts[2].split('')) {
        castling.add(c);
      }
    }
    final ep = (parts.length > 3 && parts[3] != '-') ? squareFromName(parts[3]) : null;
    final half = parts.length > 4 ? int.tryParse(parts[4]) ?? 0 : 0;
    final full = parts.length > 5 ? int.tryParse(parts[5]) ?? 1 : 1;
    return ChessState(
      board: board,
      turn: turn,
      castling: castling,
      enPassant: ep,
      halfmoveClock: half,
      fullmoveNumber: full,
    );
  }

  String toFen() {
    final sb = StringBuffer();
    for (var rank = 7; rank >= 0; rank--) {
      var empty = 0;
      for (var file = 0; file < 8; file++) {
        final p = board[squareOf(file, rank)];
        if (p == null) {
          empty++;
        } else {
          if (empty > 0) {
            sb.write(empty);
            empty = 0;
          }
          sb.write(p.fenChar);
        }
      }
      if (empty > 0) sb.write(empty);
      if (rank > 0) sb.write('/');
    }
    sb.write(' ${turn == PieceColor.white ? 'w' : 'b'} ');
    final cast = ['K', 'Q', 'k', 'q'].where(castling.contains).join();
    sb.write(cast.isEmpty ? '-' : cast);
    sb.write(' ${enPassant == null ? '-' : squareName(enPassant!)}');
    sb.write(' $halfmoveClock $fullmoveNumber');
    return sb.toString();
  }

  /// Find the king square for [color].
  int kingSquare(PieceColor color) {
    for (var i = 0; i < 64; i++) {
      final p = board[i];
      if (p != null && p.type == PieceType.king && p.color == color) return i;
    }
    return -1;
  }

  /// Is [sq] attacked by any [byColor] piece? (Used for check + castling.)
  bool isAttacked(int sq, PieceColor byColor) {
    final f = fileOf(sq), r = rankOf(sq);

    // Pawn attacks: a byColor pawn attacks diagonally "forward".
    final dir = byColor == PieceColor.white ? 1 : -1;
    for (final df in [-1, 1]) {
      final pf = f + df, pr = r - dir;
      if (onBoard(pf, pr)) {
        final p = board[squareOf(pf, pr)];
        if (p != null && p.color == byColor && p.type == PieceType.pawn) return true;
      }
    }
    // Knight.
    for (final d in _knightDeltas) {
      final nf = f + d[0], nr = r + d[1];
      if (onBoard(nf, nr)) {
        final p = board[squareOf(nf, nr)];
        if (p != null && p.color == byColor && p.type == PieceType.knight) return true;
      }
    }
    // King (adjacent).
    for (final d in _kingDeltas) {
      final nf = f + d[0], nr = r + d[1];
      if (onBoard(nf, nr)) {
        final p = board[squareOf(nf, nr)];
        if (p != null && p.color == byColor && p.type == PieceType.king) return true;
      }
    }
    // Sliding: bishops/queens on diagonals, rooks/queens on files/ranks.
    for (final d in _bishopDeltas) {
      if (_slideHits(f, r, d, byColor, {PieceType.bishop, PieceType.queen})) return true;
    }
    for (final d in _rookDeltas) {
      if (_slideHits(f, r, d, byColor, {PieceType.rook, PieceType.queen})) return true;
    }
    return false;
  }

  bool _slideHits(int f, int r, List<int> d, PieceColor byColor, Set<PieceType> types) {
    var nf = f + d[0], nr = r + d[1];
    while (onBoard(nf, nr)) {
      final p = board[squareOf(nf, nr)];
      if (p != null) {
        return p.color == byColor && types.contains(p.type);
      }
      nf += d[0];
      nr += d[1];
    }
    return false;
  }

  bool get inCheck => isAttacked(kingSquare(turn), turn.opposite);

  /// All fully-legal moves for the side to move.
  List<Move> legalMoves() {
    final moves = <Move>[];
    for (final m in _pseudoLegalMoves()) {
      final next = _applyRaw(m);
      // The move is legal iff it doesn't leave our own king in check.
      if (!next.isAttacked(next.kingSquare(turn), turn.opposite)) {
        moves.add(m);
      }
    }
    return moves;
  }

  /// Legal moves originating from [from].
  List<Move> legalMovesFrom(int from) => legalMoves().where((m) => m.from == from).toList();

  GameStatus status() {
    final hasMoves = legalMoves().isNotEmpty;
    if (hasMoves) return inCheck ? GameStatus.check : GameStatus.ongoing;
    return inCheck ? GameStatus.checkmate : GameStatus.stalemate;
  }

  /// Apply a legal [move], returning the next state. Promotion defaults to
  /// queen if the move reaches the last rank without a promotion set.
  ChessState applyMove(Move move) {
    var m = move;
    final mover = board[move.from];
    if (mover != null && mover.type == PieceType.pawn) {
      final lastRank = mover.color == PieceColor.white ? 7 : 0;
      if (rankOf(move.to) == lastRank && move.promotion == null) {
        m = Move(from: move.from, to: move.to, promotion: PieceType.queen, isEnPassant: move.isEnPassant, isCastle: move.isCastle);
      }
    }
    return _applyRaw(m);
  }

  // ── Internals ──

  ChessState _applyRaw(Move m) {
    final b = List<Piece?>.of(board);
    final mover = b[m.from]!;
    final isPawn = mover.type == PieceType.pawn;
    final isCapture = b[m.to] != null || m.isEnPassant;

    b[m.to] = m.promotion != null ? Piece(mover.color, m.promotion!) : mover;
    b[m.from] = null;

    // En passant: remove the captured pawn (behind the target square).
    if (m.isEnPassant) {
      final capRank = mover.color == PieceColor.white ? rankOf(m.to) - 1 : rankOf(m.to) + 1;
      b[squareOf(fileOf(m.to), capRank)] = null;
    }

    // Castling: move the rook too.
    if (m.isCastle) {
      final rank = rankOf(m.from);
      if (fileOf(m.to) == 6) {
        // King-side: rook h→f.
        b[squareOf(5, rank)] = b[squareOf(7, rank)];
        b[squareOf(7, rank)] = null;
      } else {
        // Queen-side: rook a→d.
        b[squareOf(3, rank)] = b[squareOf(0, rank)];
        b[squareOf(0, rank)] = null;
      }
    }

    // Update castling rights.
    final castle = Set<String>.of(castling);
    void removeIfMovedOrCaptured(int sq) {
      // If a rook's home square is vacated or captured, drop that right.
      if (sq == squareOf(0, 0)) castle.remove('Q');
      if (sq == squareOf(7, 0)) castle.remove('K');
      if (sq == squareOf(0, 7)) castle.remove('q');
      if (sq == squareOf(7, 7)) castle.remove('k');
    }

    if (mover.type == PieceType.king) {
      if (mover.color == PieceColor.white) {
        castle.removeAll(['K', 'Q']);
      } else {
        castle.removeAll(['k', 'q']);
      }
    }
    removeIfMovedOrCaptured(m.from);
    removeIfMovedOrCaptured(m.to);

    // En-passant target for the next move (only on a double pawn push).
    int? ep;
    if (isPawn && (rankOf(m.to) - rankOf(m.from)).abs() == 2) {
      ep = squareOf(fileOf(m.from), (rankOf(m.from) + rankOf(m.to)) ~/ 2);
    }

    return ChessState(
      board: b,
      turn: turn.opposite,
      castling: castle,
      enPassant: ep,
      halfmoveClock: (isPawn || isCapture) ? 0 : halfmoveClock + 1,
      fullmoveNumber: turn == PieceColor.black ? fullmoveNumber + 1 : fullmoveNumber,
    );
  }

  List<Move> _pseudoLegalMoves() {
    final moves = <Move>[];
    for (var sq = 0; sq < 64; sq++) {
      final p = board[sq];
      if (p == null || p.color != turn) continue;
      switch (p.type) {
        case PieceType.pawn:
          _pawnMoves(sq, p, moves);
        case PieceType.knight:
          _stepMoves(sq, p, _knightDeltas, moves);
        case PieceType.king:
          _stepMoves(sq, p, _kingDeltas, moves);
          _castleMoves(sq, p, moves);
        case PieceType.bishop:
          _slideMoves(sq, p, _bishopDeltas, moves);
        case PieceType.rook:
          _slideMoves(sq, p, _rookDeltas, moves);
        case PieceType.queen:
          _slideMoves(sq, p, _bishopDeltas, moves);
          _slideMoves(sq, p, _rookDeltas, moves);
      }
    }
    return moves;
  }

  void _pawnMoves(int sq, Piece p, List<Move> out) {
    final f = fileOf(sq), r = rankOf(sq);
    final dir = p.color == PieceColor.white ? 1 : -1;
    final startRank = p.color == PieceColor.white ? 1 : 6;
    final lastRank = p.color == PieceColor.white ? 7 : 0;

    void addMaybePromote(int from, int to, {bool ep = false}) {
      if (rankOf(to) == lastRank) {
        for (final promo in [PieceType.queen, PieceType.rook, PieceType.bishop, PieceType.knight]) {
          out.add(Move(from: from, to: to, promotion: promo));
        }
      } else {
        out.add(Move(from: from, to: to, isEnPassant: ep));
      }
    }

    // Forward one.
    final oneR = r + dir;
    if (onBoard(f, oneR) && board[squareOf(f, oneR)] == null) {
      addMaybePromote(sq, squareOf(f, oneR));
      // Forward two from the start rank.
      final twoR = r + 2 * dir;
      if (r == startRank && board[squareOf(f, twoR)] == null) {
        out.add(Move(from: sq, to: squareOf(f, twoR)));
      }
    }
    // Captures (incl. en passant).
    for (final df in [-1, 1]) {
      final cf = f + df, cr = r + dir;
      if (!onBoard(cf, cr)) continue;
      final target = squareOf(cf, cr);
      final tp = board[target];
      if (tp != null && tp.color != p.color) {
        addMaybePromote(sq, target);
      } else if (tp == null && enPassant == target) {
        addMaybePromote(sq, target, ep: true);
      }
    }
  }

  void _stepMoves(int sq, Piece p, List<List<int>> deltas, List<Move> out) {
    final f = fileOf(sq), r = rankOf(sq);
    for (final d in deltas) {
      final nf = f + d[0], nr = r + d[1];
      if (!onBoard(nf, nr)) continue;
      final t = board[squareOf(nf, nr)];
      if (t == null || t.color != p.color) {
        out.add(Move(from: sq, to: squareOf(nf, nr)));
      }
    }
  }

  void _slideMoves(int sq, Piece p, List<List<int>> deltas, List<Move> out) {
    final f = fileOf(sq), r = rankOf(sq);
    for (final d in deltas) {
      var nf = f + d[0], nr = r + d[1];
      while (onBoard(nf, nr)) {
        final target = squareOf(nf, nr);
        final t = board[target];
        if (t == null) {
          out.add(Move(from: sq, to: target));
        } else {
          if (t.color != p.color) out.add(Move(from: sq, to: target));
          break;
        }
        nf += d[0];
        nr += d[1];
      }
    }
  }

  void _castleMoves(int sq, Piece king, List<Move> out) {
    // Can't castle out of, through, or into check.
    if (isAttacked(sq, king.color.opposite)) return;
    final rank = rankOf(sq);
    final home = king.color == PieceColor.white ? 0 : 7;
    if (rank != home || fileOf(sq) != 4) return;
    final kSide = king.color == PieceColor.white ? 'K' : 'k';
    final qSide = king.color == PieceColor.white ? 'Q' : 'q';

    // King-side: f & g empty, e/f/g not attacked, rook on h.
    if (castling.contains(kSide) &&
        board[squareOf(5, rank)] == null &&
        board[squareOf(6, rank)] == null &&
        !isAttacked(squareOf(5, rank), king.color.opposite) &&
        !isAttacked(squareOf(6, rank), king.color.opposite) &&
        _isRook(squareOf(7, rank), king.color)) {
      out.add(Move(from: sq, to: squareOf(6, rank), isCastle: true));
    }
    // Queen-side: b/c/d empty, e/d/c not attacked, rook on a.
    if (castling.contains(qSide) &&
        board[squareOf(1, rank)] == null &&
        board[squareOf(2, rank)] == null &&
        board[squareOf(3, rank)] == null &&
        !isAttacked(squareOf(3, rank), king.color.opposite) &&
        !isAttacked(squareOf(2, rank), king.color.opposite) &&
        _isRook(squareOf(0, rank), king.color)) {
      out.add(Move(from: sq, to: squareOf(2, rank), isCastle: true));
    }
  }

  bool _isRook(int sq, PieceColor color) {
    final p = board[sq];
    return p != null && p.type == PieceType.rook && p.color == color;
  }

  static const _knightDeltas = [
    [1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2],
  ];
  static const _kingDeltas = [
    [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1],
  ];
  static const _bishopDeltas = [
    [1, 1], [1, -1], [-1, 1], [-1, -1],
  ];
  static const _rookDeltas = [
    [1, 0], [-1, 0], [0, 1], [0, -1],
  ];
}
