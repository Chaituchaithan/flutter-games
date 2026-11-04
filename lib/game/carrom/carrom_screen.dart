import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../configs/games/carrom/carrom_config.dart';
import '../../l10n/l10n.dart';
import '../../screens/match/match_result_screen.dart';
import '../../widgets/aura.dart';
import '../common/board_game_setup.dart';
import '../common/local_game_flow.dart';
import '../common/turn_timer.dart';
import 'carrom_board_view.dart';
import 'carrom_engine.dart';

const _bot = ('Nova', 'NV');
const _youColor = Color(0xFFA78BFA);
const _botColor = Color(0xFF22D3EE);

/// Quick Play setup → [CarromScreen]: difficulty and time per shot.
class CarromSetupScreen extends StatelessWidget {
  const CarromSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => BoardGameSetupScreen(
    title: carromConfig.displayName,
    blurb: context.l10n.carromBlurb,
    timeOptions: const [(label: '30s', ms: 30 * 1000), (label: '1m', ms: 60 * 1000), (label: '∞', ms: null)],
    timeRule: context.l10n.carromTimeUp,
    start: (_, difficulty, clockMs) => CarromScreen(difficulty: difficulty, clockMs: clockMs),
  );
}

/// Carrom vs the computer. You're white at the bottom: slide the striker
/// along your baseline (on the board or the slider under it), drag back
/// from the striker to aim — the guide shows the first coin you'll hit and
/// where it goes — and let go to shoot.
class CarromScreen extends StatefulWidget {
  const CarromScreen({super.key, this.difficulty = 2, this.clockMs = 30 * 1000, this.seed});

  final int difficulty;
  final int? clockMs;
  final int? seed;

  @override
  State<CarromScreen> createState() => _CarromScreenState();
}

/// The computer's shot as it plays out: slide, aim, shoot.
class _BotPlan {
  _BotPlan(this.from, this.shot);
  final double from;
  final ({double pos, double dx, double dy, double power}) shot;
  double t = 0;
}

class _CarromScreenState extends State<CarromScreen> with LocalGameFlow, SingleTickerProviderStateMixin {
  late final math.Random _rng = widget.seed == null ? math.Random() : math.Random(widget.seed);
  late final CarromGame _game = CarromGame(rng: _rng)
    ..onPocket = _onPocket
    ..onImpact = _onImpact;
  late final TurnTimer _timer = TurnTimer(limitMs: widget.clockMs, onExpire: _timeout);
  late final Ticker _ticker = createTicker(_tick);
  Duration _lastTick = Duration.zero;
  bool _wasMoving = false;

  /// Aim while dragging: direction (board units) and power 0..1.
  final CarromAim _aimState = CarromAim();
  (double, double)? get _aim => _aimState.dir;
  double get _power => _aimState.power;
  bool _dragStriker = false;

  _BotPlan? _plan;

  /// Bumped on every bot turn: a plan that comes back from the background
  /// after a pause or a newer request is dropped.
  int _botRequest = 0;
  String? _event;

  /// The line under the board, and a number that changes with it: the fade
  /// keys on the number, so flipping back to an earlier line mid-fade never
  /// gives two children the same key.
  String _line = '';
  int _lineId = 0;

  /// [text] as a keyed child for the line's fade.
  Key _lineKey(String text) {
    if (text != _line) {
      _line = text;
      _lineId++;
    }
    return ValueKey(_lineId);
  }

  /// "+1" / ♛ / FOUL rising from a pocket.
  final List<CarromPop> _pops = [];
  Duration _lastKnock = Duration.zero;
  final ValueNotifier<double> _clock = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _game.addListener(_onGameChange);
    _timer.addListener(_onChange);
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _beginTurn());
  }

  @override
  void dispose() {
    disposeFlow();
    _ticker.dispose();
    _timer.dispose();
    _game.removeListener(_onGameChange);
    _game.dispose();
    _clock.dispose();
    _aimState.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// What the screen around the board shows from the game. The board repaints
  /// itself every frame (its painter listens to the game); the rest of the
  /// screen rebuilds only when one of these changes, not 60 times a second
  /// while the discs slide.
  Object? _hud;

  void _onGameChange() {
    final g = _game;
    final hud = (
      g.pocketed[0],
      g.pocketed[1],
      g.queenOwner,
      g.queenPending,
      g.turn,
      g.winner,
      g.moving,
      g.strikerPos,
      g.moving || g.strikerClear,
    );
    if (hud == _hud) return;
    _hud = hud;
    _onChange();
  }

  void _onPocket(CarromKind k) {
    if (_game.sinking.isNotEmpty) _pops.add(CarromPop(k, _game.sinking.last.pocket, _clock.value));
    if (k == CarromKind.striker) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  /// A sharp click in the hand for a hard knock (not every graze).
  void _onImpact(double speed) {
    if (speed < 1.1 || _lastTick - _lastKnock < const Duration(milliseconds: 70)) return;
    _lastKnock = _lastTick;
    HapticFeedback.selectionClick();
  }

  String _name(int p) => p == 0 ? context.l10n.you : _bot.$1;
  bool get _myTurn => !_game.isOver && !resigned && _game.turn == 0 && !_game.moving;

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 1 / 20);
    _lastTick = elapsed;
    if (paused) return;
    // Repaints the board while pops rise and the turn glow breathes.
    _clock.value += dt;
    _pops.removeWhere((p) => _clock.value - p.born > 1.2);
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
      return;
    }
    _timer.stop();
    final request = ++_botRequest;
    scheduleBot(Duration(milliseconds: 650 + _rng.nextInt(500)), () async {
      // Plan on a copy in the background (dozens of simulated shots), so the
      // board keeps animating while the computer thinks.
      final copy = CarromGame.planningCopy(_game, seed: _rng.nextInt(1 << 30));
      final shot = await compute(planCarromShot, (copy, widget.difficulty));
      if (!mounted || paused || resigned || request != _botRequest) return;
      if (_game.turn != 1 || _game.moving || _plan != null) return;
      setState(() => _plan = _BotPlan(_game.strikerPos, shot));
    }, stillValid: () => _game.turn == 1 && !_game.moving);
  }

  /// Slide (0.5 s), aim (0.7 s), shoot.
  void _runPlan(_BotPlan p, double dt) {
    p.t += dt;
    if (p.t < 0.5) {
      final k = Curves.easeInOut.transform(p.t / 0.5);
      _game.placeStriker(p.from + (p.shot.pos - p.from) * k);
    } else if (p.t < 1.2) {
      _game.placeStriker(p.shot.pos);
      // The aim builds up like a player pulling back.
      _aimState.set(
        (p.shot.dx, p.shot.dy),
        p.shot.power * Curves.easeOut.transform(((p.t - 0.5) / 0.6).clamp(0, 1)),
      );
    } else {
      _plan = null;
      _aimState.clear();
      for (var k = 0; k <= 20 && !_game.strikerClear; k++) {
        _game.placeStriker(0.5 + (k.isOdd ? 1 : -1) * ((k + 1) ~/ 2) * 0.05);
      }
      _game.shoot(p.shot.dx, p.shot.dy, p.shot.power);
      // Nowhere to put the striker: pass, never leave the computer stuck.
      if (!_game.moving) {
        _game.passTurn();
        _beginTurn();
      }
    }
  }

  void _onShotEnd() {
    _describe();
    _beginTurn();
  }

  void _describe() {
    final l = context.l10n;
    final r = _game.last;
    if (r == null) return;
    final n = _name(r.player);
    final parts = <String>[];
    if (r.foul) {
      parts.add(l.carromFoul);
    } else {
      if (r.covered) parts.add(l.carromCovered(n));
      if (r.queen && _game.queenPending == r.player) {
        parts.add(l.carromQueenIn(n));
      }
      if (r.own > 0 && !r.covered) parts.add(l.carromPocketedOwn(n, r.own));
      if (r.returned > 0) parts.add(l.carromLastCoin);
    }
    if (r.queenReturned) parts.add(l.carromQueenBack);
    if (r.other > 0) {
      parts.add(l.carromPocketedOther(r.other, _name(1 - r.player)));
    }
    if (parts.isEmpty) parts.add(l.carromNothing(_name(_game.turn)));
    _event = parts.join(' · ');
  }

  void _timeout() {
    if (!_myTurn) return;
    showAuraToast(context, context.l10n.carromTimeUp, kind: AuraToastKind.info);
    setState(() {
      _aimState.clear();
      _event = null;
    });
    _game.passTurn();
    _beginTurn();
  }

  // ── Your shot ──

  (double, double) _toBoard(Offset local, double side) {
    final f = side * CarromBoardPainter.frame;
    final s = side - 2 * f;
    return ((local.dx - f) / s, (local.dy - f) / s);
  }

  void _panStart(DragStartDetails d, double side) {
    if (!_myTurn || paused) return;
    final (x, y) = _toBoard(d.localPosition, side);
    final st = _game.striker;
    final near = math.sqrt(math.pow(x - st.x, 2) + math.pow(y - st.y, 2)) < 0.075;
    if (near) {
      _dragStriker = false;
      // Aiming starts: the line under the board switches to the hint.
      setState(() => _aimState.set((0, 0), 0));
    } else if ((y - st.y).abs() < 0.07) {
      // On the baseline: slide the striker there.
      _dragStriker = true;
      _slideTo(x);
    }
  }

  void _slideTo(double x) =>
      _game.placeStriker((x - CarromRules.baseMin) / (CarromRules.baseMax - CarromRules.baseMin));

  void _panUpdate(DragUpdateDetails d, double side) {
    if (!_myTurn) return;
    final (x, y) = _toBoard(d.localPosition, side);
    if (_dragStriker) {
      _slideTo(x);
      return;
    }
    if (_aim == null) return;
    final st = _game.striker;
    // Slingshot: pull away from where you want it to go.
    final px = st.x - x, py = st.y - y;
    final len = math.sqrt(px * px + py * py);
    _aimState.set((px, py), (len / 0.24).clamp(0.0, 1.0));
  }

  void _panEnd() {
    if (_dragStriker) {
      _dragStriker = false;
      return;
    }
    final aim = _aim;
    final power = _power;
    setState(_aimState.clear);
    if (aim == null || !_myTurn || power < 0.08 || !_game.strikerClear) return;
    _timer.stop();
    HapticFeedback.mediumImpact();
    _event = null;
    _game.shoot(aim.$1, aim.$2, power);
  }

  // ── LocalGameFlow ──

  @override
  String get pauseSubtitle => context.l10n.carromSubtitle(_game.pocketed[0], _bot.$1, _game.pocketed[1]);

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
              ? l.carromWinSub(_game.boardPoints)
              : l.carromLoseSub(_bot.$1, _game.coinsLeft(0)),
          youScore: _game.pocketed[0],
          oppScore: _game.pocketed[1],
          oppName: _bot.$1,
          oppInitials: _bot.$2,
          // Quick Play vs the computer: nothing to earn.
          practice: true,
          playAgain: (_) => CarromScreen(difficulty: widget.difficulty, clockMs: widget.clockMs),
        ),
      ),
    );
  }

  String get _hint {
    final l = context.l10n;
    if (_game.isOver) return '';
    if (_game.turn == 1) return _game.moving ? '' : l.carromAiming(_bot.$1);
    if (_game.moving) return '';
    if (!_game.strikerClear) return l.carromBlockedHint;
    if (_game.queenPending == 0) return l.carromCoverHint;
    return l.carromPlaceHint;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final g = _game;
    final line = g.moving || _event == null || (_myTurn && _aim != null) ? _hint : _event!;
    String sub(int p) {
      final s = l.carromCoinsOf(p == 0 ? l.carromWhite : l.carromBlack, g.pocketed[p]);
      return g.queenOwner == p ? '$s · ♛' : s;
    }

    return guardBack(
      AuraScaffold(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LocalGameHeader(
              title: '${carromConfig.icon} ${carromConfig.displayName}',
              subtitle: l.carromSubtitle(g.pocketed[0], _bot.$1, g.pocketed[1]),
              live: !g.isOver && !resigned,
              onPause: openPause,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: BoardPlayerCard(
                    name: _bot.$1,
                    initials: _bot.$2,
                    sub: sub(1),
                    color: _botColor,
                    active: !g.isOver && g.turn == 1,
                    turnText: !g.isOver && g.turn == 1 ? l.carromAiming(_bot.$1) : null,
                  ),
                ),
                const SizedBox(width: 8),
                CarromTray(count: g.pocketed[1], kind: CarromKind.black, queen: g.queenOwner == 1),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final side = math.min(box.maxWidth, box.maxHeight);
                  final board = GestureDetector(
                    onPanStart: (d) => _panStart(d, side),
                    onPanUpdate: (d) => _panUpdate(d, side),
                    onPanEnd: (_) => _panEnd(),
                    onPanCancel: _panEnd,
                    child: Stack(
                      children: [
                        RepaintBoundary(
                          child: CustomPaint(size: Size.square(side), painter: const CarromSurfacePainter()),
                        ),
                        RepaintBoundary(
                          child: CustomPaint(
                            size: Size.square(side),
                            painter: CarromBoardPainter(
                              game: g,
                              aimState: _aimState,
                              yourTurn: _myTurn,
                              pops: _pops,
                              time: _clock,
                              repaint: Listenable.merge([g, _clock, _aimState]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  // The lamp over the table: a warm pool of light behind the board.
                  return DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        radius: 0.75,
                        colors: [Color(0x40FFC27A), Color(0x14FFB060), Colors.transparent],
                        stops: [0, 0.55, 1],
                      ),
                    ),
                    child: Center(child: board),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 34,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    line,
                    key: _lineKey(line),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: AuraText.cardSub.copyWith(
                      fontSize: 12.5,
                      color: _myTurn ? AuraColors.amber : Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
            _BaselineSlider(
              value: g.strikerPos,
              enabled: _myTurn,
              blocked: _myTurn && !g.strikerClear,
              onChanged: g.placeStriker,
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
                    turnText: !g.isOver && g.turn == 0 ? l.carromYourShot : null,
                    progress: !g.isOver && g.turn == 0 && !g.moving ? _timer.fraction : null,
                  ),
                ),
                const SizedBox(width: 8),
                CarromTray(count: g.pocketed[0], kind: CarromKind.white, queen: g.queenOwner == 0),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

/// The track under the board: drag the striker along your baseline.
class _BaselineSlider extends StatelessWidget {
  const _BaselineSlider({required this.value, required this.enabled, required this.blocked, required this.onChanged});
  final double value;
  final bool enabled;
  final bool blocked;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.45,
    child: LayoutBuilder(
      builder: (context, box) {
        // The striker sits in the wooden groove: its disc is the groove's
        // height (plus a hair, so no wood shows round it) and it slides right
        // into the rounded ends.
        const rim = 4.0; // red surround
        const groove = 36.0;
        const track = groove + 2 * rim;
        const disc = groove + 2;
        const thumb = disc + 6; // CarromStrikerIcon leaves 3 px round its disc
        final w = box.maxWidth - thumb;
        void at(Offset p) => enabled ? onChanged(((p.dx - thumb / 2) / w).clamp(0.0, 1.0)) : null;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => at(d.localPosition),
          onHorizontalDragUpdate: (d) => at(d.localPosition),
          child: SizedBox(
            height: 54,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // A wooden groove in a red lacquered surround, like the board.
                Container(
                  height: track,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(track / 2),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFA42A1E), Color(0xFF6E140D), Color(0xFF3E0805)],
                    ),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3))],
                  ),
                  padding: const EdgeInsets.all(rim),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(groove / 2),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFB5733F), Color(0xFFDDA067), Color(0xFFC4824A)],
                        stops: [0, 0.45, 1],
                      ),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.35)),
                    ),
                  ),
                ),
                Positioned(
                  left: value * w,
                  child: CarromStrikerIcon(size: thumb, ring: blocked ? AuraColors.danger : null),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
