import 'dart:math';

import 'chess_engine.dart';

/// The chess AI for local "vs computer" play. [depth] picks the level:
///
/// * 1, Easy: looks one move ahead on material, so it's easy to out-plan.
/// * 2, Medium: looks 3 moves ahead, follows captures to the end and knows
///   about piece placement, pawns and king safety.
/// * 3, Hard: the same, searching deeper and deeper until [timeMs] runs out.
///
/// Medium and Hard are an iterative-deepening alpha-beta search with
/// quiescence, a transposition table and killer/history move ordering. Pure
/// Dart, no assets.
class ChessBot {
  ChessBot({this.depth = 2, Random? rng, this.timeMs = 3000, List<String> history = const []})
    : _rng = rng ?? Random(),
      _history = history {
    _salt = _rng.nextInt(1 << 30);
  }

  final int depth;

  /// Longest Medium and Hard may think about a move.
  final int timeMs;

  /// [ChessState.positionKey] of the positions played so far: walking back
  /// into one counts as a draw, so it won't throw away a won game repeating.
  final List<String> _history;
  final Random _rng;
  late final int _salt;

  static const int _inf = 1 << 30;
  static const int _mate = 1 << 20;
  static const int _mateFound = _mate - 200;
  static const int _maxPly = 48;
  static const int _quiesceDepth = 8;

  static const Map<PieceType, int> _value = {
    PieceType.pawn: 100,
    PieceType.knight: 320,
    PieceType.bishop: 330,
    PieceType.rook: 500,
    PieceType.queen: 900,
    PieceType.king: 0, // king safety handled via checkmate scoring
  };

  /// Best move for the side to move in [state], or null if none (game over).
  Move? chooseMove(ChessState state) {
    final moves = state.legalMoves();
    if (moves.isEmpty) return null;
    moves.shuffle(_rng); // vary between equally-scored moves
    if (moves.length == 1) return moves.first;
    return depth <= 1 ? _easyMove(state, moves) : _searchMove(state, moves);
  }

  // ── Easy ──

  Move _easyMove(ChessState state, List<Move> moves) {
    Move? best;
    var bestScore = -_inf;
    for (final m in moves) {
      final next = state.applyMove(m);
      final replies = next.legalMoves();
      final int score;
      if (replies.isEmpty) {
        score = next.inCheck ? _mate : 0;
      } else {
        score = -_easyEval(next, replies.length);
      }
      if (score > bestScore) {
        bestScore = score;
        best = m;
      }
    }
    return best ?? moves.first;
  }

  /// Material, a small centre bonus for knights/bishops/pawns, and mobility.
  int _easyEval(ChessState s, int myMobility) {
    var score = myMobility;
    for (var i = 0; i < 64; i++) {
      final p = s.board[i];
      if (p == null) continue;
      var v = _value[p.type]!;
      final minor = p.type == PieceType.knight || p.type == PieceType.bishop || p.type == PieceType.pawn;
      final file = fileOf(i), rank = rankOf(i);
      if (minor && file >= 2 && file <= 5 && rank >= 2 && rank <= 5) v += 10;
      score += p.color == s.turn ? v : -v;
    }
    return score;
  }

  // ── Medium and Hard: the search ──

  final Stopwatch _clock = Stopwatch();
  final Map<int, _Entry> _table = {};
  final Map<int, int> _seen = {}; // positions on the board and in this line
  final List<List<Move?>> _killers = List.generate(_maxPly + 2, (_) => [null, null]);
  final Map<int, int> _quietScore = {};

  Move _searchMove(ChessState state, List<Move> moves) {
    _clock.start();
    for (final key in _history) {
      final h = _hash(ChessState.fromFen('$key 0 1'));
      _seen[h] = (_seen[h] ?? 0) + 1;
    }
    final maxDepth = depth == 2 ? 3 : _maxPly - 8;
    final rootHash = _hash(state);
    var best = moves.first;
    try {
      for (var d = 1; d <= maxDepth; d++) {
        // Not worth starting a depth it can't finish.
        if (d > 1 && _clock.elapsedMilliseconds > timeMs * 0.55) break;
        final (move, score) = _searchRoot(state, moves, d, best, rootHash);
        best = move;
        if (score.abs() >= _mateFound) break;
      }
    } on _OutOfTime {
      // Keep the last move a finished (or partly searched) depth settled on.
      if (_partial != null) best = _partial!;
    }
    _clock.stop();
    return best;
  }

  Move? _partial;

  (Move, int) _searchRoot(ChessState state, List<Move> moves, int d, Move first, int rootHash) {
    moves.remove(first);
    moves.insert(0, first);
    var alpha = -_inf;
    Move? best;
    _partial = null;
    for (final m in moves) {
      final next = state.applyMove(m);
      final h = _hash(next);
      _enter(h);
      final int score;
      try {
        score = -_search(next, h, d - 1, -_inf, -alpha, 1);
      } finally {
        _leave(h);
      }
      if (score > alpha) {
        alpha = score;
        best = m;
        // A better move at a new depth is worth playing even if time runs out.
        _partial = m;
      }
    }
    return (best ?? first, alpha);
  }

  void _enter(int h) => _seen[h] = (_seen[h] ?? 0) + 1;
  void _leave(int h) {
    final n = _seen[h]! - 1;
    if (n == 0) {
      _seen.remove(h);
    } else {
      _seen[h] = n;
    }
  }

  void _checkTime() {
    if (_clock.elapsedMilliseconds >= timeMs) throw const _OutOfTime();
  }

  int _search(ChessState s, int hash, int depthLeft, int alpha, int beta, int ply) {
    _checkTime();
    if ((_seen[hash] ?? 0) > 1 || s.halfmoveClock >= 100 || s.insufficientMaterial) return 0;
    final inCheck = s.inCheck;
    if (inCheck && ply < _maxPly) depthLeft++; // never stop the search on a check
    if (depthLeft <= 0 || ply >= _maxPly) return _quiesce(s, alpha, beta, ply, _quiesceDepth);

    final alpha0 = alpha;
    final entry = _table[hash];
    if (entry != null && entry.depth >= depthLeft) {
      final v = _fromTable(entry.score, ply);
      if (entry.bound == _Bound.exact) return v;
      if (entry.bound == _Bound.lower && v >= beta) return v;
      if (entry.bound == _Bound.upper && v <= alpha) return v;
    }

    final moves = s.legalMoves();
    if (moves.isEmpty) return inCheck ? -_mate + ply : 0;
    _order(s, moves, entry?.move, ply);

    var value = -_inf;
    Move? best;
    for (var i = 0; i < moves.length; i++) {
      final m = moves[i];
      final next = s.applyMove(m);
      final h = _hash(next);
      final quiet = !_isCapture(s, m) && m.promotion == null;
      _enter(h);
      int score;
      try {
        // Late quiet moves are unlikely: look at them less, and properly only
        // if they surprise.
        if (i >= 4 && depthLeft >= 3 && quiet && !inCheck && !next.inCheck) {
          score = -_search(next, h, depthLeft - 2, -alpha - 1, -alpha, ply + 1);
          if (score > alpha) score = -_search(next, h, depthLeft - 1, -beta, -alpha, ply + 1);
        } else {
          score = -_search(next, h, depthLeft - 1, -beta, -alpha, ply + 1);
        }
      } finally {
        _leave(h);
      }
      if (score > value) {
        value = score;
        best = m;
      }
      if (value > alpha) alpha = value;
      if (alpha >= beta) {
        if (quiet) {
          final k = _killers[ply];
          if (k[0] != m) {
            k[1] = k[0];
            k[0] = m;
          }
          final key = m.from * 64 + m.to;
          _quietScore[key] = (_quietScore[key] ?? 0) + depthLeft * depthLeft;
        }
        break;
      }
    }
    if (_table.length > 400000) _table.clear();
    _table[hash] = _Entry(
      depthLeft,
      _toTable(value, ply),
      value <= alpha0 ? _Bound.upper : (value >= beta ? _Bound.lower : _Bound.exact),
      best,
    );
    return value;
  }

  /// Follow the captures until the position is quiet, so a search never stops
  /// halfway through an exchange. In check, every reply is looked at.
  int _quiesce(ChessState s, int alpha, int beta, int ply, int left) {
    _checkTime();
    final inCheck = s.inCheck;
    if (!inCheck) {
      final stand = _evaluate(s);
      if (left <= 0 || stand >= beta) return stand;
      if (stand > alpha) alpha = stand;
    } else if (left <= 0) {
      return _evaluate(s);
    }
    final all = s.legalMoves();
    if (all.isEmpty) return inCheck ? -_mate + ply : 0;
    final stand = inCheck ? -_inf : alpha;
    final moves = inCheck ? all : all.where((m) => _isCapture(s, m) || m.promotion != null).toList();
    moves.sort((a, b) => _captureScore(s, b) - _captureScore(s, a));
    var value = stand;
    for (final m in moves) {
      final score = -_quiesce(s.applyMove(m), -beta, -alpha, ply + 1, left - 1);
      if (score > value) value = score;
      if (value > alpha) alpha = value;
      if (alpha >= beta) break;
    }
    return value;
  }

  static bool _isCapture(ChessState s, Move m) => s.board[m.to] != null || m.isEnPassant;

  /// Most valuable victim first, taken by the least valuable attacker.
  static int _captureScore(ChessState s, Move m) {
    var score = 0;
    if (_isCapture(s, m)) {
      final victim = s.board[m.to]?.type ?? PieceType.pawn;
      score = _value[victim]! * 10 - _value[s.board[m.from]!.type]! + 1000;
    }
    if (m.promotion != null) score += _value[m.promotion]! * 10;
    return score;
  }

  void _order(ChessState s, List<Move> moves, Move? tableMove, int ply) {
    final k = _killers[ply];
    int rank(Move m) {
      if (m == tableMove) return 1 << 28;
      final c = _captureScore(s, m);
      if (c > 0) return (1 << 20) + c;
      if (m == k[0]) return (1 << 19) + 1;
      if (m == k[1]) return 1 << 19;
      return _quietScore[m.from * 64 + m.to] ?? 0;
    }

    final ranks = {for (final m in moves) m: rank(m)};
    moves.sort((a, b) => ranks[b]! - ranks[a]!);
  }

  // A mate's score counts from the root, the table's from this position.
  static int _toTable(int v, int ply) => v >= _mateFound ? v + ply : (v <= -_mateFound ? v - ply : v);
  static int _fromTable(int v, int ply) => v >= _mateFound ? v - ply : (v <= -_mateFound ? v + ply : v);

  // ── Position hash ──

  static final List<int> _keys = () {
    final r = Random(20261102);
    return List.generate(12 * 64 + 1 + 4 + 8, (_) => (r.nextInt(1 << 30) << 22) ^ r.nextInt(1 << 30));
  }();

  static int _hash(ChessState s) {
    var h = 0;
    for (var i = 0; i < 64; i++) {
      final p = s.board[i];
      if (p != null) h ^= _keys[(p.type.index * 2 + p.color.index) * 64 + i];
    }
    if (s.turn == PieceColor.black) h ^= _keys[12 * 64];
    const rights = ['K', 'Q', 'k', 'q'];
    for (var i = 0; i < 4; i++) {
      if (s.castling.contains(rights[i])) h ^= _keys[12 * 64 + 1 + i];
    }
    if (s.enPassant != null) h ^= _keys[12 * 64 + 5 + fileOf(s.enPassant!)];
    return h;
  }

  // ── Evaluation ──

  // Piece-square tables, drawn from White's side (first row = rank 8).
  static const List<int> _pawnTable = [
    0, 0, 0, 0, 0, 0, 0, 0,
    50, 50, 50, 50, 50, 50, 50, 50,
    10, 10, 20, 30, 30, 20, 10, 10,
    5, 5, 10, 25, 25, 10, 5, 5,
    0, 0, 0, 20, 20, 0, 0, 0,
    5, -5, -10, 0, 0, -10, -5, 5,
    5, 10, 10, -20, -20, 10, 10, 5,
    0, 0, 0, 0, 0, 0, 0, 0,
  ];
  static const List<int> _knightTable = [
    -50, -40, -30, -30, -30, -30, -40, -50,
    -40, -20, 0, 0, 0, 0, -20, -40,
    -30, 0, 10, 15, 15, 10, 0, -30,
    -30, 5, 15, 20, 20, 15, 5, -30,
    -30, 0, 15, 20, 20, 15, 0, -30,
    -30, 5, 10, 15, 15, 10, 5, -30,
    -40, -20, 0, 5, 5, 0, -20, -40,
    -50, -40, -30, -30, -30, -30, -40, -50,
  ];
  static const List<int> _bishopTable = [
    -20, -10, -10, -10, -10, -10, -10, -20,
    -10, 0, 0, 0, 0, 0, 0, -10,
    -10, 0, 5, 10, 10, 5, 0, -10,
    -10, 5, 5, 10, 10, 5, 5, -10,
    -10, 0, 10, 10, 10, 10, 0, -10,
    -10, 10, 10, 10, 10, 10, 10, -10,
    -10, 5, 0, 0, 0, 0, 5, -10,
    -20, -10, -10, -10, -10, -10, -10, -20,
  ];
  static const List<int> _rookTable = [
    0, 0, 0, 0, 0, 0, 0, 0,
    5, 10, 10, 10, 10, 10, 10, 5,
    -5, 0, 0, 0, 0, 0, 0, -5,
    -5, 0, 0, 0, 0, 0, 0, -5,
    -5, 0, 0, 0, 0, 0, 0, -5,
    -5, 0, 0, 0, 0, 0, 0, -5,
    -5, 0, 0, 0, 0, 0, 0, -5,
    0, 0, 0, 5, 5, 0, 0, 0,
  ];
  static const List<int> _queenTable = [
    -20, -10, -10, -5, -5, -10, -10, -20,
    -10, 0, 0, 0, 0, 0, 0, -10,
    -10, 0, 5, 5, 5, 5, 0, -10,
    -5, 0, 5, 5, 5, 5, 0, -5,
    0, 0, 5, 5, 5, 5, 0, -5,
    -10, 5, 5, 5, 5, 5, 0, -10,
    -10, 0, 5, 0, 0, 0, 0, -10,
    -20, -10, -10, -5, -5, -10, -10, -20,
  ];
  static const List<int> _kingMiddle = [
    -30, -40, -40, -50, -50, -40, -40, -30,
    -30, -40, -40, -50, -50, -40, -40, -30,
    -30, -40, -40, -50, -50, -40, -40, -30,
    -30, -40, -40, -50, -50, -40, -40, -30,
    -20, -30, -30, -40, -40, -30, -30, -20,
    -10, -20, -20, -20, -20, -20, -20, -10,
    20, 20, 0, 0, 0, 0, 20, 20,
    20, 30, 10, 0, 0, 10, 30, 20,
  ];
  static const List<int> _kingEnd = [
    -50, -40, -30, -20, -20, -30, -40, -50,
    -30, -20, -10, 0, 0, -10, -20, -30,
    -30, -10, 20, 30, 30, 20, -10, -30,
    -30, -10, 30, 40, 40, 30, -10, -30,
    -30, -10, 30, 40, 40, 30, -10, -30,
    -30, -10, 20, 30, 30, 20, -10, -30,
    -30, -30, 0, 0, 0, 0, -30, -30,
    -50, -30, -30, -30, -30, -30, -30, -50,
  ];
  static const List<int> _passedBonus = [0, 5, 10, 20, 35, 60, 90, 0];

  /// Score from the side-to-move's point of view: material, placement, pawn
  /// structure, bishops and rooks, king safety, and driving a lone king to
  /// the edge in the endgame.
  int _evaluate(ChessState s) {
    final board = s.board;
    final pawnsOn = [List.filled(8, 0), List.filled(8, 0)];
    final bishops = [0, 0];
    final kings = [0, 0];
    final material = [0, 0];
    var phase = 0;
    var middle = 0, end = 0;
    final rooks = <int>[];
    for (var i = 0; i < 64; i++) {
      final p = board[i];
      if (p == null) continue;
      final c = p.color.index;
      final sign = c == 0 ? 1 : -1;
      final t = (c == 0 ? 7 - rankOf(i) : rankOf(i)) * 8 + fileOf(i);
      final v = _value[p.type]!;
      material[c] += v;
      switch (p.type) {
        case PieceType.pawn:
          pawnsOn[c][fileOf(i)]++;
          middle += sign * (v + _pawnTable[t]);
          end += sign * (v + _pawnTable[t]);
        case PieceType.knight:
          phase += 1;
          middle += sign * (v + _knightTable[t]);
          end += sign * (v + _knightTable[t]);
        case PieceType.bishop:
          phase += 1;
          bishops[c]++;
          middle += sign * (v + _bishopTable[t]);
          end += sign * (v + _bishopTable[t]);
        case PieceType.rook:
          phase += 2;
          rooks.add(i);
          middle += sign * (v + _rookTable[t]);
          end += sign * (v + _rookTable[t]);
        case PieceType.queen:
          phase += 4;
          middle += sign * (v + _queenTable[t]);
          end += sign * (v + _queenTable[t]);
        case PieceType.king:
          kings[c] = i;
          middle += sign * _kingMiddle[t];
          end += sign * _kingEnd[t];
      }
    }
    var both = 0;
    if (bishops[0] >= 2) both += 30;
    if (bishops[1] >= 2) both -= 30;
    // Rooks like open files.
    for (final i in rooks) {
      final c = board[i]!.color.index;
      final sign = c == 0 ? 1 : -1;
      final f = fileOf(i);
      if (pawnsOn[c][f] == 0) both += sign * (pawnsOn[1 - c][f] == 0 ? 20 : 10);
    }
    // Pawns: doubled and isolated are weak, passed ones grow as they advance.
    for (var i = 0; i < 64; i++) {
      final p = board[i];
      if (p == null || p.type != PieceType.pawn) continue;
      final c = p.color.index;
      final sign = c == 0 ? 1 : -1;
      final f = fileOf(i), r = rankOf(i);
      final mine = pawnsOn[c];
      if (mine[f] > 1) both -= sign * 8;
      if ((f == 0 || mine[f - 1] == 0) && (f == 7 || mine[f + 1] == 0)) both -= sign * 12;
      if (_isPassed(board, p.color, f, r)) {
        final bonus = _passedBonus[c == 0 ? r : 7 - r];
        middle += sign * bonus;
        end += sign * bonus * 2;
      }
    }
    // King safety: pawns in front of the king, and no open files beside it.
    for (final c in const [0, 1]) {
      final sign = c == 0 ? 1 : -1;
      final kf = fileOf(kings[c]), kr = rankOf(kings[c]);
      final ahead = kr + (c == 0 ? 1 : -1);
      var shield = 0;
      for (var f = max(0, kf - 1); f <= min(7, kf + 1); f++) {
        if (ahead >= 0 && ahead <= 7) {
          final p = board[squareOf(f, ahead)];
          if (p != null && p.type == PieceType.pawn && p.color.index == c) shield++;
        }
        if (pawnsOn[c][f] == 0) middle -= sign * 15;
      }
      middle += sign * (shield * 12 - 18);
    }
    // Winning endgame: walk the kings together, push the other to the edge.
    final lead = material[0] - material[1];
    if (lead.abs() >= 300 && phase <= 8) {
      final strong = lead > 0 ? 0 : 1;
      final weakKing = kings[1 - strong], strongKing = kings[strong];
      double fromCentre(int v) => (v - 3.5).abs();
      final edge = fromCentre(fileOf(weakKing)) + fromCentre(rankOf(weakKing));
      final apart = (fileOf(weakKing) - fileOf(strongKing)).abs() + (rankOf(weakKing) - rankOf(strongKing)).abs();
      both += (strong == 0 ? 1 : -1) * (edge * 10 + (14 - apart) * 4).round();
    }
    final weight = min(phase, 24);
    var score = both + (middle * weight + end * (24 - weight)) ~/ 24;
    if (s.turn == PieceColor.black) score = -score;
    // A touch of variety in the opening, so no two games are the same.
    if (s.fullmoveNumber <= 6) score += ((_hash(s) ^ _salt) & 15) - 8;
    return score + 10;
  }

  static bool _isPassed(List<Piece?> board, PieceColor color, int file, int rank) {
    final step = color == PieceColor.white ? 1 : -1;
    for (var f = max(0, file - 1); f <= min(7, file + 1); f++) {
      for (var r = rank + step; r >= 0 && r <= 7; r += step) {
        final p = board[squareOf(f, r)];
        if (p != null && p.type == PieceType.pawn && p.color != color) return false;
      }
    }
    return true;
  }
}

enum _Bound { exact, lower, upper }

class _Entry {
  const _Entry(this.depth, this.score, this.bound, this.move);
  final int depth, score;
  final _Bound bound;
  final Move? move;
}

class _OutOfTime implements Exception {
  const _OutOfTime();
}
