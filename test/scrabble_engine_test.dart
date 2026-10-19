import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snakeladder/game/scrabble/scrabble_words.g.dart';

import 'package:snakeladder/game/scrabble/scrabble_engine.dart';

void main() {
  final lex = Lexicon.fromText(File('assets/scrabble/words.txt').readAsStringSync());

  test('standard premium layout', () {
    int count(Premium p) => premiums.where((x) => x == p).length;
    expect(count(Premium.tw), 8);
    expect(count(Premium.dw), 17); // 16 + the centre star
    expect(count(Premium.tl), 12);
    expect(count(Premium.dl), 24);
    expect(premiums[kCenter], Premium.dw);
  });

  test('first move CAT across the centre scores 10 (centre is double word)', () {
    final board = List<Tile?>.filled(225, null);
    final placed = {7 * 15 + 6: const Tile('C'), 7 * 15 + 7: const Tile('A'), 7 * 15 + 8: const Tile('T')};
    final (play, err, _) = evaluatePlay(board, placed, lex);
    expect(err, isNull);
    expect(play!.words, ['CAT']);
    expect(play.score, 10);
  });

  test('rejects gaps, non-words and a first move off the centre', () {
    final board = List<Tile?>.filled(225, null);
    expect(evaluatePlay(board, {0: const Tile('A'), 1: const Tile('T')}, lex).$2, PlayError.firstMoveCenter);
    expect(evaluatePlay(board, {112: const Tile('X'), 113: const Tile('Q')}, lex).$2, PlayError.notAWord);
    expect(evaluatePlay(board, {111: const Tile('C'), 113: const Tile('T')}, lex).$2, PlayError.gap);
  });

  test('move generation finds plays and they all validate', () {
    final board = List<Tile?>.filled(225, null);
    final rack = [for (final c in 'RETAINS'.split('')) Tile(c)];
    final plays = generatePlays(board, rack, lex);
    expect(plays, isNotEmpty);
    expect(plays.first.score, greaterThanOrEqualTo(50), reason: 'RETAINS / NASTIER etc. is a bingo');
    for (final p in plays.take(20)) {
      expect(evaluatePlay(board, p.tiles, lex).$2, isNull);
    }
  });

  test('computer vs computer games finish with consistent scores', () {
    for (final seed in [1, 2]) {
      final g = ScrabbleGame(rng: math.Random(seed));
      var guard = 0;
      while (!g.over && guard++ < 200) {
        final p = chooseScrabblePlay(g.board, g.racks[g.turn], lex, 3, seed + guard);
        if (p != null) {
          g.play(p);
        } else if (g.canExchange) {
          g.exchange(g.racks[g.turn].take(3).toList());
        } else {
          g.pass();
        }
      }
      expect(g.over, isTrue, reason: 'seed $seed');
      expect(g.scores[0] + g.scores[1], greaterThan(100));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the compiled word list matches assets/scrabble/words.txt (re-run tools/gen_scrabble_words.dart)', () {
    final file = File('assets/scrabble/words.txt')
        .readAsLinesSync()
        .map((w) => w.trim().toUpperCase())
        .where((w) => w.length >= 2)
        .toList();
    expect(scrabbleWordList.split('\n'), file);
  });
}
