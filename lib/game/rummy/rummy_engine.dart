import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../common/playing_cards.dart';

/// 13-card Indian Rummy (points): two decks + two printed jokers, a cut
/// wild joker, sequences (one must be pure) and sets; losers score their
/// unmelded cards, capped at 80.
abstract final class RummyRules {
  static const handSize = 13;
  static const maxPoints = 80;
  static const firstDrop = 20;
  static const middleDrop = 40;

  /// A (as 1), J, Q, K and 10 count 10; 2–9 face value; jokers 0.
  static int points(PlayingCard c, int wildRank) {
    if (isJoker(c, wildRank)) return 0;
    return c.rank == 1 || c.rank >= 10 ? 10 : c.rank;
  }

  static bool isJoker(PlayingCard c, int wildRank) => c.isJoker || c.rank == wildRank;
}

enum MeldKind { pureSequence, sequence, set, invalid }

/// What a group of cards makes.
MeldKind classify(List<PlayingCard> g, int wildRank) {
  if (g.length < 3) return MeldKind.invalid;
  if (_isRun(g.where((c) => !c.isJoker).toList(), 0) && g.every((c) => !c.isJoker)) return MeldKind.pureSequence;
  final jokers = g.where((c) => RummyRules.isJoker(c, wildRank)).length;
  final naturals = g.where((c) => !RummyRules.isJoker(c, wildRank)).toList();
  if (naturals.isEmpty) return MeldKind.sequence; // all jokers
  if (_isRun(naturals, jokers) && naturals.every((c) => c.suit == naturals.first.suit)) return MeldKind.sequence;
  final sameRank = naturals.every((c) => c.rank == naturals.first.rank);
  final distinctSuits = naturals.map((c) => c.suit).toSet().length == naturals.length;
  if (sameRank && distinctSuits && g.length <= 4) return MeldKind.set;
  return MeldKind.invalid;
}

/// [cards] (same suit, distinct ranks) form a run, with [jokers] wild cards
/// filling gaps or extending the ends. Ace is low (A-2-3) or high (Q-K-A).
bool _isRun(List<PlayingCard> cards, int jokers) {
  if (cards.isEmpty) return jokers >= 3;
  if (cards.any((c) => c.suit != cards.first.suit)) return false;
  if (cards.map((c) => c.rank).toSet().length != cards.length) return false;
  bool fits(List<int> r) {
    r.sort();
    final span = r.last - r.first + 1;
    return span - r.length <= jokers && span + (jokers - (span - r.length)) <= 14;
  }

  final low = cards.map((c) => c.rank).toList();
  final high = cards.map((c) => c.rank == 1 ? 14 : c.rank).toList();
  return fits(low) || fits(high);
}

bool isSequence(MeldKind k) => k == MeldKind.pureSequence || k == MeldKind.sequence;

/// Are these groups a valid declaration? (All 13 cards in valid melds,
/// at least two sequences, at least one of them pure.)
bool isValidDeclaration(List<List<PlayingCard>> groups, int wildRank) {
  final kinds = [for (final g in groups) classify(g, wildRank)];
  if (groups.fold(0, (a, g) => a + g.length) != RummyRules.handSize) return false;
  if (kinds.contains(MeldKind.invalid)) return false;
  return kinds.where(isSequence).length >= 2 && kinds.contains(MeldKind.pureSequence);
}

/// The best way to group a hand.
@immutable
class Arrangement {
  const Arrangement(this.melds, this.loose, this.points, this.complete);

  /// Card groups (indexes into the hand) and the leftovers.
  final List<List<int>> melds;
  final List<int> loose;

  /// Points this hand would score now (0 when [complete]).
  final int points;

  /// Every card melded with the declaration rules met.
  final bool complete;
}

/// Finds the grouping with the fewest points by the scoring rules: with two
/// sequences (one pure) every valid meld counts; with only pure sequences,
/// just those; otherwise every card counts. Capped at [RummyRules.maxPoints].
Arrangement arrange(List<PlayingCard> hand, int wildRank) {
  final melds = _candidateMelds(hand, wildRank);
  final full = _solve(hand, wildRank, melds, needDeclare: true);
  final pureOnly = _solve(hand, wildRank, melds.where((m) => m.pure).toList(), needDeclare: false);
  final total = hand.fold(0, (a, c) => a + RummyRules.points(c, wildRank));
  _Solution best = _Solution(const [], total);
  if (full != null && full.deadwood < best.deadwood) best = full;
  if (pureOnly != null && pureOnly.chosen.isNotEmpty && pureOnly.deadwood < best.deadwood) best = pureOnly;
  final used = {for (final m in best.chosen) ...m.cards};
  final loose = [for (var i = 0; i < hand.length; i++) if (!used.contains(i)) i];
  // Show the good groups even when they don't count for scoring yet.
  final shown = best.chosen.isEmpty && full != null ? full : best;
  final shownUsed = {for (final m in shown.chosen) ...m.cards};
  return Arrangement(
    [for (final m in shown.chosen) m.cards],
    shown == best ? loose : [for (var i = 0; i < hand.length; i++) if (!shownUsed.contains(i)) i],
    math.min(best.deadwood, RummyRules.maxPoints),
    full != null && full.deadwood == 0 && hand.length == RummyRules.handSize,
  );
}

/// Points of [hand] by the scoring rules (see [arrange]).
int handPoints(List<PlayingCard> hand, int wildRank) => arrange(hand, wildRank).points;

class _Meld {
  _Meld(this.cards, this.mask, {required this.pure, required this.seq});
  final List<int> cards;
  final int mask;
  final bool pure;
  final bool seq;
}

class _Solution {
  _Solution(this.chosen, this.deadwood);
  final List<_Meld> chosen;
  final int deadwood;
}

/// Every meld the hand can make (by card index; duplicate cards from the
/// two decks give separate options).
List<_Meld> _candidateMelds(List<PlayingCard> hand, int wildRank) {
  final out = <_Meld>[];
  final seen = <int>{};
  void add(List<int> idx, {required bool pure, required bool seq}) {
    var mask = 0;
    for (final i in idx) {
      mask |= 1 << i;
    }
    if (seen.add(mask * 4 + (pure ? 2 : 0) + (seq ? 1 : 0))) out.add(_Meld(List.of(idx), mask, pure: pure, seq: seq));
  }

  final jokers = [for (var i = 0; i < hand.length; i++) if (RummyRules.isJoker(hand[i], wildRank)) i];

  // Cards by suit and rank (rank 14 = ace high).
  for (final suit in Suit.values) {
    final byRank = <int, List<int>>{};
    for (var i = 0; i < hand.length; i++) {
      final c = hand[i];
      if (c.isJoker || c.suit != suit) continue;
      byRank.putIfAbsent(c.rank, () => []).add(i);
      if (c.rank == 1) byRank.putIfAbsent(14, () => []).add(i);
    }
    for (var start = 1; start <= 12; start++) {
      for (var len = 3; start + len - 1 <= 14 && len <= 10; len++) {
        final ranks = [for (var r = start; r < start + len; r++) r];
        final present = ranks.where(byRank.containsKey).toList();
        if (present.isEmpty) continue;
        final missing = len - present.length;
        // Natural cards: one copy per rank (try both copies of duplicates).
        void pick(int k, List<int> chosen) {
          if (k == present.length) {
            if (missing == 0) {
              // A pure run (wild-rank cards in their own place count as natural).
              add(chosen, pure: true, seq: true);
            }
            if (missing <= jokers.length) {
              for (final js in _combos(jokers.where((j) => !chosen.contains(j)).toList(), missing)) {
                if (missing > 0) add([...chosen, ...js], pure: false, seq: true);
              }
            }
            return;
          }
          final copies = byRank[present[k]]!;
          for (final ci in copies.take(2)) {
            if (chosen.contains(ci)) continue;
            pick(k + 1, [...chosen, ci]);
          }
        }

        pick(0, []);
      }
    }
  }

  // Sets: same rank, distinct suits, 3–4 cards, jokers allowed.
  for (var rank = 1; rank <= 13; rank++) {
    final bySuit = <Suit, List<int>>{};
    for (var i = 0; i < hand.length; i++) {
      final c = hand[i];
      if (c.isJoker || c.rank != rank || RummyRules.isJoker(c, wildRank)) continue;
      bySuit.putIfAbsent(c.suit, () => []).add(i);
    }
    final suits = bySuit.keys.toList();
    for (var size = 1; size <= suits.length; size++) {
      for (final ss in _combos(suits, size)) {
        void pick(int k, List<int> chosen) {
          if (k == ss.length) {
            for (var total = 3; total <= 4; total++) {
              final need = total - chosen.length;
              if (need < 0 || need > jokers.length) continue;
              for (final js in _combos(jokers, need)) {
                add([...chosen, ...js], pure: false, seq: false);
              }
            }
            return;
          }
          for (final ci in bySuit[ss[k]]!.take(2)) {
            pick(k + 1, [...chosen, ci]);
          }
        }

        pick(0, []);
      }
    }
  }
  return out;
}

List<List<T>> _combos<T>(List<T> items, int k) {
  if (k == 0) return [<T>[]];
  if (k > items.length) return const [];
  final out = <List<T>>[];
  void rec(int start, List<T> cur) {
    if (cur.length == k) {
      out.add(List.of(cur));
      return;
    }
    for (var i = start; i < items.length; i++) {
      cur.add(items[i]);
      rec(i + 1, cur);
      cur.removeLast();
    }
  }

  rec(0, []);
  return out;
}

/// Exact search over the hand (bitmask DP). With [needDeclare], only
/// groupings with two sequences (one pure) count; returns null if none.
_Solution? _solve(List<PlayingCard> hand, int wildRank, List<_Meld> melds, {required bool needDeclare}) {
  final n = hand.length;
  final pts = [for (final c in hand) RummyRules.points(c, wildRank)];
  final byLow = List.generate(n, (_) => <_Meld>[]);
  for (final m in melds) {
    byLow[_lowBit(m.mask)].add(m);
  }
  // State: mask × flag (pure 0/1 × sequences 0/1/2 → 0..5) → least deadwood,
  // with the move that got there (meld or loose card) and the sub-state flag.
  const inf = 1 << 30;
  final memo = <int, List<int>>{};
  final how = <int, List<(_Meld?, int)>>{};
  List<int> go(int mask) {
    if (mask == 0) return const [0, inf, inf, inf, inf, inf];
    final cached = memo[mask];
    if (cached != null) return cached;
    final low = _lowBit(mask);
    final best = List.filled(6, inf);
    final moves = List<(_Meld?, int)>.filled(6, (null, 0));
    final rest = go(mask & ~(1 << low));
    for (var f = 0; f < 6; f++) {
      if (rest[f] < inf && rest[f] + pts[low] < best[f]) {
        best[f] = rest[f] + pts[low];
        moves[f] = (null, f);
      }
    }
    for (final m in byLow[low]) {
      if (m.mask & mask != m.mask) continue;
      final sub = go(mask & ~m.mask);
      for (var f = 0; f < 6; f++) {
        if (sub[f] >= inf) continue;
        final int nf = math.min(1, f ~/ 3 + (m.pure ? 1 : 0)) * 3 + math.min(2, f % 3 + (m.seq ? 1 : 0));
        if (sub[f] < best[nf]) {
          best[nf] = sub[f];
          moves[nf] = (m, f);
        }
      }
    }
    memo[mask] = best;
    how[mask] = moves;
    return best;
  }

  final all = (1 << n) - 1;
  final res = go(all);
  var flag = -1;
  for (var f = 0; f < 6; f++) {
    if (needDeclare && f != 5) continue; // pure ≥ 1 and sequences ≥ 2
    if (res[f] < inf && (flag < 0 || res[f] < res[flag])) flag = f;
  }
  if (flag < 0) return null;
  final chosen = <_Meld>[];
  var mask = all, f = flag;
  while (mask != 0) {
    final (m, sub) = how[mask]![f];
    if (m == null) {
      mask &= ~(1 << _lowBit(mask));
    } else {
      chosen.add(m);
      mask &= ~m.mask;
    }
    f = sub;
  }
  return _Solution(chosen, res[flag]);
}

int _lowBit(int mask) {
  var low = 0;
  while (mask & (1 << low) == 0) {
    low++;
  }
  return low;
}

// ── The game ──

enum RummyTurnPhase { draw, discard }

class RummyPlayer {
  RummyPlayer({required this.name, required this.initials, this.isYou = false});
  final String name;
  final String initials;
  final bool isYou;
  List<PlayingCard> hand = [];
  bool dropped = false;
  bool hasDrawn = false;

  /// Final score (points) once the deal ends.
  int? score;
}

/// One deal of points rummy at a table of 2–4.
class RummyGame extends ChangeNotifier {
  RummyGame({required this.players, math.Random? rng}) : _rng = rng ?? math.Random() {
    _deal();
  }

  final List<RummyPlayer> players;
  final math.Random _rng;

  late List<PlayingCard> stock;
  final List<PlayingCard> discard = [];

  /// The cut card: its rank is wild (a printed joker cut makes aces wild).
  late PlayingCard cutJoker;
  int get wildRank => cutJoker.isJoker ? 1 : cutJoker.rank;

  int turn = 0;
  RummyTurnPhase phase = RummyTurnPhase.draw;
  int? winner;

  /// Set when the last action was a wrong declaration by [turn]'s player.
  int? wrongShow;
  bool get over => winner != null;

  /// What the last player did (shown on the table).
  String? lastEvent;

  RummyPlayer get current => players[turn];
  RummyPlayer get you => players.first;

  void _deal() {
    final deck = shuffledDeck(_rng, decks: 2, jokers: 2);
    for (final p in players) {
      p.hand = [for (var i = 0; i < RummyRules.handSize; i++) deck.removeLast()];
    }
    cutJoker = deck.removeLast();
    discard.add(deck.removeLast());
    stock = deck;
    turn = _rng.nextInt(players.length);
  }

  void _refillStock() {
    if (stock.isNotEmpty) return;
    final top = discard.removeLast();
    stock = discard.toList()..shuffle(_rng);
    discard
      ..clear()
      ..add(top);
  }

  PlayingCard draw({required bool fromDiscard}) {
    assert(phase == RummyTurnPhase.draw && !over);
    _refillStock();
    final c = fromDiscard ? discard.removeLast() : stock.removeLast();
    current.hand.add(c);
    current.hasDrawn = true;
    phase = RummyTurnPhase.discard;
    lastEvent = fromDiscard ? 'picked:$c' : 'drew';
    notifyListeners();
    return c;
  }

  void discardCard(PlayingCard c) {
    assert(phase == RummyTurnPhase.discard && !over);
    current.hand.remove(c);
    discard.add(c);
    lastEvent = 'discarded:$c';
    _nextTurn();
  }

  void _nextTurn() {
    phase = RummyTurnPhase.draw;
    final active = players.where((p) => !p.dropped).length;
    if (active < 2) {
      winner = players.indexWhere((p) => !p.dropped);
      _score();
    } else {
      do {
        turn = (turn + 1) % players.length;
      } while (players[turn].dropped);
    }
    notifyListeners();
  }

  /// Show: discard [finish] and lay down [groups] (the 13 left). A wrong
  /// show costs the full 80 and ends the deal for that player.
  bool declare(PlayingCard finish, List<List<PlayingCard>> groups) {
    assert(phase == RummyTurnPhase.discard && !over);
    current.hand.remove(finish);
    discard.add(finish);
    if (isValidDeclaration(groups, wildRank)) {
      winner = turn;
      lastEvent = 'declared';
      _score();
      notifyListeners();
      return true;
    }
    // Wrong show.
    wrongShow = turn;
    current
      ..dropped = true
      ..score = RummyRules.maxPoints;
    lastEvent = 'wrongShow';
    _nextTurn();
    return false;
  }

  /// Leave the deal: 20 points before your first draw, 40 after.
  void drop() {
    final p = current;
    p
      ..dropped = true
      ..score = p.hasDrawn ? RummyRules.middleDrop : RummyRules.firstDrop;
    if (phase == RummyTurnPhase.discard) {
      // Drop after drawing: the drawn card goes back on the discard pile.
      discard.add(p.hand.removeLast());
    }
    lastEvent = 'dropped';
    _nextTurn();
  }

  void _score() {
    for (var i = 0; i < players.length; i++) {
      final p = players[i];
      if (i == winner) {
        p.score = 0;
      } else {
        p.score ??= handPoints(p.hand, wildRank);
      }
    }
  }
}

// ── Computer players ──

/// Best card to throw from [hand] (14 cards): the one leaving the fewest
/// points (the higher card on ties). Easy bots sometimes pick a worse one.
/// Returns (index, points left).
(int, int) bestThrow(List<PlayingCard> hand, int wildRank, {math.Random? rng, int difficulty = 2}) {
  final options = <(int, int, int)>[]; // (index, points left, card value)
  for (var i = 0; i < hand.length; i++) {
    final rest = [...hand]..removeAt(i);
    options.add((i, handPoints(rest, wildRank), RummyRules.points(hand[i], wildRank)));
  }
  options.sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : b.$3 - a.$3);
  final sloppy = difficulty <= 1 && rng != null && rng.nextDouble() < 0.35;
  final pick = sloppy ? options[math.min(options.length - 1, rng.nextInt(3))] : options.first;
  return (pick.$1, pick.$2);
}

/// Should a computer take the open card? (Background-isolate safe.)
/// Args: hand (13), open card, wild rank, difficulty.
bool botTakesOpenCard((List<PlayingCard>, PlayingCard, int, int) args) {
  final (hand, open, wildRank, difficulty) = args;
  if (RummyRules.isJoker(open, wildRank)) return true;
  final now = handPoints(hand, wildRank);
  final withOpen = [...hand, open];
  final (throwAt, left) = bestThrow(withOpen, wildRank);
  if (throwAt == withOpen.length - 1) return false; // it would just go back
  final threshold = switch (difficulty) {
    <= 1 => 6,
    2 => 3,
    _ => 1,
  };
  return now - left >= threshold;
}

/// Which card a computer throws from its 14, and whether that's a show.
/// Args: hand (14), wild rank, difficulty, seed. (Background-isolate safe.)
(int, bool) botThrow((List<PlayingCard>, int, int, int) args) {
  final (hand, wildRank, difficulty, seed) = args;
  final (i, left) = bestThrow(hand, wildRank, rng: math.Random(seed), difficulty: difficulty);
  final rest = [...hand]..removeAt(i);
  return (i, left == 0 && arrange(rest, wildRank).complete);
}
