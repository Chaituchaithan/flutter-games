import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Snakes & Ladders rules (local game):
/// - 2–4 players start off the board (square 0) and race to 100.
/// - Roll 1–6 and move that many squares; you must land on 100 exactly
///   (an overshoot means no move).
/// - Landing on a ladder's foot climbs it; on a snake's head slides down.
/// - A 6 earns another roll.
class SnakesRules {
  SnakesRules._();

  static const int finish = 100;

  /// Ladder foot → top.
  static const Map<int, int> ladders = {4: 25, 13: 46, 33: 49, 42: 63, 50: 69, 62: 81, 74: 92};

  /// Snake head → tail.
  static const Map<int, int> snakes = {27: 5, 40: 3, 43: 18, 54: 31, 66: 45, 76: 58, 89: 53, 99: 41};

  /// Board cell (column 0..9 from the left, row 0..9 from the TOP) of square
  /// 1..100 — boustrophedon: row 1 runs left→right from the bottom-left.
  static (int col, int row) cellOf(int square) {
    final i = square - 1;
    final fromBottom = i ~/ 10;
    final c = i % 10;
    return (fromBottom.isEven ? c : 9 - c, 9 - fromBottom);
  }
}

/// How a move ends after the walk.
enum SnakesJump { none, ladder, snake }

/// One turn's movement, for the board to animate: the squares walked one by
/// one, then an optional ladder climb / snake slide.
@immutable
class SnakesMove {
  const SnakesMove({
    required this.player,
    required this.roll,
    required this.from,
    required this.steps,
    this.jump = SnakesJump.none,
    this.jumpTo,
  });

  final int player;
  final int roll;
  final int from;

  /// Squares visited one per step (empty when the roll overshoots 100).
  final List<int> steps;
  final SnakesJump jump;
  final int? jumpTo;

  /// Where the token ends.
  int get to => jumpTo ?? (steps.isEmpty ? from : steps.last);

  bool get blocked => steps.isEmpty;
}

/// Game state + turn flow. [roll] produces a [SnakesMove] the board animates;
/// [finishMove] commits it and passes (or keeps, on a 6) the turn.
class SnakesGame extends ChangeNotifier {
  SnakesGame({required this.players, math.Random? rng})
    : assert(players >= 2 && players <= 4),
      _rng = rng ?? math.Random(),
      positions = List.filled(players, 0);

  final int players;
  final math.Random _rng;

  /// Square per player (0 = not on the board yet).
  final List<int> positions;

  int turn = 0;
  int? winner;

  /// Last die value and a counter that bumps each roll (drives the dice).
  int lastRoll = 1;
  int rollId = 0;

  /// The move being animated (null when waiting for a roll).
  SnakesMove? pending;

  /// Total rolls made (for the "Move n" header).
  int moveCount = 0;

  /// Readable summary of the last completed move.
  String lastText = '—';

  bool get isOver => winner != null;
  bool get awaitingRoll => !isOver && pending == null;

  /// Roll for the player to move. [forced] fixes the value (tests).
  SnakesMove roll({int? forced}) {
    assert(awaitingRoll);
    final v = forced ?? 1 + _rng.nextInt(6);
    lastRoll = v;
    rollId++;
    moveCount++;
    final from = positions[turn];
    final target = from + v;
    final steps = target > SnakesRules.finish ? <int>[] : [for (var s = from + 1; s <= target; s++) s];
    var jump = SnakesJump.none;
    int? jumpTo;
    if (steps.isNotEmpty) {
      if (SnakesRules.ladders.containsKey(target)) {
        jump = SnakesJump.ladder;
        jumpTo = SnakesRules.ladders[target];
      } else if (SnakesRules.snakes.containsKey(target)) {
        jump = SnakesJump.snake;
        jumpTo = SnakesRules.snakes[target];
      }
    }
    pending = SnakesMove(player: turn, roll: v, from: from, steps: steps, jump: jump, jumpTo: jumpTo);
    notifyListeners();
    return pending!;
  }

  /// Commit the animated move, then hand over the turn (a 6 keeps it).
  void finishMove({String Function(int player)? nameOf}) {
    final m = pending;
    if (m == null) return;
    positions[m.player] = m.to;
    final who = nameOf?.call(m.player) ?? 'P${m.player + 1}';
    lastText = switch (m.jump) {
      _ when m.blocked => '$who rolled ${m.roll} · needs exact',
      SnakesJump.ladder => '$who 🪜 ${m.steps.last} → ${m.to}',
      SnakesJump.snake => '$who 🐍 ${m.steps.last} → ${m.to}',
      SnakesJump.none => '$who rolled ${m.roll} → ${m.to}',
    };
    pending = null;
    if (m.to == SnakesRules.finish) {
      winner = m.player;
    } else if (m.roll != 6) {
      turn = (turn + 1) % players;
    }
    notifyListeners();
  }

  /// Ranking for results: players ordered by square (winner first).
  List<int> get standings => List.generate(players, (i) => i)..sort((a, b) => positions[b].compareTo(positions[a]));
}
