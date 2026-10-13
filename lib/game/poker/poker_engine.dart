import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../common/playing_cards.dart';

// ── Hand evaluation ──

/// A made hand: category (0 high card … 8 straight flush), tie-break ranks
/// (aces high = 14) and the five cards that make it.
@immutable
class HandValue implements Comparable<HandValue> {
  const HandValue(this.category, this.ranks, this.cards);
  final int category;
  final List<int> ranks;
  final List<PlayingCard> cards;

  static const names = [
    'High card', 'Pair', 'Two pair', 'Three of a kind', 'Straight', //
    'Flush', 'Full house', 'Four of a kind', 'Straight flush',
  ];

  String get name => category == 8 && ranks.first == 14 ? 'Royal flush' : names[category];

  @override
  int compareTo(HandValue o) {
    if (category != o.category) return category.compareTo(o.category);
    for (var i = 0; i < math.min(ranks.length, o.ranks.length); i++) {
      if (ranks[i] != o.ranks[i]) return ranks[i].compareTo(o.ranks[i]);
    }
    return 0;
  }

  bool operator >(HandValue o) => compareTo(o) > 0;
}

int pokerValue(PlayingCard c) => c.rank == 1 ? 14 : c.rank;

/// Exactly five cards.
HandValue evaluate5(List<PlayingCard> cards) {
  final v = cards.map(pokerValue).toList()..sort((a, b) => b - a);
  final flush = cards.every((c) => c.suit == cards.first.suit);
  final distinct = v.toSet().toList()..sort((a, b) => b - a);
  int? straightHigh;
  if (distinct.length == 5) {
    if (distinct.first - distinct.last == 4) straightHigh = distinct.first;
    if (distinct.first == 14 && distinct[1] == 5) straightHigh = 5; // wheel A-2-3-4-5
  }
  final counts = <int, int>{};
  for (final x in v) {
    counts[x] = (counts[x] ?? 0) + 1;
  }
  // Ranks ordered by (count, rank) descending.
  final groups = counts.keys.toList()..sort((a, b) => counts[b] != counts[a] ? counts[b]! - counts[a]! : b - a);
  final shape = [for (final g in groups) counts[g]!];
  if (straightHigh != null && flush) return HandValue(8, [straightHigh], cards);
  if (shape.first == 4) return HandValue(7, groups, cards);
  if (shape.first == 3 && shape[1] == 2) return HandValue(6, groups, cards);
  if (flush) return HandValue(5, v, cards);
  if (straightHigh != null) return HandValue(4, [straightHigh], cards);
  if (shape.first == 3) return HandValue(3, groups, cards);
  if (shape.first == 2 && shape[1] == 2) return HandValue(2, groups, cards);
  if (shape.first == 2) return HandValue(1, groups, cards);
  return HandValue(0, v, cards);
}

/// The best five of five to seven cards.
HandValue evaluateBest(List<PlayingCard> cards) {
  if (cards.length <= 5) return evaluate5(cards);
  HandValue? best;
  final pick = <PlayingCard>[];
  void choose(int start) {
    if (pick.length == 5) {
      final h = evaluate5(List.of(pick));
      if (best == null || h > best!) best = h;
      return;
    }
    for (var i = start; i <= cards.length - (5 - pick.length); i++) {
      pick.add(cards[i]);
      choose(i + 1);
      pick.removeLast();
    }
  }

  choose(0);
  return best!;
}

/// Chance [hole] wins (ties count as a share) against [opponents] random
/// hands given the [board] so far, by Monte Carlo over the unseen cards.
double estimateEquity(List<PlayingCard> hole, List<PlayingCard> board, int opponents, math.Random rng, {int iterations = 220}) {
  final known = {...hole, ...board};
  final deck = [
    for (final s in Suit.values)
      for (var r = 1; r <= 13; r++)
        if (!known.contains(PlayingCard(r, s))) PlayingCard(r, s),
  ];
  var score = 0.0;
  for (var it = 0; it < iterations; it++) {
    // Partial shuffle: just the cards needed.
    final need = opponents * 2 + (5 - board.length);
    for (var i = 0; i < need; i++) {
      final j = i + rng.nextInt(deck.length - i);
      final t = deck[i];
      deck[i] = deck[j];
      deck[j] = t;
    }
    var k = 0;
    final full = [...board, for (var i = board.length; i < 5; i++) deck[k++]];
    final mine = evaluateBest([...hole, ...full]);
    var best = true, ties = 1;
    for (var o = 0; o < opponents && best; o++) {
      final theirs = evaluateBest([deck[k++], deck[k++], ...full]);
      final c = theirs.compareTo(mine);
      if (c > 0) best = false;
      if (c == 0) ties++;
    }
    if (best) score += 1 / ties;
  }
  return score / iterations;
}

// ── The table ──

enum PokerStage { preflop, flop, turn, river, showdown }

enum PokerMove { fold, check, call, raise, allIn }

class PokerPlayer {
  PokerPlayer({required this.name, required this.initials, required this.chips, this.isYou = false});
  final String name;
  final String initials;
  final bool isYou;
  int chips;
  List<PlayingCard> hole = const [];
  bool folded = false;
  bool allIn = false;

  /// Chips put in on this street / this hand.
  int bet = 0;
  int contributed = 0;
  bool acted = false;

  /// Shown above the seat ("Raise 120", "Check"…).
  String? lastAction;
  int handsWon = 0;

  bool get busted => chips == 0 && contributed == 0;
  bool get inHand => !folded && hole.isNotEmpty;
  bool get canAct => inHand && !allIn;
}

/// One pot paid out at the end of a hand.
@immutable
class PotAward {
  const PotAward(this.amount, this.winners, this.hand);
  final int amount;
  final List<int> winners;

  /// The winning hand (null when everyone else folded).
  final HandValue? hand;
}

/// No-limit Texas Hold'em at one table: blinds, four betting rounds, side
/// pots and showdowns. The screen drives the pacing: after each action it
/// checks [roundComplete] and calls [nextStreet]; at [handOver] it shows the
/// result and calls [startHand].
class PokerGame extends ChangeNotifier {
  PokerGame({required this.players, required this.smallBlind, math.Random? rng}) : _rng = rng ?? math.Random() {
    dealer = _rng.nextInt(players.length);
  }

  final List<PokerPlayer> players;
  final int smallBlind;
  int get bigBlind => smallBlind * 2;
  final math.Random _rng;

  int dealer = 0;
  int handNo = 0;
  PokerStage stage = PokerStage.preflop;
  List<PlayingCard> deck = const [];
  final List<PlayingCard> board = [];
  int toAct = 0;
  int currentBet = 0;
  int minRaise = 0;
  bool handOver = false;
  List<PotAward> awards = const [];

  int get pot => players.fold(0, (a, p) => a + p.contributed);
  PokerPlayer get current => players[toAct];
  PokerPlayer get you => players.first;
  int toCall(PokerPlayer p) => math.max(0, currentBet - p.bet);

  /// Smallest legal raise target and the most [p] can put in (all-in).
  int minRaiseTo(PokerPlayer p) => math.min(currentBet + minRaise, p.chips + p.bet);
  int maxRaiseTo(PokerPlayer p) => p.chips + p.bet;

  Iterable<int> get _seated sync* {
    for (var i = 0; i < players.length; i++) {
      if (players[i].chips > 0) yield i;
    }
  }

  /// Players still holding cards.
  int get liveCount => players.where((p) => p.inHand).length;

  /// The game ends when you're out of chips or nobody else has any.
  bool get gameOver => handOver && (you.chips == 0 || players.where((p) => p.chips > 0).length < 2);

  int _next(int from, bool Function(PokerPlayer) ok) {
    for (var k = 1; k <= players.length; k++) {
      final i = (from + k) % players.length;
      if (ok(players[i])) return i;
    }
    return from;
  }

  void startHand() {
    handNo++;
    handOver = false;
    awards = const [];
    board.clear();
    stage = PokerStage.preflop;
    deck = shuffledDeck(_rng);
    for (final p in players) {
      p
        ..hole = const []
        ..folded = p.chips == 0
        ..allIn = false
        ..bet = 0
        ..contributed = 0
        ..acted = false
        ..lastAction = null;
    }
    dealer = _next(dealer, (p) => p.chips > 0);
    final seated = _seated.toList();
    final headsUp = seated.length == 2;
    final sb = headsUp ? dealer : _next(dealer, (p) => p.chips > 0);
    final bb = _next(sb, (p) => p.chips > 0);
    for (final i in seated) {
      players[i].hole = [deck.removeLast(), deck.removeLast()];
    }
    _post(players[sb], smallBlind);
    _post(players[bb], bigBlind);
    currentBet = bigBlind;
    minRaise = bigBlind;
    toAct = _next(bb, (p) => p.canAct);
    notifyListeners();
  }

  void _post(PokerPlayer p, int amount) {
    final a = math.min(amount, p.chips);
    p
      ..chips -= a
      ..bet += a
      ..contributed += a;
    if (p.chips == 0) p.allIn = true;
  }

  /// [p] acts. For raise, [raiseTo] is the total bet this street.
  void act(PokerMove move, {int raiseTo = 0}) {
    final p = current;
    switch (move) {
      case PokerMove.fold:
        p
          ..folded = true
          ..lastAction = 'Fold';
      case PokerMove.check:
        assert(toCall(p) == 0);
        p.lastAction = 'Check';
      case PokerMove.call:
        final a = math.min(toCall(p), p.chips);
        _post(p, a);
        p.lastAction = p.allIn ? 'All-in' : 'Call ${_fmt(a)}';
      case PokerMove.raise || PokerMove.allIn:
        final target = move == PokerMove.allIn ? maxRaiseTo(p) : raiseTo.clamp(minRaiseTo(p), maxRaiseTo(p));
        final raiseBy = target - currentBet;
        _post(p, target - p.bet);
        if (target > currentBet) {
          // A full raise reopens the betting; a short all-in doesn't change
          // the minimum raise.
          if (raiseBy >= minRaise) minRaise = raiseBy;
          currentBet = target;
          for (final o in players) {
            if (o != p && o.canAct) o.acted = false;
          }
        }
        p.lastAction = p.allIn ? 'All-in' : (currentBet == target && raiseBy > 0 ? 'Raise ${_fmt(target)}' : 'Call');
    }
    p.acted = true;
    if (liveCount == 1) {
      _awardUncontested();
    } else if (!roundComplete) {
      toAct = _next(toAct, (o) => o.canAct);
    }
    notifyListeners();
  }

  /// Everyone still able to act has acted and matched the bet (a lone
  /// player with nothing to call doesn't act against all-in opponents).
  bool get roundComplete {
    if (handOver) return false;
    final actors = players.where((p) => p.canAct).toList();
    if (actors.isEmpty) return true;
    if (actors.length == 1 && actors.first.bet >= currentBet) return true;
    return actors.every((p) => p.acted && p.bet == currentBet);
  }

  /// Nobody can bet any more (all-in): deal the rest without stopping.
  bool get runningOut => players.where((p) => p.canAct).length <= 1 && liveCount > 1;

  /// Close the betting round and deal the next street (or show down).
  void nextStreet() {
    for (final p in players) {
      p
        ..bet = 0
        ..acted = false;
      if (p.inHand && !p.allIn) p.lastAction = null;
    }
    currentBet = 0;
    minRaise = bigBlind;
    switch (stage) {
      case PokerStage.preflop:
        board.addAll([deck.removeLast(), deck.removeLast(), deck.removeLast()]);
        stage = PokerStage.flop;
      case PokerStage.flop:
        board.add(deck.removeLast());
        stage = PokerStage.turn;
      case PokerStage.turn:
        board.add(deck.removeLast());
        stage = PokerStage.river;
      case PokerStage.river || PokerStage.showdown:
        _showdown();
        notifyListeners();
        return;
    }
    toAct = _next(dealer, (p) => p.canAct);
    notifyListeners();
  }

  void _awardUncontested() {
    final w = players.indexWhere((p) => p.inHand);
    final amount = pot;
    players[w].chips += amount;
    players[w].handsWon++;
    awards = [PotAward(amount, [w], null)];
    _endHand();
  }

  /// Split the pot into main and side pots by contribution level and pay
  /// each to the best hand among the players who put in that much.
  void _showdown() {
    stage = PokerStage.showdown;
    final values = {for (var i = 0; i < players.length; i++) if (players[i].inHand) i: evaluateBest([...players[i].hole, ...board])};
    final levels = {for (final p in players) if (p.contributed > 0) p.contributed}.toList()..sort();
    final out = <PotAward>[];
    var prev = 0;
    for (final level in levels) {
      final amount = players.fold(0, (a, p) => a + math.max(0, math.min(p.contributed, level) - prev));
      final eligible = [for (final i in values.keys) if (players[i].contributed >= level) i];
      final contributors = players.where((p) => p.contributed >= level).length;
      prev = level;
      if (amount == 0) continue;
      if (eligible.length == 1 && contributors == 1) {
        // An uncalled all-in excess: just returned.
        players[eligible.first].chips += amount;
        continue;
      }
      if (eligible.isEmpty) {
        // Only folded players reached this level: it goes to the best live hand.
        eligible.addAll(values.keys);
      }
      final best = eligible.map((i) => values[i]!).reduce((a, b) => a > b ? a : b);
      final winners = [for (final i in eligible) if (values[i]!.compareTo(best) == 0) i];
      // Odd chips to the first winner left of the dealer.
      winners.sort((a, b) => ((a - dealer - 1) % players.length).compareTo((b - dealer - 1) % players.length));
      final share = amount ~/ winners.length;
      for (final w in winners) {
        players[w].chips += share;
      }
      players[winners.first].chips += amount - share * winners.length;
      // Merge with the previous award when the same players win.
      if (out.isNotEmpty && listEquals(out.last.winners, winners)) {
        out[out.length - 1] = PotAward(out.last.amount + amount, winners, best);
      } else {
        out.add(PotAward(amount, winners, best));
      }
    }
    for (final w in {for (final a in out) ...a.winners}) {
      players[w].handsWon++;
    }
    awards = out;
    _endHand();
  }

  void _endHand() {
    handOver = true;
    for (final p in players) {
      p
        ..bet = 0
        ..contributed = 0;
    }
  }

  /// Showdown hand of [i] (null before the river or after a fold).
  HandValue? handOf(int i) {
    final p = players[i];
    if (!p.inHand || board.length < 3) return null;
    return evaluateBest([...p.hole, ...board]);
  }
}

String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// A computer player's choice: (move, raise-to).
(PokerMove, int) botDecision(PokerGame g, int difficulty, math.Random rng) {
  final p = g.current;
  final opponents = g.players.where((o) => o.inHand && o != p).length;
  final noise = switch (difficulty) {
    <= 1 => 0.14,
    2 => 0.07,
    _ => 0.03,
  };
  final equity = (estimateEquity(p.hole, g.board, opponents, rng, iterations: difficulty >= 3 ? 320 : 200) +
          (rng.nextDouble() * 2 - 1) * noise)
      .clamp(0.0, 1.0);
  final call = g.toCall(p);
  final pot = g.pot;
  // How good a hand must be to bet with this many opponents.
  final strong = 1 / (opponents + 1) + 0.25;
  final bluff = switch (difficulty) {
    <= 1 => 0.04,
    2 => 0.08,
    _ => 0.12,
  };
  int sized(double fraction) {
    final target = g.currentBet + math.max(g.minRaise, (pot * fraction).round());
    return target.clamp(g.minRaiseTo(p), g.maxRaiseTo(p)).toInt();
  }

  if (call == 0) {
    if (equity > strong || rng.nextDouble() < bluff) {
      final t = sized(equity > strong + 0.2 ? 0.75 : 0.5);
      return (t >= g.maxRaiseTo(p) ? PokerMove.allIn : PokerMove.raise, t);
    }
    return (PokerMove.check, 0);
  }
  final potOdds = call / (pot + call);
  if (equity > strong + 0.15 && rng.nextDouble() < 0.6 && g.maxRaiseTo(p) > g.currentBet) {
    final t = sized(0.8);
    return (t >= g.maxRaiseTo(p) ? PokerMove.allIn : PokerMove.raise, t);
  }
  if (equity >= potOdds + 0.02 || (difficulty <= 1 && rng.nextDouble() < 0.2)) {
    return (call >= p.chips ? PokerMove.allIn : PokerMove.call, 0);
  }
  return (PokerMove.fold, 0);
}
