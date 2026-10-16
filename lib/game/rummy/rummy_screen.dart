import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../screens/match/match_result_screen.dart';
import '../../widgets/aura.dart';
import '../common/dice_game_kit.dart' show SetupTile;
import '../common/local_game_flow.dart';
import '../common/playing_cards.dart';
import '../common/turn_timer.dart';
import 'rummy_engine.dart';

const _botNames = [('Nova', 'NV'), ('Rex', 'RX'), ('Mia', 'MI')];
const _botColors = [Color(0xFF22D3EE), Color(0xFFF97316), Color(0xFF22C55E)];

/// Quick Play setup → [RummyScreen]: players, difficulty, time per turn.
class RummySetupScreen extends StatefulWidget {
  const RummySetupScreen({super.key});

  @override
  State<RummySetupScreen> createState() => _RummySetupScreenState();
}

class _RummySetupScreenState extends State<RummySetupScreen> {
  int _players = 2;
  int _difficulty = 2;
  int? _clockMs = 30 * 1000;

  Widget _label(String t) => Text(
    t,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
    style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700),
  );

  Widget _row<T>(List<(T, String)> options, T value, ValueChanged<T> onPick) => Row(
    children: [
      for (var i = 0; i < options.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: SetupTile(
            selected: options[i].$1 == value,
            onTap: () => setState(() => onPick(options[i].$1)),
            child: Center(child: _label(options[i].$2)),
          ),
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AuraScaffold(
      appBar: AuraAppBar(title: l.quickPlay),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text('Rummy', style: AuraText.headline.copyWith(fontSize: 24)),
          const SizedBox(height: 6),
          Text(l.rummyBlurb, style: AuraText.cardSub),
          const SizedBox(height: 22),
          SectionBar(l.players),
          const SizedBox(height: 10),
          _row([for (final n in const [2, 3, 4]) (n, l.youPlusAi(n - 1))], _players, (v) => _players = v),
          const SizedBox(height: 22),
          SectionBar(l.difficulty),
          const SizedBox(height: 10),
          _row([(1, l.easy), (2, l.medium), (3, l.hard)], _difficulty, (v) => _difficulty = v),
          const SizedBox(height: 22),
          SectionBar(l.timePerMove),
          const SizedBox(height: 10),
          _row([(30 * 1000, l.timeSec(30)), (60 * 1000, l.timeMin(1)), (null, l.unlimited)], _clockMs, (v) => _clockMs = v),
          const SizedBox(height: 28),
          GradientButton(
            label: l.startGame,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RummyScreen(players: _players, difficulty: _difficulty, clockMs: _clockMs)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 13-card points rummy vs the computer: opponents on top, the closed deck,
/// wild joker and open deck in the middle, your hand in groups at the
/// bottom (each group labelled pure sequence / sequence / set / invalid).
class RummyScreen extends StatefulWidget {
  const RummyScreen({super.key, this.players = 2, this.difficulty = 2, this.clockMs = 30 * 1000, @visibleForTesting this.seed});

  final int players;
  final int difficulty;
  final int? clockMs;
  final int? seed;

  @override
  State<RummyScreen> createState() => _RummyScreenState();
}

class _RummyScreenState extends State<RummyScreen> with LocalGameFlow {
  late final math.Random _rng = widget.seed == null ? math.Random() : math.Random(widget.seed);
  late final RummyGame _game;
  late final TurnTimer _timer = TurnTimer(limitMs: widget.clockMs, onExpire: _timeout);

  /// Your hand as you've grouped it.
  List<List<PlayingCard>> _groups = [];
  final Set<PlayingCard> _selected = {};
  PlayingCard? _justDrawn;
  int _points = 0;

  /// The table message ("Nova discarded 7♥").
  String? _event;

  /// A computer is busy (picking / thinking).
  String? _botStatus;

  @override
  void initState() {
    super.initState();
    _game = RummyGame(
      players: [
        RummyPlayer(name: 'You', initials: 'YOU', isYou: true),
        for (var i = 0; i < widget.players - 1; i++) RummyPlayer(name: _botNames[i].$1, initials: _botNames[i].$2),
      ],
      rng: _rng,
    )..addListener(_onChange);
    _timer.addListener(_onChange);
    _groups = _bySuit(_game.you.hand);
    _recount();
    WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
  }

  @override
  void dispose() {
    disposeFlow();
    _timer.dispose();
    _game.removeListener(_onChange);
    _game.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  int get _wild => _game.wildRank;

  /// Starting layout: by suit (ranks in order), jokers together.
  List<List<PlayingCard>> _bySuit(List<PlayingCard> hand) {
    final jokers = hand.where((c) => RummyRules.isJoker(c, _wild)).toList();
    final out = <List<PlayingCard>>[];
    for (final s in Suit.values) {
      final g = hand.where((c) => !RummyRules.isJoker(c, _wild) && c.suit == s).toList()..sort((a, b) => a.rank - b.rank);
      if (g.isNotEmpty) out.add(g);
    }
    if (jokers.isNotEmpty) out.add(jokers);
    return out;
  }

  /// Auto-arrange: the best melds first, leftovers by suit.
  void _sort() {
    final hand = _game.you.hand;
    final a = arrange(hand, _wild);
    final melds = [for (final m in a.melds) [for (final i in m) hand[i]]];
    melds.sort((x, y) => classify(x, _wild).index - classify(y, _wild).index);
    setState(() {
      _groups = [...melds, ..._bySuit([for (final i in a.loose) hand[i]])];
      _selected.clear();
    });
  }

  /// Selected cards become one new group.
  void _group() {
    if (_selected.length < 2) return;
    setState(() {
      for (final g in _groups) {
        g.removeWhere(_selected.contains);
      }
      _groups.removeWhere((g) => g.isEmpty);
      _groups.add(_selected.toList());
      _selected.clear();
    });
  }

  /// Your points for the hand as it stands (13 cards), recomputed only
  /// when the hand changes.
  String? _countedFor;
  void _recount() {
    final hand = _game.you.hand;
    if (hand.length != RummyRules.handSize) return;
    final key = hand.join(',');
    if (key == _countedFor) return;
    _countedFor = key;
    _points = handPoints(hand, _wild);
  }

  RummyPlayer get _me => _game.you;
  bool get _myTurn => !_game.over && _game.current.isYou && !_me.dropped;

  /// Next turn: start your timer, or let a computer play.
  void _advance() {
    if (!mounted || paused || resigned) return;
    if (_game.over || _me.dropped) {
      _timer.stop();
      endGame(delay: const Duration(milliseconds: 1600));
      return;
    }
    if (_game.current.isYou) {
      _timer.start();
      return;
    }
    _timer.stop();
    _botTurn(_game.turn);
  }

  Future<void> _botTurn(int seat) async {
    final l = context.l10n;
    final bot = _game.players[seat];
    setState(() => _botStatus = l.rummyPicking);
    final think = switch (widget.difficulty) {
      <= 1 => 1100 + _rng.nextInt(900),
      2 => 1300 + _rng.nextInt(1100),
      _ => 1500 + _rng.nextInt(1300),
    };
    scheduleBot(Duration(milliseconds: think), () async {
      final open = _game.discard.last;
      final take = await compute(botTakesOpenCard, (List.of(bot.hand), open, _wild, widget.difficulty));
      if (!mounted || paused || resigned || _game.turn != seat || _game.over) return;
      final drawn = _game.draw(fromDiscard: take);
      setState(() {
        _event = take ? l.rummyPicked(bot.name, drawn.toString()) : l.rummyDrew(bot.name);
        _botStatus = l.rummyThinking;
      });
      final (i, show) = await compute(botThrow, (List.of(bot.hand), _wild, widget.difficulty, _rng.nextInt(1 << 30)));
      scheduleBot(Duration(milliseconds: 700 + _rng.nextInt(600)), () {
        if (_game.turn != seat || _game.over) return;
        final card = bot.hand[i];
        if (show) {
          final rest = [...bot.hand]..remove(card);
          final a = arrange(rest, _wild);
          _game.declare(card, [for (final m in a.melds) [for (final k in m) rest[k]]]);
        } else {
          _game.discardCard(card);
          _event = l.rummyDiscarded(bot.name, card.toString());
        }
        _botStatus = null;
        _advance();
      });
    });
  }

  void _draw({required bool fromDiscard}) {
    if (!_myTurn || _game.phase != RummyTurnPhase.draw || paused) return;
    final c = _game.draw(fromDiscard: fromDiscard);
    setState(() {
      _groups.add([c]);
      _justDrawn = c;
      _selected
        ..clear()
        ..add(c);
      _event = null;
    });
    Timer(const Duration(milliseconds: 1600), () {
      if (mounted && _justDrawn == c) setState(() => _justDrawn = null);
    });
  }

  void _removeFromGroups(PlayingCard c) {
    for (final g in _groups) {
      g.remove(c);
    }
    _groups.removeWhere((g) => g.isEmpty);
  }

  void _discard() {
    if (!_myTurn || _game.phase != RummyTurnPhase.discard || _selected.length != 1) return;
    final c = _selected.single;
    _timer.stop();
    setState(() {
      _removeFromGroups(c);
      _selected.clear();
      _justDrawn = null;
    });
    _game.discardCard(c);
    _recount();
    _advance();
  }

  Future<void> _declare() async {
    if (!_myTurn || _game.phase != RummyTurnPhase.discard || _selected.length != 1) return;
    final l = context.l10n;
    final finish = _selected.single;
    final groups = [for (final g in _groups) g.where((c) => c != finish).toList()]..removeWhere((g) => g.isEmpty);
    final valid = isValidDeclaration(groups, _wild);
    final ok = await showAuraDialog(
      context,
      icon: valid ? Icons.emoji_events_rounded : Icons.warning_amber_rounded,
      title: l.rummyDeclareTitle,
      body: valid ? l.rummyValidShow : l.rummyInvalidShow,
      primaryLabel: l.rummyDeclare,
      secondaryLabel: l.cancel,
      destructive: !valid,
    );
    if (ok != true || !mounted || !_myTurn) return;
    _timer.stop();
    setState(() {
      _removeFromGroups(finish);
      _selected.clear();
    });
    _game.declare(finish, groups);
    _advance();
  }

  Future<void> _drop() async {
    if (!_myTurn) return;
    final l = context.l10n;
    final cost = _me.hasDrawn ? RummyRules.middleDrop : RummyRules.firstDrop;
    final ok = await showAuraDialog(
      context,
      icon: Icons.exit_to_app_rounded,
      title: l.rummyDropTitle,
      body: l.rummyDropBody(cost),
      primaryLabel: l.rummyDrop,
      secondaryLabel: l.cancel,
      destructive: true,
    );
    if (ok != true || !mounted || !_myTurn) return;
    _timer.stop();
    _game.drop();
    _advance();
  }

  /// Out of time: take from the closed deck and throw that card back.
  void _timeout() {
    if (!_myTurn) return;
    if (_game.phase == RummyTurnPhase.draw) _draw(fromDiscard: false);
    final c = _justDrawn ?? _me.hand.last;
    setState(() {
      _selected
        ..clear()
        ..add(c);
    });
    _discard();
  }

  @override
  String get pauseSubtitle => context.l10n.rummyPoints(_points);

  @override
  void pauseGame() {
    super.pauseGame();
    _timer.pause();
  }

  @override
  void onResumeGame() {
    if (_myTurn) {
      _timer.resume();
    } else {
      _advance();
    }
  }

  @override
  void showResult() {
    final l = context.l10n;
    final w = _game.winner;
    final won = !resigned && w == 0;
    final myScore = _me.score ?? handPoints(_me.hand, _wild);
    final others = [for (final p in _game.players.skip(1)) p.score ?? handPoints(p.hand, _wild)];
    final subtitle = resigned
        ? l.youForfeitedMatch
        : won
        ? l.rummyWinSub
        : _game.wrongShow == 0
        ? l.rummyWrongShowSub
        : _me.dropped
        ? l.rummyDroppedSub(myScore)
        : l.rummyLoseSub(w == null ? '' : _game.players[w].name, myScore);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchResultScreen(
          outcome: won ? MatchOutcome.victory : MatchOutcome.defeat,
          subtitle: subtitle,
          youScore: myScore,
          oppScore: others.reduce(math.min),
          oppName: widget.players == 2 ? _botNames[0].$1 : l.bestAi,
          oppInitials: widget.players == 2 ? _botNames[0].$2 : 'AI',
          // Quick Play vs the computer: nothing to earn.
          practice: true,
          playAgain: (_) => RummyScreen(players: widget.players, difficulty: widget.difficulty, clockMs: widget.clockMs),
        ),
      ),
    );
  }

  String _wildLabel() => _game.cutJoker.isJoker ? 'A' : _game.cutJoker.label;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final g = _game;
    // Keep your groups in step with the hand (e.g. after a timeout).
    final inGroups = {for (final x in _groups) ...x};
    if (inGroups.length != _me.hand.length || !_me.hand.every(inGroups.contains)) {
      _groups = _bySuit(_me.hand);
    }
    if (_me.hand.length == RummyRules.handSize) _recount();
    final canDraw = _myTurn && g.phase == RummyTurnPhase.draw;
    final canThrow = _myTurn && g.phase == RummyTurnPhase.discard && _selected.length == 1;
    return AuraScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocalGameHeader(
            title: '🀄 Rummy',
            subtitle: l.rummySubtitle(_wildLabel()),
            live: !g.over,
            onPause: openPause,
          ),
          const SizedBox(height: 10),
          // Opponents.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 1; i < g.players.length; i++) ...[
                  if (i > 1) const SizedBox(width: 8),
                  Expanded(
                    child: BoardPlayerCard(
                      name: g.players[i].name,
                      initials: g.players[i].initials,
                      sub: g.players[i].dropped ? l.droppedLabel : l.cardsCount(g.players[i].hand.length),
                      color: _botColors[(i - 1) % _botColors.length],
                      active: !g.over && g.turn == i,
                      turnText: !g.over && g.turn == i ? (_botStatus ?? l.rummyThinking) : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // The table: closed deck + wild joker, open deck, the last move.
          Expanded(
            child: _Felt(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Pile(
                        label: l.closedDeck,
                        glow: canDraw,
                        onTap: () => _draw(fromDiscard: false),
                        child: SizedBox(
                          width: 92,
                          height: 86,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // Wild joker tucked sideways under the deck.
                              Positioned(
                                left: 28,
                                top: 4,
                                child: Transform.rotate(angle: math.pi / 2, child: PlayingCardView(card: g.cutJoker, width: 56, wild: true)),
                              ),
                              for (var k = 0; k < 4; k++)
                                Positioned(left: 4 + k * 1.5, top: 4 - k * 1.5, child: const PlayingCardView(card: null, width: 56, faceUp: false)),
                              Positioned(
                                left: 0,
                                bottom: -2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                                  child: Text('${g.stock.length}', style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 30),
                      _Pile(
                        label: l.openDeck,
                        glow: canDraw,
                        onTap: () => _draw(fromDiscard: true),
                        child: SizedBox(
                          width: 64,
                          height: 86,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 320),
                            transitionBuilder: (c, a) => SlideTransition(
                              position: Tween(begin: const Offset(0, -0.6), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
                              child: FadeTransition(opacity: a, child: c),
                            ),
                            child: g.discard.isEmpty
                                ? const SizedBox.shrink()
                                : PlayingCardView(
                                    key: ValueKey(g.discard.last),
                                    card: g.discard.last,
                                    width: 60,
                                    wild: RummyRules.isJoker(g.discard.last, _wild) && !g.discard.last.isJoker,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 18,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        _event ?? (canDraw ? l.rummyDrawHint : (_myTurn ? l.rummyDiscardHint : '')),
                        key: ValueKey(_event ?? '$canDraw$_myTurn'),
                        style: AuraText.cardSub.copyWith(fontSize: 12.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Your hand.
          SizedBox(height: 124, child: _Hand(groups: _groups, selected: _selected, wildRank: _wild, justDrawn: _justDrawn, onTap: _toggle)),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(l.rummyPoints(_points), style: AuraText.cardTitle.copyWith(fontSize: 13.5, color: AuraColors.amber)),
              const SizedBox(width: 10),
              Expanded(
                child: _myTurn && widget.clockMs != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: _timer.fraction ?? 1,
                          minHeight: 4,
                          color: _timer.urgent ? AuraColors.danger : AuraColors.accentGlow,
                          backgroundColor: Colors.white12,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _SmallAction(icon: Icons.sort_rounded, label: l.rummySort, onTap: _sort),
              const SizedBox(width: 6),
              _SmallAction(icon: Icons.merge_type_rounded, label: l.rummyGroup, onTap: _selected.length >= 2 ? _group : null),
              const SizedBox(width: 6),
              _SmallAction(icon: Icons.exit_to_app_rounded, label: l.rummyDrop, onTap: _myTurn ? _drop : null),
              const SizedBox(width: 8),
              Expanded(child: GradientButton(label: l.rummyDiscard, enabled: canThrow, onPressed: _discard)),
              const SizedBox(width: 8),
              Expanded(
                child: Opacity(
                  opacity: canThrow ? 1 : 0.4,
                  child: GestureDetector(
                    onTap: canThrow ? _declare : null,
                    child: Container(
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF15803D)]),
                      ),
                      child: Text(
                        l.rummyDeclare,
                        style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  void _toggle(PlayingCard c) => setState(() => _selected.contains(c) ? _selected.remove(c) : _selected.add(c));
}

class _Felt extends StatelessWidget {
  const _Felt({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: const RadialGradient(radius: 0.9, colors: [Color(0xFF1E8A4C), Color(0xFF0F5A2F), Color(0xFF073D1F)]),
      border: Border.all(color: const Color(0xFF4A2511), width: 8),
      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 8))],
    ),
    child: child,
  );
}

class _Pile extends StatelessWidget {
  const _Pile({required this.label, required this.child, required this.onTap, required this.glow});
  final String label;
  final Widget child;
  final VoidCallback onTap;
  final bool glow;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: glow ? AuraColors.amber.withValues(alpha: 0.8) : Colors.transparent, width: 2),
            boxShadow: [BoxShadow(color: AuraColors.amber.withValues(alpha: glow ? 0.35 : 0), blurRadius: 16)],
          ),
          child: child,
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

/// Your groups side by side (cards overlapping to fit the width), with each
/// group's label underneath. Tap cards to select them.
class _Hand extends StatelessWidget {
  const _Hand({required this.groups, required this.selected, required this.wildRank, required this.justDrawn, required this.onTap});
  final List<List<PlayingCard>> groups;
  final Set<PlayingCard> selected;
  final int wildRank;
  final PlayingCard? justDrawn;
  final ValueChanged<PlayingCard> onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 8.0;
        final n = groups.fold(0, (a, g) => a + g.length);
        final gCount = groups.length;
        // Full-size cards when they fit with a readable overlap; smaller when
        // there are many groups (each card keeps at least 30% showing).
        final fit = (box.maxWidth - (gCount - 1) * gap) / (gCount + 0.3 * (n - gCount));
        final cardW = math.min(54.0, fit);
        final free = box.maxWidth - gCount * cardW - (gCount - 1) * gap;
        final step = n > gCount ? (free / (n - gCount)).clamp(cardW * 0.3, cardW * 0.72) : cardW;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var gi = 0; gi < groups.length; gi++) ...[
              if (gi > 0) const SizedBox(width: gap),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: cardW + (groups[gi].length - 1) * step,
                    height: cardW * 1.4 + 14,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (var k = 0; k < groups[gi].length; k++)
                          AnimatedPositioned(
                            key: ValueKey(groups[gi][k]),
                            duration: const Duration(milliseconds: 180),
                            left: k * step,
                            top: selected.contains(groups[gi][k]) ? 0 : 14,
                            child: GestureDetector(
                              onTap: () => onTap(groups[gi][k]),
                              child: PlayingCardView(
                                card: groups[gi][k],
                                width: cardW,
                                selected: selected.contains(groups[gi][k]),
                                wild: RummyRules.isJoker(groups[gi][k], wildRank) && !groups[gi][k].isJoker,
                                highlight: groups[gi][k] == justDrawn ? AuraColors.amber : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  // The label never widens the group.
                  SizedBox(
                    width: cardW + (groups[gi].length - 1) * step,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _GroupLabel(kind: groups[gi].length >= 3 ? classify(groups[gi], wildRank) : null, l: l),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.kind, required this.l});
  final MeldKind? kind;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final k = kind;
    if (k == null) return const SizedBox(height: 15);
    final (text, color) = switch (k) {
      MeldKind.pureSequence => (l.meldPure, AuraColors.green),
      MeldKind.sequence => (l.meldSequence, const Color(0xFF60A5FA)),
      MeldKind.set => (l.meldSet, const Color(0xFFC084FC)),
      MeldKind.invalid => (l.meldInvalid, AuraColors.danger),
    };
    return Container(
      height: 15,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
      child: Text(text, maxLines: 1, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Container(
        width: 50,
        height: 52,
        decoration: AuraGlass.decoration(radius: 14, shadow: false),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 9.5)),
          ],
        ),
      ),
    ),
  );
}
