import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/ludo/ludo_engine.dart';
import 'package:snakeladder/game/snakes/snakes_engine.dart';

void main() {
  group('Snakes & Ladders', () {
    test('100 random 4-player games all finish on exactly 100', () {
      for (var seed = 0; seed < 100; seed++) {
        final g = SnakesGame(players: 4, rng: math.Random(seed));
        var guard = 0;
        while (!g.isOver && guard++ < 5000) {
          g.roll();
          g.finishMove();
        }
        expect(g.isOver, isTrue, reason: 'seed $seed');
        expect(g.positions[g.winner!], SnakesRules.finish);
        expect(g.positions.every((p) => p >= 0 && p <= 100), isTrue);
      }
    });

    test('ladders climb, snakes slide, overshoot stays, 6 rolls again', () {
      final g = SnakesGame(players: 2, rng: math.Random(1));
      final m = g.roll(forced: 4); // 0 → 4 = ladder foot
      expect(m.jump, SnakesJump.ladder);
      g.finishMove();
      expect(g.positions[0], 25);
      expect(g.turn, 1);

      g.positions[1] = 98;
      final over = g.roll(forced: 5); // 103 > 100
      expect(over.blocked, isTrue);
      g.finishMove();
      expect(g.positions[1], 98);

      g.positions[0] = 21;
      final s = g.roll(forced: 6); // 27 = snake head
      expect(s.jump, SnakesJump.snake);
      g.finishMove();
      expect(g.positions[0], 5);
      expect(g.turn, 0, reason: 'a 6 keeps the turn');
    });
  });

  group('Ludo', () {
    test('100 random bot games (2–4 players) all finish', () {
      for (var seed = 0; seed < 100; seed++) {
        final colors = LudoColor.values.take(2 + seed % 3).toList();
        final g = LudoGame(colors: colors, rng: math.Random(seed));
        var guard = 0;
        while (!g.isOver && guard++ < 20000) {
          g.roll();
          if (g.passIfStuck()) continue;
          g.move(g.chooseBotMove());
          g.finishMove();
        }
        expect(g.isOver, isTrue, reason: 'seed $seed');
        expect(g.homeCount(g.winner!), 4);
      }
    });

    test('a 6 leaves base, captures send home, safe squares protect', () {
      final g = LudoGame(colors: [LudoColor.red, LudoColor.yellow], rng: math.Random(2));
      g.roll(forced: 3);
      expect(g.passIfStuck(), isTrue, reason: 'all in base, no 6');
      expect(g.current, LudoColor.yellow);

      g.roll(forced: 6);
      expect(g.movable, [0, 1, 2, 3]);
      final out = g.move(0);
      expect(out.leavesBase, isTrue);
      g.finishMove();
      expect(g.tokens[LudoColor.yellow]![0], 0);
      expect(g.current, LudoColor.yellow, reason: 'a 6 rolls again');

      // Red token two squares behind a yellow token on an unsafe square.
      g.tokens[LudoColor.yellow]![0] = 3; // yellow relative 3 = track 29
      g.tokens[LudoColor.red]![1] = 27; // red relative 27 = track 27
      g.roll(forced: 1);
      g.move(0);
      g.finishMove(); // yellow moved to 4 (track 30); turn → red
      expect(g.current, LudoColor.red);
      g.roll(forced: 3); // red 27 → 30 = yellow's square
      final cap = g.move(1);
      expect(cap.captured, [(LudoColor.yellow, 0)]);
      g.finishMove();
      expect(g.tokens[LudoColor.yellow]![0], LudoRules.base);
      expect(g.current, LudoColor.red, reason: 'a capture rolls again');

      // On a star (track 34) nobody is captured.
      g.tokens[LudoColor.yellow]![1] = 8; // yellow 8 = track 34 (star)
      g.tokens[LudoColor.red]![1] = 32;
      g.roll(forced: 2);
      final safe = g.move(1);
      expect(safe.captured, isEmpty);
    });

    test('no overshooting home; exact roll finishes', () {
      final g = LudoGame(colors: [LudoColor.blue, LudoColor.green], rng: math.Random(3));
      g.tokens[LudoColor.blue]![0] = 54;
      g.roll(forced: 4);
      expect(g.movable, isEmpty);
      g.passIfStuck();
      g.roll(forced: 1);
      g.passIfStuck();
      g.tokens[LudoColor.blue]![0] = 54;
      g.roll(forced: 2);
      expect(g.movable, [0]);
      expect(g.move(0).reachesHome, isTrue);
    });
  });
}
