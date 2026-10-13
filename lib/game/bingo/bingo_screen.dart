import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../screens/match/match_result_screen.dart';
import '../../widgets/aura.dart';
import '../common/dice_game_kit.dart' show SetupTile, diceBotNames;
import '../common/local_game_flow.dart';
import 'bingo_engine.dart';

/// Column colours (B I N G O).
const _colColors = [Color(0xFF3B82F6), Color(0xFFE11D48), Color(0xFFA855F7), Color(0xFF22C55E), Color(0xFFF59E0B)];
Color bingoColor(int n) => _colColors[(n - 1) ~/ 15];

/// Quick Play setup → [BingoScreen]: players, pattern, call speed,
/// difficulty (how fast the computer daubs and claims).
class BingoSetupScreen extends StatefulWidget {
  const BingoSetupScreen({super.key});

  @override
  State<BingoSetupScreen> createState() => _BingoSetupScreenState();
}

class _BingoSetupScreenState extends State<BingoSetupScreen> {
  int _players = 3;
  BingoPattern _pattern = BingoPattern.line;
  int _callMs = 4000;
  int _difficulty = 2;

  Widget _label(String t) => Text(
    t,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
    style: TextStyle(
      fontFamily: AuraText.displayFamily,
      color: Colors.white,
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
    ),
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
          Text('Bingo', style: AuraText.headline.copyWith(fontSize: 24)),
          const SizedBox(height: 6),
          Text(l.bingoBlurb, style: AuraText.cardSub),
          const SizedBox(height: 22),
          SectionBar(l.players),
          const SizedBox(height: 10),
          _row(
            [
              for (final n in const [2, 3, 4]) (n, l.youPlusAi(n - 1)),
            ],
            _players,
            (v) => _players = v,
          ),
          const SizedBox(height: 22),
          SectionBar(l.pattern),
          const SizedBox(height: 10),
          _row(
            [
              (BingoPattern.line, l.patternLine),
              (BingoPattern.corners, l.patternCorners),
              (BingoPattern.fullHouse, l.patternFullHouse),
            ],
            _pattern,
            (v) => _pattern = v,
          ),
          const SizedBox(height: 22),
          SectionBar(l.callSpeed),
          const SizedBox(height: 10),
          _row([(2500, l.speedFast), (4000, l.speedNormal), (6000, l.speedSlow)], _callMs, (v) => _callMs = v),
          const SizedBox(height: 22),
          SectionBar(l.computerPlayers),
          const SizedBox(height: 10),
          _row([(1, l.easy), (2, l.medium), (3, l.hard)], _difficulty, (v) => _difficulty = v),
          const SizedBox(height: 28),
          GradientButton(
            label: l.startGame,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    BingoScreen(players: _players, pattern: _pattern, callMs: _callMs, difficulty: _difficulty),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Bingo vs the computer: the caller (current ball + recent balls + next-call
/// ring), the other players' progress, your card (tap called numbers to
/// daub, or auto-daub) and the BINGO! button. First valid claim wins.
class BingoScreen extends StatefulWidget {
  const BingoScreen({
    super.key,
    this.players = 3,
    this.pattern = BingoPattern.line,
    this.callMs = 4000,
    this.difficulty = 2,
  });

  final int players;
  final BingoPattern pattern;
  final int callMs;

  /// Computer reaction: 1 slow · 2 medium · 3 fast.
  final int difficulty;

  @override
  State<BingoScreen> createState() => _BingoScreenState();
}

class _BingoScreenState extends State<BingoScreen> with LocalGameFlow, TickerProviderStateMixin {
  final _rng = math.Random();
  late final BingoGame _game = BingoGame(players: widget.players, pattern: widget.pattern, rng: _rng)
    ..addListener(_onChange);
  late final AnimationController _callRing = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.callMs),
  );
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  Timer? _caller;
  final List<Timer> _botTimers = [];
  bool _autoDaub = false;
  DateTime? _lockedUntil;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleCall(const Duration(milliseconds: 1200)));
  }

  @override
  void dispose() {
    _stopTimers();
    disposeFlow();
    _callRing.dispose();
    _pulse.dispose();
    _game.removeListener(_onChange);
    _game.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  bool get _isOver => _game.over || resigned;

  void _stopTimers() {
    _caller?.cancel();
    for (final t in _botTimers) {
      t.cancel();
    }
    _botTimers.clear();
    _callRing.stop();
  }

  void _scheduleCall(Duration wait) {
    _caller?.cancel();
    if (_isOver || paused) return;
    _callRing.duration = wait;
    _callRing.forward(from: 0);
    _caller = Timer(wait, _call);
  }

  void _call() {
    if (!mounted || _isOver || paused) return;
    _game.callNext();
    if (_autoDaub) _game.daubAll(0);
    _botsReact();
    if (_game.exhausted && _game.winner == null) {
      _finish();
    } else {
      _scheduleCall(Duration(milliseconds: widget.callMs));
    }
  }

  /// Each computer daubs after a short reaction and claims once complete.
  void _botsReact() {
    final (react, claim) = switch (widget.difficulty) {
      <= 1 => ((900, 1300), (2200, 1800)),
      2 => ((600, 900), (1200, 1200)),
      _ => ((300, 500), (500, 700)),
    };
    for (var s = 1; s < _game.seats.length; s++) {
      final seat = s;
      _botTimers.add(
        Timer(Duration(milliseconds: react.$1 + _rng.nextInt(react.$2)), () {
          if (!mounted || _isOver || paused) return;
          _game.daubAll(seat);
          if (_game.seats[seat].needed(_game.pattern) == 0) {
            _botTimers.add(
              Timer(Duration(milliseconds: claim.$1 + _rng.nextInt(claim.$2)), () {
                if (!mounted || _isOver || paused) return;
                if (_game.claim(seat)) _finish();
              }),
            );
          }
        }),
      );
    }
  }

  void _tapCell(int cell) {
    if (_isOver || paused) return;
    _game.daub(0, cell);
  }

  bool get _locked => _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  void _claim() {
    if (_isOver || paused || _locked) return;
    if (_game.claim(0)) {
      _finish();
    } else {
      // False bingo: claims lock for a few seconds.
      setState(() => _lockedUntil = DateTime.now().add(const Duration(seconds: 4)));
      showAuraToast(context, context.l10n.notYet, kind: AuraToastKind.error);
      Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() {});
      });
    }
  }

  void _finish() {
    _stopTimers();
    endGame(immediate: resigned);
  }

  @override
  void pauseGame() {
    super.pauseGame();
    _stopTimers();
  }

  @override
  String get pauseSubtitle => context.l10n.ballOf(_game.called.length);

  @override
  void onResumeGame() {
    // Bots catch up on what was called, then calling continues.
    _botsReact();
    _scheduleCall(Duration(milliseconds: widget.callMs));
  }

  String _name(int seat) => seat == 0 ? context.l10n.you : diceBotNames[seat - 1].$1;

  @override
  void showResult() {
    final l = context.l10n;
    final w = _game.winner;
    final outcome = resigned || (w != null && w != 0)
        ? MatchOutcome.defeat
        : w == 0
        ? MatchOutcome.victory
        : MatchOutcome.draw;
    final best = [for (var s = 1; s < _game.seats.length; s++) _game.seats[s].marked.length].reduce(math.max);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchResultScreen(
          outcome: outcome,
          subtitle: resigned
              ? l.youForfeitedMatch
              : w == null
              ? l.bingoNoWinner
              : w == 0
              ? l.bingoWinSub(_game.called.length)
              : l.bingoLoseSub(_name(w)),
          youScore: _game.seats[0].marked.length,
          oppScore: best,
          oppName: widget.players == 2 ? _name(1) : l.bestAi,
          oppInitials: widget.players == 2 ? diceBotNames[0].$2 : 'AI',
          reward: switch (outcome) {
            MatchOutcome.victory => '+50 XP',
            MatchOutcome.draw => '+30 XP',
            MatchOutcome.defeat => '+20 XP',
          },
          playAgain: (_) => BingoScreen(
            players: widget.players,
            pattern: widget.pattern,
            callMs: widget.callMs,
            difficulty: widget.difficulty,
          ),
        ),
      ),
    );
  }

  String get _patternName => switch (widget.pattern) {
    BingoPattern.line => context.l10n.patternLine,
    BingoPattern.corners => context.l10n.patternCorners,
    BingoPattern.fullHouse => context.l10n.patternFullHouse,
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final me = _game.seats[0];
    final ready = me.needed(_game.pattern) == 0 && !_isOver;
    return AuraScaffold(
      // Slimmer side margins so the board can be as large as possible.
      padding: const EdgeInsets.symmetric(horizontal: 12),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocalGameHeader(
            title: '🎱 Bingo',
            subtitle: '${l.ballOf(_game.called.length)} · $_patternName',
            live: !_isOver,
            onPause: openPause,
          ),
          const SizedBox(height: 12),
          // Other players' progress.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var s = 1; s < _game.seats.length; s++) ...[
                  if (s > 1) const SizedBox(width: 8),
                  Expanded(
                    child: BoardPlayerCard(
                      name: _name(s),
                      initials: diceBotNames[s - 1].$2,
                      sub: l.needsN(_game.seats[s].needed(_game.pattern)),
                      color: _colColors[(s + 1) % 5],
                      active: _game.seats[s].needed(_game.pattern) <= 1 && !_isOver,
                      turnText: '',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Caller(game: _game, ring: _callRing),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 0.91, // 5×5 square cells + the B-I-N-G-O header
                child: _CardView(seat: me, called: _game.called.toSet(), onTap: _tapCell),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(l.daubHint, textAlign: TextAlign.center, style: AuraText.caption),
          const SizedBox(height: 8),
          Row(
            children: [
              Column(
                children: [
                  Switch(
                    value: _autoDaub,
                    activeTrackColor: AuraColors.brandPurple,
                    onChanged: (v) {
                      setState(() => _autoDaub = v);
                      if (v) _game.daubAll(0);
                    },
                  ),
                  Text(l.autoDaub, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, child) =>
                      Transform.scale(scale: ready ? 1 + 0.04 * math.sin(_pulse.value * 2 * math.pi) : 1, child: child),
                  child: GradientButton(label: l.bingoButton, enabled: !_isOver && !_locked, onPressed: _claim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// The caller: the current ball (drops in), a ring counting to the next
/// call, and the last balls called.
class _Caller extends StatelessWidget {
  const _Caller({required this.game, required this.ring});
  final BingoGame game;
  final Animation<double> ring;

  @override
  Widget build(BuildContext context) {
    final recent = game.called.reversed.skip(1).take(5).toList();
    final current = game.current;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AuraGlass.decoration(radius: 20, shadow: false),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: ring,
                  builder: (_, _) => CircularProgressIndicator(
                    value: 1 - ring.value,
                    strokeWidth: 4,
                    color: AuraColors.accentGlow,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 450),
                  transitionBuilder: (child, a) => ScaleTransition(
                    scale: CurvedAnimation(parent: a, curve: Curves.elasticOut),
                    child: RotationTransition(turns: Tween(begin: -0.25, end: 0.0).animate(a), child: child),
                  ),
                  child: current == null
                      ? const SizedBox(key: ValueKey(0), width: 74, height: 74)
                      : BingoBall(key: ValueKey(current), number: current, size: 74),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.ballOf(game.called.length), style: AuraText.cardTitle.copyWith(fontSize: 15)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final n in recent) ...[
                      Opacity(opacity: 0.85, child: BingoBall(number: n, size: 34)),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A glossy bingo ball: column colour with a white face showing the letter
/// and number.
class BingoBall extends StatelessWidget {
  const BingoBall({super.key, required this.number, required this.size});
  final int number;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = bingoColor(number);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Color.lerp(c, Colors.white, 0.45)!, c, Color.lerp(c, Colors.black, 0.35)!],
          stops: const [0, 0.55, 1],
        ),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.45), blurRadius: size * 0.25)],
      ),
      child: Center(
        child: Container(
          width: size * 0.62,
          height: size * 0.62,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (size > 40)
                Text(
                  bingoLetter(number),
                  style: TextStyle(color: c, fontSize: size * 0.14, fontWeight: FontWeight.w900, height: 1),
                ),
              Text(
                '$number',
                style: TextStyle(
                  color: const Color(0xFF1F1A2E),
                  fontSize: size * (size > 40 ? 0.24 : 0.28),
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Your card: B I N G O header and the 5×5 numbers; daubs stamp on.
class _CardView extends StatelessWidget {
  const _CardView({required this.seat, required this.called, required this.onTap});
  final BingoSeat seat;
  final Set<int> called;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1630), Color(0xFF070510)],
        ),
        border: Border.all(color: const Color(0xFF22D3EE).withValues(alpha: 0.3), width: 1.5),
        boxShadow: [BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3), blurRadius: 30, spreadRadius: -4)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (var c = 0; c < 5; c++)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(color: _colColors[c], borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      'BINGO'[c],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AuraText.displayFamily,
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 5,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < 25; i++)
                  GestureDetector(
                    onTap: () => onTap(i),
                    child: _Cell(number: seat.card.cells[i], daubed: seat.marked.contains(i)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.number, required this.daubed});
  final int number;
  final bool daubed;

  @override
  Widget build(BuildContext context) {
    final free = number == 0;
    return Container(
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFDFBFF), Color(0xFFE3DDF2)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            free ? '★' : '$number',
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: free ? AuraColors.amber : const Color(0xFF1F1A2E),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          // The daub stamp pops on.
          AnimatedScale(
            scale: daubed ? 1 : 0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            child: Container(
              margin: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AuraColors.brandPink.withValues(alpha: 0.75),
                    AuraColors.brandPurple.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),
          ),
          if (daubed)
            Text(
              free ? '★' : '$number',
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}
