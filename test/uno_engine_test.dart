import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snakeladder/game/uno/uno_engine.dart';

void main() {
  test('108-card deck: 76 numbers, 24 actions, 8 wilds', () {
    final d = UnoRules.deck();
    expect(d.length, 108);
    expect(d.where((c) => c.kind == UnoKind.number).length, 76);
    expect(d.where((c) => c.kind == UnoKind.number && c.number == 0).length, 4);
    expect(d.where((c) => c.isWild).length, 8);
    expect(d.map((c) => c.id).toSet().length, 108);
  });

  test('deal: 7 each, a number card turned up', () {
    final g = UnoGame(players: 4, rng: math.Random(1));
    expect(g.hands.every((h) => h.length == 7), isTrue);
    expect(g.top.kind, UnoKind.number);
    expect(g.color, g.top.color);
    expect(g.drawPileCount, 108 - 28 - 1);
  });

  test('matching: colour, number, symbol or wild', () {
    const top = UnoCard(0, UnoKind.number, color: UnoColor.red, number: 5);
    expect(
      UnoRules.canPlay(const UnoCard(1, UnoKind.number, color: UnoColor.red, number: 2), top, UnoColor.red),
      isTrue,
    );
    expect(
      UnoRules.canPlay(const UnoCard(2, UnoKind.number, color: UnoColor.blue, number: 5), top, UnoColor.red),
      isTrue,
    );
    expect(
      UnoRules.canPlay(const UnoCard(3, UnoKind.number, color: UnoColor.blue, number: 6), top, UnoColor.red),
      isFalse,
    );
    expect(UnoRules.canPlay(const UnoCard(4, UnoKind.wild), top, UnoColor.red), isTrue);
    const skip = UnoCard(5, UnoKind.skip, color: UnoColor.green);
    expect(UnoRules.canPlay(const UnoCard(6, UnoKind.skip, color: UnoColor.blue), skip, UnoColor.green), isTrue);
    // After a wild, only the named colour (or another wild) matches.
    const wild = UnoCard(7, UnoKind.wild);
    expect(
      UnoRules.canPlay(const UnoCard(8, UnoKind.number, color: UnoColor.yellow, number: 1), wild, UnoColor.yellow),
      isTrue,
    );
    expect(
      UnoRules.canPlay(const UnoCard(9, UnoKind.number, color: UnoColor.red, number: 1), wild, UnoColor.yellow),
      isFalse,
    );
  });

  UnoGame rigged(int players, List<UnoCard> hand0) {
    final g = UnoGame(players: players, rng: math.Random(3));
    g.hands[0]
      ..clear()
      ..addAll(hand0);
    g.discard.add(const UnoCard(500, UnoKind.number, color: UnoColor.red, number: 9));
    g.color = UnoColor.red;
    return g;
  }

  test('Skip, Reverse and +2', () {
    var g = rigged(4, const [
      UnoCard(501, UnoKind.skip, color: UnoColor.red),
      UnoCard(502, UnoKind.number, color: UnoColor.red, number: 1),
      UnoCard(503, UnoKind.number, color: UnoColor.red, number: 2),
    ]);
    g.play(g.hands[0].first);
    expect(g.turn, 2);

    g = rigged(4, const [
      UnoCard(501, UnoKind.reverse, color: UnoColor.red),
      UnoCard(502, UnoKind.number, color: UnoColor.red, number: 1),
      UnoCard(503, UnoKind.number, color: UnoColor.red, number: 2),
    ]);
    g.play(g.hands[0].first);
    expect(g.direction, -1);
    expect(g.turn, 3);

    // Two players: Reverse = Skip.
    g = rigged(2, const [
      UnoCard(501, UnoKind.reverse, color: UnoColor.red),
      UnoCard(502, UnoKind.number, color: UnoColor.red, number: 1),
      UnoCard(503, UnoKind.number, color: UnoColor.red, number: 2),
    ]);
    g.play(g.hands[0].first);
    expect(g.turn, 0);

    g = rigged(4, const [
      UnoCard(501, UnoKind.drawTwo, color: UnoColor.red),
      UnoCard(502, UnoKind.number, color: UnoColor.red, number: 1),
      UnoCard(503, UnoKind.number, color: UnoColor.red, number: 2),
    ]);
    final before = g.hands[1].length;
    g.play(g.hands[0].first);
    expect(g.hands[1].length, before + 2);
    expect(g.turn, 2);
  });

  test('Wild +4 names the colour; the next player draws 4', () {
    final g = rigged(3, const [
      UnoCard(501, UnoKind.wildDrawFour),
      UnoCard(502, UnoKind.number, color: UnoColor.red, number: 1),
      UnoCard(503, UnoKind.number, color: UnoColor.red, number: 2),
    ]);
    final before = g.hands[1].length;
    g.play(g.hands[0].first, chosen: UnoColor.blue);
    expect(g.color, UnoColor.blue);
    expect(g.hands[1].length, before + 4);
    expect(g.turn, 2);
  });

  test('UNO call: forget it and draw 2; call it and keep one card', () {
    const two = [
      UnoCard(501, UnoKind.number, color: UnoColor.red, number: 1),
      UnoCard(502, UnoKind.number, color: UnoColor.blue, number: 2),
    ];
    var g = rigged(2, two);
    g.play(g.hands[0].first);
    expect(g.hands[0].length, 3);
    expect(g.events.whereType<UnoCaught>(), isNotEmpty);
    g = rigged(2, two);
    g.play(g.hands[0].first, saidUno: true);
    expect(g.hands[0].length, 1);
  });

  test('last card wins and scores the others\' cards', () {
    final g = rigged(2, const [UnoCard(501, UnoKind.number, color: UnoColor.red, number: 4)]);
    g.hands[1]
      ..clear()
      ..addAll(const [
        UnoCard(600, UnoKind.wild),
        UnoCard(601, UnoKind.skip, color: UnoColor.blue),
        UnoCard(602, UnoKind.number, color: UnoColor.green, number: 7),
      ]);
    g.play(g.hands[0].single);
    expect(g.winner, 0);
    expect(g.winnerPoints, 50 + 20 + 7);
  });

  test('drawing: a playable card may be played or kept; else the turn passes', () {
    final g = rigged(2, const [UnoCard(501, UnoKind.number, color: UnoColor.blue, number: 1)]);
    final c = g.draw()!;
    if (g.canPlay(c)) {
      expect(g.drawn, c);
      expect(g.playable(), [c]);
      g.pass();
    }
    expect(g.turn, 1);
    expect(g.drawn, isNull);
  });

  test('bots play whole games to a winner at every level', () {
    for (var d = 1; d <= 3; d++) {
      for (var seed = 0; seed < 15; seed++) {
        final rng = math.Random(seed);
        final g = UnoGame(players: 2 + seed % 3, rng: rng);
        var steps = 0;
        while (!g.isOver && steps++ < 3000) {
          final m = unoBotMove(g, d, rng);
          if (m.card != null) {
            g.play(m.card!, chosen: m.color, saidUno: m.sayUno);
          } else if (g.drawn == null) {
            g.draw();
          } else {
            g.pass();
          }
        }
        expect(g.isOver, isTrue, reason: 'd$d seed$seed');
        // No card lost or duplicated.
        expect(g.hands.fold(0, (a, h) => a + h.length) + g.discard.length + g.drawPileCount, 108);
      }
    }
  });
}
