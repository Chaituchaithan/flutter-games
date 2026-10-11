import 'package:flutter/foundation.dart';

/// Checkers sides. Dark moves first (English / American draughts).
enum CheckerSide { dark, light }

extension CheckerSideX on CheckerSide {
  CheckerSide get other => this == CheckerSide.dark ? CheckerSide.light : CheckerSide.dark;

  /// Row direction a man moves: dark starts at the bottom and moves up.
  int get forward => this == CheckerSide.dark ? -1 : 1;
}

@immutable
class Checker {
  const Checker(this.side, {this.king = false});
  final CheckerSide side;
  final bool king;
}

/// One move: the squares visited ([path].first = start) and the opponent
/// squares jumped (in order).
@immutable
class CheckerMove {
  const CheckerMove(this.path, [this.captures = const []]);
  final List<int> path;
  final List<int> captures;

  int get from => path.first;
  int get to => path.last;
  bool get isCapture => captures.isNotEmpty;

  @override
  bool operator ==(Object other) => other is CheckerMove && listEquals(other.path, path);
  @override
  int get hashCode => Object.hashAll(path);
}

/// English draughts on an 8×8 board (squares 0..63, row × 8 + col, row 0 at
/// the top; only dark squares — (row + col) odd — are used):
/// - 12 men each; Dark starts on rows 5–7 and moves first;
/// - men move one square diagonally forward; kings one square any diagonal;
/// - capturing is compulsory and a multi-jump must be completed;
/// - a man reaching the far row is crowned (and that ends the move);
/// - a player with no legal move loses; 40 moves by each side with no
///   capture and no man moving is a draw.
@immutable
class CheckersState {
  const CheckersState(this.board, this.turn, {this.quietPlies = 0});

  final List<Checker?> board;
  final CheckerSide turn;

  /// Plies since the last capture or man move (draw at 80).
  final int quietPlies;

  static const drawPlies = 80;

  factory CheckersState.initial() {
    final b = List<Checker?>.filled(64, null);
    for (var sq = 0; sq < 64; sq++) {
      final r = sq ~/ 8, c = sq % 8;
      if ((r + c).isEven) continue;
      if (r <= 2) b[sq] = const Checker(CheckerSide.light);
      if (r >= 5) b[sq] = const Checker(CheckerSide.dark);
    }
    return CheckersState(b, CheckerSide.dark);
  }

  static bool _on(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;

  List<(int, int)> _dirs(Checker p) =>
      p.king ? const [(-1, -1), (-1, 1), (1, -1), (1, 1)] : [(p.side.forward, -1), (p.side.forward, 1)];

  /// Every legal move for the side to move (captures only, if any exist).
  List<CheckerMove> legalMoves() {
    final jumps = <CheckerMove>[];
    final steps = <CheckerMove>[];
    for (var sq = 0; sq < 64; sq++) {
      final p = board[sq];
      if (p == null || p.side != turn) continue;
      _jumpsFrom(sq, p, List.of(board), [sq], const [], jumps);
      final r = sq ~/ 8, c = sq % 8;
      for (final (dr, dc) in _dirs(p)) {
        final nr = r + dr, nc = c + dc;
        if (_on(nr, nc) && board[nr * 8 + nc] == null) steps.add(CheckerMove([sq, nr * 8 + nc]));
      }
    }
    return jumps.isNotEmpty ? jumps : steps;
  }

  /// Depth-first multi-jumps; a man that is crowned mid-sequence stops.
  void _jumpsFrom(int sq, Checker p, List<Checker?> b, List<int> path, List<int> caps, List<CheckerMove> out) {
    final r = sq ~/ 8, c = sq % 8;
    var extended = false;
    for (final (dr, dc) in _dirs(p)) {
      final mr = r + dr, mc = c + dc, lr = r + 2 * dr, lc = c + 2 * dc;
      if (!_on(lr, lc)) continue;
      final mid = mr * 8 + mc, land = lr * 8 + lc;
      final victim = b[mid];
      if (victim == null || victim.side == p.side || b[land] != null || caps.contains(mid)) continue;
      extended = true;
      final nb = List.of(b)
        ..[sq] = null
        ..[land] = p;
      final crowned = !p.king && _isLastRow(land, p.side);
      if (crowned) {
        out.add(CheckerMove([...path, land], [...caps, mid]));
      } else {
        _jumpsFrom(land, p, nb, [...path, land], [...caps, mid], out);
      }
    }
    if (!extended && caps.isNotEmpty) out.add(CheckerMove(path, caps));
  }

  static bool _isLastRow(int sq, CheckerSide s) => s == CheckerSide.dark ? sq ~/ 8 == 0 : sq ~/ 8 == 7;

  CheckersState play(CheckerMove m) {
    final b = List<Checker?>.of(board);
    final piece = b[m.from]!;
    b[m.from] = null;
    for (final x in m.captures) {
      b[x] = null;
    }
    final crowned = !piece.king && _isLastRow(m.to, piece.side);
    b[m.to] = crowned ? Checker(piece.side, king: true) : piece;
    final quiet = (m.isCapture || !piece.king) ? 0 : quietPlies + 1;
    return CheckersState(b, turn.other, quietPlies: quiet);
  }

  int countOf(CheckerSide s) => board.where((p) => p?.side == s).length;
  int kingsOf(CheckerSide s) => board.where((p) => p?.side == s && p!.king).length;

  bool get isDraw => quietPlies >= drawPlies;
  bool get isOver => isDraw || legalMoves().isEmpty;

  /// The winner once over (null = draw / ongoing). No moves = the side to
  /// move loses.
  CheckerSide? get winner => isDraw ? null : (legalMoves().isEmpty ? turn.other : null);
}

/// Computer player: alpha-beta over material, kings, advancement and the back
/// row. [depth] 2 (easy) … 6 (hard).
class CheckersBot {
  const CheckersBot({required this.depth});
  final int depth;

  CheckerMove? chooseMove(CheckersState s) {
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

  int _search(CheckersState s, int d, int alpha, int beta, CheckerSide me) {
    final moves = s.legalMoves();
    if (moves.isEmpty) return s.turn == me ? -100000 - d : 100000 + d;
    if (s.isDraw) return 0;
    if (d <= 0) return _eval(s, me);
    var a = alpha, b = beta;
    if (s.turn == me) {
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

  int _eval(CheckersState s, CheckerSide me) {
    var score = 0;
    for (var sq = 0; sq < 64; sq++) {
      final p = s.board[sq];
      if (p == null) continue;
      final r = sq ~/ 8, c = sq % 8;
      var v = p.king ? 160 : 100;
      if (!p.king) v += 3 * (p.side == CheckerSide.dark ? 7 - r : r); // advancement
      if (c >= 2 && c <= 5 && r >= 2 && r <= 5) v += 4; // centre
      if (!p.king && ((p.side == CheckerSide.dark && r == 7) || (p.side == CheckerSide.light && r == 0))) v += 6;
      score += p.side == me ? v : -v;
    }
    return score;
  }
}

/// Game controller for the screen.
class CheckersGame extends ChangeNotifier {
  CheckersState state = CheckersState.initial();

  /// The last move and the pieces it captured (for the animation).
  CheckerMove? lastMove;
  List<(int, Checker)> lastCaptured = const [];
  int moveCount = 0;

  void play(CheckerMove m) {
    lastCaptured = [for (final x in m.captures) (x, state.board[x]!)];
    state = state.play(m);
    lastMove = m;
    moveCount++;
    notifyListeners();
  }
}

/// Standard checkers notation: dark squares numbered 1–32 from the top-left.
int checkersSquareNumber(int sq) => (sq ~/ 8) * 4 + (sq % 8) ~/ 2 + 1;
