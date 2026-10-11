import 'package:flutter/foundation.dart';

/// Othello disc colours. Black moves first.
enum Disc { black, white }

extension DiscX on Disc {
  Disc get other => this == Disc.black ? Disc.white : Disc.black;
}

/// Othello (Reversi) rules on an 8×8 board, squares 0..63 (row × 8 + col,
/// row 0 at the top):
/// - start with four discs in the centre, Black to move;
/// - a move must outflank at least one line of opponent discs, which flip;
/// - a player with no legal move passes; when neither can move the game ends
///   and the most discs wins.
@immutable
class OthelloState {
  const OthelloState(this.cells, this.turn);

  /// null = empty.
  final List<Disc?> cells;
  final Disc turn;

  factory OthelloState.initial() {
    final c = List<Disc?>.filled(64, null);
    c[27] = Disc.white;
    c[28] = Disc.black;
    c[35] = Disc.black;
    c[36] = Disc.white;
    return OthelloState(c, Disc.black);
  }

  static const _dirs = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)];

  /// Discs [who] would flip by playing [sq] (empty = illegal).
  List<int> flipsFor(int sq, Disc who) {
    if (cells[sq] != null) return const [];
    final out = <int>[];
    final r0 = sq ~/ 8, c0 = sq % 8;
    for (final (dr, dc) in _dirs) {
      final line = <int>[];
      var r = r0 + dr, c = c0 + dc;
      while (r >= 0 && r < 8 && c >= 0 && c < 8) {
        final d = cells[r * 8 + c];
        if (d == null) break;
        if (d == who) {
          out.addAll(line);
          break;
        }
        line.add(r * 8 + c);
        r += dr;
        c += dc;
      }
    }
    return out;
  }

  List<int> legalMoves([Disc? who]) {
    final w = who ?? turn;
    return [
      for (var i = 0; i < 64; i++)
        if (cells[i] == null && flipsFor(i, w).isNotEmpty) i,
    ];
  }

  /// Place at [sq] for the player to move, flip, and hand over the turn (the
  /// opponent passes automatically when they have no move).
  OthelloState play(int sq) {
    final flips = flipsFor(sq, turn);
    assert(flips.isNotEmpty, 'illegal move');
    final c = List<Disc?>.of(cells);
    c[sq] = turn;
    for (final f in flips) {
      c[f] = turn;
    }
    final next = OthelloState(c, turn.other);
    return next.legalMoves().isEmpty ? OthelloState(c, turn) : next;
  }

  int count(Disc d) => cells.where((x) => x == d).length;

  /// Neither side can move.
  bool get isOver => legalMoves(Disc.black).isEmpty && legalMoves(Disc.white).isEmpty;

  /// Winner once over (null = draw / not over).
  Disc? get winner {
    if (!isOver) return null;
    final b = count(Disc.black), w = count(Disc.white);
    return b == w ? null : (b > w ? Disc.black : Disc.white);
  }
}

/// Computer player: alpha-beta search over a positional + mobility
/// evaluation. [depth] 1 (easy) … 4 (hard).
class OthelloBot {
  const OthelloBot({required this.depth});
  final int depth;

  /// Corner-heavy square weights (the classic table).
  static const _w = [
    100,
    -20,
    10,
    5,
    5,
    10,
    -20,
    100,
    -20,
    -50,
    -2,
    -2,
    -2,
    -2,
    -50,
    -20,
    10,
    -2,
    -1,
    -1,
    -1,
    -1,
    -2,
    10,
    5,
    -2,
    -1,
    -1,
    -1,
    -1,
    -2,
    5,
    5,
    -2,
    -1,
    -1,
    -1,
    -1,
    -2,
    5,
    10,
    -2,
    -1,
    -1,
    -1,
    -1,
    -2,
    10,
    -20,
    -50,
    -2,
    -2,
    -2,
    -2,
    -50,
    -20,
    100,
    -20,
    10,
    5,
    5,
    10,
    -20,
    100,
  ];

  int? chooseMove(OthelloState s) {
    final moves = s.legalMoves();
    if (moves.isEmpty) return null;
    final me = s.turn;
    var best = moves.first;
    var bestScore = -1 << 30;
    for (final m in moves) {
      final v = _search(s.play(m), depth - 1, -1 << 30, 1 << 30, me);
      if (v > bestScore) {
        bestScore = v;
        best = m;
      }
    }
    return best;
  }

  int _search(OthelloState s, int d, int alpha, int beta, Disc me) {
    if (d <= 0 || s.isOver) return _eval(s, me);
    final moves = s.legalMoves();
    final maximizing = s.turn == me;
    var a = alpha, b = beta;
    if (maximizing) {
      var v = -1 << 30;
      for (final m in moves) {
        final r = _search(s.play(m), d - 1, a, b, me);
        if (r > v) v = r;
        if (v > a) a = v;
        if (a >= b) break;
      }
      return v;
    }
    var v = 1 << 30;
    for (final m in moves) {
      final r = _search(s.play(m), d - 1, a, b, me);
      if (r < v) v = r;
      if (v < b) b = v;
      if (a >= b) break;
    }
    return v;
  }

  int _eval(OthelloState s, Disc me) {
    if (s.isOver) {
      final diff = s.count(me) - s.count(me.other);
      return diff > 0 ? 100000 + diff : (diff < 0 ? -100000 + diff : 0);
    }
    var pos = 0;
    for (var i = 0; i < 64; i++) {
      final d = s.cells[i];
      if (d == me) pos += _w[i];
      if (d == me.other) pos -= _w[i];
    }
    final mobility = s.legalMoves(me).length - s.legalMoves(me.other).length;
    return pos + 5 * mobility;
  }
}

/// Game controller for the screen: the state, the last move, flips to
/// animate, and passes.
class OthelloGame extends ChangeNotifier {
  OthelloState state = OthelloState.initial();

  /// Last placed square and what it flipped (drives the flip animation).
  int? lastMove;
  List<int> lastFlips = const [];
  int moveCount = 0;

  /// Set when the side to move had to pass on the previous turn.
  Disc? passed;

  void play(int sq) {
    final mover = state.turn;
    lastFlips = state.flipsFor(sq, mover);
    lastMove = sq;
    final next = state.play(sq);
    // The same player moves again → the opponent passed.
    passed = (!next.isOver && next.turn == mover) ? mover.other : null;
    state = next;
    moveCount++;
    notifyListeners();
  }

  void reset() {
    state = OthelloState.initial();
    lastMove = null;
    lastFlips = const [];
    moveCount = 0;
    passed = null;
    notifyListeners();
  }
}

/// "d3"-style name of a square.
String othelloSquareName(int sq) => '${String.fromCharCode(97 + sq % 8)}${sq ~/ 8 + 1}';
