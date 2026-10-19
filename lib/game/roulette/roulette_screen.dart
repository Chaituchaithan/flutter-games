import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../widgets/aura.dart';
import '../common/playing_cards.dart' show CasinoChip;
import 'roulette_engine.dart';

String _fmt(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

const _green = Color(0xFF0F7A47);
const _redPocket = Color(0xFFC81E32);
const _blackPocket = Color(0xFF15121F);

Color pocketColor(int n) => n == 0 || n == doubleZero
    ? _green
    : (RouletteRules.isRed(n) ? _redPocket : _blackPocket);

const _chipValues = [10, 25, 100, 500, 1000];

/// European roulette, practice chips: place chips on the table, spin, and
/// watch the ball settle. Rounds repeat; leave with the back button.
class RouletteScreen extends StatefulWidget {
  const RouletteScreen({super.key, this.variant = RouletteVariant.european, @visibleForTesting this.game});

  /// European, French or American table.
  final RouletteVariant variant;

  /// A prepared game (tests); null = a new one.
  final RouletteGame? game;

  @override
  State<RouletteScreen> createState() => _RouletteScreenState();
}

class _RouletteScreenState extends State<RouletteScreen> with TickerProviderStateMixin {
  late final RouletteGame _game = widget.game ?? RouletteGame(variant: widget.variant);
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 7200));
  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  /// Between spins the wheel keeps turning slowly, as on a real table.
  late final AnimationController _idle = AnimationController(vsync: this, duration: const Duration(seconds: 48))
    ..repeat();
  final _rng = math.Random();

  int _chip = 25;

  /// Wheel angle at rest (radians, clockwise from the top).
  double _wheelRest = 0;
  _SpinPlan? _plan;

  /// The camera is on the wheel (the spin and the number).
  bool _closeUp = false;
  Timer? _nextRound, _pullBack;

  @override
  void initState() {
    super.initState();
    _game.addListener(_onChange);
  }

  @override
  void dispose() {
    _nextRound?.cancel();
    _pullBack?.cancel();
    _spin.dispose();
    _glow.dispose();
    _idle.dispose();
    _game.removeListener(_onChange);
    _game.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  double get _wheelAngle => _plan != null ? _plan!.wheelAt(_spin.value) : _wheelRest + _idle.value * 2 * math.pi;

  void _place(BetSpot spot) {
    if (_game.phase != RoulettePhase.betting) return;
    if (_chip > _game.balance) {
      showAuraToast(context, context.l10n.notEnoughChips, kind: AuraToastKind.error);
    } else if (!_game.place(spot, _chip)) {
      showAuraToast(context, context.l10n.tableLimitReached, kind: AuraToastKind.info);
    }
  }

  Future<void> _doSpin() async {
    if (_game.phase != RoulettePhase.betting) return;
    if (_game.bets.isEmpty) {
      showAuraToast(context, context.l10n.placeYourBets, kind: AuraToastKind.info);
      return;
    }
    _wheelRest = _wheelAngle % (2 * math.pi);
    _idle.stop();
    final result = _game.spin();
    _plan = _SpinPlan(_wheelRest, _game.variant.wheel.indexOf(result), _rng, _game.variant.wheel.length);
    setState(() => _closeUp = true);
    await _spin.forward(from: 0);
    if (!mounted) return;
    _wheelRest = _plan!.wheelAt(1) % (2 * math.pi);
    _game.settle();
    // Hold on the number, then back to the table: the dolly marks it and
    // the winning chips glow.
    _pullBack = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _closeUp = false);
    });
    _nextRound = Timer(const Duration(milliseconds: 4800), _continue);
  }

  void _continue() {
    _nextRound?.cancel();
    _pullBack?.cancel();
    if (!mounted || _game.phase != RoulettePhase.result) return;
    setState(() {
      _closeUp = false;
      _plan = null;
    });
    _game.nextRound();
    _idle
      ..reset()
      ..repeat();
  }

  /// Tap during the result: first back to the table, then the next round.
  void _skip() {
    if (_game.phase != RoulettePhase.result) return;
    if (_closeUp) {
      _pullBack?.cancel();
      setState(() => _closeUp = false);
    } else {
      _continue();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final g = _game;
    final betting = g.phase == RoulettePhase.betting;
    final broke = betting && g.balance < _chipValues.first && g.bets.isEmpty;
    return AuraScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GameHeader(
            title: '🎡 Roulette',
            subtitle: '${variantName(context, g.variant)} · ${l.practiceChips}',
            pot: '0',
            leading: GlassIconButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).maybePop()),
            trailing: _BalancePill(balance: g.balance),
          ),
          const SizedBox(height: 6),
          _History(results: g.results),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                const stageH = 142.0;
                final closeH = math.min(box.maxHeight * 0.78, box.maxWidth * 1.08);
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: stageH),
                          _StatusLine(game: g),
                          const SizedBox(height: 6),
                          Expanded(
                            child: _Felt(
                              child: GestureDetector(
                                onTap: betting ? null : _skip,
                                child: AnimatedBuilder(
                                  animation: _glow,
                                  builder: (_, _) => _RouletteTable(
                                    game: g,
                                    onPlace: _place,
                                    glow: math.sin(_glow.value * 2 * math.pi) * 0.5 + 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (broke)
                            _TopUp(onTap: g.refill)
                          else
                            _ChipTray(selected: _chip, balance: g.balance, onPick: (v) => setState(() => _chip = v)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _RoundAction(
                                icon: Icons.undo_rounded,
                                label: l.undo,
                                onTap: betting && g.bets.isNotEmpty ? g.undo : null,
                              ),
                              const SizedBox(width: 8),
                              _RoundAction(
                                icon: Icons.close_rounded,
                                label: l.clearBets,
                                onTap: betting && g.bets.isNotEmpty ? g.clear : null,
                              ),
                              const SizedBox(width: 8),
                              g.canRepeat
                                  ? _RoundAction(
                                      icon: Icons.replay_rounded,
                                      label: l.repeatBets,
                                      onTap: betting ? () => g.repeat() : null,
                                    )
                                  : _RoundAction(
                                      icon: Icons.exposure_plus_2_rounded,
                                      label: l.doubleBets,
                                      onTap: betting && g.bets.isNotEmpty ? () => g.double() : null,
                                    ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _SpinButton(label: l.spinButton, enabled: betting, onTap: _doSpin),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                    // The wheel at the head of the table; close up while it spins.
                    Positioned(
                      left: -12,
                      right: -12,
                      top: 0,
                      child: GestureDetector(
                        onTap: betting ? null : _skip,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 560),
                          curve: Curves.easeInOutCubic,
                          height: _closeUp ? closeH : stageH,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: _closeUp ? 0.7 : 0),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: _closeUp
                                  ? const [Color(0xF2050409), Color(0xF20B0814), Color(0xE6050409)]
                                  : const [Color(0x00050409), Color(0x00050409), Color(0x00050409)],
                            ),
                          ),
                          child: AnimatedBuilder(
                            animation: Listenable.merge([_spin, _idle, _glow]),
                            builder: (_, _) => _WheelStage(
                              game: g,
                              plan: _plan,
                              angle: _wheelAngle,
                              t: _spin.value,
                              smallH: stageH,
                              bigH: closeH,
                              showResult: _closeUp && g.phase == RoulettePhase.result,
                              glow: _glow.value,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// How one spin moves: the wheel turns clockwise and slows; the ball runs the
/// other way on the track, drops in with a few bounces at [land] and then
/// rides its pocket.
class _SpinPlan {
  _SpinPlan(this.start, this.pocket, math.Random rng, this.pockets)
    : wheelTurns = 1.4 + rng.nextDouble() * 0.6,
      ballTurns = 5.5 + rng.nextDouble() * 1.5;

  final double start;
  final int pocket;
  final double wheelTurns;
  final double ballTurns;

  static const land = 0.8;

  /// Pockets on this wheel (37, or 38 with double zero).
  final int pockets;
  double get seg => 2 * math.pi / pockets;

  double wheelAt(double t) =>
      start +
      wheelTurns *
          2 *
          math.pi *
          Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));

  double ballAt(double t) {
    if (t >= land) return wheelAt(t) + pocket * seg;
    final target = wheelAt(land) + pocket * seg;
    return target +
        ballTurns * 2 * math.pi * (1 - Curves.easeOutQuad.transform(t / land));
  }

  /// Ball distance from the centre as a fraction of the wheel radius.
  double ballRadius(double t) {
    const track = 0.8, rest = 0.555;
    final u = t / land;
    if (u < 0.55) return track;
    if (u >= 1) return rest;
    final v = (u - 0.55) / 0.45;
    final base = track + (rest - track) * Curves.easeIn.transform(v);
    // Deflectors make it hop a few times on the way in.
    return base +
        (track - rest) * 0.22 * (1 - v) * math.sin(v * math.pi * 5).abs();
  }
}

/// The wheel seen across the table: tilted in perspective, sitting in its
/// bowl. While betting it's small at the head of the table; for the spin the
/// stage grows and the camera comes closer (less tilt), then shows the number.
class _WheelStage extends StatelessWidget {
  const _WheelStage({
    required this.game,
    required this.plan,
    required this.angle,
    required this.t,
    required this.smallH,
    required this.bigH,
    required this.showResult,
    required this.glow,
  });

  final RouletteGame game;
  final _SpinPlan? plan;
  final double angle;
  final double t;
  final double smallH, bigH;
  final bool showResult;
  final double glow;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final k = ((box.maxHeight - smallH) / math.max(1, bigH - smallH)).clamp(0.0, 1.0);
      final tilt = 1.0 + (0.6 - 1.0) * k;
      final room = showResult ? box.maxHeight - 120 : box.maxHeight - 8;
      final d = math.min(box.maxWidth * (0.74 + 0.22 * k), room / (math.cos(tilt) + 0.08));
      final p = plan;
      final r = game.result;
      final done = game.phase == RoulettePhase.result;
      return ClipRect(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: showResult ? const Alignment(0, -0.55) : Alignment.center,
              child: SizedBox(
                width: d,
                height: d * (math.cos(tilt) + 0.08),
                child: OverflowBox(
                  maxWidth: d,
                  maxHeight: d,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // The bowl's shadow on the table.
                      Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0011)
                          ..rotateX(-tilt)
                          ..translateByDouble(0.0, d * 0.035, 0.0, 1.0),
                        child: Container(
                          width: d,
                          height: d,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: d * 0.06, spreadRadius: d * 0.01),
                            ],
                          ),
                        ),
                      ),
                      Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0011)
                          ..rotateX(-tilt),
                        child: SizedBox.square(
                          dimension: d,
                          child: CustomPaint(
                            painter: _WheelPainter(
                              wheel: angle,
                              order: game.variant.wheel,
                              ball: p?.ballAt(t),
                              ballR: p?.ballRadius(t),
                              highlight: done ? r : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (k > 0.6 && game.phase == RoulettePhase.spinning)
              Positioned(
                top: 12,
                child: Text(
                  context.l10n.noMoreBets.toUpperCase(),
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: const Color(0xFFFDE68A),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.4,
                  ),
                ),
              ),
            if (showResult && r != null) Positioned(bottom: 14, child: _ResultBadge(game: game, glow: glow)),
          ],
        ),
      );
    },
  );
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.game, required this.glow});
  final RouletteGame game;
  final double glow;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final r = game.result!;
    final net = game.lastReturn;
    final pulse = math.sin(glow * 2 * math.pi).abs();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.elasticOut,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 66,
            height: 66,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pocketColor(r),
              border: Border.all(color: const Color(0xFFFDE68A), width: 3),
              boxShadow: [BoxShadow(color: pocketColor(r).withValues(alpha: 0.5 + 0.4 * pulse), blurRadius: 28)],
            ),
            child: Text(
              pocketLabel(r),
              style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            net > 0 ? l.youWinAmount(_fmt(net)) : l.noWinThisTime,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: net > 0 ? AuraColors.green : Colors.white70,
              fontSize: net > 0 ? 22 : 16,
              fontWeight: FontWeight.w900,
              shadows: net > 0 ? [Shadow(color: AuraColors.green.withValues(alpha: 0.6), blurRadius: 18)] : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// "PLACE YOUR BETS" / "NO MORE BETS" / "17 RED · You win 350", and the
/// total on the table.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.game});
  final RouletteGame game;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final g = game;
    final r = g.result;
    final String text;
    Color color = const Color(0xFFFDE68A);
    switch (g.phase) {
      case RoulettePhase.betting:
        text = l.placeYourBets.toUpperCase();
      case RoulettePhase.spinning:
        text = l.noMoreBets.toUpperCase();
      case RoulettePhase.result:
        final word = r == null || r == 0 || r == doubleZero ? '' : ' ${RouletteRules.isRed(r) ? l.betRed : l.betBlack}';
        final net = g.lastReturn;
        text = '${pocketLabel(r ?? 0)}${word.toUpperCase()}${net > 0 ? ' · ${l.youWinAmount(_fmt(net))}' : ''}';
        if (net > 0) color = AuraColors.green;
    }
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: color,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
                if (g.phase == RoulettePhase.betting && g.bets.isEmpty)
                  Text(
                    l.rouletteHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AuraText.caption.copyWith(fontSize: 10.5, height: 1.2),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.black.withValues(alpha: 0.35),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              l.totalBetAmount(_fmt(g.totalBet)),
              style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// The table's leather rail and baize; the layout is printed on it.
class _Felt extends StatelessWidget {
  const _Felt({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF5B2A12), Color(0xFF3B1808), Color(0xFF4A200C)],
      ),
      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6))],
      border: Border.all(color: const Color(0xFF7A3E1C), width: 1),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: CustomPaint(
        painter: const _BaizePainter(),
        child: Padding(padding: const EdgeInsets.fromLTRB(8, 10, 8, 8), child: child),
      ),
    ),
  );
}

class _BaizePainter extends CustomPainter {
  const _BaizePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.3),
          radius: 1.1,
          colors: [Color(0xFF15814A), Color(0xFF0E6238), Color(0xFF07401F)],
        ).createShader(r),
    );
    // Cloth texture: fine speckles.
    final rng = math.Random(7);
    final light = <Offset>[], dark = <Offset>[];
    for (var i = 0; i < 1400; i++) {
      final p = Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height);
      (i.isEven ? light : dark).add(p);
    }
    canvas.drawPoints(
      PointMode.points,
      light,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..strokeWidth = 1.2,
    );
    canvas.drawPoints(
      PointMode.points,
      dark,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.10)
        ..strokeWidth = 1.2,
    );
    // Inner shadow under the rail.
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  @override
  bool shouldRepaint(_BaizePainter old) => false;
}

/// The dealer's marker on the winning number.
class _Dolly extends StatelessWidget {
  const _Dolly({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: -1, end: 0),
    duration: const Duration(milliseconds: 420),
    curve: Curves.bounceOut,
    builder: (_, v, child) => Transform.translate(offset: Offset(0, v * size), child: child),
    child: CustomPaint(size: Size(size, size * 1.1), painter: _DollyPainter()),
  );
}

class _DollyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final ew = w * 0.7, eh = w * 0.26;
    final top = Offset(w / 2, h * 0.22), base = Offset(w / 2, h * 0.78);
    canvas.drawOval(
      Rect.fromCenter(center: base + Offset(w * 0.08, eh * 0.35), width: ew * 1.1, height: eh * 1.1),
      Paint()
        ..color = Colors.black54
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    final body = Path()
      ..moveTo(top.dx - ew / 2, top.dy)
      ..lineTo(base.dx - ew / 2, base.dy)
      ..arcToPoint(Offset(base.dx + ew / 2, base.dy), radius: Radius.elliptical(ew / 2, eh / 2), clockwise: false)
      ..lineTo(top.dx + ew / 2, top.dy)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFB0B7C3), Colors.white, Color(0xFFCBD2DC), Color(0xFF8A93A1)],
          stops: [0, 0.35, 0.7, 1],
        ).createShader(Rect.fromLTWH(top.dx - ew / 2, top.dy, ew, base.dy - top.dy)),
    );
    canvas.drawOval(
      Rect.fromCenter(center: top, width: ew, height: eh),
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFFFFF3C4), Color(0xFFD4A017)]).createShader(
          Rect.fromCenter(center: top, width: ew, height: eh),
        ),
    );
    canvas.drawOval(
      Rect.fromCenter(center: top, width: ew, height: eh),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF8A6A10),
    );
  }

  @override
  bool shouldRepaint(_DollyPainter old) => false;
}

/// A European wheel: wooden rim, ball track with deflectors, the 37 numbered
/// pockets, the cone and the turret. [wheel] is its rotation; [ball] /
/// [ballR] place the ball (absolute angle, fraction of the radius).
class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.wheel, required this.order, this.ball, this.ballR, this.highlight});

  /// Pockets in wheel order (European or American).
  final List<int> order;
  final double wheel;
  final double? ball;
  final double? ballR;
  final int? highlight;

  double get seg => 2 * math.pi / order.length;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    // Shadow + wooden rim.
    canvas.drawCircle(
      c + Offset(0, r * 0.03),
      r,
      Paint()
        ..color = Colors.black54
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.05),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Color(0xFF7C2D12),
            Color(0xFFB45309),
            Color(0xFF5B2108),
            Color(0xFFA16207),
            Color(0xFF7C2D12),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(
      c,
      r * 0.97,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.015
        ..color = const Color(0xFFFDE68A).withValues(alpha: 0.5),
    );
    // Ball track.
    canvas.drawCircle(
      c,
      r * 0.88,
      Paint()
        ..shader = RadialGradient(
          colors: const [
            Color(0xFF3F3A4D),
            Color(0xFF1C1828),
            Color(0xFF0C0A12),
          ],
          stops: const [0.82, 0.92, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.88)),
    );
    // Deflectors (diamonds) on the track.
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4 + math.pi / 8;
      final p = c + Offset(math.cos(a), math.sin(a)) * r * 0.81;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(a);
      canvas.drawPath(
        Path()
          ..moveTo(-r * 0.03, 0)
          ..lineTo(0, -r * 0.012)
          ..lineTo(r * 0.03, 0)
          ..lineTo(0, r * 0.012)
          ..close(),
        Paint()..color = const Color(0xFFE5E7EB),
      );
      canvas.restore();
    }

    // Rotating part: number ring, pockets, cone, turret.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(wheel);
    final ringOuter = r * 0.74, ringInner = r * 0.6, pocketInner = r * 0.48;
    for (var i = 0; i < order.length; i++) {
      final n = order[i];
      final a0 = -math.pi / 2 + i * seg - seg / 2;
      final col = pocketColor(n);
      final ring = Path()
        ..arcTo(
          Rect.fromCircle(center: Offset.zero, radius: ringOuter),
          a0,
          seg,
          true,
        )
        ..arcTo(
          Rect.fromCircle(center: Offset.zero, radius: ringInner),
          a0 + seg,
          -seg,
          false,
        )
        ..close();
      canvas.drawPath(ring, Paint()..color = col);
      final pocket = Path()
        ..arcTo(
          Rect.fromCircle(center: Offset.zero, radius: ringInner),
          a0,
          seg,
          true,
        )
        ..arcTo(
          Rect.fromCircle(center: Offset.zero, radius: pocketInner),
          a0 + seg,
          -seg,
          false,
        )
        ..close();
      canvas.drawPath(
        pocket,
        Paint()..color = Color.lerp(col, Colors.black, 0.45)!,
      );
      if (n == highlight) {
        canvas.drawPath(
          ring,
          Paint()..color = Colors.white.withValues(alpha: 0.28),
        );
      }
      // Separators (frets).
      final sep = Paint()
        ..color = const Color(0xFFFCD34D)
        ..strokeWidth = math.max(0.8, r * 0.008);
      canvas.drawLine(
        Offset(math.cos(a0), math.sin(a0)) * pocketInner,
        Offset(math.cos(a0), math.sin(a0)) * ringOuter,
        sep,
      );
      // Number, reading outward.
      final mid = a0 + seg / 2;
      final tp = TextPainter(
        text: TextSpan(
          text: pocketLabel(n),
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: Colors.white,
            fontSize: r * 0.075,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.rotate(mid + math.pi / 2);
      tp.paint(
        canvas,
        Offset(-tp.width / 2, -(ringOuter + ringInner) / 2 - tp.height / 2),
      );
      canvas.restore();
    }
    canvas.drawCircle(
      Offset.zero,
      ringOuter,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.012
        ..color = const Color(0xFFFCD34D),
    );
    canvas.drawCircle(
      Offset.zero,
      ringInner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.008
        ..color = const Color(0xFFFCD34D),
    );
    // Cone.
    canvas.drawCircle(
      Offset.zero,
      pocketInner,
      Paint()
        ..shader =
            RadialGradient(
              center: const Alignment(-0.3, -0.3),
              colors: const [
                Color(0xFFD97706),
                Color(0xFF92400E),
                Color(0xFF451A03),
              ],
            ).createShader(
              Rect.fromCircle(center: Offset.zero, radius: pocketInner),
            ),
    );
    for (var i = 0; i < 4; i++) {
      canvas.save();
      canvas.rotate(i * math.pi / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-r * 0.018, -r * 0.3, r * 0.036, r * 0.3),
          Radius.circular(r * 0.02),
        ),
        Paint()..color = const Color(0xFFFDE68A),
      );
      canvas.drawCircle(
        Offset(0, -r * 0.3),
        r * 0.03,
        Paint()..color = const Color(0xFFFEF3C7),
      );
      canvas.restore();
    }
    canvas.drawCircle(
      Offset.zero,
      r * 0.07,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFFBEB), Color(0xFFD97706)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 0.07)),
    );
    canvas.restore();

    // Ball.
    final b = ball;
    if (b != null && ballR != null) {
      final a = -math.pi / 2 + b;
      final p = c + Offset(math.cos(a), math.sin(a)) * r * ballR!;
      final br = r * 0.036;
      canvas.drawCircle(
        p + Offset(br * 0.3, br * 0.4),
        br,
        Paint()
          ..color = Colors.black54
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, br * 0.4),
      );
      canvas.drawCircle(
        p,
        br,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.4),
            colors: const [Colors.white, Color(0xFFE5E7EB), Color(0xFF9CA3AF)],
          ).createShader(Rect.fromCircle(center: p, radius: br)),
      );
    }
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.wheel != wheel ||
      old.ball != ball ||
      old.ballR != ballR ||
      old.highlight != highlight;
}

/// The betting table, vertical (0 at the top, 12 rows of 3, column bets at
/// the bottom; dozens and even-money bets down the left side). Tap a number
/// for a straight bet, the line between two numbers for a split, a crossing
/// for a corner, the left edge of a row for a street.
class _RouletteTable extends StatelessWidget {
  const _RouletteTable({
    required this.game,
    required this.onPlace,
    required this.glow,
  });
  final RouletteGame game;
  final ValueChanged<BetSpot> onPlace;
  final double glow;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return LayoutBuilder(
      builder: (context, box) {
        final geo = _TableGeo.fit(box.biggest, doubleZero: game.variant.doubleZeroTable);
        final chips = <Widget>[];
        for (final e in game.bets.entries) {
          final p = geo.anchor(e.key);
          final won =
              game.phase == RoulettePhase.result &&
              game.winningSpots.contains(e.key);
          final cs = geo.rh * 0.78;
          chips.add(
            Positioned(
              left: p.dx - cs / 2,
              top: p.dy - cs / 2,
              child: IgnorePointer(
                child: Container(
                  decoration: won
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AuraColors.green.withValues(
                                alpha: 0.5 + 0.4 * glow,
                              ),
                              blurRadius: 14,
                              spreadRadius: 2,
                            ),
                          ],
                        )
                      : null,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(1, 2))],
                    ),
                    child: CasinoChip(value: e.value, size: cs),
                  ),
                ),
              ),
            ),
          );
        }
        final w = game.phase == RoulettePhase.result ? game.result : null;
        if (w != null) {
          final cell = w == 0 ? geo.zero : (w == doubleZero ? geo.zeroZero : geo.number(w));
          final ds = geo.rh * 0.62;
          chips.add(
            Positioned(
              left: cell.center.dx - ds / 2,
              top: cell.center.dy - ds * 0.9,
              child: IgnorePointer(child: _Dolly(key: ValueKey('dolly$w'), size: ds)),
            ),
          );
        }
        return Center(
          child: SizedBox(
            width: geo.width,
            height: geo.height,
            child: GestureDetector(
              onTapUp: (d) {
                final spot = geo.spotAt(d.localPosition);
                if (spot != null) onPlace(spot);
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TablePainter(
                        geo: geo,
                        labels: (l.betRed, l.betBlack, l.betOdd, l.betEven),
                        win: game.phase == RoulettePhase.result
                            ? game.result
                            : null,
                        glow: glow,
                        french: game.variant == RouletteVariant.french,
                      ),
                    ),
                  ),
                  ...chips,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Table layout maths (shared by painting, hit-testing and chip anchors).
class _TableGeo {
  _TableGeo(this.side, this.cw, this.rh, {this.hasDoubleZero = false});

  /// American table: the zero row is split into 0 and 00.
  final bool hasDoubleZero;

  /// Width of each of the two side columns, a number cell, a row.
  final double side, cw, rh;

  static _TableGeo fit(Size s, {bool doubleZero = false}) {
    final side = s.width * 0.135;
    final cw = (s.width - 2 * side) / 3;
    final rh = math.min(s.height / 14, cw * 0.62);
    return _TableGeo(side, cw, rh, hasDoubleZero: doubleZero);
  }

  double get width => 2 * side + 3 * cw;
  double get height => 14 * rh;
  double get x0 => 2 * side;
  double get y0 => rh;

  Rect get zero => Rect.fromLTWH(x0, 0, hasDoubleZero ? 1.5 * cw : 3 * cw, rh);
  Rect get zeroZero => Rect.fromLTWH(x0 + 1.5 * cw, 0, 1.5 * cw, rh);
  Rect number(int n) {
    final (row, col) = RouletteRules.cellOf(n);
    return Rect.fromLTWH(x0 + col * cw, y0 + row * rh, cw, rh);
  }

  Rect column(int c) => Rect.fromLTWH(x0 + c * cw, y0 + 12 * rh, cw, rh);
  Rect dozen(int d) => Rect.fromLTWH(side, y0 + d * 4 * rh, side, 4 * rh);

  /// Even-money spots top to bottom: 1–18, EVEN, RED, BLACK, ODD, 19–36.
  static final evenMoney = [
    BetSpot.lowBet,
    BetSpot.evenBet,
    BetSpot.redBet,
    BetSpot.blackBet,
    BetSpot.oddBet,
    BetSpot.highBet,
  ];
  Rect even(int i) => Rect.fromLTWH(0, y0 + i * 2 * rh, side, 2 * rh);

  BetSpot? spotAt(Offset p) {
    if (zero.contains(p)) return BetSpot.straight(0);
    if (hasDoubleZero && zeroZero.contains(p)) return BetSpot.straight(doubleZero);
    final x = p.dx, y = p.dy;
    if (y >= y0 && y < y0 + 12 * rh) {
      if (x >= x0) {
        final fx = (x - x0) / cw, fy = (y - y0) / rh;
        final col = fx.floor().clamp(0, 2), row = fy.floor().clamp(0, 11);
        final ex = fx - col, ey = fy - row;
        const e = 0.24;
        final n = row * 3 + col + 1;
        final left = ex < e && col > 0, right = ex > 1 - e && col < 2;
        final top = ey < e && row > 0, bottom = ey > 1 - e && row < 11;
        if (ex < e && col == 0 && !top && !bottom) return BetSpot.street(row);
        if ((left || right) && (top || bottom)) {
          final c0 = left ? col - 1 : col, r0 = top ? row - 1 : row;
          return BetSpot.corner(r0 * 3 + c0 + 1);
        }
        if (left) return BetSpot.split(n - 1, n);
        if (right) return BetSpot.split(n, n + 1);
        if (top) return BetSpot.split(n - 3, n);
        if (bottom) return BetSpot.split(n, n + 3);
        return BetSpot.straight(n);
      }
      if (x >= side) {
        return BetSpot.dozen(((y - y0) / (4 * rh)).floor().clamp(0, 2));
      }
      return evenMoney[((y - y0) / (2 * rh)).floor().clamp(0, 5)];
    }
    if (y >= y0 + 12 * rh && x >= x0) {
      return BetSpot.column(((x - x0) / cw).floor().clamp(0, 2));
    }
    return null;
  }

  /// Where a spot's chips sit.
  Offset anchor(BetSpot s) {
    switch (s.kind) {
      case BetKind.straight:
        if (s.index == doubleZero) return zeroZero.center;
        return s.index == 0 ? zero.center : number(s.index).center;
      case BetKind.split:
        final a = s.numbers.reduce(math.min), b = s.numbers.reduce(math.max);
        final ra = number(a);
        return b == a + 1
            ? Offset(ra.right, ra.center.dy)
            : Offset(ra.center.dx, ra.bottom);
      case BetKind.street:
        return Offset(x0, y0 + s.index * rh + rh / 2);
      case BetKind.corner:
        final r = number(s.index);
        return r.bottomRight;
      case BetKind.dozen:
        return dozen(s.index).center;
      case BetKind.column:
        return column(s.index).center;
      default:
        return even(evenMoney.indexOf(s)).center;
    }
  }
}

/// The layout printed on the baize: red and black number boxes in a cream
/// grid, the arched 0 (0 | 00 on American), "2 to 1", the dozens and the
/// even-money boxes with the red / black diamonds.
class _TablePainter extends CustomPainter {
  _TablePainter({required this.geo, required this.labels, required this.win, required this.glow, this.french = false});

  /// French names on the table (Manque / Passe / Pair / Impair, P12 / M12 / D12).
  final bool french;
  final _TableGeo geo;
  final (String, String, String, String) labels;
  final int? win;
  final double glow;

  static const _cream = Color(0xFFF1E7CB);
  static const _red = Color(0xFFB8142C);
  static const _black = Color(0xFF121014);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = _cream.withValues(alpha: 0.92);

    void label(Rect r, String text, {bool vertical = false, double font = 0.4, Color color = _cream, double spacing = 0}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: color,
            fontSize: geo.rh * font,
            fontWeight: FontWeight.w700,
            letterSpacing: spacing,
            shadows: const [Shadow(color: Colors.black38, offset: Offset(0.5, 1), blurRadius: 1)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(r.center.dx, r.center.dy);
      if (vertical) canvas.rotate(-math.pi / 2);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    // 0 (and 00): green with an arched top.
    Path arch(Rect r) => Path()
      ..moveTo(r.left, r.bottom)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.right, r.top + r.height * 0.45)
      ..quadraticBezierTo(r.center.dx, r.top - r.height * 0.42, r.left, r.top + r.height * 0.45)
      ..close();
    final zeros = [geo.zero, if (geo.hasDoubleZero) geo.zeroZero];
    for (var i = 0; i < zeros.length; i++) {
      final p = arch(zeros[i]);
      canvas.drawPath(p, Paint()..color = _green);
      canvas.drawPath(p, line);
      label(zeros[i].shift(Offset(0, geo.rh * 0.08)), i == 0 ? '0' : '00', font: 0.5, color: Colors.white);
    }

    // Numbers.
    for (var n = 1; n <= 36; n++) {
      final r = geo.number(n);
      final red = RouletteRules.isRed(n);
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: red ? const [Color(0xFFCB2038), _red] : const [Color(0xFF26222B), _black],
          ).createShader(r),
      );
      canvas.drawRect(
        r.deflate(2.2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.white.withValues(alpha: 0.07),
      );
      label(r, '$n', font: 0.47, color: Colors.white);
      canvas.drawRect(r, line);
    }

    // Columns, dozens, even-money.
    for (var c = 0; c < 3; c++) {
      canvas.drawRect(geo.column(c), line);
      label(geo.column(c), '2 to 1', font: 0.3);
    }
    final dozens = french ? const ['P12', 'M12', 'D12'] : const ['1st 12', '2nd 12', '3rd 12'];
    for (var d = 0; d < 3; d++) {
      canvas.drawRect(geo.dozen(d), line);
      label(geo.dozen(d), dozens[d], vertical: true, font: 0.42, spacing: 1);
    }
    final evens = french
        ? const ['MANQUE', 'PAIR', '', '', 'IMPAIR', 'PASSE']
        : ['1–18', labels.$4.toUpperCase(), '', '', labels.$3.toUpperCase(), '19–36'];
    for (var i = 0; i < 6; i++) {
      final r = geo.even(i);
      canvas.drawRect(r, line);
      if (i == 2 || i == 3) {
        final d = Path()
          ..moveTo(r.center.dx, r.center.dy - r.height * 0.32)
          ..lineTo(r.center.dx + r.width * 0.3, r.center.dy)
          ..lineTo(r.center.dx, r.center.dy + r.height * 0.32)
          ..lineTo(r.center.dx - r.width * 0.3, r.center.dy)
          ..close();
        canvas.drawPath(d, Paint()..color = i == 2 ? _red : _black);
        canvas.drawPath(d, line);
      } else {
        label(r, evens[i], vertical: true, font: 0.36, spacing: 1);
      }
    }
    // The outer edge, a touch heavier.
    canvas.drawRect(
      Rect.fromLTWH(0, geo.y0, geo.width, 13 * geo.rh),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _cream,
    );

    // The winning number glows.
    final w = win;
    if (w != null) {
      final r = w == 0 ? geo.zero : (w == doubleZero ? geo.zeroZero : geo.number(w));
      canvas.drawRect(
        r.inflate(2),
        Paint()
          ..color = AuraColors.amber.withValues(alpha: 0.35 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawRect(
        r.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = AuraColors.amber.withValues(alpha: 0.6 + 0.4 * glow),
      );
    }
  }

  @override
  bool shouldRepaint(_TablePainter old) => true;
}

/// The results display beside a real wheel: the last numbers in their
/// colours, newest first and boxed.
class _History extends StatelessWidget {
  const _History({required this.results});
  final List<int> results;

  static Color _ink(int n) => n == 0 || n == doubleZero
      ? const Color(0xFF34D399)
      : (RouletteRules.isRed(n) ? const Color(0xFFFF4D5E) : Colors.white);

  @override
  Widget build(BuildContext context) => Container(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      color: const Color(0xFF09080D),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2))],
    ),
    child: results.isEmpty
        ? Center(child: Text(context.l10n.lastResults, style: AuraText.caption.copyWith(fontSize: 11.5)))
        : ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: results.length,
            separatorBuilder: (_, _) => const SizedBox(width: 2),
            itemBuilder: (_, i) => Center(
              child: Container(
                width: 30,
                height: 24,
                alignment: Alignment.center,
                decoration: i == 0
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: pocketColor(results[i]),
                        border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
                      )
                    : null,
                child: Text(
                  pocketLabel(results[i]),
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: i == 0 ? Colors.white : _ink(results[i]),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(color: _ink(results[i]).withValues(alpha: 0.6), blurRadius: 6)],
                  ),
                ),
              ),
            ),
          ),
  );
}

/// Your chips in a wooden tray; the chosen one is lifted.
class _ChipTray extends StatelessWidget {
  const _ChipTray({required this.selected, required this.balance, required this.onPick});
  final int selected;
  final int balance;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => Container(
    height: 58,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(29),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2A1408), Color(0xFF4A230E), Color(0xFF2A1408)],
      ),
      border: Border.all(color: const Color(0xFF7A3E1C)),
      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 3))],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final v in _chipValues)
          GestureDetector(
            onTap: () => onPick(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              transform: Matrix4.translationValues(0, v == selected ? -6 : 0, 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 5, offset: const Offset(0, 3)),
                  if (v == selected) BoxShadow(color: AuraColors.amber.withValues(alpha: 0.55), blurRadius: 14, spreadRadius: 1),
                ],
              ),
              child: Opacity(
                opacity: v <= balance ? 1 : 0.35,
                child: CasinoChip(value: v, size: 42, selected: v == selected),
              ),
            ),
          ),
      ],
    ),
  );
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: SizedBox(
        width: 54,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF3A3346), Color(0xFF1C1724)],
                ),
                border: Border.all(color: const Color(0xFFFDE68A).withValues(alpha: 0.45)),
              ),
              child: Icon(icon, size: 19, color: Colors.white),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The casino-gold spin button.
class _SpinButton extends StatelessWidget {
  const _SpinButton({required this.label, required this.enabled, required this.onTap});
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.45,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF1B8), Color(0xFFF2C14E), Color(0xFFB7791F)],
            stops: [0, 0.45, 1],
          ),
          border: Border.all(color: const Color(0xFF7A4E0E), width: 1.5),
          boxShadow: [
            if (enabled) BoxShadow(color: const Color(0xFFF2C14E).withValues(alpha: 0.45), blurRadius: 18),
            const BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: const Color(0xFF3B2405),
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
      ),
    ),
  );
}

class _BalancePill extends StatelessWidget {
  const _BalancePill({required this.balance});
  final int balance;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(99),
      color: Colors.white.withValues(alpha: 0.08),
      border: Border.all(color: AuraColors.amber.withValues(alpha: 0.5)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.toll_rounded, size: 16, color: AuraColors.amber),
        const SizedBox(width: 6),
        TweenAnimationBuilder<double>(
          tween: Tween(end: balance.toDouble()),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => Text(
            _fmt(v.round()),
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _TopUp extends StatelessWidget {
  const _TopUp({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: AuraGlass.decoration(radius: 16, shadow: false),
    child: Row(
      children: [
        Expanded(child: Text(context.l10n.outOfChips, style: AuraText.cardSub)),
        TextButton(onPressed: onTap, child: Text(context.l10n.topUp)),
      ],
    ),
  );
}

String variantName(BuildContext context, RouletteVariant v) => switch (v) {
  RouletteVariant.european => context.l10n.rouletteEuropean,
  RouletteVariant.french => context.l10n.rouletteFrench,
  RouletteVariant.american => context.l10n.rouletteAmerican,
};

/// Quick Play setup → [RouletteScreen]: European, French or American table.
class RouletteSetupScreen extends StatefulWidget {
  const RouletteSetupScreen({super.key});

  @override
  State<RouletteSetupScreen> createState() => _RouletteSetupScreenState();
}

class _RouletteSetupScreenState extends State<RouletteSetupScreen> {
  RouletteVariant _variant = RouletteVariant.european;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final subs = {
      RouletteVariant.european: l.rouletteEuropeanSub,
      RouletteVariant.french: l.rouletteFrenchSub,
      RouletteVariant.american: l.rouletteAmericanSub,
    };
    return AuraScaffold(
      appBar: AuraAppBar(title: l.quickPlay),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text('Roulette', style: AuraText.headline.copyWith(fontSize: 24)),
          const SizedBox(height: 6),
          Text(l.rouletteSetupBlurb, style: AuraText.cardSub),
          const SizedBox(height: 22),
          SectionBar(l.chooseTable),
          const SizedBox(height: 10),
          for (final v in RouletteVariant.values) ...[
            GestureDetector(
              onTap: () => setState(() => _variant = v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: _variant == v
                      ? AuraGradients.brand
                      : LinearGradient(colors: [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.03)]),
                  border: Border.all(color: _variant == v ? Colors.white.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.14), width: 2),
                ),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 64,
                      child: CustomPaint(painter: _WheelPainter(wheel: 0, order: v.wheel)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(variantName(context, v), style: AuraText.cardTitle.copyWith(fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(subs[v]!, style: AuraText.cardSub.copyWith(fontSize: 12, color: Colors.white70)),
                          const SizedBox(height: 4),
                          Text(
                            l.houseEdge(v.edge),
                            style: const TextStyle(color: AuraColors.amber, fontSize: 11.5, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 16),
          GradientButton(
            label: l.startGame,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RouletteScreen(variant: _variant)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
