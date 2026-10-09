import 'package:flutter/foundation.dart';

import 'chess_engine.dart';

/// Drives a single chess game: holds the live [ChessState], the current
/// selection + legal targets, the last move (for highlighting), and a simple
/// move history. UI-agnostic so it can be fed either by local taps (hot-seat)
/// or by the socket layer later.
class ChessController extends ChangeNotifier {
  ChessController({ChessState? initial, PieceColor? localColor})
      : _state = initial ?? ChessState.initial() {
    _localColor = localColor;
  }

  ChessState _state;
  ChessState get state => _state;

  /// When set, the player may only move pieces of this colour (multiplayer).
  /// Null = hot-seat (both sides tappable). Settable because the colour is only
  /// known once the server sends `game.started`.
  PieceColor? _localColor;
  PieceColor? get localColor => _localColor;
  set localColor(PieceColor? c) {
    _localColor = c;
    notifyListeners();
  }

  int? _selected;
  int? get selected => _selected;

  List<Move> _targets = const [];
  List<Move> get targets => _targets;

  Move? _lastMove;
  Move? get lastMove => _lastMove;

  final List<String> _sanHistory = [];
  List<String> get history => List.unmodifiable(_sanHistory);

  /// Side that made the most recent move, or null before the first move.
  PieceColor? get lastMover => _sanHistory.isEmpty ? null : _state.turn.opposite;

  /// Opponent pieces [c] has captured (16 minus the opponent's pieces left;
  /// promotions don't change the count).
  int capturesBy(PieceColor c) => 16 - _state.board.where((p) => p != null && p.color != c).length;

  /// Mockup "LAST MOVE" text: `"<name> played e4"`, `" · capture"` appended on
  /// a capture; `"Match started · Chess"` before any move.
  String lastMoveText(String Function(PieceColor) nameOf) {
    final mover = lastMover;
    if (mover == null) return 'Match started · Chess';
    final san = _sanHistory.last;
    return '${nameOf(mover)} played $san${san.contains('x') ? ' · capture' : ''}';
  }

  /// Invoked when the LOCAL player commits a move (not external) — the online
  /// session hooks this to send `game.action` to the server.
  void Function(Move move)? onLocalMove;

  GameStatus get status => _state.status();
  bool get isOver => status == GameStatus.checkmate || status == GameStatus.stalemate || status == GameStatus.draw;

  /// The king square to flag when in check (null otherwise).
  int? get checkedKing => _state.inCheck ? _state.kingSquare(_state.turn) : null;

  bool _canControl(PieceColor color) => localColor == null || localColor == color;

  /// Tap handling: select a piece, or move the selected piece to [sq].
  /// Returns a pending promotion move if the UI must ask which piece to promote
  /// to; otherwise applies immediately and returns null.
  Move? onTapSquare(int sq) {
    if (isOver) return null;
    final piece = _state.pieceAt(sq);

    // Second tap on a legal target → move.
    if (_selected != null) {
      final matching = _targets.where((m) => m.to == sq).toList();
      if (matching.isNotEmpty) {
        // Promotion needs a choice (several moves share from/to).
        if (matching.length > 1 && matching.every((m) => m.promotion != null)) {
          return matching.first; // UI shows the promotion picker
        }
        _commit(matching.first);
        return null;
      }
    }

    // Select one of our own pieces whose side it is to move.
    if (piece != null && piece.color == _state.turn && _canControl(piece.color)) {
      _selected = sq;
      _targets = _state.legalMovesFrom(sq);
    } else {
      _selected = null;
      _targets = const [];
    }
    notifyListeners();
    return null;
  }

  /// Apply a promotion the UI resolved (user picked a piece type).
  void promote(Move base, PieceType type) {
    _commit(Move(from: base.from, to: base.to, promotion: type));
  }

  /// Apply an opponent/bot move given only its coordinates (from the socket's
  /// `last_action`). Reconstructs the full legal move — so castling, en passant
  /// and promotion flags are correct — keeping the engine in sync. Returns false
  /// if the coordinates don't match a legal move (desync).
  bool applyExternalCoords(int from, int to, {PieceType? promotion}) {
    final candidates = _state.legalMovesFrom(from).where((m) => m.to == to).toList();
    if (candidates.isEmpty) return false;
    final chosen = promotion != null
        ? candidates.firstWhere((m) => m.promotion == promotion, orElse: () => candidates.first)
        : candidates.first;
    _commit(chosen, external: true);
    return true;
  }

  void _commit(Move move, {bool external = false}) {
    _sanHistory.add(_describe(move));
    _state = _state.applyMove(move);
    _lastMove = move;
    _selected = null;
    _targets = const [];
    notifyListeners();
    if (!external) onLocalMove?.call(move);
  }

  /// Minimal human-readable move text (not full SAN, but enough for a log).
  String _describe(Move m) {
    final p = _state.pieceAt(m.from);
    const letter = {
      PieceType.pawn: '',
      PieceType.knight: 'N',
      PieceType.bishop: 'B',
      PieceType.rook: 'R',
      PieceType.queen: 'Q',
      PieceType.king: 'K',
    };
    if (m.isCastle) return fileOf(m.to) == 6 ? 'O-O' : 'O-O-O';
    final capture = _state.pieceAt(m.to) != null || m.isEnPassant;
    final promo = m.promotion != null ? '=${letter[m.promotion]}' : '';
    // A pawn capture names the pawn's starting file (exd5), per SAN.
    final pawnFile = p?.type == PieceType.pawn && capture ? squareName(m.from)[0] : '';
    return '${letter[p?.type] ?? ''}$pawnFile${capture ? 'x' : ''}${squareName(m.to)}$promo';
  }

  void reset() {
    _state = ChessState.initial();
    _selected = null;
    _targets = const [];
    _lastMove = null;
    _sanHistory.clear();
    notifyListeners();
  }
}
