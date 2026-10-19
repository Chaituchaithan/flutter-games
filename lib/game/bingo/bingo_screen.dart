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

  /// Tumbling balls in the blower.
  late final AnimationController _tumble = AnimationController(vsync: this, duration: const Duration(seconds: 6))
    ..repeat();

  /// The win celebration (winning cells light up in turn + confetti).
  late final AnimationController _party = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  /// Your completed group when you win (lit cell by cell).
  List<int>? _winGroup;

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
    _tumble.dispose();
    _party.dispose();
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
    _tumble.stop();
    final w = _game.winner;
    if (!resigned && w != null) {
      // Celebrate first: your winning cells light up with confetti, or the
      // computer's BINGO! banner shows — then the result screen.
      if (w == 0) _winGroup = winningGroup(_game.seats[0].marked, _game.pattern);
      _party.forward(from: 0);
      setState(() {});
      endGame(delay: Duration(milliseconds: w == 0 ? 2800 : 2200));
      return;
    }
    endGame(immediate: resigned);
  }

  @override
  void pauseGame() {
    super.pauseGame();
    _stopTimers();
    _tumble.stop();
  }

  @override
  String get pauseSubtitle => context.l10n.ballOf(_game.called.length);

  @override
  void resumeGame() {
    _tumble.repeat();
    super.resumeGame();
  }

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
          // Quick Play vs the computer: nothing to earn.
          practice: true,
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
    final w = _game.winner;
    return guardBack(
      AuraScaffold(
      // Slimmer side margins so the board can be as large as possible.
      padding: const EdgeInsets.symmetric(horizontal: 12),
      body: Stack(
        children: [
          Positioned.fill(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocalGameHeader(
            title: '🎱 Bingo',
            subtitle: '${l.ballOf(_game.called.length)} · $_patternName',
            live: !_isOver,
            onPause: openPause,
          ),
          const SizedBox(height: 8),
          // Other players' progress: compact chips (the card gets the room).
          Row(
            children: [
              for (var s = 1; s < _game.seats.length; s++) ...[
                if (s > 1) const SizedBox(width: 6),
                Expanded(
                  child: _RivalChip(
                    name: _name(s),
                    initials: diceBotNames[s - 1].$2,
                    needs: l.needsN(_game.seats[s].needed(_game.pattern)),
                    color: _colColors[(s + 1) % 5],
                    hot: _game.seats[s].needed(_game.pattern) <= 1 && !_isOver,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _Caller(
            game: _game,
            ring: _callRing,
            tumble: _tumble,
            phrases: Localizations.localeOf(context).languageCode == 'en',
            onTap: () => _showCalledBoard(context, _game.called.toSet()),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 0.91, // 5×5 square cells + the B-I-N-G-O header
                child: _CardView(
                  seat: me,
                  called: _game.called.toSet(),
                  onTap: _tapCell,
                  pulse: _pulse,
                  party: _party,
                  // Hint called-but-unmarked numbers only when daubing by hand.
                  hintCalled: !_autoDaub && !_isOver,
                  nearWin: _isOver ? const {} : oneToGo(me.marked, _game.pattern),
                  winGroup: _winGroup,
                ),
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
      )),
          // Win moment: confetti (you) or the computer's BINGO! banner.
          if (w != null && !resigned)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _party,
                  builder: (_, _) => CustomPaint(
                    painter: w == 0 ? _ConfettiPainter(_party.value) : null,
                    child: Center(
                      child: _BingoShout(
                        t: _party.value,
                        text: w == 0 ? l.bingoButton : l.botCalledBingo(_name(w)),
                        color: w == 0 ? AuraColors.brandPink : _colColors[(w + 1) % 5],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }
}

/// A computer player: avatar, name and how close they are ("Needs 2");
/// glows when one away.
class _RivalChip extends StatelessWidget {
  const _RivalChip({required this.name, required this.initials, required this.needs, required this.color, required this.hot});
  final String name;
  final String initials;
  final String needs;
  final Color color;
  final bool hot;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      color: hot ? color.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.05),
      border: Border.all(color: hot ? color : Colors.white.withValues(alpha: 0.12)),
      boxShadow: [BoxShadow(color: color.withValues(alpha: hot ? 0.45 : 0), blurRadius: 12)],
    ),
    child: Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.3)!])),
          child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              Text(needs, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: hot ? color : Colors.white60, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Every number 1–75 by column, the called ones lit (tap on the caller).
void _showCalledBoard(BuildContext context, Set<int> called) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF120E22),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${context.l10n.calledNumbers} · ${called.length}/75',
              style: AuraText.cardTitle.copyWith(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            for (var c = 0; c < 5; c++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _colColors[c], borderRadius: BorderRadius.circular(7)),
                      child: Text(
                        'BINGO'[c],
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Wrap(
                        spacing: 3,
                        runSpacing: 3,
                        children: [
                          for (var n = c * 15 + 1; n <= c * 15 + 15; n++)
                            Container(
                              width: 19,
                              height: 19,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: called.contains(n) ? _colColors[c] : Colors.white.withValues(alpha: 0.06),
                                boxShadow: called.contains(n)
                                    ? [BoxShadow(color: _colColors[c].withValues(alpha: 0.5), blurRadius: 6)]
                                    : null,
                              ),
                              child: Text(
                                '$n',
                                style: TextStyle(
                                  color: called.contains(n) ? Colors.white : Colors.white38,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Classic bingo calls for a few numbers (English only).
const _calls = {
  1: "Kelly's eye",
  7: 'Lucky seven',
  11: 'Legs eleven',
  13: 'Unlucky for some',
  21: 'Key of the door',
  22: 'Two little ducks',
  45: 'Halfway there',
  50: 'Half a century',
  66: 'Clickety click',
  75: 'The last one',
};

/// The caller: the ball blower (tumbling balls), the drawn ball beside it
/// with a ring counting to the next call, the call line, and the last balls.
/// Tap for the full called-numbers board.
class _Caller extends StatelessWidget {
  const _Caller({
    required this.game,
    required this.ring,
    required this.tumble,
    required this.phrases,
    required this.onTap,
  });
  final BingoGame game;
  final Animation<double> ring;
  final Animation<double> tumble;
  final bool phrases;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final recent = game.called.reversed.skip(1).take(4).toList();
    final current = game.current;
    final call = current == null ? null : '${bingoLetter(current)}-$current';
    final phrase = current != null && phrases ? _calls[current] : null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: AuraGlass.decoration(radius: 18, shadow: false),
        child: Row(
          children: [
            // The blower.
            SizedBox(
              width: 56,
              height: 64,
              child: AnimatedBuilder(
                animation: tumble,
                builder: (_, _) => CustomPaint(painter: _BlowerPainter(tumble.value, game.called.length)),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 68,
              height: 68,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: ring,
                    builder: (_, _) => SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: 1 - ring.value,
                        strokeWidth: 4,
                        color: AuraColors.accentGlow,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  // The drawn ball rolls in from the blower (left).
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 650),
                    transitionBuilder: (child, a) {
                      // The previous ball just fades; only the new one rolls in.
                      if (child.key != ValueKey(current)) return FadeTransition(opacity: a, child: child);
                      final c = CurvedAnimation(parent: a, curve: Curves.easeOutBack);
                      return SlideTransition(
                        position: Tween(begin: const Offset(-1.1, -0.2), end: Offset.zero).animate(c),
                        child: RotationTransition(
                          turns: Tween(begin: -0.6, end: 0.0).animate(c),
                          child: ScaleTransition(scale: Tween(begin: 0.5, end: 1.0).animate(c), child: child),
                        ),
                      );
                    },
                    child: current == null
                        ? const SizedBox(key: ValueKey(0), width: 56, height: 56)
                        : BingoBall(key: ValueKey(current), number: current, size: 56),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          call ?? context.l10n.ballOf(game.called.length),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AuraText.cardTitle.copyWith(fontSize: 17),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(context.l10n.ballOf(game.called.length), style: AuraText.caption),
                    ],
                  ),
                  SizedBox(
                    height: 16,
                    child: Text(
                      phrase ?? context.l10n.tapForBoard,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: phrase != null ? AuraColors.amber : Colors.white38,
                        fontSize: 11.5,
                        fontStyle: phrase != null ? FontStyle.italic : FontStyle.normal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (var i = 0; i < recent.length; i++) ...[
                        Opacity(opacity: 1 - i * 0.15, child: BingoBall(number: recent[i], size: 26)),
                        const SizedBox(width: 5),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A glass blower dome with balls tumbling in the air jet; it empties a
/// little as balls are called.
class _BlowerPainter extends CustomPainter {
  _BlowerPainter(this.t, this.calledCount);
  final double t;
  final int calledCount;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.width / 2 + 2);
    final r = size.width / 2 - 2;
    // Stand.
    final stand = Path()
      ..moveTo(c.dx - r * 0.45, c.dy + r * 0.85)
      ..lineTo(c.dx + r * 0.45, c.dy + r * 0.85)
      ..lineTo(c.dx + r * 0.6, size.height)
      ..lineTo(c.dx - r * 0.6, size.height)
      ..close();
    canvas.drawPath(
      stand,
      Paint()..shader = const LinearGradient(colors: [Color(0xFFB45309), Color(0xFFFDE68A), Color(0xFF92400E)]).createShader(stand.getBounds()),
    );
    // Dome glass.
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF22D3EE).withValues(alpha: 0.06));
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r - 1.5)));
    final balls = math.max(6, 16 - calledCount ~/ 6);
    for (var i = 0; i < balls; i++) {
      final speed = 1 + (i % 4) * 0.35;
      final a = t * 2 * math.pi * speed + i * 2.399;
      final orbit = r * (0.25 + 0.55 * ((i * 0.618) % 1));
      // The jet lifts balls from the bottom: bias upward with a bounce.
      final bounce = math.sin(t * 2 * math.pi * (2 + i % 3) + i) * r * 0.18;
      final p = c + Offset(math.cos(a) * orbit, math.sin(a) * orbit * 0.8 + bounce);
      final col = _colColors[i % 5];
      canvas.drawCircle(p, r * 0.16, Paint()..color = col);
      canvas.drawCircle(p - Offset(r * 0.05, r * 0.05), r * 0.06, Paint()..color = Colors.white.withValues(alpha: 0.7));
    }
    canvas.restore();
    // Rim + glass highlight.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.35),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 5),
      math.pi * 1.1,
      math.pi * 0.45,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.4),
    );
  }

  @override
  bool shouldRepaint(_BlowerPainter old) => old.t != t || old.calledCount != calledCount;
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

/// Your card: B I N G O header and the 5×5 numbers. Daubs stamp on with an
/// ink splash; called-but-unmarked numbers glow (hand daubing), "1 to go"
/// cells shine amber, and your winning cells light up in turn.
class _CardView extends StatelessWidget {
  const _CardView({
    required this.seat,
    required this.called,
    required this.onTap,
    required this.pulse,
    required this.party,
    required this.hintCalled,
    required this.nearWin,
    this.winGroup,
  });
  final BingoSeat seat;
  final Set<int> called;
  final ValueChanged<int> onTap;
  final Animation<double> pulse;
  final Animation<double> party;
  final bool hintCalled;
  final Set<int> nearWin;
  final List<int>? winGroup;

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
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color.lerp(_colColors[c], Colors.white, 0.18)!, _colColors[c]],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [BoxShadow(color: _colColors[c].withValues(alpha: 0.45), blurRadius: 10, spreadRadius: -2)],
                    ),
                    child: Text(
                      'BINGO'[c],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AuraText.displayFamily,
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        shadows: const [Shadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1))],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: Listenable.merge([pulse, party]),
              // Five rows sharing the height (cells stretch to fit — never
              // cut off when the card is short).
              builder: (_, _) => Column(
                children: [
                  for (var row = 0; row < 5; row++)
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var col = 0; col < 5; col++)
                            Expanded(child: _cell(row * 5 + col)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(int i) => GestureDetector(
    onTap: () => onTap(i),
    child: _Cell(
      number: seat.card.cells[i],
      color: _colColors[i % 5],
      daubed: seat.marked.contains(i),
      callable: hintCalled && !seat.marked.contains(i) && called.contains(seat.card.cells[i]),
      near: nearWin.contains(i),
      pulse: math.sin(pulse.value * 2 * math.pi) * 0.5 + 0.5,
      win: _winLight(i),
    ),
  );

  /// 0 → 1 as this winning cell lights up (one after another); 0 otherwise.
  double _winLight(int i) {
    final g = winGroup;
    if (g == null) return 0;
    final k = g.indexOf(i);
    if (k < 0) return 0;
    final start = k * 0.08;
    return ((party.value - start) / 0.12).clamp(0.0, 1.0);
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.number,
    required this.color,
    required this.daubed,
    required this.callable,
    required this.near,
    required this.pulse,
    required this.win,
  });
  final int number;
  final Color color;
  final bool daubed;

  /// Called but not marked yet (hand daubing hint).
  final bool callable;

  /// Marking this cell would complete a pattern.
  final bool near;
  final double pulse;

  /// Winning-cell light (0..1).
  final double win;

  @override
  Widget build(BuildContext context) {
    final free = number == 0;
    final glow = win > 0
        ? AuraColors.amber
        : near
        ? AuraColors.amber
        : callable
        ? color
        : null;
    final glowA = win > 0 ? 0.9 * win : (near ? 0.35 + 0.35 * pulse : (callable ? 0.25 + 0.4 * pulse : 0.0));
    return Container(
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: win > 0
              ? [Color.lerp(const Color(0xFFFDFBFF), const Color(0xFFFDE68A), win)!, Color.lerp(const Color(0xFFE3DDF2), AuraColors.amber, win)!]
              : const [Color(0xFFFDFBFF), Color(0xFFE3DDF2)],
        ),
        border: glow == null ? null : Border.all(color: glow.withValues(alpha: glowA), width: 2),
        boxShadow: glow == null ? null : [BoxShadow(color: glow.withValues(alpha: glowA * 0.8), blurRadius: 10)],
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
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
          // The daub: an ink splash ring, then the stamp.
          if (daubed)
            TweenAnimationBuilder<double>(
              key: const ValueKey('daub'),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 520),
              builder: (_, t, _) => CustomPaint(
                size: Size.infinite,
                painter: _DaubPainter(t, free ? AuraColors.brandPink : color),
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
                shadows: const [Shadow(color: Colors.black38, blurRadius: 3)],
              ),
            ),
          if (near && !daubed)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(color: AuraColors.amber, borderRadius: BorderRadius.circular(5)),
                child: Text(
                  context.l10n.oneToGoTag,
                  style: const TextStyle(color: Color(0xFF1F1A2E), fontSize: 6.5, fontWeight: FontWeight.w900),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ink-stamp daub: a splash ring bursts out, the round stamp lands with a
/// slight overshoot and a few droplets.
class _DaubPainter extends CustomPainter {
  _DaubPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - 5;
    // Splash ring.
    if (t < 1) {
      canvas.drawCircle(
        c,
        r * (0.6 + 0.8 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - t)
          ..color = color.withValues(alpha: 0.6 * (1 - t)),
      );
    }
    final land = Curves.easeOutBack.transform((t / 0.6).clamp(0.0, 1.0));
    final rr = r * land;
    canvas.drawCircle(
      c,
      rr,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: [Color.lerp(color, Colors.white, 0.25)!.withValues(alpha: 0.92), color.withValues(alpha: 0.88)],
        ).createShader(Rect.fromCircle(center: c, radius: math.max(rr, 1))),
    );
    // Droplets.
    for (var i = 0; i < 5; i++) {
      final a = i * 1.257 + 0.4;
      final d = rr + 2 + 2 * (i % 2);
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * d, 1.4 * land, Paint()..color = color.withValues(alpha: 0.8));
    }
  }

  @override
  bool shouldRepaint(_DaubPainter old) => old.t != t || old.color != color;
}

/// Falling confetti over the screen while you celebrate.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);
    for (var i = 0; i < 90; i++) {
      final x0 = rng.nextDouble() * size.width;
      final speed = 0.6 + rng.nextDouble() * 0.8;
      final delay = rng.nextDouble() * 0.35;
      final p = ((t - delay) * speed * 1.6).clamp(0.0, 1.2);
      if (p <= 0) continue;
      final y = -20 + p * (size.height + 40);
      final sway = math.sin(p * 9 + i) * 18;
      final spin = p * 14 + i;
      canvas.save();
      canvas.translate(x0 + sway, y);
      canvas.rotate(spin);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: 7, height: 3 + 4 * math.cos(spin).abs()),
        Paint()..color = _colColors[i % 5].withValues(alpha: t > 0.85 ? (1 - t) / 0.15 : 1),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// The big "BINGO!" (or "Mia called BINGO!") that pops over the card.
class _BingoShout extends StatelessWidget {
  const _BingoShout({required this.t, required this.text, required this.color});
  final double t;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final inT = Curves.elasticOut.transform((t / 0.3).clamp(0.0, 1.0));
    return Opacity(
      opacity: t < 0.05 ? t / 0.05 : 1,
      child: Transform.scale(
        scale: 0.4 + 0.6 * inT,
        child: Transform.rotate(
          angle: -0.08,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(colors: [color, Color.lerp(color, AuraColors.amber, 0.5)!]),
              border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 40)],
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: Colors.white,
                fontSize: text.length > 10 ? 24 : 44,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                shadows: const [Shadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
