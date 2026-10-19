import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The four card colours.
enum UnoColor { red, yellow, green, blue }

enum UnoKind { number, skip, reverse, drawTwo, wild, wildDrawFour }

/// One card. [id] makes the two copies of e.g. "red 7" distinct.
@immutable
class UnoCard {
  const UnoCard(this.id, this.kind, {this.color, this.number});

  final int id;
  final UnoKind kind;

  /// null for wild cards.
  final UnoColor? color;

  /// 0–9 for number cards.
  final int? number;

  bool get isWild => kind == UnoKind.wild || kind == UnoKind.wildDrawFour;

  /// Points it scores for the winner: face value, 20 for actions, 50 wild.
  int get points => switch (kind) {
    UnoKind.number => number!,
    UnoKind.skip || UnoKind.reverse || UnoKind.drawTwo => 20,
    UnoKind.wild || UnoKind.wildDrawFour => 50,
  };

  /// "7", "Skip", "+2", "Wild", "+4" (the colour is shown separately).
  String get label => switch (kind) {
    UnoKind.number => '$number',
    UnoKind.skip => 'Skip',
    UnoKind.reverse => 'Reverse',
    UnoKind.drawTwo => '+2',
    UnoKind.wild => 'Wild',
    UnoKind.wildDrawFour => 'Wild +4',
  };

  @override
  bool operator ==(Object other) => other is UnoCard && other.id == id;

  @override
  int get hashCode => id;

  @override
  String toString() => color == null ? label : '${color!.name} $label';
}

abstract final class UnoRules {
  static const handSize = 7;

  /// Forgot to call "UNO" with one card left: draw this many.
  static const unoPenalty = 2;

  /// The 108-card deck: per colour one 0, two each of 1–9, Skip, Reverse
  /// and +2; plus four Wild and four Wild +4.
  static List<UnoCard> deck() {
    final out = <UnoCard>[];
    var id = 0;
    for (final c in UnoColor.values) {
      out.add(UnoCard(id++, UnoKind.number, color: c, number: 0));
      for (var copy = 0; copy < 2; copy++) {
        for (var n = 1; n <= 9; n++) {
          out.add(UnoCard(id++, UnoKind.number, color: c, number: n));
        }
        for (final k in const [UnoKind.skip, UnoKind.reverse, UnoKind.drawTwo]) {
          out.add(UnoCard(id++, k, color: c));
        }
      }
    }
    for (var i = 0; i < 4; i++) {
      out.add(UnoCard(id++, UnoKind.wild));
      out.add(UnoCard(id++, UnoKind.wildDrawFour));
    }
    return out;
  }

  /// Can [card] go on [top] when the colour in play is [color]?
  static bool canPlay(UnoCard card, UnoCard top, UnoColor color) {
    if (card.isWild) return true;
    if (card.color == color) return true;
    if (card.kind == UnoKind.number) {
      return top.kind == UnoKind.number && top.number == card.number;
    }
    return card.kind == top.kind;
  }
}

/// What a turn did — the screen turns it into a line of text.
sealed class UnoEvent {
  const UnoEvent(this.seat);
  final int seat;
}

class UnoPlayed extends UnoEvent {
  const UnoPlayed(super.seat, this.card, {this.chosen, this.saidUno = false});
  final UnoCard card;

  /// The colour named with a wild.
  final UnoColor? chosen;
  final bool saidUno;
}

class UnoDrew extends UnoEvent {
  const UnoDrew(super.seat, this.count, {this.forced = false});
  final int count;

  /// Made to draw by a +2 / +4 (and lost the turn).
  final bool forced;
}

class UnoPassed extends UnoEvent {
  const UnoPassed(super.seat);
}

/// Went down to one card without calling "UNO": drew the penalty.
class UnoCaught extends UnoEvent {
  const UnoCaught(super.seat);
}

class UnoSkipped extends UnoEvent {
  const UnoSkipped(super.seat);
}

/// One round of Uno: deal 7 each, match colour / number / symbol, first to
/// empty their hand wins and scores everyone else's cards.
class UnoGame extends ChangeNotifier {
  UnoGame({required int players, math.Random? rng}) : _rng = rng ?? math.Random() {
    assert(players >= 2 && players <= 4);
    _draw = UnoRules.deck()..shuffle(_rng);
    hands = [for (var p = 0; p < players; p++) <UnoCard>[]];
    for (var i = 0; i < UnoRules.handSize; i++) {
      for (final h in hands) {
        h.add(_draw.removeLast());
      }
    }
    // The first card turned up is a number card (action / wild cards go
    // back into the pile — keeps the opening simple and fair).
    while (true) {
      final c = _draw.removeLast();
      if (c.kind == UnoKind.number) {
        discard.add(c);
        color = c.color!;
        break;
      }
      _draw.insert(_rng.nextInt(_draw.length + 1), c);
    }
  }

  final math.Random _rng;
  late List<UnoCard> _draw;
  late final List<List<UnoCard>> hands;
  final List<UnoCard> discard = [];

  /// The colour in play (a wild's named colour, else the top card's).
  late UnoColor color;

  int turn = 0;

  /// +1 clockwise, -1 after a Reverse.
  int direction = 1;

  /// The current player drew and may play [drawn] (else pass).
  UnoCard? drawn;

  int? winner;
  int moves = 0;

  /// Everything that happened in the last action (in order).
  List<UnoEvent> events = const [];

  int get players => hands.length;
  bool get isOver => winner != null;
  UnoCard get top => discard.last;
  int get drawPileCount => _draw.length;

  int next([int from = -1, int steps = 1]) {
    final f = from < 0 ? turn : from;
    return ((f + direction * steps) % players + players) % players;
  }

  bool canPlay(UnoCard c) => UnoRules.canPlay(c, top, color);

  /// The current player's legal cards (only the drawn one after a draw).
  List<UnoCard> playable([int? seat]) {
    final s = seat ?? turn;
    if (s == turn && drawn != null) {
      return canPlay(drawn!) ? [drawn!] : const [];
    }
    return hands[s].where(canPlay).toList();
  }

  List<UnoCard> _take(int n) {
    final out = <UnoCard>[];
    for (var i = 0; i < n; i++) {
      if (_draw.isEmpty) {
        // Reshuffle everything under the top card.
        if (discard.length <= 1) break;
        final keep = discard.removeLast();
        _draw = discard.toList()..shuffle(_rng);
        discard
          ..clear()
          ..add(keep);
      }
      out.add(_draw.removeLast());
    }
    return out;
  }

  /// Play [card] from the current hand. Wilds need [chosen]. [saidUno] =
  /// the player called "UNO" (only matters going down to one card).
  void play(UnoCard card, {UnoColor? chosen, bool saidUno = false}) {
    if (isOver) return;
    final hand = hands[turn];
    assert(hand.contains(card) && playable().contains(card), 'illegal play $card');
    assert(!card.isWild || chosen != null, 'a wild needs a colour');
    final ev = <UnoEvent>[];
    hand.remove(card);
    discard.add(card);
    drawn = null;
    moves++;
    color = card.isWild ? chosen! : card.color!;
    ev.add(UnoPlayed(turn, card, chosen: card.isWild ? chosen : null, saidUno: saidUno && hand.length == 1));
    if (hand.isEmpty) {
      winner = turn;
      events = ev;
      notifyListeners();
      return;
    }
    if (hand.length == 1 && !saidUno) {
      hand.addAll(_take(UnoRules.unoPenalty));
      ev.add(UnoCaught(turn));
    }
    switch (card.kind) {
      case UnoKind.skip:
        ev.add(UnoSkipped(next()));
        turn = next(turn, 2);
      case UnoKind.reverse:
        direction = -direction;
        if (players == 2) {
          // Two players: Reverse works like Skip.
          ev.add(UnoSkipped(next()));
          turn = next(turn, 2);
        } else {
          turn = next();
        }
      case UnoKind.drawTwo || UnoKind.wildDrawFour:
        final victim = next();
        hands[victim].addAll(_take(card.kind == UnoKind.drawTwo ? 2 : 4));
        ev.add(UnoDrew(victim, card.kind == UnoKind.drawTwo ? 2 : 4, forced: true));
        turn = next(turn, 2);
      case UnoKind.number || UnoKind.wild:
        turn = next();
    }
    events = ev;
    notifyListeners();
  }

  /// Draw one card. If it can't be played the turn passes straight away;
  /// otherwise [drawn] is set and the player plays it or [pass]es.
  UnoCard? draw() {
    if (isOver || drawn != null) return null;
    final got = _take(1);
    moves++;
    if (got.isEmpty) {
      // Nothing left to draw anywhere: just pass.
      events = [UnoPassed(turn)];
      turn = next();
      notifyListeners();
      return null;
    }
    final c = got.single;
    hands[turn].add(c);
    events = [UnoDrew(turn, 1)];
    if (canPlay(c)) {
      drawn = c;
    } else {
      turn = next();
    }
    notifyListeners();
    return c;
  }

  /// Keep the drawn card and end the turn.
  void pass() {
    if (drawn == null || isOver) return;
    drawn = null;
    events = [UnoPassed(turn)];
    turn = next();
    notifyListeners();
  }

  /// What the winner scores: everyone else's cards.
  int get winnerPoints => [
    for (var p = 0; p < players; p++)
      if (p != winner) ...hands[p],
  ].fold(0, (a, c) => a + c.points);

  int handPoints(int seat) => hands[seat].fold(0, (a, c) => a + c.points);
}

/// The computer's choice for its turn: a card (and colour for a wild), or
/// null to draw / pass. Higher [difficulty] keeps wilds back, punishes a
/// player about to go out, and names its strongest colour.
({UnoCard? card, UnoColor? color, bool sayUno}) unoBotMove(UnoGame g, int difficulty, math.Random rng) {
  final seat = g.turn;
  final hand = g.hands[seat];
  final options = g.playable(seat);
  // Easy sometimes forgets to call UNO.
  final sayUno = hand.length == 2 && (difficulty >= 2 || rng.nextDouble() < 0.6);
  if (options.isEmpty) return (card: null, color: null, sayUno: false);

  UnoColor bestColor(Iterable<UnoCard> rest) {
    final counts = {for (final c in UnoColor.values) c: 0};
    for (final c in rest) {
      if (c.color != null) {
        counts[c.color!] = counts[c.color!]! + (difficulty >= 3 ? c.points + 1 : 1);
      }
    }
    final most = counts.values.reduce(math.max);
    if (most == 0) return UnoColor.values[rng.nextInt(4)];
    final ties = counts.entries.where((e) => e.value == most).map((e) => e.key).toList();
    return ties[rng.nextInt(ties.length)];
  }

  UnoCard pick;
  if (difficulty <= 1) {
    pick = options[rng.nextInt(options.length)];
  } else {
    final nextHand = g.hands[g.next(seat)].length;
    double score(UnoCard c) {
      var s = 0.0;
      // Save wilds for when they're needed.
      if (c.isWild) s -= 40;
      if (c.kind == UnoKind.wildDrawFour) s -= 10;
      // Get rid of high cards first.
      s += c.points * 0.4;
      if (c.color != null) {
        s += hand.where((h) => h.color == c.color).length * 2;
      }
      // Next player is about to go out: hit them.
      if (nextHand <= 2) {
        if (c.kind == UnoKind.drawTwo || c.kind == UnoKind.wildDrawFour) {
          s += difficulty >= 3 ? 90 : 50;
        }
        if (c.kind == UnoKind.skip || c.kind == UnoKind.reverse) {
          s += difficulty >= 3 ? 60 : 30;
        }
      }
      return s + rng.nextDouble() * (difficulty >= 3 ? 2 : 6);
    }

    pick = options.reduce((a, b) => score(a) >= score(b) ? a : b);
  }
  return (card: pick, color: pick.isWild ? bestColor(hand.where((c) => c != pick)) : null, sayUno: sayUno);
}
