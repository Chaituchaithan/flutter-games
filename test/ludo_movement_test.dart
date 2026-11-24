// Pawn movement checks for both board layouts.
//
// Offline (classic): full 4-player games played by the engine's bot, and
// every move is checked: the path has exactly the dice's number of steps,
// every step lands on the next square (orthogonally adjacent cell, or the
// centre when it finishes), a capture sends the victim to base, and finishing
// needs the exact number.
//
// Online (server layout, ludo.md "The board"): every square-to-square step of
// every colour's full route is checked the same way.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/ludo/ludo_engine.dart';

/// Board point of a progress value (the centre for home), in cells.
(double, double)? _point(LudoLayout layout, LudoColor c, int p) {
  if (p == layout.home) return (7.0, 7.0);
  final cell = layout.cellOf(c, p);
  return cell == null ? null : (cell.$1.toDouble(), cell.$2.toDouble());
}

/// Problems on one step from [a] to [b] for colour [c].
String? _stepProblem(LudoLayout layout, LudoColor c, int a, int b) {
  final pa = _point(layout, c, a), pb = _point(layout, c, b);
  if (pa == null || pb == null) return 'no cell for $a or $b';
  final dx = (pa.$1 - pb.$1).abs(), dy = (pa.$2 - pb.$2).abs();
  if (b == layout.home) {
    // Into the centre: from the lane's last square, which touches the centre block.
    return (pa.$1 >= 5 && pa.$1 <= 9 && pa.$2 >= 5 && pa.$2 <= 9) ? null : 'jumps into home from far away';
  }
  final cellA = layout.cellOf(c, a)!, cellB = layout.cellOf(c, b)!;
  // The online lane's 6th square is drawn as a real square on the centre's edge.
  final drawnInner = layout.innerLaneCell && cellB == LudoLayout.innerCell(c);
  if (_inCentre(cellB) && !drawnInner) return 'step ${a}→$b lands inside the centre home block ${cellB.toString()}';
  if (dx + dy == 1) return null;
  if (layout.innerLaneCell && a == layout.lastTrack && b == layout.lastTrack + 1) {
    // Online: the hop bends around the lane mouth, which touches both ends.
    final m = layout.laneMouth(c);
    bool touches((int, int) x) => (x.$1 - m.$1).abs() + (x.$2 - m.$2).abs() == 1;
    return touches(cellA) && touches(cellB) ? null : 'lane entry ${a}→$b does not pass the lane mouth $m';
  }
  if (dx == 1 && dy == 1) {
    // The track turns a corner diagonally around each arm (e.g. (5,6)→(6,5)).
    final bothTrack = a <= layout.lastTrack && b <= layout.lastTrack;
    if (bothTrack) return null;
    return 'diagonal step ${a}→$b from $cellA into the lane at $cellB';
  }
  return 'step ${a}→$b jumps from $cellA to $cellB';
}

bool _inCentre((int, int) cell) => cell.$1 >= 6 && cell.$1 <= 8 && cell.$2 >= 6 && cell.$2 <= 8;

class _Played {
  int moves = 0, captures = 0, entries = 0, finishes = 0, noMoves = 0;
  final problems = <String>[];
}

/// One full offline game, every move checked.
_Played _playOffline(int seed) {
  final g = LudoGame(colors: LudoColor.values, rng: math.Random(seed));
  final out = _Played();
  var guard = 0;
  while (!g.isOver && guard++ < 5000) {
    final dice = g.roll();
    if (g.passIfStuck()) {
      out.noMoves++;
      continue;
    }
    final c = g.current;
    final token = g.chooseBotMove();
    final before = {for (final o in g.colors) o: [...g.tokens[o]!]};
    final m = g.move(token);
    // 1) Steps = dice (a base exit needs a 6 and is one step onto the start).
    if (m.leavesBase) {
      if (dice != 6) out.problems.add('left base on a $dice');
      if (m.to != 0) out.problems.add('base exit lands on ${m.to}, not the start');
      out.entries++;
    } else {
      if (m.path.length != dice) out.problems.add('rolled $dice but path has ${m.path.length} steps (${m.from}→${m.to})');
      if (m.to > LudoRules.home) out.problems.add('overshot home: ${m.to}');
      // 2) Every step lands on the next square.
      var prev = m.from;
      for (final p in m.path) {
        final why = _stepProblem(LudoLayout.classic, c, prev, p);
        if (why != null) out.problems.add('${c.name}: $why');
        prev = p;
      }
    }
    g.finishMove();
    // 3) Captures go back to base; nothing else moved.
    for (final (o, i) in m.captured) {
      if (g.tokens[o]![i] != LudoRules.base) out.problems.add('captured ${o.name} #$i not sent home');
    }
    for (final o in g.colors) {
      for (var i = 0; i < 4; i++) {
        final moved = (o == c && i == token) || m.captured.contains((o, i));
        if (!moved && g.tokens[o]![i] != before[o]![i]) out.problems.add('${o.name} #$i moved by itself');
      }
    }
    if (m.captured.isNotEmpty) out.captures += m.captured.length;
    if (m.reachesHome) out.finishes++;
    out.moves++;
  }
  if (!g.isOver) out.problems.add('game did not finish');
  return out;
}

void main() {
  group('offline Quick Play (classic board): full games', () {
    for (final seed in [1, 2, 3]) {
      test('game $seed: every move is the dice count, square by square', () {
        final r = _playOffline(seed);
        debugPrint('[LUDO] offline game $seed: ${r.moves} moves, ${r.entries} base exits, '
            '${r.captures} captures, ${r.finishes} pawns home, ${r.noMoves} rolls with no move');
        expect(r.problems, isEmpty, reason: r.problems.take(10).join('\n'));
        expect(r.finishes, greaterThanOrEqualTo(4), reason: 'the winner brought all four home');
      });
    }

    test('finishing needs the exact number; the last lane square is 1 from home', () {
      for (final c in LudoColor.values) {
        // Each lane square's distance to home matches what the board shows.
        for (var p = LudoRules.lastTrack + 1; p < LudoRules.home; p++) {
          final cell = LudoLayout.classic.cellOf(c, p)!;
          final lane = LudoRules.homeColumn[c]!;
          final shownAway = lane.length - lane.indexOf(cell); // squares left to walk on screen
          expect(shownAway, LudoRules.home - p, reason: '${c.name} at $p');
        }
      }
    });
  });

  group('online (server layout): every step of every route', () {
    test('report', () {
      final problems = <String>{};
      for (final c in LudoColor.values) {
        for (var p = 0; p < LudoLayout.server.home; p++) {
          final why = _stepProblem(LudoLayout.server, c, p, p + 1);
          if (why != null) problems.add('${c.name}: $why');
        }
      }
      for (final p in problems) {
        debugPrint('[LUDO] online layout: $p');
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  });
}
