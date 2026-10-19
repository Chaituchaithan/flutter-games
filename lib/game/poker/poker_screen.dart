import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../screens/match/match_result_screen.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';
import '../common/dice_game_kit.dart' show SetupTile;
import '../common/local_game_flow.dart';
import '../common/playing_cards.dart';
import '../common/turn_timer.dart';
import 'poker_engine.dart';

String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// Computer players at the table.
const _botNames = [('Nova', 'NV'), ('Rex', 'RX'), ('Mia', 'MI'), ('Kai', 'KA'), ('Zoe', 'ZO')];
const _seatColors = [AuraColors.brandPurple, Color(0xFF22D3EE), Color(0xFFF97316), Color(0xFF22C55E), Color(0xFFEC4899), Color(0xFFFACC15)];

/// Hand name in the app language.
String handName(BuildContext context, HandValue h) {
  final l = context.l10n;
  if (h.category == 8 && h.ranks.first == 14) return l.handRoyalFlush;
  return [
    l.handHighCard, l.handPair, l.handTwoPair, l.handThreeKind, l.handStraight, //
    l.handFlush, l.handFullHouse, l.handFourKind, l.handStraightFlush,
  ][h.category];
}

/// Quick Play setup → [PokerScreen]: players, difficulty, stakes, time.
class PokerSetupScreen extends StatefulWidget {
  const PokerSetupScreen({super.key});

  @override
  State<PokerSetupScreen> createState() => _PokerSetupScreenState();
}

class _PokerSetupScreenState extends State<PokerSetupScreen> {
  int _players = 4;
  int _difficulty = 2;
  int _stakes = 0;
  int? _clockMs = 30 * 1000;

  static const _stakeOptions = [(1000, 10), (2000, 25), (5000, 50)];

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
          Text('Poker', style: AuraText.headline.copyWith(fontSize: 24)),
          const SizedBox(height: 6),
          Text(l.pokerBlurb, style: AuraText.cardSub),
          const SizedBox(height: 22),
          SectionBar(l.players),
          const SizedBox(height: 10),
          _row([for (final n in const [2, 3, 4, 6]) (n, l.youPlusAi(n - 1))], _players, (v) => _players = v),
          const SizedBox(height: 22),
          SectionBar(l.difficulty),
          const SizedBox(height: 10),
          _row([(1, l.easy), (2, l.medium), (3, l.hard)], _difficulty, (v) => _difficulty = v),
          const SizedBox(height: 22),
          SectionBar(l.pokerStakes),
          const SizedBox(height: 10),
          _row(
            [
              for (var i = 0; i < _stakeOptions.length; i++)
                (i, '${_fmt(_stakeOptions[i].$1)} · ${_stakeOptions[i].$2}/${_stakeOptions[i].$2 * 2}'),
            ],
            _stakes,
            (v) => _stakes = v,
          ),
          const SizedBox(height: 22),
          SectionBar(l.timePerMove),
          const SizedBox(height: 10),
          _row(
            [(30 * 1000, l.timeSec(30)), (60 * 1000, l.timeMin(1)), (null, l.unlimited)],
            _clockMs,
            (v) => _clockMs = v,
          ),
          const SizedBox(height: 28),
          GradientButton(
            label: l.startGame,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PokerScreen(
                  players: _players,
                  difficulty: _difficulty,
                  startingChips: _stakeOptions[_stakes].$1,
                  smallBlind: _stakeOptions[_stakes].$2,
                  clockMs: _clockMs,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Texas Hold'em vs the computer: the table (seats around the felt, the
/// board and pot in the middle), your hole cards and the action bar.
class PokerScreen extends StatefulWidget {
  const PokerScreen({
    super.key,
    this.players = 4,
    this.difficulty = 2,
    this.startingChips = 1000,
    this.smallBlind = 10,
    this.clockMs = 30 * 1000,
    @visibleForTesting this.seed,
  });

  final int players;
  final int difficulty;
  final int startingChips;
  final int smallBlind;
  final int? clockMs;
  final int? seed;

  @override
  State<PokerScreen> createState() => _PokerScreenState();
}

class _PokerScreenState extends State<PokerScreen> with LocalGameFlow, TickerProviderStateMixin {
  late final math.Random _rng = widget.seed == null ? math.Random() : math.Random(widget.seed);
  late final PokerGame _game;
  late final TurnTimer _timer = TurnTimer(limitMs: widget.clockMs, onExpire: _timeout);

  /// Cards flying from the dealer at the start of a hand.
  late final AnimationController _deal = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _raising = false;
  int _raiseTo = 0;
  Timer? _flow;

  @override
  void initState() {
    super.initState();
    _game = PokerGame(
      players: [
        PokerPlayer(name: 'You', initials: 'YOU', chips: widget.startingChips, isYou: true),
        for (var i = 0; i < widget.players - 1; i++)
          PokerPlayer(name: _botNames[i].$1, initials: _botNames[i].$2, chips: widget.startingChips),
      ],
      smallBlind: widget.smallBlind,
      rng: _rng,
    )..addListener(_onChange);
    _timer.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _newHand());
  }

  @override
  void dispose() {
    _flow?.cancel();
    disposeFlow();
    _deal.dispose();
    _timer.dispose();
    _game.removeListener(_onChange);
    _game.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _later(Duration d, VoidCallback f) {
    _flow?.cancel();
    _flow = Timer(d, () {
      if (mounted && !paused && !resigned) f();
    });
  }

  void _newHand() {
    _raising = false;
    _game.startHand();
    _deal.duration = Duration(milliseconds: 300 + _game.players.where((p) => p.hole.isNotEmpty).length * 2 * 110);
    _deal.forward(from: 0).then((_) => _advance());
  }

  /// Decide what happens next: deal a street, show down, or hand the turn
  /// to the next player (you or a computer).
  void _advance() {
    if (!mounted || paused || resigned) return;
    final g = _game;
    _timer.stop();
    if (g.handOver) {
      _later(const Duration(milliseconds: 3200), () {
        if (_game.gameOver) {
          endGame(immediate: true);
        } else {
          _newHand();
        }
      });
      return;
    }
    if (g.roundComplete) {
      // All-in run-outs deal a little slower, for suspense.
      _later(Duration(milliseconds: g.runningOut ? 1300 : 750), () {
        _game.nextStreet();
        _advance();
      });
      return;
    }
    if (g.current.isYou) {
      _raiseTo = g.minRaiseTo(g.you);
      _timer.start();
      return;
    }
    final think = switch (widget.difficulty) {
      <= 1 => 900 + _rng.nextInt(900),
      2 => 1200 + _rng.nextInt(1300),
      _ => 1500 + _rng.nextInt(1700),
    };
    scheduleBot(Duration(milliseconds: think), () {
      final (move, to) = botDecision(_game, widget.difficulty, _rng);
      _game.act(move, raiseTo: to);
      _advance();
    });
  }

  void _youAct(PokerMove move, {int raiseTo = 0}) {
    if (!_game.current.isYou || _game.handOver || paused) return;
    _timer.stop();
    setState(() => _raising = false);
    _game.act(move, raiseTo: raiseTo);
    _advance();
  }

  void _timeout() {
    if (!_game.current.isYou || _game.handOver) return;
    _youAct(_game.toCall(_game.you) == 0 ? PokerMove.check : PokerMove.fold);
  }

  @override
  void pauseGame() {
    super.pauseGame();
    _flow?.cancel();
    _timer.pause();
  }

  @override
  String get pauseSubtitle => context.l10n.pokerHand(_game.handNo);

  @override
  void onResumeGame() {
    if (_game.current.isYou && !_game.handOver && !_game.roundComplete) {
      _timer.resume();
    } else {
      _advance();
    }
  }

  @override
  void showResult() {
    final l = context.l10n;
    final won = !resigned && _game.you.chips > 0;
    final bots = _game.players.skip(1);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchResultScreen(
          outcome: won ? MatchOutcome.victory : MatchOutcome.defeat,
          subtitle: resigned ? l.youForfeitedMatch : (won ? l.pokerWinSub : l.pokerLoseSub),
          youScore: _game.you.handsWon,
          oppScore: bots.map((p) => p.handsWon).reduce(math.max),
          oppName: widget.players == 2 ? _botNames[0].$1 : l.bestAi,
          oppInitials: widget.players == 2 ? _botNames[0].$2 : 'AI',
          // Quick Play vs the computer: nothing to earn.
          practice: true,
          playAgain: (_) => PokerScreen(
            players: widget.players,
            difficulty: widget.difficulty,
            startingChips: widget.startingChips,
            smallBlind: widget.smallBlind,
            clockMs: widget.clockMs,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final g = _game;
    final me = g.you;
    final myTurn = !g.handOver && g.current.isYou && !g.roundComplete && _deal.isCompleted;
    final myHand = g.handOf(0);
    final winners = {for (final a in g.awards) ...a.winners};
    final winCards = g.stage == PokerStage.showdown && g.handOver
        ? {for (final a in g.awards) ...?a.hand?.cards}
        : <PlayingCard>{};
    return guardBack(
      AuraScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocalGameHeader(
            title: '🃏 Poker',
            subtitle: '${l.pokerHand(g.handNo)} · ${l.pokerBlinds(_fmt(g.smallBlind), _fmt(g.bigBlind))}',
            live: !resigned,
            onPause: openPause,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _Table(
              game: g,
              deal: _deal,
              winners: g.handOver ? winners : const {},
              winCards: winCards,
              timer: _timer,
            ),
          ),
          const SizedBox(height: 6),
          // Your hole cards + what you have.
          SizedBox(
            height: 104,
            child: Row(
              children: [
                for (var i = 0; i < me.hole.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _Flip(
                      key: ValueKey('${g.handNo}-me-$i'),
                      delay: Duration(milliseconds: 250 + i * 220),
                      child: Transform.rotate(
                        angle: (i == 0 ? -1 : 1) * 0.05,
                        child: PlayingCardView(
                          card: me.hole[i],
                          width: 66,
                          dimmed: me.folded,
                          highlight: winCards.contains(me.hole[i]) ? AuraColors.amber : null,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        myHand == null ? '' : handName(context, myHand),
                        style: AuraText.cardTitle.copyWith(fontSize: 16, color: AuraColors.amber),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _status(context),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AuraText.cardSub.copyWith(fontSize: 12.5),
                      ),
                      if (myTurn && widget.clockMs != null) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: _timer.fraction ?? 1,
                            minHeight: 4,
                            color: _timer.urgent ? AuraColors.danger : AuraColors.accentGlow,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _raising && myTurn ? _RaisePanel(game: g, value: _raiseTo, onChanged: (v) => setState(() => _raiseTo = v)) : const SizedBox.shrink(),
          ),
          _ActionBar(
            game: g,
            enabled: myTurn,
            raising: _raising,
            raiseTo: _raiseTo,
            onFold: () => _youAct(PokerMove.fold),
            onCheckCall: () => _youAct(g.toCall(me) == 0 ? PokerMove.check : (g.toCall(me) >= me.chips ? PokerMove.allIn : PokerMove.call)),
            onRaise: () {
              if (!_raising) {
                setState(() => _raising = true);
              } else {
                _youAct(_raiseTo >= g.maxRaiseTo(me) ? PokerMove.allIn : PokerMove.raise, raiseTo: _raiseTo);
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
    );
  }

  String _status(BuildContext context) {
    final l = context.l10n;
    final g = _game;
    if (g.handOver && g.awards.isNotEmpty) return _awardText(context, g, g.awards.last);
    if (g.you.folded) return l.pokerFold;
    if (g.current.isYou && !g.roundComplete) return l.yourMove;
    return l.pokerWaiting(g.current.name);
  }
}

String _awardText(BuildContext context, PokerGame g, PotAward a) {
  final l = context.l10n;
  final name = a.winners.length > 1 ? null : (g.players[a.winners.first].isYou ? l.you : g.players[a.winners.first].name);
  if (name == null) return l.pokerSplit(a.hand == null ? '' : handName(context, a.hand!));
  return a.hand == null ? l.pokerWins(name, _fmt(a.amount)) : l.pokerWinsWith(name, _fmt(a.amount), handName(context, a.hand!));
}

/// Seat positions (fractions of the table box), you first then clockwise.
List<Offset> _seatSpots(int n) => [
  const Offset(0.5, 0.9),
  ...switch (n - 1) {
    1 => const [Offset(0.5, 0.1)],
    2 => const [Offset(0.17, 0.22), Offset(0.83, 0.22)],
    3 => const [Offset(0.12, 0.42), Offset(0.5, 0.08), Offset(0.88, 0.42)],
    4 => const [Offset(0.11, 0.55), Offset(0.24, 0.13), Offset(0.76, 0.13), Offset(0.89, 0.55)],
    _ => const [Offset(0.1, 0.66), Offset(0.12, 0.28), Offset(0.5, 0.07), Offset(0.88, 0.28), Offset(0.9, 0.66)],
  },
];

class _Table extends StatelessWidget {
  const _Table({required this.game, required this.deal, required this.winners, required this.winCards, required this.timer});
  final PokerGame game;
  final Animation<double> deal;
  final Set<int> winners;
  final Set<PlayingCard> winCards;
  final TurnTimer timer;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final g = game;
    final n = g.players.length;
    final spots = _seatSpots(n);
    return AnimatedBuilder(
      animation: deal,
      builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        Offset at(Offset f) => Offset(f.dx * w, f.dy * h);
        final center = Offset(w / 2, h * 0.47);
        final cardW = math.min(46.0, (w - 40) / 5 - 6);
        final showAll = g.stage == PokerStage.showdown || g.runningOut;
        // Who receives cards, in dealing order (from the dealer's left).
        final dealt = [for (var k = 1; k <= n; k++) (g.dealer + k) % n].where((i) => g.players[i].hole.isNotEmpty).toList();
        final children = <Widget>[
          Positioned.fill(child: CustomPaint(painter: _FeltPainter())),
          // Board.
          Positioned(
            left: 0,
            right: 0,
            top: center.dy - cardW * 0.7,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: i < g.board.length
                        ? _Flip(
                            key: ValueKey('${g.handNo}-b$i'),
                            delay: Duration(milliseconds: i < 3 ? i * 160 : 0),
                            child: PlayingCardView(
                              card: g.board[i],
                              width: cardW,
                              highlight: winCards.contains(g.board[i]) ? AuraColors.amber : null,
                            ),
                          )
                        : Container(
                            width: cardW,
                            height: cardW * 1.4,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(cardW * 0.1),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                            ),
                          ),
                  ),
              ],
            ),
          ),
          // Pot (slides to the winner at the end of the hand).
          AnimatedPositioned(
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeInOutCubic,
            left: (winners.isEmpty ? center.dx : at(spots[winners.first]).dx) - 70,
            top: (winners.isEmpty ? center.dy - cardW * 0.7 - 34 : at(spots[winners.first]).dy - 10),
            width: 140,
            child: Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: g.pot > 0 || winners.isNotEmpty ? 1 : 0,
                child: _PotPill(amount: winners.isEmpty ? g.pot : g.awards.fold(0, (a, b) => a + b.amount), label: l.pokerPot),
              ),
            ),
          ),
          if (g.handOver && g.awards.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              top: center.dy + cardW * 0.85,
              child: Center(child: _WinBanner(text: _awardText(context, g, g.awards.last))),
            ),
        ];
        // Seats (yours sits on the rail, cards shown below the table).
        for (var i = 0; i < n; i++) {
          final p = g.players[i];
          if (p.busted && !p.inHand && p.chips == 0 && i != 0) {
            children.add(_seatAt(at(spots[i]), _EmptySeat(name: p.name)));
            continue;
          }
          final k = dealt.indexOf(i);
          final acting = !g.handOver && g.toAct == i && !g.roundComplete && deal.isCompleted;
          children.add(
            _seatAt(
              at(spots[i]),
              _Seat(
                player: p,
                color: _seatColors[i % _seatColors.length],
                acting: acting,
                winner: winners.contains(i),
                dealer: g.dealer == i,
                showCards: i != 0 && p.inHand && showAll,
                cardsIn: k < 0 ? 0 : ((deal.value * dealt.length * 2 - k) / 1.2).clamp(0.0, 2.0),
                hideCards: i == 0,
                timer: acting && p.isYou ? timer : null,
                winCards: winCards,
              ),
            ),
          );
          // This street's bet in front of the seat.
          if (p.bet > 0) {
            final pos = Offset.lerp(at(spots[i]), center, 0.42)!;
            children.add(Positioned(left: pos.dx - 40, top: pos.dy - 12, width: 80, child: Center(child: _BetStack(amount: p.bet))));
          }
        }
        // Cards in flight from the dealer.
        if (!deal.isCompleted) {
          for (var k = 0; k < dealt.length * 2; k++) {
            final t = (deal.value * dealt.length * 2 - k % dealt.length - (k ~/ dealt.length) * dealt.length) / 1.2;
            if (t <= 0 || t >= 1) continue;
            final to = at(spots[dealt[k % dealt.length]]);
            final p = Offset.lerp(center, to, Curves.easeOutCubic.transform(t))!;
            children.add(
              Positioned(
                left: p.dx - 12,
                top: p.dy - 17,
                child: Transform.rotate(angle: t * math.pi * 2, child: const PlayingCardView(card: null, width: 24, faceUp: false)),
              ),
            );
          }
        }
        return Stack(clipBehavior: Clip.none, children: children);
      },
    ),
    );
  }

  Widget _seatAt(Offset c, Widget child) => Positioned(left: c.dx - 48, top: c.dy - 46, width: 96, child: child);
}

class _FeltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final table = Rect.fromLTWH(size.width * 0.04, size.height * 0.1, size.width * 0.92, size.height * 0.78);
    final outer = RRect.fromRectAndRadius(table, Radius.circular(table.width / 2));
    // Shadow, padded rail, felt with a spotlight, inner line.
    canvas.drawRRect(outer.shift(const Offset(0, 8)), Paint()..color = Colors.black54..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4A2511), Color(0xFF2A1408)],
        ).createShader(table),
    );
    final felt = outer.deflate(14);
    canvas.drawRRect(
      felt,
      Paint()
        ..shader = const RadialGradient(
          radius: 0.9,
          colors: [Color(0xFF1E8A4C), Color(0xFF0F5A2F), Color(0xFF073D1F)],
        ).createShader(felt.outerRect),
    );
    canvas.drawRRect(
      felt.deflate(12),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFFDE68A).withValues(alpha: 0.25),
    );
    canvas.drawRRect(
      outer.deflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFFDE68A).withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_FeltPainter old) => false;
}

class _Seat extends StatelessWidget {
  const _Seat({
    required this.player,
    required this.color,
    required this.acting,
    required this.winner,
    required this.dealer,
    required this.showCards,
    required this.cardsIn,
    required this.hideCards,
    required this.winCards,
    this.timer,
  });
  final PokerPlayer player;
  final Color color;
  final bool acting;
  final bool winner;
  final bool dealer;
  final bool showCards;

  /// How many hole cards have arrived (0–2, from the deal animation).
  final double cardsIn;
  final bool hideCards;
  final Set<PlayingCard> winCards;
  final TurnTimer? timer;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = player;
    final name = p.isYou ? l.you : p.name;
    final initials = p.isYou ? ProviderScope.containerOf(context).read(currentUserProvider).initials : p.initials;
    return Opacity(
      opacity: p.folded && !winner ? 0.5 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 50,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Hole cards fanned behind the avatar (opponents).
                if (!hideCards && p.hole.isNotEmpty && !p.folded)
                  for (var c = 0; c < 2; c++)
                    if (cardsIn > c || showCards)
                      Positioned(
                        top: -16,
                        left: 34 + c * 14.0,
                        child: Transform.rotate(
                          angle: (c - 0.5) * 0.25,
                          child: PlayingCardView(
                            card: p.hole[c],
                            width: showCards ? 30 : 22,
                            faceUp: showCards,
                            highlight: showCards && winCards.contains(p.hole[c]) ? AuraColors.amber : null,
                          ),
                        ),
                      ),
                // Avatar with a glow while acting / winning.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.35)!]),
                    border: Border.all(color: winner ? AuraColors.amber : (acting ? Colors.white : Colors.white24), width: winner || acting ? 2.5 : 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: (winner ? AuraColors.amber : color).withValues(alpha: winner || acting ? 0.7 : 0),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Text(
                    initials,
                    style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
                if (acting && timer != null && timer!.fraction != null)
                  SizedBox.square(
                    dimension: 52,
                    child: CircularProgressIndicator(
                      value: timer!.fraction,
                      strokeWidth: 3,
                      color: timer!.urgent ? AuraColors.danger : AuraColors.accentGlow,
                    ),
                  ),
                if (acting && timer == null)
                  const SizedBox.square(dimension: 52, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white54)),
                if (dealer)
                  Positioned(
                    left: 14,
                    bottom: -2,
                    child: Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 3)]),
                      child: const Text('D', style: TextStyle(color: Color(0xFF111827), fontSize: 10, fontWeight: FontWeight.w900)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                Text(
                  p.allIn ? l.pokerAllIn : _fmt(p.chips),
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: p.allIn ? AuraColors.danger : AuraColors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          // Last action ("Raise 120").
          SizedBox(
            height: 16,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: p.lastAction == null || p.isYou
                  ? const SizedBox.shrink()
                  : Text(
                      _localAction(context, p.lastAction!),
                      key: ValueKey(p.lastAction),
                      style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The engine's "Raise 120" / "Call 40" / "Check" in the app language.
String _localAction(BuildContext context, String a) {
  final l = context.l10n;
  if (a == 'Fold') return l.pokerFold;
  if (a == 'Check') return l.pokerCheck;
  if (a == 'All-in') return l.pokerAllIn;
  if (a.startsWith('Raise ')) return l.pokerRaiseTo(a.substring(6));
  if (a.startsWith('Call ')) return l.pokerCall(a.substring(5));
  if (a == 'Call') return l.pokerCall('');
  return a;
}

class _EmptySeat extends StatelessWidget {
  const _EmptySeat({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: 0.35,
    child: Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white38)),
          child: const Icon(Icons.event_seat_rounded, color: Colors.white38),
        ),
        const SizedBox(height: 3),
        Text(name, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    ),
  );
}

class _BetStack extends StatelessWidget {
  const _BetStack({required this.amount});
  final int amount;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CasinoChip(value: amount, size: 18),
      const SizedBox(width: 3),
      Text(
        _fmt(amount),
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, shadows: [Shadow(color: Colors.black, blurRadius: 3)]),
      ),
    ],
  );
}

class _PotPill extends StatelessWidget {
  const _PotPill({required this.amount, required this.label});
  final int amount;
  final String Function(String) label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: AuraColors.amber.withValues(alpha: 0.6)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CasinoChip(value: amount, size: 16),
        const SizedBox(width: 5),
        TweenAnimationBuilder<double>(
          tween: Tween(end: amount.toDouble()),
          duration: const Duration(milliseconds: 400),
          builder: (_, v, _) => Text(
            label(_fmt(v.round())),
            style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class _WinBanner extends StatelessWidget {
  const _WinBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 700),
    curve: Curves.elasticOut,
    builder: (_, v, child) => Transform.scale(scale: 0.6 + 0.4 * v, child: child),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)]),
        boxShadow: [BoxShadow(color: AuraColors.amber.withValues(alpha: 0.6), blurRadius: 18)],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF1F1A2E), fontSize: 12.5, fontWeight: FontWeight.w900),
      ),
    ),
  );
}

/// Deals a card face down, then turns it over.
class _Flip extends StatelessWidget {
  const _Flip({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final total = delay + const Duration(milliseconds: 420);
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      builder: (_, v, _) {
        final t = ((v - start) / (1 - start)).clamp(0.0, 1.0);
        final angle = (1 - Curves.easeOutCubic.transform(t)) * math.pi;
        final back = angle > math.pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.002)
            ..rotateY(angle),
          child: back ? _backOf(child) : child,
        );
      },
    );
  }

  /// The same-size card back (mirrored so it reads correctly mid-flip).
  Widget _backOf(Widget card) {
    double width = 46;
    var c = card;
    if (c is Transform) c = c.child!;
    if (c is PlayingCardView) width = c.width;
    return PlayingCardView(card: null, width: width, faceUp: false);
  }
}

class _RaisePanel extends StatelessWidget {
  const _RaisePanel({required this.game, required this.value, required this.onChanged});
  final PokerGame game;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final me = game.you;
    final lo = game.minRaiseTo(me), hi = game.maxRaiseTo(me);
    final pot = game.pot;
    int clampTo(int v) => v.clamp(lo, hi);
    final presets = [
      (l.pokerMin, lo),
      (l.pokerHalfPot, clampTo(game.currentBet + pot ~/ 2)),
      (l.pokerFullPot, clampTo(game.currentBet + pot)),
      (l.pokerAllIn, hi),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: AuraGlass.decoration(radius: 16, shadow: false),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < presets.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(presets[i].$2),
                    child: Container(
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: value == presets[i].$2 ? AuraColors.brandPurple.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.07),
                      ),
                      child: Text(presets[i].$1, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (hi > lo)
            Slider(
              value: value.clamp(lo, hi).toDouble(),
              min: lo.toDouble(),
              max: hi.toDouble(),
              activeColor: AuraColors.brandPink,
              onChanged: (v) {
                // Snap to the big blind.
                final bb = game.bigBlind;
                onChanged(clampTo((v / bb).round() * bb));
              },
            ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.game,
    required this.enabled,
    required this.raising,
    required this.raiseTo,
    required this.onFold,
    required this.onCheckCall,
    required this.onRaise,
  });
  final PokerGame game;
  final bool enabled;
  final bool raising;
  final int raiseTo;
  final VoidCallback onFold;
  final VoidCallback onCheckCall;
  final VoidCallback onRaise;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final me = game.you;
    final call = game.toCall(me);
    final canRaise = enabled && game.maxRaiseTo(me) > game.currentBet && me.chips > call;
    Widget button(String label, List<Color> colors, VoidCallback? onTap) => Expanded(
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
              boxShadow: onTap == null ? null : [BoxShadow(color: colors.first.withValues(alpha: 0.35), blurRadius: 12, spreadRadius: -4)],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                child: Text(
                  label,
                  style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Row(
      children: [
        button(l.pokerFold, const [Color(0xFFF43F5E), Color(0xFFBE123C)], enabled ? onFold : null),
        const SizedBox(width: 8),
        button(
          call == 0 ? l.pokerCheck : (call >= me.chips ? l.pokerAllIn : l.pokerCall(_fmt(call))),
          const [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
          enabled ? onCheckCall : null,
        ),
        const SizedBox(width: 8),
        button(
          raising ? (raiseTo >= game.maxRaiseTo(me) ? l.pokerAllIn : l.pokerRaiseTo(_fmt(raiseTo))) : l.pokerRaise,
          const [Color(0xFF22C55E), Color(0xFF15803D)],
          canRaise ? onRaise : null,
        ),
      ],
    );
  }
}
