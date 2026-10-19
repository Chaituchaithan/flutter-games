import 'dart:math' as math;
import 'dart:ui' as ui;

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
  late final CarromGame _game = CarromGame(rng: _rng)..onPocket = _onPocket;
  late final TurnTimer _timer = TurnTimer(limitMs: widget.clockMs, onExpire: _timeout);
  late final Ticker _ticker = createTicker(_tick);
  Duration _lastTick = Duration.zero;
  bool _wasMoving = false;

  /// Aim while dragging: direction (board units) and power 0..1.
  (double, double)? _aim;
  double _power = 0;
  bool _dragStriker = false;

  _BotPlan? _plan;
  String? _event;

  /// "+1" / ♛ / FOUL rising from a pocket.
  final List<_Pop> _pops = [];
  double _clock = 0;

  /// Tilted 3D view of the board.
  bool _tilted = false;

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

  void _onPocket(CarromKind k) {
    if (_game.sinking.isNotEmpty) _pops.add(_Pop(k, _game.sinking.last.pocket, _clock));
    if (k == CarromKind.striker) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  String _name(int p) => p == 0 ? context.l10n.you : _bot.$1;
  bool get _myTurn => !_game.isOver && !resigned && _game.turn == 0 && !_game.moving;

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 1 / 20);
    _lastTick = elapsed;
    if (paused) return;
    _clock += dt;
    _pops.removeWhere((p) => _clock - p.born > 1.2);
    _game.step(dt);
    // Keep painting while pops rise and the turn glow breathes.
    if (!_game.moving && mounted) setState(() {});
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
    scheduleBot(Duration(milliseconds: 650 + _rng.nextInt(500)), () {
      final shot = _game.botShot(widget.difficulty);
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
      _aim = (p.shot.dx, p.shot.dy);
      _power = p.shot.power * Curves.easeOut.transform(((p.t - 0.5) / 0.6).clamp(0, 1));
    } else {
      _plan = null;
      _aim = null;
      if (!_game.strikerClear) _game.placeStriker(0.5);
      _game.shoot(p.shot.dx, p.shot.dy, p.shot.power);
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
      _aim = null;
      _event = null;
    });
    _game.passTurn();
    _beginTurn();
  }

  // ── Your shot ──

  (double, double) _toBoard(Offset local, double side) {
    final f = side * _BoardPainter.frame;
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
      _aim = (0, 0);
      _power = 0;
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
    setState(() {
      _aim = (px, py);
      _power = (len / 0.24).clamp(0.0, 1.0);
    });
  }

  void _panEnd() {
    if (_dragStriker) {
      _dragStriker = false;
      return;
    }
    final aim = _aim;
    setState(() => _aim = null);
    if (aim == null || !_myTurn || _power < 0.08 || !_game.strikerClear) return;
    _timer.stop();
    HapticFeedback.mediumImpact();
    _event = null;
    _game.shoot(aim.$1, aim.$2, _power);
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
    String sub(int p) {
      final s = l.carromCoinsOf(p == 0 ? l.carromWhite : l.carromBlack, g.pocketed[p]);
      return g.queenOwner == p ? '$s · ♛' : s;
    }

    return AuraScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocalGameHeader(
            title: '${carromConfig.icon} ${carromConfig.displayName}',
            subtitle: l.carromSubtitle(g.pocketed[0], _bot.$1, g.pocketed[1]),
            live: !g.isOver && !resigned,
            onPause: openPause,
            perspective: _tilted,
            onTogglePerspective: () => setState(() => _tilted = !_tilted),
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
              _Tray(count: g.pocketed[1], kind: CarromKind.black, queen: g.queenOwner == 1),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                // Tilted, the board can be a little wider than tall.
                final side = _tilted ? math.min(box.maxWidth, box.maxHeight * 1.18) : math.min(box.maxWidth, box.maxHeight);
                final board = GestureDetector(
                  onPanStart: (d) => _panStart(d, side),
                  onPanUpdate: (d) => _panUpdate(d, side),
                  onPanEnd: (_) => _panEnd(),
                  onPanCancel: _panEnd,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: Size.square(side),
                      painter: _BoardPainter(
                        game: g,
                        aim: _aim,
                        power: _power,
                        yourTurn: _myTurn,
                        pops: _pops,
                        clock: _clock,
                        repaint: g,
                      ),
                    ),
                  ),
                );
                return Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _tilted
                        ? OverflowBox(
                            key: const ValueKey('3d'),
                            maxWidth: side,
                            maxHeight: side,
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.0014)
                                ..rotateX(-0.5),
                              child: board,
                            ),
                          )
                        : KeyedSubtree(key: const ValueKey('2d'), child: board),
                  ),
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
                  g.moving || _event == null || (_myTurn && _aim != null) ? _hint : _event!,
                  key: ValueKey('${_event}_$_hint${g.moving}'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: AuraText.cardSub.copyWith(fontSize: 12.5, color: _myTurn ? AuraColors.amber : Colors.white70),
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
              _Tray(count: g.pocketed[0], kind: CarromKind.white, queen: g.queenOwner == 0),
            ],
          ),
          const SizedBox(height: 10),
        ],
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
        const thumb = 40.0;
        final w = box.maxWidth - thumb;
        void at(Offset p) => enabled ? onChanged(((p.dx - thumb / 2) / w).clamp(0.0, 1.0)) : null;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => at(d.localPosition),
          onHorizontalDragUpdate: (d) => at(d.localPosition),
          child: SizedBox(
            height: 44,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: thumb / 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: Colors.white.withValues(alpha: 0.08),
                    border: Border.all(color: Colors.white24),
                  ),
                ),
                Positioned(
                  left: value * w,
                  child: Container(
                    width: thumb,
                    height: thumb,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(colors: [Colors.white, Color(0xFFDCE3F0)]),
                      border: Border.all(color: blocked ? AuraColors.danger : const Color(0xFF3B5BDB), width: 3),
                      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3))],
                    ),
                    child: Icon(
                      Icons.swap_horiz_rounded,
                      size: 20,
                      color: blocked ? AuraColors.danger : const Color(0xFF3B5BDB),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// The whole board: wooden frame, plywood surface with its markings, the
/// four pockets, coins with shadows, coins dropping into pockets, and the
/// aim guide.
class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.game,
    required this.aim,
    required this.power,
    required this.yourTurn,
    required this.pops,
    required this.clock,
    super.repaint,
  });

  final CarromGame game;
  final (double, double)? aim;
  final double power;
  final bool yourTurn;
  final List<_Pop> pops;

  /// Seconds since the game started (pops and the turn glow).
  final double clock;

  /// The board itself (frame, plywood, markings, pockets) doesn't change:
  /// recorded once per size.
  static ui.Picture? _surface;
  static double _surfaceSide = 0;

  /// Frame width as a share of the board's side.
  static const frame = 0.065;

  static const _ink = Color(0xFF7A2E1A);
  static const _red = Color(0xFFC62828);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width;
    final f = side * frame;
    final s = side - 2 * f;
    Offset at(double x, double y) => Offset(f + x * s, f + y * s);

    if (_surface == null || _surfaceSide != side) {
      final rec = ui.PictureRecorder();
      _paintSurface(Canvas(rec), size, at, f, s);
      _surface?.dispose();
      _surface = rec.endRecording();
      _surfaceSide = side;
    }
    canvas.drawShadow(
      Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(side * 0.03))),
      Colors.black,
      12,
      false,
    );
    canvas.drawPicture(_surface!);
    _turnGlow(canvas, at, s);

    // Coins dropping in.
    for (final k in game.sinking) {
      final (px, py) = CarromRules.pockets[k.pocket];
      final t = (k.t / 0.35).clamp(0.0, 1.0);
      final pos = Offset.lerp(at(k.x, k.y), at(px, py), Curves.easeIn.transform(t))!;
      final r = (k.kind == CarromKind.striker ? CarromRules.strikerR : CarromRules.coinR) * s * (1 - 0.55 * t);
      canvas.saveLayer(
        Rect.fromCircle(center: pos, radius: r * 2),
        Paint()..color = Colors.white.withValues(alpha: 1 - t),
      );
      _disc(canvas, pos, r, k.kind, shadow: false);
      canvas.restore();
    }

    // Motion trails behind fast discs.
    for (final d in game.discs) {
      final sp = d.speed;
      if (sp < 0.35) continue;
      final c = at(d.x, d.y);
      final tail = c - Offset(d.vx, d.vy) * (0.045 * s / 1);
      canvas.drawLine(
        c,
        tail,
        Paint()
          ..strokeWidth = d.r * s * 1.5
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(c, tail, [
            _base(d.kind).withValues(alpha: (0.32 * sp / 3).clamp(0.0, 0.32)),
            _base(d.kind).withValues(alpha: 0),
          ]),
      );
    }

    // Coins, striker last (on top).
    for (final d in game.discs) {
      if (d.kind == CarromKind.striker) continue;
      _disc(canvas, at(d.x, d.y), d.r * s, d.kind);
    }
    final st = game.striker;
    if (game.discs.contains(st)) {
      final c = at(st.x, st.y);
      _disc(canvas, c, st.r * s, CarromKind.striker);
      if (!game.moving && !game.strikerClear) {
        canvas.drawCircle(
          c,
          st.r * s + 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = const Color(0xFFEF4444),
        );
      } else if (yourTurn && aim == null) {
        // Your shot: a soft ring on the striker.
        canvas.drawCircle(
          c,
          st.r * s + 4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white.withValues(alpha: 0.7),
        );
      }
    }

    _guide(canvas, at, s);
    _lighting(canvas, size);
    _pops(canvas, at, s);
  }

  static Color _base(CarromKind k) => switch (k) {
    CarromKind.white => const Color(0xFFFBF3E0),
    CarromKind.black => const Color(0xFF3A3A40),
    CarromKind.queen => const Color(0xFFE53950),
    CarromKind.striker => const Color(0xFFDDE6FF),
  };

  /// Whose turn: their baseline glows softly.
  void _turnGlow(Canvas canvas, Offset Function(double, double) at, double s) {
    if (game.isOver || game.moving) return;
    final y = CarromRules.baseY(game.turn);
    final pulse = 0.55 + 0.45 * math.sin(clock * 3.2);
    final color = game.turn == 0 ? const Color(0xFFA78BFA) : const Color(0xFF22D3EE);
    final r = Rect.fromPoints(
      at(CarromRules.baseMin - 0.02, y - CarromRules.coinR * 1.6),
      at(CarromRules.baseMax + 0.02, y + CarromRules.coinR * 1.6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(r.height / 2)),
      Paint()
        ..color = color.withValues(alpha: 0.22 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  /// Light from a lamp above the board, and the lacquer's sheen.
  void _lighting(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          size.center(Offset.zero),
          size.width * 0.75,
          [Colors.white.withValues(alpha: 0.06), Colors.transparent, Colors.black.withValues(alpha: 0.28)],
          [0, 0.55, 1],
        ),
    );
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          r.topLeft,
          r.bottomRight,
          [Colors.transparent, Colors.white.withValues(alpha: 0.07), Colors.transparent],
          [0.32, 0.42, 0.52],
        ),
    );
  }

  /// "+1" / ♛ / FOUL rising from the pocket.
  void _pops(Canvas canvas, Offset Function(double, double) at, double s) {
    for (final p in pops) {
      final t = ((clock - p.born) / 1.2).clamp(0.0, 1.0);
      final (px, py) = CarromRules.pockets[p.pocket];
      final c = at(px, py) + Offset(px < 0.5 ? s * 0.07 : -s * 0.07, (py < 0.5 ? s * 0.06 : -s * 0.06) - t * s * 0.08);
      final (text, color) = switch (p.kind) {
        CarromKind.white => ('+1', const Color(0xFFFFF4D6)),
        CarromKind.black => ('+1', const Color(0xFF22D3EE)),
        CarromKind.queen => ('♛ +3', const Color(0xFFFF5470)),
        CarromKind.striker => ('FOUL', const Color(0xFFEF4444)),
      };
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color.withValues(alpha: 1 - t * t),
            fontSize: s * 0.05 * (1 + 0.25 * Curves.elasticOut.transform((t * 3).clamp(0.0, 1.0))),
            fontWeight: FontWeight.w900,
            shadows: [Shadow(color: Colors.black.withValues(alpha: 0.8 * (1 - t)), blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _paintSurface(Canvas canvas, Size size, Offset Function(double, double) at, double f, double s) {
    final side = size.width;
    // Frame.
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(side * 0.03));
    canvas.drawShadow(Path()..addRRect(outer), Colors.black, 10, false);
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B3A1A), Color(0xFF3A1A08), Color(0xFF5A2E12)],
        ).createShader(Offset.zero & size),
    );
    // Grain running along each side of the frame.
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final rng = math.Random(5);
    // Each rail's grain stays on that rail (they meet at the mitres).
    Path rail(List<Offset> pts) => Path()..addPolygon(pts, true);
    final sides = [
      rail([Offset.zero, Offset(side, 0), Offset(side - f, f), Offset(f, f)]),
      rail([Offset(0, side), Offset(side, side), Offset(side - f, side - f), Offset(f, side - f)]),
      rail([Offset.zero, Offset(f, f), Offset(f, side - f), Offset(0, side)]),
      rail([Offset(side, 0), Offset(side - f, f), Offset(side - f, side - f), Offset(side, side)]),
    ];
    for (var k = 0; k < 4; k++) {
      canvas.save();
      canvas.clipPath(sides[k]);
      for (var i = 0; i < 14; i++) {
        final o = f * (0.05 + 0.9 * rng.nextDouble());
        fg.color = (i.isEven ? Colors.black : Colors.white).withValues(alpha: 0.05 + rng.nextDouble() * 0.06);
        final d = rng.nextDouble() * 2;
        switch (k) {
          case 0:
            canvas.drawLine(Offset(0, o), Offset(side, o + d), fg);
          case 1:
            canvas.drawLine(Offset(0, side - o), Offset(side, side - o - d), fg);
          case 2:
            canvas.drawLine(Offset(o, 0), Offset(o + d, side), fg);
          default:
            canvas.drawLine(Offset(side - o, 0), Offset(side - o - d, side), fg);
        }
      }
      canvas.restore();
    }
    // Mitred corner joints.
    final joint = Paint()
      ..strokeWidth = 1.2
      ..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawLine(Offset.zero, Offset(f, f), joint);
    canvas.drawLine(Offset(side, 0), Offset(side - f, f), joint);
    canvas.drawLine(Offset(0, side), Offset(f, side - f), joint);
    canvas.drawLine(Offset(side, side), Offset(side - f, side - f), joint);
    // Polished top edge and the bevel down to the board.
    canvas.drawRRect(
      outer.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.16),
    );
    canvas.drawRect(
      Rect.fromLTWH(f, f, s, s).inflate(2.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF1E0C03),
    );

    // Playing surface.
    final play = Rect.fromLTWH(f, f, s, s);
    canvas.drawRect(
      play,
      Paint()
        ..shader = const RadialGradient(
          radius: 0.85,
          colors: [Color(0xFFF6E3B8), Color(0xFFEBCF97), Color(0xFFD9B678)],
        ).createShader(play),
    );
    // Faint grain.
    final grain = Paint()
      ..color = const Color(0xFFB8925A).withValues(alpha: 0.10)
      ..strokeWidth = 1;
    for (var i = 0; i < 90; i++) {
      final y0 = f + s * (i + 0.5) / 90;
      grain.color = const Color(0xFFB8925A).withValues(alpha: 0.05 + (i * 37 % 7) / 70);
      final path = Path()..moveTo(f, y0);
      for (var k = 1; k <= 8; k++) {
        final x = f + s * k / 8;
        path.quadraticBezierTo(x - s / 16, y0 + math.sin(i * 0.7 + k) * 3.5, x, y0 + math.sin(i * 1.3 + k * 0.6) * 2);
      }
      canvas.drawPath(path, grain..style = PaintingStyle.stroke);
    }
    // Inner shadow from the frame.
    canvas.drawRect(
      play,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.012
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    _markings(canvas, at, s);

    // Pockets.
    for (final (px, py) in CarromRules.pockets) {
      final c = at(px, py);
      final r = CarromRules.pocketR * s * 1.08;
      // Leather lip, then the drop into the net.
      canvas.drawCircle(
        c,
        r + 3,
        Paint()
          ..shader = ui.Gradient.radial(c, r + 3, [const Color(0xFF4A2A14), const Color(0xFF2A1407)], [0.8, 1]),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()..shader = ui.Gradient.radial(c + Offset(r * 0.2, r * 0.25), r, [Colors.black, const Color(0xFF151010)]),
      );
      final net = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = Colors.white.withValues(alpha: 0.06);
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.9)));
      for (var k = -4; k <= 4; k++) {
        canvas.drawLine(c + Offset(-r, k * r / 4 - r), c + Offset(r, k * r / 4 + r), net);
        canvas.drawLine(c + Offset(-r, k * r / 4 + r), c + Offset(r, k * r / 4 - r), net);
      }
      canvas.restore();
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.black,
      );
    }

  }

  void _markings(Canvas canvas, Offset Function(double, double) at, double s) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, s * 0.0028)
      ..color = _ink;
    // Four baselines: two lines with a red circle at each end.
    final gap = CarromRules.coinR;
    for (var side = 0; side < 4; side++) {
      for (final off in [-gap, gap]) {
        final inset = CarromRules.baseInset + off;
        (Offset, Offset) seg(double a, double b) => switch (side) {
          0 => (at(a, 1 - inset), at(b, 1 - inset)),
          1 => (at(a, inset), at(b, inset)),
          2 => (at(inset, a), at(inset, b)),
          _ => (at(1 - inset, a), at(1 - inset, b)),
        };
        final (p, q) = seg(CarromRules.baseMin, CarromRules.baseMax);
        canvas.drawLine(p, q, line);
      }
      for (final end in [CarromRules.baseMin, CarromRules.baseMax]) {
        final c = switch (side) {
          0 => at(end, 1 - CarromRules.baseInset),
          1 => at(end, CarromRules.baseInset),
          2 => at(CarromRules.baseInset, end),
          _ => at(1 - CarromRules.baseInset, end),
        };
        canvas.drawCircle(c, gap * s, Paint()..color = _red);
        canvas.drawCircle(c, gap * s, line);
        canvas.drawCircle(c, gap * s * 0.55, Paint()..color = const Color(0xFFF6E3B8).withValues(alpha: 0.35));
      }
    }
    // Diagonal arrows from each pocket.
    for (final (cx, cy) in CarromRules.pockets) {
      final dx = cx < 0.5 ? 1.0 : -1.0, dy = cy < 0.5 ? 1.0 : -1.0;
      final a = at(cx + dx * 0.075, cy + dy * 0.075), b = at(cx + dx * 0.29, cy + dy * 0.29);
      canvas.drawLine(a, b, line);
      // Arrow head toward the pocket.
      final u = (a - b) / (a - b).distance;
      final n = Offset(-u.dy, u.dx);
      final h = s * 0.018;
      canvas.drawLine(a, a - u * h + n * h * 0.7, line);
      canvas.drawLine(a, a - u * h - n * h * 0.7, line);
      // The arc at the tail.
      canvas.drawArc(Rect.fromCircle(center: b, radius: s * 0.028), math.atan2(u.dy, u.dx) - 2.1, 4.2, false, line);
    }
    // Centre: outer ring, a star, the red spot.
    final c = at(0.5, 0.5);
    canvas.drawCircle(c, s * 0.115, line);
    canvas.drawCircle(c, s * 0.108, line);
    final star = Path();
    for (var i = 0; i < 16; i++) {
      final r = (i.isEven ? 0.1 : 0.045) * s;
      final a = -math.pi / 2 + i * math.pi / 8;
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    canvas.drawPath(star, Paint()..color = _red.withValues(alpha: 0.16));
    canvas.drawPath(star, line..color = _ink.withValues(alpha: 0.6));
    canvas.drawCircle(c, s * 0.0225, Paint()..color = _red);
  }

  void _disc(Canvas canvas, Offset c, double r, CarromKind kind, {bool shadow = true}) {
    if (shadow) {
      canvas.drawCircle(
        c + Offset(r * 0.18, r * 0.26),
        r * 1.02,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.25),
      );
    }
    final (base, edge, ring) = switch (kind) {
      CarromKind.white => (const Color(0xFFFBF3E0), const Color(0xFFD9C79F), const Color(0xFFC2A878)),
      CarromKind.black => (const Color(0xFF3A3A40), const Color(0xFF16161A), const Color(0xFF66666E)),
      CarromKind.queen => (const Color(0xFFE53950), const Color(0xFF9E1028), const Color(0xFFFFA3B0)),
      CarromKind.striker => (const Color(0xFFFFFFFF), const Color(0xFFCFD6E4), const Color(0xFF3B5BDB)),
    };
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.05,
          colors: [base, edge],
        ).createShader(rect),
    );
    final rp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, r * 0.09)
      ..color = ring.withValues(alpha: 0.85);
    // Turned grooves: a dark cut with a lit edge just inside it.
    final lit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, r * 0.04)
      ..color = Colors.white.withValues(alpha: kind == CarromKind.black ? 0.18 : 0.45);
    for (final k in const [0.8, 0.58, 0.34]) {
      canvas.drawCircle(c, r * k, rp..strokeWidth = math.max(0.6, r * 0.06));
      canvas.drawCircle(c + Offset(r * 0.02, r * 0.03), r * (k - 0.05), lit);
    }
    if (kind == CarromKind.striker) {
      // Striker emblem: a small star.
      final p = Path();
      for (var i = 0; i < 10; i++) {
        final rr = (i.isEven ? 0.32 : 0.14) * r;
        final a = -math.pi / 2 + i * math.pi / 5;
        final q = c + Offset(math.cos(a) * rr, math.sin(a) * rr);
        i == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(p..close(), Paint()..color = ring);
    }
    // Rim and shine.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, r * 0.07)
        ..color = edge,
    );
    canvas.drawCircle(c + Offset(-r * 0.35, -r * 0.4), r * 0.22, Paint()..color = Colors.white.withValues(alpha: 0.35));
  }

  void _guide(Canvas canvas, Offset Function(double, double) at, double s) {
    final a = aim;
    if (a == null || power < 0.02 || game.moving) return;
    final st = game.striker;
    final from = at(st.x, st.y);
    final g = carromAimGuide(game, a.$1, a.$2);
    final to = at(g.x, g.y);
    // Dotted path to first contact.
    final dir = to - from;
    final len = dir.distance;
    if (len > 1) {
      final u = dir / len;
      final dot = Paint()..color = Colors.white.withValues(alpha: 0.85);
      for (var d = st.r * s + 6; d < len; d += 9) {
        canvas.drawCircle(from + u * d, 1.6, dot);
      }
    }
    // Ghost striker at contact.
    canvas.drawCircle(
      to,
      st.r * s,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.75),
    );
    // Where the coin goes.
    final hit = g.hit;
    if (hit != null) {
      final hc = at(hit.x, hit.y);
      final n = hc - to;
      final nl = n.distance;
      if (nl > 0) {
        final u = n / nl;
        canvas.drawLine(
          hc,
          hc + u * s * 0.16,
          Paint()
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFFFD43B).withValues(alpha: 0.9),
        );
      }
    }
    // Power: an arc round the striker, green → red.
    final pc = Color.lerp(const Color(0xFF22C55E), const Color(0xFFEF4444), power)!;
    canvas.drawArc(
      Rect.fromCircle(center: from, radius: st.r * s + 7),
      -math.pi / 2,
      2 * math.pi * power,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = pc,
    );
    // The pull-back band behind the striker.
    final la = math.sqrt(a.$1 * a.$1 + a.$2 * a.$2);
    if (la > 0) {
      final back = from - Offset(a.$1 / la, a.$2 / la) * (power * 0.24 * s);
      canvas.drawLine(
        from,
        back,
        Paint()
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = pc.withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}

class _Pop {
  _Pop(this.kind, this.pocket, this.born);
  final CarromKind kind;
  final int pocket;
  final double born;
}

/// A player's pocketed coins, in a little wooden tray (3 × 3), with the
/// queen beside them once covered.
class _Tray extends StatelessWidget {
  const _Tray({required this.count, required this.kind, required this.queen});
  final int count;
  final CarromKind kind;
  final bool queen;

  @override
  Widget build(BuildContext context) {
    final fill = kind == CarromKind.white ? const Color(0xFFF5ECD7) : const Color(0xFF2E2E34);
    final ring = kind == CarromKind.white ? const Color(0xFFC2A878) : const Color(0xFF66666E);
    return Container(
      width: 70,
      height: 70,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A2E12), Color(0xFF2E1406)],
        ),
        border: Border.all(color: const Color(0xFF7A3E1C)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              for (var i = 0; i < CarromRules.coinsEach; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < count ? fill : Colors.black.withValues(alpha: 0.35),
                    border: Border.all(color: i < count ? ring : Colors.white10, width: 1.5),
                    boxShadow: i < count ? const [BoxShadow(color: Colors.black54, blurRadius: 2, offset: Offset(0, 1))] : null,
                  ),
                ),
            ],
          ),
          if (queen)
            Positioned(
              right: -8,
              top: -8,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE53950),
                  border: Border.all(color: const Color(0xFFFFA3B0), width: 2),
                  boxShadow: const [BoxShadow(color: Color(0x88E53950), blurRadius: 8)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
