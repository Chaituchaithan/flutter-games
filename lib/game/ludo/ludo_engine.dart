import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Ludo colours in turn order (clockwise from the top-left base).
enum LudoColor { red, green, yellow, blue }

/// Classic Ludo on a 15×15 board (local game):
/// - 4 tokens per player wait in their base; a 6 brings one onto its start
///   square.
/// - Tokens run 51 squares of the shared track, then 5 squares of their own
///   home column, and finish in the centre (progress 0..56).
/// - Landing on an opponent's token captures it (back to base) — except on
///   the safe squares (each start square and the four stars).
/// - A 6, a capture or bringing a token home earns another roll; three 6s in a
///   row forfeit the turn. Overshooting home isn't allowed.
/// - First player with all four tokens home wins.
class LudoRules {
  LudoRules._();

  static const int base = -1;
  static const int lastTrack = 50; // relative progress of the last track square
  static const int home = 56; // finished

  /// The 52 track squares as (column, row), row 0 at the top, starting at
  /// red's start square and running clockwise.
  static const List<(int, int)> track = [
    (1, 6),
    (2, 6),
    (3, 6),
    (4, 6),
    (5, 6),
    (6, 5),
    (6, 4),
    (6, 3),
    (6, 2),
    (6, 1),
    (6, 0),
    (7, 0),
    (8, 0),
    (8, 1),
    (8, 2),
    (8, 3),
    (8, 4),
    (8, 5),
    (9, 6),
    (10, 6),
    (11, 6),
    (12, 6),
    (13, 6),
    (14, 6),
    (14, 7),
    (14, 8),
    (13, 8),
    (12, 8),
    (11, 8),
    (10, 8),
    (9, 8),
    (8, 9),
    (8, 10),
    (8, 11),
    (8, 12),
    (8, 13),
    (8, 14),
    (7, 14),
    (6, 14),
    (6, 13),
    (6, 12),
    (6, 11),
    (6, 10),
    (6, 9),
    (5, 8),
    (4, 8),
    (3, 8),
    (2, 8),
    (1, 8),
    (0, 8),
    (0, 7),
    (0, 6),
  ];

  /// Track index of each colour's start square.
  static int startIndex(LudoColor c) => c.index * 13;

  /// Safe squares (track indices): the four starts + the four stars.
  static const Set<int> safe = {0, 8, 13, 21, 26, 34, 39, 47};

  /// Home column squares (progress 51..55) for each colour, outside → in.
  static const Map<LudoColor, List<(int, int)>> homeColumn = {
    LudoColor.red: [(1, 7), (2, 7), (3, 7), (4, 7), (5, 7)],
    LudoColor.green: [(7, 1), (7, 2), (7, 3), (7, 4), (7, 5)],
    LudoColor.yellow: [(13, 7), (12, 7), (11, 7), (10, 7), (9, 7)],
    LudoColor.blue: [(7, 13), (7, 12), (7, 11), (7, 10), (7, 9)],
  };

  /// Absolute track index for a token's relative progress (null off-track).
  static int? trackIndex(LudoColor c, int progress) =>
      progress < 0 || progress > lastTrack ? null : (startIndex(c) + progress) % 52;

  /// Board cell (column, row) of a token at [progress] (base/home excluded).
  static (int, int)? cellOf(LudoColor c, int progress) {
    final t = trackIndex(c, progress);
    if (t != null) return track[t];
    if (progress > lastTrack && progress < home) return homeColumn[c]![progress - lastTrack - 1];
    return null;
  }
}

/// A token move the board animates: [path] = the cells' progress values in
/// order (from+1 .. to), [captured] = opponent tokens sent home.
@immutable
class LudoMove {
  const LudoMove({
    required this.color,
    required this.token,
    required this.from,
    required this.to,
    this.captured = const [],
  });

  final LudoColor color;
  final int token;
  final int from;
  final int to;
  final List<(LudoColor, int)> captured;

  bool get leavesBase => from == LudoRules.base;
  bool get reachesHome => to == LudoRules.home;

  /// Progress values stepped through (a base exit is a single step).
  List<int> get path => leavesBase ? [0] : [for (var p = from + 1; p <= to; p++) p];
}

/// Game state + turn flow.
///
/// Flow per turn: [roll] → if [movable] is empty the turn passes (see
/// [passIfStuck]) → [move] returns a [LudoMove] for the board to animate →
/// [finishMove] commits it and keeps or passes the turn.
class LudoGame extends ChangeNotifier {
  LudoGame({required this.colors, math.Random? rng})
    : assert(colors.length >= 2 && colors.length <= 4),
      _rng = rng ?? math.Random(),
      tokens = {for (final c in colors) c: List.filled(4, LudoRules.base)};

  /// Colours in play, in turn order.
  final List<LudoColor> colors;
  final math.Random _rng;

  /// Progress of each colour's 4 tokens (−1 base · 0..55 board · 56 home).
  final Map<LudoColor, List<int>> tokens;

  int _turn = 0;
  LudoColor get current => colors[_turn];

  /// Die value for the current turn (null = not rolled yet).
  int? rolled;
  int lastRoll = 1;
  int rollId = 0;
  int _sixes = 0;

  /// Move being animated.
  LudoMove? pending;

  LudoColor? winner;
  int moveCount = 0;
  String lastText = '—';

  bool get isOver => winner != null;
  bool get awaitingRoll => !isOver && rolled == null && pending == null;
  bool get awaitingMove => !isOver && rolled != null && pending == null;

  int homeCount(LudoColor c) => tokens[c]!.where((p) => p == LudoRules.home).length;

  /// Tokens of the current player that can move with [rolled].
  List<int> get movable {
    final r = rolled;
    if (r == null) return const [];
    final list = tokens[current]!;
    return [
      for (var i = 0; i < 4; i++)
        if (list[i] == LudoRules.base ? r == 6 : list[i] != LudoRules.home && list[i] + r <= LudoRules.home) i,
    ];
  }

  /// Roll the die for [current]. Three 6s in a row end the turn at once.
  int roll({int? forced}) {
    assert(awaitingRoll);
    final v = forced ?? 1 + _rng.nextInt(6);
    rolled = v;
    lastRoll = v;
    rollId++;
    moveCount++;
    if (v == 6) {
      _sixes++;
    } else {
      _sixes = 0;
    }
    notifyListeners();
    return v;
  }

  /// Three 6s, or nothing can move: the turn passes. Returns true if it did.
  bool passIfStuck({String Function(LudoColor)? nameOf}) {
    if (!awaitingMove) return false;
    final who = nameOf?.call(current) ?? current.name;
    if (_sixes >= 3) {
      lastText = '$who rolled three 6s · turn lost';
      _nextPlayer();
      return true;
    }
    if (movable.isEmpty) {
      lastText = '$who rolled $rolled · no move';
      _nextPlayer();
      return true;
    }
    return false;
  }

  /// Move [token] of the current player by the rolled value.
  LudoMove move(int token) {
    assert(awaitingMove && movable.contains(token));
    final c = current;
    final from = tokens[c]![token];
    final to = from == LudoRules.base ? 0 : from + rolled!;
    final captured = <(LudoColor, int)>[];
    final t = LudoRules.trackIndex(c, to);
    if (t != null && !LudoRules.safe.contains(t)) {
      for (final o in colors) {
        if (o == c) continue;
        final list = tokens[o]!;
        for (var i = 0; i < 4; i++) {
          if (LudoRules.trackIndex(o, list[i]) == t) captured.add((o, i));
        }
      }
    }
    pending = LudoMove(color: c, token: token, from: from, to: to, captured: captured);
    notifyListeners();
    return pending!;
  }

  /// Commit the animated move; keep the turn on a 6 / capture / home.
  void finishMove({String Function(LudoColor)? nameOf}) {
    final m = pending;
    if (m == null) return;
    tokens[m.color]![m.token] = m.to;
    for (final (o, i) in m.captured) {
      tokens[o]![i] = LudoRules.base;
    }
    final who = nameOf?.call(m.color) ?? m.color.name;
    lastText = m.captured.isNotEmpty
        ? '$who captured ${m.captured.length == 1 ? 'a token' : '${m.captured.length} tokens'}'
        : m.reachesHome
        ? '$who brought a token home'
        : m.leavesBase
        ? '$who entered the board'
        : '$who moved $rolled';
    pending = null;
    final again = rolled == 6 || m.captured.isNotEmpty || m.reachesHome;
    if (homeCount(m.color) == 4) {
      winner = m.color;
      rolled = null;
    } else if (again) {
      rolled = null; // same player rolls again
    } else {
      _nextPlayer();
    }
    notifyListeners();
  }

  void _nextPlayer() {
    rolled = null;
    _sixes = 0;
    _turn = (_turn + 1) % colors.length;
    notifyListeners();
  }

  // ── Computer player ──

  /// Pick a token for [current] (assumes [awaitingMove] and moves exist).
  /// Priorities: finish > capture > leave base > reach safety > escape a
  /// threat > advance the most progressed token.
  int chooseBotMove() {
    final c = current;
    final r = rolled!;
    final list = tokens[c]!;
    var best = movable.first;
    var bestScore = double.negativeInfinity;
    for (final i in movable) {
      final from = list[i];
      final to = from == LudoRules.base ? 0 : from + r;
      var score = 0.0;
      if (to == LudoRules.home) score += 100;
      final t = LudoRules.trackIndex(c, to);
      if (t != null && !LudoRules.safe.contains(t) && _opponentsAt(t)) score += 80;
      if (from == LudoRules.base) score += 60;
      if (t != null && LudoRules.safe.contains(t)) score += 25;
      if (to > LudoRules.lastTrack) score += 30; // into the home column
      final fromT = LudoRules.trackIndex(c, from);
      if (fromT != null && !LudoRules.safe.contains(fromT) && _threatened(c, fromT)) score += 35;
      if (t != null && !LudoRules.safe.contains(t) && _threatened(c, t)) score -= 40;
      score += to * 0.5 + _rng.nextDouble();
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
  }

  bool _opponentsAt(int t) => colors.any((o) => o != current && tokens[o]!.any((p) => LudoRules.trackIndex(o, p) == t));

  /// An opponent token sits 1–6 squares behind track index [t].
  bool _threatened(LudoColor me, int t) {
    for (final o in colors) {
      if (o == me) continue;
      for (final p in tokens[o]!) {
        final ot = LudoRules.trackIndex(o, p);
        if (ot == null) continue;
        final gap = (t - ot) % 52;
        if (gap >= 1 && gap <= 6) return true;
      }
    }
    return false;
  }
}
