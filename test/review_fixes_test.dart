import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/chess/chess_engine.dart';
import 'package:snakeladder/game/common/playing_cards.dart';
import 'package:snakeladder/game/crash/crash_engine.dart';
import 'package:snakeladder/game/poker/poker_engine.dart';
import 'package:snakeladder/game/racing/racing_engine.dart';
import 'package:snakeladder/game/rummy/rummy_engine.dart';
import 'package:snakeladder/game/uno/uno_engine.dart';

/// Always returns [v] / 0 — pins the crash point.
class _FixedRng implements math.Random {
  _FixedRng(this.v);
  final double v;
  @override
  double nextDouble() => v;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

void main() {
  group('crash', () {
    test('a long frame past the crash still pays an auto cash-out below it', () {
      final g = CrashGame(rng: _FixedRng(0.5), balance: 1000); // crash at 1.98×
      g
        ..setAuto(0, 1.5)
        ..toggleBet(0);
      final t0 = DateTime.now();
      g.tick(t0.add(const Duration(seconds: 7))); // flight starts
      g.tick(t0.add(const Duration(seconds: 17))); // one huge frame
      expect(g.phase, CrashPhase.crashed);
      expect(g.crashPoint, 1.98);
      expect(g.bets[0].cashedAt, 1.5);
      expect(g.balance, 1000 - 50 + 75);
    });

    test('an auto target equal to the crash point pays', () {
      final g = CrashGame(rng: _FixedRng(0.5), balance: 1000); // crash at 1.98×
      g
        ..setAuto(0, 1.98)
        ..toggleBet(0);
      final t0 = DateTime.now();
      g.tick(t0.add(const Duration(seconds: 7)));
      g.tick(t0.add(const Duration(seconds: 17)));
      expect(g.bets[0].cashedAt, 1.98);
      expect(g.balance, 1000 - 50 + 99);
    });

    test('an auto target above the crash point still loses', () {
      final g = CrashGame(rng: _FixedRng(0.5), balance: 1000);
      g
        ..setAuto(0, 2.5)
        ..toggleBet(0);
      final t0 = DateTime.now();
      g.tick(t0.add(const Duration(seconds: 7)));
      g.tick(t0.add(const Duration(seconds: 17)));
      expect(g.bets[0].cashedAt, isNull);
      expect(g.balance, 950);
    });
  });

  test('poker: a short all-in does not reopen raising for players who acted', () {
    final g = PokerGame(
      players: [
        PokerPlayer(name: 'You', initials: 'YO', chips: 1000, isYou: true),
        PokerPlayer(name: 'A', initials: 'AA', chips: 1000),
        PokerPlayer(name: 'B', initials: 'BB', chips: 1000),
      ],
      smallBlind: 10,
      rng: math.Random(3),
    )..startHand();
    while (!g.roundComplete) {
      g.act(g.toCall(g.current) == 0 ? PokerMove.check : PokerMove.call);
    }
    g.nextStreet();

    final opener = g.current;
    g.act(PokerMove.raise, raiseTo: 100);
    final short = g.current..chips = 130; // all-in to 130: 30 more, under the 100 minimum
    g.act(PokerMove.allIn);
    expect(short.allIn, isTrue);
    expect(g.currentBet, 130);
    final third = g.current;
    expect(g.canRaise(third), isTrue, reason: 'had not acted yet this street');
    g.act(PokerMove.call);

    expect(g.current, same(opener));
    expect(g.canRaise(opener), isFalse);
    g.act(PokerMove.raise, raiseTo: 600); // treated as a call
    expect(opener.bet, 130);
    expect(g.currentBet, 130);
    expect(g.roundComplete, isTrue);
  });

  group('uno: Wild +4 only without a card of the colour in play', () {
    UnoGame setUp(List<UnoCard> hand) {
      final g = UnoGame(players: 2, rng: math.Random(1));
      g.discard.add(const UnoCard(900, UnoKind.number, color: UnoColor.red, number: 5));
      g.color = UnoColor.red;
      g.hands[g.turn]
        ..clear()
        ..addAll(hand);
      return g;
    }

    const four = UnoCard(901, UnoKind.wildDrawFour);
    test('holding red: not playable', () {
      final g = setUp([four, const UnoCard(902, UnoKind.number, color: UnoColor.red, number: 7)]);
      expect(g.playable(), isNot(contains(four)));
    });
    test('no red: playable', () {
      final g = setUp([four, const UnoCard(903, UnoKind.number, color: UnoColor.blue, number: 7)]);
      expect(g.playable(), contains(four));
    });
  });

  test('chess: en passant only counts for repetition when a capture is possible', () {
    final noCapture = ChessState.fromFen('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1');
    expect(noCapture.positionKey.split(' ')[3], '-');
    final capture = ChessState.fromFen('rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1');
    expect(capture.positionKey.split(' ')[3], 'e3');
  });

  group('rummy', () {
    RummyGame newGame() => RummyGame(
      players: [
        RummyPlayer(name: 'You', initials: 'YO', isYou: true),
        RummyPlayer(name: 'A', initials: 'AA'),
      ],
      rng: math.Random(5),
    );

    test('a valid-looking declaration of cards not in hand is a wrong show', () {
      final g = newGame()..draw(fromDiscard: false);
      final seat = g.turn;
      PlayingCard h(int r) => PlayingCard(r, Suit.hearts, deck: 1);
      PlayingCard s(int r) => PlayingCard(r, Suit.spades, deck: 1);
      PlayingCard cl(int r) => PlayingCard(r, Suit.clubs, deck: 1);
      PlayingCard d(int r) => PlayingCard(r, Suit.diamonds, deck: 1);
      final forged = [
        [h(1), h(2), h(3), h(4)],
        [s(5), s(6), s(7)],
        [cl(9), cl(10), cl(11)],
        [d(12), d(13), d(1)],
      ];
      expect(isValidDeclaration(forged, g.wildRank), isTrue);
      expect(g.declare(g.current.hand.last, forged), isFalse);
      expect(g.wrongShow, seat);
    });

    test('dropping after a draw returns the drawn card, even if the hand was reordered', () {
      final g = newGame();
      final drawn = g.draw(fromDiscard: false);
      g.current.hand.sort((a, b) => b.rank - a.rank);
      final p = g.current;
      g.drop();
      expect(g.discard.last, drawn);
      expect(p.hand, isNot(contains(drawn)));
    });
  });

  group('racing: live standings', () {
    test('neck-and-neck cars keep their places; the order still ends exact', () {
      for (var seed = 0; seed < 30; seed++) {
        final g = RacingGame(rng: math.Random(seed), balance: 1000)..start();
        List<int>? shown;
        for (var f = 0; f < 60 * 13; f++) {
          final t = f / 60;
          final next = g.stableStandings(t, shown);
          if (shown != null) {
            // Two running cars only swap when the new leader is truly ahead.
            for (var i = 0; i < next.length; i++) {
              for (var j = i + 1; j < next.length; j++) {
                final up = next[i], down = next[j];
                final swapped = shown.indexOf(up) > shown.indexOf(down);
                if (swapped && g.runs[up].finishAt > t && g.runs[down].finishAt > t) {
                  expect(g.runs[up].at(t), greaterThan(g.runs[down].at(t)));
                }
              }
            }
          }
          shown = next;
        }
        expect(shown, g.order);
      }
    });

    test('a tiny lead does not reorder', () {
      final g = RacingGame(rng: math.Random(1), balance: 1000)..start();
      const t = 5.0;
      final exact = g.standings(t);
      final a = exact[0], b = exact[1];
      final gap = g.runs[a].at(t) - g.runs[b].at(t);
      final previous = [b, a, ...exact.skip(2)];
      final shown = g.stableStandings(t, previous, margin: gap + 0.001);
      expect(shown.take(2), [b, a], reason: 'within the margin: keep the shown order');
      expect(g.stableStandings(t, previous, margin: 0).take(2), [a, b]);
    });
  });
}
