import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../app/screen_orientation.dart';
import '../../configs/games/snooker/snooker_config.dart';
import '../../l10n/l10n.dart';
import '../../screens/match/match_result_screen.dart';
import '../../widgets/aura.dart';
import '../common/board_game_setup.dart';
import '../common/local_game_flow.dart';
import '../common/turn_timer.dart';
import 'snooker_engine.dart';
import 'snooker_table_view.dart';

const _bot = ('Nova', 'NV');
const _youColor = Color(0xFFA78BFA);
const _botColor = Color(0xFF22D3EE);

/// Quick Play setup → [SnookerScreen]: difficulty and time per shot.
class SnookerSetupScreen extends StatelessWidget {
  const SnookerSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => BoardGameSetupScreen(
    title: snookerConfig.displayName,
    blurb: context.l10n.snookerBlurb,
    timeOptions: const [(label: '30s', ms: 30 * 1000), (label: '1m', ms: 60 * 1000), (label: '∞', ms: null)],
    defaultClockMs: 60 * 1000,
    timeRule: context.l10n.snookerTimeUp,
    start: (_, difficulty, clockMs) => SnookerScreen(difficulty: difficulty, clockMs: clockMs),
  );
}

/// A frame of snooker vs the computer. Drag on the table to swing the cue,
/// nudge it with the fine-aim strip, choose where the tip lands on the spin
/// pad, then pull the power bar and let go to strike.
class SnookerScreen extends StatefulWidget {
  const SnookerScreen({super.key, this.difficulty = 2, this.clockMs = 60 * 1000, this.seed});

  final int difficulty;
  final int? clockMs;
  final int? seed;

  @override
  State<SnookerScreen> createState() => _SnookerScreenState();
}

/// The computer's shot as it plays out: settle on the line, draw back, strike.
class _BotPlan {
  _BotPlan(this.fromAngle, this.shot);
  final double fromAngle;
  final ({double x, double y, double dx, double dy, double power, double side, double top}) shot;
  double t = 0;
}

class _SnookerScreenState extends State<SnookerScreen> with LocalGameFlow, SingleTickerProviderStateMixin {
  late final math.Random _rng = widget.seed == null ? math.Random() : math.Random(widget.seed);
  late final SnookerGame _game = SnookerGame(rng: _rng)
    ..onPocket = _onPocket
    ..onImpact = _onImpact;
  late final TurnTimer _timer = TurnTimer(limitMs: widget.clockMs, onExpire: _timeout);
  late final Ticker _ticker = createTicker(_tick);
  Duration _lastTick = Duration.zero;
  Duration _lastKnock = Duration.zero;
  bool _wasMoving = false;

  double _angle = -math.pi / 2;
  double _power = 0;
  Offset _tip = Offset.zero;
  bool _dragCue = false;

  _BotPlan? _plan;
  String? _event;

  /// Each player's latest pots, newest last (the top bar shows six).
  final List<List<SnookerKind>> _potted = [[], []];

  @override
  void initState() {
    super.initState();
    // Snooker plays on its side, like a real table in front of you.
    LandscapeMode.enter();
    _game.addListener(_onChange);
    _timer.addListener(_onChange);
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _beginTurn());
  }

  @override
  void dispose() {
    disposeFlow();
    _ticker.dispose();
    _timer.dispose();
    _game.removeListener(_onChange);
    _game.dispose();
    LandscapeMode.exit();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _onPocket(SnookerKind k) {
    if (k != SnookerKind.cue) {
      final mine = _potted[_game.turn]..add(k);
      if (mine.length > 6) mine.removeAt(0);
    }
    if (k == SnookerKind.cue) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  /// A click in the hand for a real knock (not every touch).
  void _onImpact(double speed) {
    if (speed < 0.8 || _lastTick - _lastKnock < const Duration(milliseconds: 80)) return;
    _lastKnock = _lastTick;
    HapticFeedback.selectionClick();
  }

  String _name(int p) => p == 0 ? context.l10n.you : _bot.$1;
  bool get _myTurn => !_game.isOver && !resigned && _game.turn == 0 && !_game.moving;

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 1 / 20);
    _lastTick = elapsed;
    if (paused) return;
    _game.step(dt);
    final plan = _plan;
    if (plan != null) _runPlan(plan, dt);
    if (_wasMoving && !_game.moving) _onShotEnd();
    _wasMoving = _game.moving;
  }

  void _beginTurn() {
    if (!mounted || paused || resigned) return;
    if (_game.isOver) {
      _timer.stop();
      endGame(delay: const Duration(milliseconds: 1400));
      return;
    }
    if (_game.turn == 0) {
      _timer.start();
      _aimAtNearest();
      return;
    }
    _timer.stop();
    scheduleBot(Duration(milliseconds: 700 + _rng.nextInt(600)), () {
      final shot = _game.botShot(widget.difficulty);
      _game.placeCue(shot.x, shot.y);
      setState(() {
        _plan = _BotPlan(_angle, shot);
        _tip = Offset.zero;
      });
    }, stillValid: () => _game.turn == 1 && !_game.moving);
  }

  /// Start the player's aim on the closest ball they may hit.
  void _aimAtNearest() {
    final c = _game.cue;
    SnookerBall? best;
    var bestD = double.infinity;
    for (final b in _game.ballsOn) {
      final d = math.pow(b.x - c.x, 2) + math.pow(b.y - c.y, 2);
      if (d < bestD) {
        bestD = d.toDouble();
        best = b;
      }
    }
    if (best != null) setState(() => _angle = math.atan2(best!.y - c.y, best.x - c.x));
  }

  /// Settle on the line (0.8 s), draw back (0.7 s), strike.
  void _runPlan(_BotPlan p, double dt) {
    p.t += dt;
    final target = math.atan2(p.shot.dy, p.shot.dx);
    var delta = target - p.fromAngle;
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    while (delta < -math.pi) {
      delta += 2 * math.pi;
    }
    if (p.t < 0.8) {
      _angle = p.fromAngle + delta * Curves.easeInOut.transform(p.t / 0.8);
      _power = 0;
    } else if (p.t < 1.5) {
      _angle = target;
      _power = p.shot.power * Curves.easeOut.transform((p.t - 0.8) / 0.7);
    } else {
      _plan = null;
      _power = 0;
      final hit = _game.shoot(p.shot.dx, p.shot.dy, p.shot.power, side: p.shot.side, top: p.shot.top);
      // Never leave the computer stuck on its turn.
      if (!hit) {
        _game.passTurn();
        _beginTurn();
      }
    }
    if (mounted) setState(() {});
  }

  void _onShotEnd() {
    _describe();
    _tip = Offset.zero;
    _beginTurn();
  }

  String _ballName(AppLocalizations l, SnookerKind? k) => switch (k) {
    null => l.snookerAnyColour,
    SnookerKind.cue => '',
    SnookerKind.red => l.snookerRed,
    SnookerKind.yellow => l.snookerYellow,
    SnookerKind.green => l.snookerGreen,
    SnookerKind.brown => l.snookerBrown,
    SnookerKind.blue => l.snookerBlue,
    SnookerKind.pink => l.snookerPink,
    SnookerKind.black => l.snookerBlack,
  };

  void _describe() {
    final l = context.l10n;
    final r = _game.last;
    if (r == null) return;
    final parts = <String>[];
    if (r.foul > 0) {
      if (r.inOff) parts.add(l.snookerInOff);
      parts.add(l.snookerFoul(r.foul, _name(1 - r.player)));
    } else if (r.points > 0) {
      parts.add(l.snookerScored(_name(r.player), r.points));
    } else {
      parts.add(l.snookerNothing(_name(_game.turn)));
    }
    if (_game.freeBall) parts.add(l.snookerFreeBall);
    if (_game.blackGame && !_game.isOver) parts.add(l.snookerBlackGame);
    _event = parts.join(' · ');
  }

  void _timeout() {
    if (!_myTurn) return;
    showAuraToast(context, context.l10n.snookerTimeUp, kind: AuraToastKind.info);
    setState(() {
      _power = 0;
      _event = null;
    });
    _game.passTurn();
    _beginTurn();
  }

  // ── Your shot ──

  void _tablePanStart(DragStartDetails d, SnookerLayout layout) {
    if (!_myTurn || paused) return;
    final (x, y) = layout.toTable(d.localPosition);
    final c = _game.cue;
    final onCue = math.sqrt(math.pow(x - c.x, 2) + math.pow(y - c.y, 2)) < 0.14;
    _dragCue = _game.inHand && onCue;
    if (!_dragCue) _aimAt(x, y);
  }

  void _tablePanUpdate(DragUpdateDetails d, SnookerLayout layout) {
    if (!_myTurn) return;
    final (x, y) = layout.toTable(d.localPosition);
    if (_dragCue) {
      _game.placeCue(x, y);
    } else {
      _aimAt(x, y);
    }
  }

  void _aimAt(double x, double y) {
    final c = _game.cue;
    if (x == c.x && y == c.y) return;
    setState(() => _angle = math.atan2(y - c.y, x - c.x));
  }

  void _strike() {
    final p = _power;
    setState(() => _power = 0);
    if (!_myTurn || paused || p < 0.03) return;
    _timer.stop();
    HapticFeedback.mediumImpact();
    _event = null;
    _game.shoot(math.cos(_angle), math.sin(_angle), p, side: _tip.dx, top: -_tip.dy);
  }

  // ── LocalGameFlow ──

  @override
  String get pauseSubtitle => context.l10n.snookerSubtitle(_game.scores[0], _bot.$1, _game.scores[1], _game.redsLeft);

  @override
  void pauseGame() {
    super.pauseGame();
    _timer.pause();
  }

  @override
  void onResumeGame() {
    _lastTick = Duration.zero;
    if (_myTurn) {
      _timer.resume();
    } else if (!_game.moving && _plan == null) {
      _beginTurn();
    }
  }

  @override
  void showResult() {
    final l = context.l10n;
    final won = !resigned && _game.winner == 0;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchResultScreen(
          outcome: won ? MatchOutcome.victory : MatchOutcome.defeat,
          subtitle: resigned
              ? l.youForfeitedMatch
              : won
              ? l.snookerWinSub(_game.highBreak[0])
              : l.snookerLoseSub(_bot.$1, _game.highBreak[1]),
          youScore: _game.scores[0],
          oppScore: _game.scores[1],
          oppName: _bot.$1,
          oppInitials: _bot.$2,
          // Quick Play vs the computer: nothing to earn.
          practice: true,
          playAgain: (_) => SnookerScreen(difficulty: widget.difficulty, clockMs: widget.clockMs),
        ),
      ),
    );
  }

  String get _hint {
    final l = context.l10n;
    final g = _game;
    if (g.isOver || g.moving) return '';
    if (g.turn == 1) return l.snookerAiming(_bot.$1);
    final on = g.freeBall ? l.snookerFreeBall : l.snookerBallOn(_ballName(l, g.target));
    return '$on · ${g.inHand ? l.snookerPlaceHint : l.snookerAimHint}';
  }

  @override
  Widget build(BuildContext context) => guardBack(
    AuraScaffold(
      padding: EdgeInsets.zero,
      showGlow: false,
      body: LayoutBuilder(
        // Until the phone turns (and on a tall browser window) the screen is
        // still portrait: lay the game out sideways anyway.
        builder: (context, box) =>
            box.maxWidth >= box.maxHeight ? _landscape(context) : RotatedBox(quarterTurns: 1, child: _landscape(context)),
      ),
    ),
  );

  Widget _landscape(BuildContext context) {
    final l = context.l10n;
    final g = _game;
    final message = g.moving || _event == null ? _hint : (_myTurn ? '${_event!} · $_hint' : _event!);
    final cueUp = !g.isOver && !g.moving && g.balls.contains(g.cue);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopBar(
            onPause: openPause,
            redsLeft: g.redsLeft,
            players: [
              (
                name: l.you,
                initials: 'YOU',
                color: _youColor,
                score: g.scores[0],
                potted: _potted[0],
                active: !g.isOver && g.turn == 0,
                breakPoints: g.turn == 0 ? g.currentBreak : 0,
                progress: !g.isOver && g.turn == 0 && !g.moving ? _timer.fraction : null,
              ),
              (
                name: _bot.$1,
                initials: _bot.$2,
                color: _botColor,
                score: g.scores[1],
                potted: _potted[1],
                active: !g.isOver && g.turn == 1,
                breakPoints: g.turn == 1 ? g.currentBreak : 0,
                progress: null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left: spin, then power.
                Opacity(
                  opacity: _myTurn ? 1 : 0.45,
                  child: SizedBox(
                    width: 58,
                    child: Column(
                      children: [
                        _SpinPad(
                          tip: _tip,
                          label: l.snookerSpin,
                          onChanged: _myTurn ? (t) => setState(() => _tip = t) : null,
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _PowerBar(
                            key: const ValueKey('snooker-power'),
                            label: l.snookerPower,
                            power: _power,
                            onChanged: _myTurn ? (p) => setState(() => _power = p) : null,
                            onRelease: _strike,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _table(cueUp)),
                      SizedBox(
                        height: 18,
                        child: Center(
                          child: Text(
                            message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AuraText.cardSub.copyWith(fontSize: 11, color: _myTurn ? AuraColors.amber : Colors.white70),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Right: the ball on, then fine aim.
                SizedBox(
                  width: 58,
                  child: Column(
                    children: [
                      _BallOn(kind: g.isOver ? null : g.target, freeBall: g.freeBall),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Opacity(
                          opacity: _myTurn ? 1 : 0.45,
                          child: _FineAim(
                            label: l.snookerFineAim,
                            onNudge: _myTurn ? (d) => setState(() => _angle += d * 0.0012) : null,
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
    );
  }

  Widget _table(bool cueUp) => LayoutBuilder(
    builder: (context, box) {
      final aspect = SnookerLayout.aspectFor(landscape: true);
      var h = box.maxHeight;
      var w = h * aspect;
      if (w > box.maxWidth) {
        w = box.maxWidth;
        h = w / aspect;
      }
      final size = Size(w, h);
      final layout = SnookerLayout(size, landscape: true);
      final g = _game;
      return Center(
        child: GestureDetector(
          onPanStart: (d) => _tablePanStart(d, layout),
          onPanUpdate: (d) => _tablePanUpdate(d, layout),
          child: SizedBox.fromSize(
            size: size,
            child: Stack(
              children: [
                RepaintBoundary(
                  child: CustomPaint(size: size, painter: const SnookerTablePainter(landscape: true)),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    size: size,
                    painter: SnookerBallsPainter(
                      game: g,
                      aim: cueUp ? (math.cos(_angle), math.sin(_angle)) : null,
                      power: _power,
                      showGuide: _myTurn,
                      inHandRing: _myTurn && g.inHand,
                      landscape: true,
                      repaint: g,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

typedef _Player = ({
  String name,
  String initials,
  Color color,
  int score,
  List<SnookerKind> potted,
  bool active,
  int breakPoints,
  double? progress,
});

/// Across the top: pause, each player with their latest pots, the score
/// between them and the reds still on the table.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onPause, required this.players, required this.redsLeft});
  final VoidCallback onPause;
  final List<_Player> players;
  final int redsLeft;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 46,
    child: Row(
      children: [
        _SquareButton(icon: Icons.pause_rounded, onTap: onPause),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2A3F78), Color(0xFF16244D)],
              ),
              border: Border.all(color: const Color(0xFF4F6BB5)),
            ),
            child: Row(
              children: [
                Expanded(child: _PlayerPill(p: players[0], mirrored: false)),
                _Score(left: players[0].score, right: players[1].score, redsLeft: redsLeft),
                Expanded(child: _PlayerPill(p: players[1], mirrored: true)),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF2B5FD9),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF8FB2FF), width: 1.5),
        ),
        child: Icon(icon, color: Colors.white, size: 26),
      ),
    ),
  );
}

class _PlayerPill extends StatelessWidget {
  const _PlayerPill({required this.p, required this.mirrored});
  final _Player p;
  final bool mirrored;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: p.color.withValues(alpha: 0.9),
        border: Border.all(color: p.active ? AuraColors.amber : Colors.white24, width: p.active ? 2 : 1),
        boxShadow: p.active ? [BoxShadow(color: AuraColors.amber.withValues(alpha: 0.5), blurRadius: 8)] : null,
      ),
      child: Text(
        p.initials,
        style: AuraText.cardSub.copyWith(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF14102A)),
      ),
    );
    final name = p.breakPoints > 0 ? '${p.name} · ${p.breakPoints}' : p.name;
    final info = Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: mirrored ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AuraText.cardSub.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 3),
          _PottedRow(potted: p.potted, mirrored: mirrored),
          if (p.progress != null) ...[
            const SizedBox(height: 2),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: p.progress,
                minHeight: 2.5,
                backgroundColor: Colors.white12,
                color: AuraColors.amber,
              ),
            ),
          ],
        ],
      ),
    );
    return Row(
      children: mirrored
          ? [info, const SizedBox(width: 8), avatar]
          : [avatar, const SizedBox(width: 8), info],
    );
  }
}

/// Six sockets, the latest pots filling them.
class _PottedRow extends StatelessWidget {
  const _PottedRow({required this.potted, required this.mirrored});
  final List<SnookerKind> potted;
  final bool mirrored;

  @override
  Widget build(BuildContext context) {
    final cells = [
      for (var i = 0; i < 6; i++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: i < potted.length
              ? SnookerBallIcon(kind: potted[i], size: 13)
              : Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0C1533),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                ),
        ),
    ];
    return Row(mainAxisSize: MainAxisSize.min, children: mirrored ? cells.reversed.toList() : cells);
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.left, required this.right, required this.redsLeft});
  final int left, right, redsLeft;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xFF0C1533),
            border: Border.all(color: const Color(0xFF4F6BB5)),
          ),
          child: Text(
            '$left : $right',
            style: AuraText.cardSub.copyWith(
              fontSize: 15, height: 1.2,
              fontWeight: FontWeight.w800,
              fontStyle: FontStyle.italic,
              color: AuraColors.amber,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SnookerBallIcon(kind: SnookerKind.red, size: 10),
            const SizedBox(width: 3),
            Text('× $redsLeft', style: AuraText.cardSub.copyWith(fontSize: 10, color: Colors.white70)),
          ],
        ),
      ],
    ),
  );
}

/// The ball you must hit next (any colour: all six).
class _BallOn extends StatelessWidget {
  const _BallOn({required this.kind, required this.freeBall});
  final SnookerKind? kind;
  final bool freeBall;

  static const _colours = [
    SnookerKind.yellow,
    SnookerKind.green,
    SnookerKind.brown,
    SnookerKind.blue,
    SnookerKind.pink,
    SnookerKind.black,
  ];

  @override
  Widget build(BuildContext context) {
    final k = kind;
    return SizedBox(
      width: 50,
      height: 50,
      child: k != null && !freeBall
          ? SnookerBallIcon(kind: k, size: 50)
          : Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              spacing: 2,
              runSpacing: 2,
              children: [for (final c in _colours) SnookerBallIcon(kind: c, size: 14)],
            ),
    );
  }
}

/// Choose where the tip lands on the cue ball: above = top spin, below =
/// screw, either side = side.
class _SpinPad extends StatelessWidget {
  const _SpinPad({required this.tip, required this.label, required this.onChanged});
  final Offset tip;
  final String label;
  final ValueChanged<Offset>? onChanged;

  static const _size = 54.0;

  void _at(Offset p) {
    var t = (p - const Offset(_size / 2, _size / 2)) / (_size / 2);
    if (t.distance > 1) t = t / t.distance;
    // Near the centre means a plain centre-ball hit.
    onChanged?.call(t.distance < 0.12 ? Offset.zero : t);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _at(d.localPosition),
      onPanUpdate: (d) => _at(d.localPosition),
      child: SnookerBallIcon(kind: SnookerKind.cue, size: _size, tip: tip),
    ),
  );
}

/// A tall ribbed wheel: dragging it up or down turns the cue by hair's
/// breadths.
class _FineAim extends StatefulWidget {
  const _FineAim({required this.label, required this.onNudge});
  final String label;
  final ValueChanged<double>? onNudge;

  @override
  State<_FineAim> createState() => _FineAimState();
}

class _FineAimState extends State<_FineAim> {
  double _travel = 0;

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) {
        if (widget.onNudge == null) return;
        setState(() => _travel += d.delta.dy);
        widget.onNudge!(d.delta.dy);
      },
      child: Center(
        child: Container(
          width: 30,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(colors: [Color(0xFF0B0F1E), Color(0xFF2A3247), Color(0xFF0B0F1E)]),
            border: Border.all(color: const Color(0xFF4F6BB5)),
          ),
          child: CustomPaint(painter: _RibsPainter(_travel), size: Size.infinite),
        ),
      ),
    ),
  );
}

class _RibsPainter extends CustomPainter {
  const _RibsPainter(this.travel);
  final double travel;

  @override
  bool shouldRepaint(_RibsPainter old) => old.travel != travel;

  @override
  void paint(Canvas canvas, Size size) {
    // Ribs on a turning wheel: closer together towards its ends.
    final mid = size.height / 2;
    for (var k = -40; k <= 40; k++) {
      final a = (k * 8 + travel % 8) / mid; // −1..1 across the wheel
      if (a.abs() >= 1) continue;
      final y = mid + math.sin(a * math.pi / 2) * mid;
      final lit = math.cos(a * math.pi / 2);
      canvas.drawLine(
        Offset(5, y),
        Offset(size.width - 5, y),
        Paint()
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.06 + 0.22 * lit),
      );
    }
  }
}

/// Pull down the bar for power; let go to strike, slide back to the top to
/// call it off. A cue sticks out at the level you've pulled to.
class _PowerBar extends StatelessWidget {
  const _PowerBar({super.key, required this.label, required this.power, required this.onChanged, required this.onRelease});
  final String label;
  final double power;
  final ValueChanged<double>? onChanged;
  final VoidCallback onRelease;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    value: '${(power * 100).round()}%',
    child: LayoutBuilder(
      builder: (context, box) {
        void at(Offset p) => onChanged?.call((p.dy / box.maxHeight).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) => at(d.localPosition),
          onVerticalDragUpdate: (d) => at(d.localPosition),
          onVerticalDragEnd: (_) => onRelease(),
          child: CustomPaint(size: Size(box.maxWidth, box.maxHeight), painter: _PowerPainter(power)),
        );
      },
    ),
  );
}

class _PowerPainter extends CustomPainter {
  const _PowerPainter(this.power);
  final double power;

  @override
  bool shouldRepaint(_PowerPainter old) => old.power != power;

  @override
  void paint(Canvas canvas, Size size) {
    const w = 26.0;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH((size.width - w) / 2, 0, w, size.height),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      track,
      Paint()..shader = const LinearGradient(colors: [Color(0xFF05070F), Color(0xFF1A2033), Color(0xFF05070F)]).createShader(track.outerRect),
    );
    // The pulled-back part, green to red.
    if (power > 0) {
      final fill = Rect.fromLTRB(track.left, 0, track.right, size.height * power);
      canvas.save();
      canvas.clipRRect(track);
      canvas.drawRect(
        fill,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF22C55E), Color(0xFFF59E0B), Color(0xFFEF4444)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
      canvas.restore();
    }
    // A ruler down the middle.
    for (var i = 1; i < 20; i++) {
      final y = size.height * i / 20;
      final big = i % 5 == 0;
      canvas.drawLine(
        Offset(size.width / 2 - (big ? 7 : 4), y),
        Offset(size.width / 2 + (big ? 7 : 4), y),
        Paint()
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: big ? 0.45 : 0.25),
      );
    }
    canvas.drawRRect(
      track,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF4F6BB5),
    );
    // The cue across the bar at the pull: shaft, ferrule, blue tip.
    final y = (size.height * power).clamp(6.0, size.height - 6);
    final shaft = RRect.fromRectAndRadius(Rect.fromLTRB(0, y - 3, size.width - 6, y + 3), const Radius.circular(3));
    canvas.drawRRect(shaft.shift(const Offset(1, 2)), Paint()..color = Colors.black45);
    canvas.drawRRect(
      shaft,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFFF2DDAE), Color(0xFFC9A46A)],
        ).createShader(shaft.outerRect),
    );
    canvas.drawRect(Rect.fromLTRB(size.width - 10, y - 3, size.width - 7, y + 3), Paint()..color = const Color(0xFFF2EEE0));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(size.width - 7, y - 3, size.width - 3, y + 3), const Radius.circular(2)),
      Paint()..color = const Color(0xFF3A6EA5),
    );
    // The level marker on the left.
    final m = Path()
      ..moveTo(track.left - 1, y)
      ..lineTo(track.left - 8, y - 5)
      ..lineTo(track.left - 8, y + 5)
      ..close();
    canvas.drawPath(m, Paint()..color = AuraColors.amber);
  }
}
