import 'dart:math';

import 'chess_engine.dart';

/// A lightweight chess AI for local "vs computer" play. Negamax search with
/// alpha-beta pruning over the rules engine, using material + a small
/// mobility/centre bonus. [depth] maps to difficulty (future level selection):
/// 1 ≈ Easy, 2 ≈ Medium, 3 ≈ Hard. Pure Dart, no assets, deterministic given a
/// seeded [Random].
class ChessBot {
  ChessBot({this.depth = 2, Random? rng}) : _rng = rng ?? Random();

  final int depth;
  final Random _rng;

  static const int _inf = 1 << 30;
  static const int _mate = 1 << 20;

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
    Move? best;
    var bestScore = -_inf;
    var alpha = -_inf;
    const beta = _inf;
    for (final m in moves) {
      final score = -_negamax(state.applyMove(m), depth - 1, -beta, -alpha);
      if (score > bestScore) {
        bestScore = score;
        best = m;
      }
      if (score > alpha) alpha = score;
    }
    return best ?? moves.first;
  }

  int _negamax(ChessState s, int depth, int alpha, int beta) {
    final moves = s.legalMoves();
    if (moves.isEmpty) {
      // No legal moves: checkmate (side to move loses) or stalemate (draw).
      return s.inCheck ? -_mate - depth : 0;
    }
    if (depth == 0) return _evaluate(s, moves.length);
    var value = -_inf;
    for (final m in moves) {
      final score = -_negamax(s.applyMove(m), depth - 1, -beta, -alpha);
      if (score > value) value = score;
      if (value > alpha) alpha = value;
      if (alpha >= beta) break; // prune
    }
    return value;
  }

  /// Material balance from the side-to-move's perspective, plus a small bonus
  /// for mobility and central occupation.
  int _evaluate(ChessState s, int myMobility) {
    var score = 0;
    for (var i = 0; i < 64; i++) {
      final p = s.board[i];
      if (p == null) continue;
      var v = _value[p.type]!;
      // Small centre bonus for knights/bishops/pawns.
      final file = fileOf(i), rank = rankOf(i);
      final central = (file >= 2 && file <= 5 && rank >= 2 && rank <= 5) ? 10 : 0;
      v += central;
      score += (p.color == s.turn) ? v : -v;
    }
    score += myMobility; // ~1 centipawn per legal move for the side to move
    return score;
  }
}
