import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/common/playing_cards.dart';
import 'package:snakeladder/game/poker/poker_engine.dart';

PlayingCard c(String s) {
  const ranks = {'A': 1, 'K': 13, 'Q': 12, 'J': 11, 'T': 10};
  final r = ranks[s[0]] ?? int.parse(s[0]);
  final suit = {'s': Suit.spades, 'h': Suit.hearts, 'd': Suit.diamonds, 'c': Suit.clubs}[s[1]]!;
  return PlayingCard(r, suit);
}

List<PlayingCard> cs(String s) => s.split(' ').map(c).toList();

void main() {
  test('hand categories', () {
    expect(evaluateBest(cs('As Ks Qs Js Ts 2c 3d')).name, 'Royal flush');
    expect(evaluateBest(cs('9h 9d 9s 9c Kd 2c 3d')).name, 'Four of a kind');
    expect(evaluateBest(cs('9h 9d 9s Kc Kd 2c 3d')).name, 'Full house');
    expect(evaluateBest(cs('2h 7h 9h Jh Kh 2c 3d')).name, 'Flush');
    expect(evaluateBest(cs('Ah 2d 3s 4c 5d Kc Qd')).name, 'Straight');
    expect(evaluateBest(cs('Ah 2d 3s 4c 5d Kc Qd')).ranks, [5], reason: 'the wheel is five-high');
    expect(evaluateBest(cs('8h 8d 3s 3c Ad Kc Qd')).name, 'Two pair');
    expect(evaluateBest(cs('Ah 9d 7s 5c 3d 2c Jd')).name, 'High card');
  });

  test('comparisons and kickers', () {
    final aceKicker = evaluateBest(cs('Kh Kd As 7c 4d 3c 2d'));
    final queenKicker = evaluateBest(cs('Kc Ks Qs 7h 4h 3s 2s'));
    expect(aceKicker > queenKicker, isTrue);
    expect(evaluateBest(cs('Ah Kh Qh Jh 9h 2c 3d')) > evaluateBest(cs('Td Jd Qc Kd As 2c 3d')), isTrue, reason: 'flush beats straight');
  });

  test('equity: aces are big favourites heads-up preflop', () {
    final e = estimateEquity(cs('As Ah'), const [], 1, math.Random(1), iterations: 600);
    expect(e, inInclusiveRange(0.78, 0.9));
  });

  test('blinds, folds and an uncontested pot', () {
    final players = [
      PokerPlayer(name: 'You', initials: 'YO', chips: 1000, isYou: true),
      PokerPlayer(name: 'Nova', initials: 'NV', chips: 1000),
    ];
    final g = PokerGame(players: players, smallBlind: 10, rng: math.Random(2))..startHand();
    expect(g.pot, 30);
    g.act(PokerMove.fold);
    expect(g.handOver, isTrue);
    expect(players.fold(0, (a, p) => a + p.chips), 2000, reason: 'chips are conserved');
  });

  test('side pots: a short all-in wins only what it covered', () {
    final players = [
      PokerPlayer(name: 'You', initials: 'YO', chips: 100, isYou: true),
      PokerPlayer(name: 'A', initials: 'AA', chips: 1000),
      PokerPlayer(name: 'B', initials: 'BB', chips: 1000),
    ];
    final g = PokerGame(players: players, smallBlind: 10, rng: math.Random(5))..startHand();
    // Everyone goes all-in / calls until the hand is decided.
    var guard = 0;
    while (!g.handOver && guard++ < 50) {
      if (g.roundComplete) {
        g.nextStreet();
        continue;
      }
      g.act(g.current.chips > 0 ? PokerMove.allIn : PokerMove.call);
    }
    expect(g.handOver, isTrue);
    expect(players.fold(0, (a, p) => a + p.chips), 2100, reason: 'chips are conserved');
    expect(players[0].chips, anyOf(0, 300, inInclusiveRange(100, 300)), reason: 'the short stack wins at most 3 × 100');
  });

  test('a full betting round reaches the flop', () {
    final players = [
      PokerPlayer(name: 'You', initials: 'YO', chips: 1000, isYou: true),
      PokerPlayer(name: 'A', initials: 'AA', chips: 1000),
      PokerPlayer(name: 'B', initials: 'BB', chips: 1000),
    ];
    final g = PokerGame(players: players, smallBlind: 10, rng: math.Random(9))..startHand();
    while (!g.roundComplete) {
      g.act(g.toCall(g.current) == 0 ? PokerMove.check : PokerMove.call);
    }
    g.nextStreet();
    expect(g.stage, PokerStage.flop);
    expect(g.board.length, 3);
    expect(g.pot, 60);
  });
}
