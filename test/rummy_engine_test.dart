import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/common/playing_cards.dart';
import 'package:snakeladder/game/rummy/rummy_engine.dart';

PlayingCard c(String s, {int deck = 0}) {
  if (s == 'JK') return PlayingCard.joker(deck: deck);
  const ranks = {'A': 1, 'K': 13, 'Q': 12, 'J': 11, 'T': 10};
  final r = ranks[s[0]] ?? int.parse(s[0]);
  final suit = {'s': Suit.spades, 'h': Suit.hearts, 'd': Suit.diamonds, 'c': Suit.clubs}[s[1]]!;
  return PlayingCard(r, suit, deck: deck);
}

List<PlayingCard> cs(String s) => s.split(' ').map(c).toList();

void main() {
  const wild = 5; // fives are wild in these tests

  test('meld kinds', () {
    expect(classify(cs('4h 5h 6h'), wild), MeldKind.pureSequence, reason: 'a wild card in its natural place is pure');
    expect(classify(cs('Qs Ks As'), wild), MeldKind.pureSequence, reason: 'ace high');
    expect(classify(cs('As 2s 3s'), wild), MeldKind.pureSequence, reason: 'ace low');
    expect(classify(cs('Ks As 2s'), wild), MeldKind.invalid, reason: 'no wrap-around');
    expect(classify(cs('7d 9d 5c'), wild), MeldKind.sequence, reason: 'wild five fills the gap');
    expect(classify(cs('7d JK 9d Td'), wild), MeldKind.sequence);
    expect(classify(cs('8h 8s 8d'), wild), MeldKind.set);
    expect(classify(cs('8h 8s JK'), wild), MeldKind.set);
    expect(classify(cs('8h 8h 8d'), wild), MeldKind.invalid, reason: 'two of one suit');
    expect(classify(cs('8h 8s'), wild), MeldKind.invalid, reason: 'too short');
  });

  test('declaration needs two sequences, one pure', () {
    final good = [cs('4h 5h 6h'), cs('7d JK 9d'), cs('8h 8s 8c'), cs('Kd Ks Kc Kh')];
    expect(isValidDeclaration(good, wild), isTrue);
    final noPure = [cs('4h JK 6h'), cs('7d JK 9d'), cs('8h 8s 8c'), cs('Kd Ks Kc Kh')];
    expect(isValidDeclaration(noPure, wild), isFalse);
    final oneSeq = [cs('4h 5h 6h'), cs('9s 9d 9c'), cs('8h 8s 8c'), cs('Kd Ks Kc Kh')];
    expect(isValidDeclaration(oneSeq, wild), isFalse);
  });

  test('arrange finds a complete hand', () {
    final hand = cs('6h 7d 8h 8s 8c Kd Ks 4h 9d JK Kc 5h Kh');
    final a = arrange(hand, wild);
    expect(a.complete, isTrue);
    expect(a.points, 0);
  });

  test('points: no pure sequence → every card counts (capped at 80)', () {
    final hand = cs('Ks Qd Jc Th 9s 8d 7c 6h 4s 3d 2c Ad Ah');
    expect(handPoints(hand, wild), 80);
    final low = cs('2s 3d 4c 2h 3s 4d 2c 3h 4s 6d 7c 6h 7s');
    expect(handPoints(low, wild), lessThanOrEqualTo(80));
  });

  test('points: one pure sequence only exempts that sequence', () {
    // Pure 2-3-4♠; the rest makes no other sequence or set.
    final hand = cs('2s 3s 4s 6h 9h 7d Td 8c 2c 4d 3c 6c Jd');
    final total = hand.fold(0, (a, x) => a + RummyRules.points(x, wild));
    expect(total - 9, lessThan(80));
    expect(handPoints(hand, wild), total - 9);
  });

  test('solver is quick enough for a turn', () {
    final rng = math.Random(7);
    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      final deck = shuffledDeck(rng, decks: 2, jokers: 2);
      handPoints(deck.take(14).toList(), 1 + rng.nextInt(13));
    }
    expect(sw.elapsedMilliseconds / 20, lessThan(150));
  });

  test('a deal: draw, discard, drop', () {
    final g = RummyGame(
      players: [RummyPlayer(name: 'You', initials: 'YO', isYou: true), RummyPlayer(name: 'Nova', initials: 'NV')],
      rng: math.Random(3),
    );
    expect(g.players.every((p) => p.hand.length == 13), isTrue);
    final before = g.discard.length;
    g.draw(fromDiscard: false);
    g.discardCard(g.current.hand.first);
    expect(g.discard.length, before + 1);
    g.drop(); // the next player drops before drawing
    expect(g.over, isTrue);
    expect(g.players.firstWhere((p) => p.dropped).score, RummyRules.firstDrop);
  });
}
