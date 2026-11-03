import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

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

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _onPocket(SnookerKind k) {
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
  Widget build(BuildContext context) {
    final l = context.l10n;
    final g = _game;
    String sub(int p) {
      final score = '${g.scores[p]}';
      return g.turn == p && g.currentBreak > 0 ? '$score · ${l.snookerBreak(g.currentBreak)}' : score;
    }

    final message = g.moving || _event == null ? _hint : '${_event!}\n$_hint';
    final cueUp = !g.isOver && !g.moving && g.balls.contains(g.cue);
    return guardBack(
      AuraScaffold(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LocalGameHeader(
              title: '${snookerConfig.icon} ${snookerConfig.displayName}',
              subtitle: l.snookerSubtitle(g.scores[0], _bot.$1, g.scores[1], g.redsLeft),
              live: !g.isOver && !resigned,
              onPause: openPause,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: BoardPlayerCard(
                    name: l.you,
                    initials: 'YOU',
                    sub: sub(0),
                    color: _youColor,
                    active: !g.isOver && g.turn == 0,
                    turnText: !g.isOver && g.turn == 0 ? l.snookerYourShot : null,
                    progress: !g.isOver && g.turn == 0 && !g.moving ? _timer.fraction : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BoardPlayerCard(
                    name: _bot.$1,
                    initials: _bot.$2,
                    sub: sub(1),
                    color: _botColor,
                    active: !g.isOver && g.turn == 1,
                    turnText: !g.isOver && g.turn == 1 ? l.snookerAiming(_bot.$1) : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  var h = box.maxHeight;
                  var w = h * SnookerLayout.aspect;
                  if (w > box.maxWidth) {
                    w = box.maxWidth;
                    h = w / SnookerLayout.aspect;
                  }
                  final size = Size(w, h);
                  final layout = SnookerLayout(size);
                  return Center(
                    child: GestureDetector(
                      onPanStart: (d) => _tablePanStart(d, layout),
                      onPanUpdate: (d) => _tablePanUpdate(d, layout),
                      child: SizedBox.fromSize(
                        size: size,
                        child: Stack(
                          children: [
                            RepaintBoundary(
                              child: CustomPaint(size: size, painter: const SnookerTablePainter()),
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
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 34,
              child: Center(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AuraText.cardSub.copyWith(fontSize: 11.5, color: _myTurn ? AuraColors.amber : Colors.white70),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Opacity(
              opacity: _myTurn ? 1 : 0.45,
              child: Row(
                children: [
                  _SpinPad(
                    tip: _tip,
                    label: l.snookerSpin,
                    onChanged: _myTurn ? (t) => setState(() => _tip = t) : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      children: [
                        _FineAim(
                          label: l.snookerFineAim,
                          onNudge: _myTurn ? (dx) => setState(() => _angle += dx * 0.0012) : null,
                        ),
                        const SizedBox(height: 8),
                        _PowerBar(
                          key: const ValueKey('snooker-power'),
                          label: l.snookerPower,
                          power: _power,
                          onChanged: _myTurn ? (p) => setState(() => _power = p) : null,
                          onRelease: _strike,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
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

  static const _size = 62.0;

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

/// A ribbed strip: dragging it turns the cue by hair's breadths.
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
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onHorizontalDragUpdate: (d) {
      if (widget.onNudge == null) return;
      setState(() => _travel += d.delta.dx);
      widget.onNudge!(d.delta.dx);
    },
    child: Container(
      height: 28,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: Colors.white24),
      ),
      child: CustomPaint(
        painter: _RibsPainter(_travel),
        child: Center(
          child: Text(widget.label, style: AuraText.cardSub.copyWith(fontSize: 10.5, color: Colors.white70)),
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
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    final start = travel % 8;
    for (var x = start; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 5), Offset(x, size.height - 5), p);
    }
  }
}

/// Pull along the bar for power; let go to strike, slide back to zero to
/// call it off.
class _PowerBar extends StatelessWidget {
  const _PowerBar({super.key, required this.label, required this.power, required this.onChanged, required this.onRelease});
  final String label;
  final double power;
  final ValueChanged<double>? onChanged;
  final VoidCallback onRelease;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      void at(Offset p) => onChanged?.call((p.dx / box.maxWidth).clamp(0.0, 1.0));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) => at(d.localPosition),
        onHorizontalDragUpdate: (d) => at(d.localPosition),
        onHorizontalDragEnd: (_) => onRelease(),
        child: Container(
          height: 26,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.white.withValues(alpha: 0.07),
            border: Border.all(color: Colors.white24),
          ),
          child: Stack(
            children: [
              FractionallySizedBox(
                widthFactor: power,
                heightFactor: 1,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF22C55E), Color(0xFFF59E0B), Color(0xFFEF4444)]),
                  ),
                ),
              ),
              Center(
                child: Text(label, style: AuraText.cardSub.copyWith(fontSize: 10.5, color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    },
  );
}
