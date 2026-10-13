import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../widgets/aura.dart';
import '../common/playing_cards.dart' show CasinoChip;
import 'roulette_engine.dart';

String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

const _green = Color(0xFF0F7A47);
const _redPocket = Color(0xFFC81E32);
const _blackPocket = Color(0xFF15121F);

Color pocketColor(int n) => n == 0 ? _green : (RouletteRules.isRed(n) ? _redPocket : _blackPocket);

const _chipValues = [10, 25, 100, 500, 1000];

/// European roulette, practice chips: place chips on the table, spin, and
/// watch the ball settle. Rounds repeat; leave with the back button.
class RouletteScreen extends StatefulWidget {
  const RouletteScreen({super.key, @visibleForTesting this.game});

  /// A prepared game (tests); null = a new one.
  final RouletteGame? game;

  @override
  State<RouletteScreen> createState() => _RouletteScreenState();
}

class _RouletteScreenState extends State<RouletteScreen> with TickerProviderStateMixin {
  late final RouletteGame _game = widget.game ?? RouletteGame();
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 7200));
  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();
  final _rng = math.Random();

  int _chip = 25;

  /// Wheel angle at rest (radians, clockwise from the top).
  double _wheelRest = 0;
  _SpinPlan? _plan;
  Timer? _nextRound;

  @override
  void initState() {
    super.initState();
    _game.addListener(_onChange);
  }

  @override
  void dispose() {
    _nextRound?.cancel();
    _spin.dispose();
    _glow.dispose();
    _game.removeListener(_onChange);
    _game.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

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
    final result = _game.spin();
    _plan = _SpinPlan(_wheelRest, RouletteRules.wheel.indexOf(result), _rng);
    await _spin.forward(from: 0);
    if (!mounted) return;
    _wheelRest = _plan!.wheelAt(1) % (2 * math.pi);
    _game.settle();
    _nextRound = Timer(const Duration(milliseconds: 3400), _continue);
  }

  void _continue() {
    _nextRound?.cancel();
    if (!mounted || _game.phase != RoulettePhase.result) return;
    _plan = null;
    _game.nextRound();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final g = _game;
    final betting = g.phase == RoulettePhase.betting;
    final broke = betting && g.balance < _chipValues.first && g.bets.isEmpty;
    return AuraScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GameHeader(
                  title: '🎡 Roulette',
                  subtitle: l.practiceChips,
                  pot: '0',
                  leading: GlassIconButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).maybePop()),
                  trailing: _BalancePill(balance: g.balance),
                ),
                const SizedBox(height: 8),
                _ResultsStrip(results: g.results),
                const SizedBox(height: 8),
                // Small wheel + status while betting.
                SizedBox(
                  height: 116,
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 116,
                        child: CustomPaint(painter: _WheelPainter(wheel: _wheelRest, highlight: g.results.isEmpty ? null : g.results.first)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.placeYourBets, style: AuraText.cardTitle.copyWith(fontSize: 18)),
                            const SizedBox(height: 4),
                            Flexible(
                              child: Text(
                                l.rouletteHint,
                                style: AuraText.caption.copyWith(fontSize: 11.5),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l.totalBetAmount(_fmt(g.totalBet)),
                              style: TextStyle(
                                fontFamily: AuraText.displayFamily,
                                color: AuraColors.amber,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _glow,
                    builder: (_, _) => _RouletteTable(
                      game: g,
                      onPlace: _place,
                      glow: math.sin(_glow.value * 2 * math.pi) * 0.5 + 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (broke)
                  _TopUp(onTap: g.refill)
                else
                  _ChipBar(selected: _chip, balance: g.balance, onPick: (v) => setState(() => _chip = v)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _ActionChip(icon: Icons.undo_rounded, label: l.undo, onTap: betting && g.bets.isNotEmpty ? g.undo : null),
                    const SizedBox(width: 6),
                    _ActionChip(icon: Icons.delete_outline_rounded, label: l.clearBets, onTap: betting && g.bets.isNotEmpty ? g.clear : null),
                    const SizedBox(width: 6),
                    g.canRepeat
                        ? _ActionChip(icon: Icons.replay_rounded, label: l.repeatBets, onTap: betting ? () => g.repeat() : null)
                        : _ActionChip(
                            icon: Icons.exposure_plus_2_rounded,
                            label: l.doubleBets,
                            onTap: betting && g.bets.isNotEmpty ? () => g.double() : null,
                          ),
                    const SizedBox(width: 8),
                    Expanded(child: GradientButton(label: l.spinButton, enabled: betting, onPressed: _doSpin)),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
          // The spin: a big wheel over the dimmed table, then the result.
          if (!betting && _plan != null)
            Positioned.fill(
              child: GestureDetector(
                onTap: g.phase == RoulettePhase.result ? _continue : null,
                child: _SpinOverlay(game: g, plan: _plan!, spin: _spin, glow: _glow),
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
  _SpinPlan(this.start, this.pocket, math.Random rng)
    : wheelTurns = 1.4 + rng.nextDouble() * 0.6,
      ballTurns = 5.5 + rng.nextDouble() * 1.5;

  final double start;
  final int pocket;
  final double wheelTurns;
  final double ballTurns;

  static const land = 0.8;
  static const seg = 2 * math.pi / 37;

  double wheelAt(double t) => start + wheelTurns * 2 * math.pi * Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));

  double ballAt(double t) {
    if (t >= land) return wheelAt(t) + pocket * seg;
    final target = wheelAt(land) + pocket * seg;
    return target + ballTurns * 2 * math.pi * (1 - Curves.easeOutQuad.transform(t / land));
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
    return base + (track - rest) * 0.22 * (1 - v) * math.sin(v * math.pi * 5).abs();
  }
}

class _SpinOverlay extends StatelessWidget {
  const _SpinOverlay({required this.game, required this.plan, required this.spin, required this.glow});
  final RouletteGame game;
  final _SpinPlan plan;
  final Animation<double> spin;
  final Animation<double> glow;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final done = game.phase == RoulettePhase.result;
    final r = game.result!;
    final net = game.lastReturn;
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      child: LayoutBuilder(
        builder: (context, box) {
          final size = math.min(box.maxWidth - 24, 330.0);
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                done ? '' : l.noMoreBets,
                style: AuraText.cardTitle.copyWith(fontSize: 16, color: Colors.white70, letterSpacing: 1),
              ),
              const SizedBox(height: 14),
              SizedBox.square(
                dimension: size,
                child: AnimatedBuilder(
                  animation: spin,
                  builder: (_, _) {
                    final t = spin.value;
                    return CustomPaint(
                      painter: _WheelPainter(
                        wheel: plan.wheelAt(t),
                        ball: plan.ballAt(t),
                        ballR: plan.ballRadius(t),
                        highlight: done ? r : null,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (c, a) => ScaleTransition(
                  scale: CurvedAnimation(parent: a, curve: Curves.elasticOut),
                  child: FadeTransition(opacity: a, child: c),
                ),
                child: !done
                    ? const SizedBox(key: ValueKey('spinning'), height: 110)
                    : Column(
                        key: const ValueKey('result'),
                        children: [
                          AnimatedBuilder(
                            animation: glow,
                            builder: (_, child) => Container(
                              width: 74,
                              height: 74,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: pocketColor(r),
                                border: Border.all(color: AuraColors.amber, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: pocketColor(r).withValues(alpha: 0.5 + 0.4 * math.sin(glow.value * 2 * math.pi).abs()),
                                    blurRadius: 30,
                                  ),
                                ],
                              ),
                              child: child,
                            ),
                            child: Text(
                              '$r',
                              style: TextStyle(
                                fontFamily: AuraText.displayFamily,
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            net > 0 ? l.youWinAmount(_fmt(net)) : l.noWinThisTime,
                            style: TextStyle(
                              fontFamily: AuraText.displayFamily,
                              color: net > 0 ? AuraColors.green : Colors.white70,
                              fontSize: net > 0 ? 24 : 17,
                              fontWeight: FontWeight.w900,
                              shadows: net > 0 ? [Shadow(color: AuraColors.green.withValues(alpha: 0.6), blurRadius: 18)] : null,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A European wheel: wooden rim, ball track with deflectors, the 37 numbered
/// pockets, the cone and the turret. [wheel] is its rotation; [ball] /
/// [ballR] place the ball (absolute angle, fraction of the radius).
class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.wheel, this.ball, this.ballR, this.highlight});
  final double wheel;
  final double? ball;
  final double? ballR;
  final int? highlight;

  static const seg = 2 * math.pi / 37;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    // Shadow + wooden rim.
    canvas.drawCircle(c + Offset(0, r * 0.03), r, Paint()..color = Colors.black54..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.05));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const SweepGradient(
          colors: [Color(0xFF7C2D12), Color(0xFFB45309), Color(0xFF5B2108), Color(0xFFA16207), Color(0xFF7C2D12)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(c, r * 0.97, Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.015..color = const Color(0xFFFDE68A).withValues(alpha: 0.5));
    // Ball track.
    canvas.drawCircle(
      c,
      r * 0.88,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xFF3F3A4D), Color(0xFF1C1828), Color(0xFF0C0A12)],
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
    for (var i = 0; i < 37; i++) {
      final n = RouletteRules.wheel[i];
      final a0 = -math.pi / 2 + i * seg - seg / 2;
      final col = pocketColor(n);
      final ring = Path()
        ..arcTo(Rect.fromCircle(center: Offset.zero, radius: ringOuter), a0, seg, true)
        ..arcTo(Rect.fromCircle(center: Offset.zero, radius: ringInner), a0 + seg, -seg, false)
        ..close();
      canvas.drawPath(ring, Paint()..color = col);
      final pocket = Path()
        ..arcTo(Rect.fromCircle(center: Offset.zero, radius: ringInner), a0, seg, true)
        ..arcTo(Rect.fromCircle(center: Offset.zero, radius: pocketInner), a0 + seg, -seg, false)
        ..close();
      canvas.drawPath(pocket, Paint()..color = Color.lerp(col, Colors.black, 0.45)!);
      if (n == highlight) {
        canvas.drawPath(ring, Paint()..color = Colors.white.withValues(alpha: 0.28));
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
          text: '$n',
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
      tp.paint(canvas, Offset(-tp.width / 2, -(ringOuter + ringInner) / 2 - tp.height / 2));
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, ringOuter, Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.012..color = const Color(0xFFFCD34D));
    canvas.drawCircle(Offset.zero, ringInner, Paint()..style = PaintingStyle.stroke..strokeWidth = r * 0.008..color = const Color(0xFFFCD34D));
    // Cone.
    canvas.drawCircle(
      Offset.zero,
      pocketInner,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: const [Color(0xFFD97706), Color(0xFF92400E), Color(0xFF451A03)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: pocketInner)),
    );
    for (var i = 0; i < 4; i++) {
      canvas.save();
      canvas.rotate(i * math.pi / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-r * 0.018, -r * 0.3, r * 0.036, r * 0.3), Radius.circular(r * 0.02)),
        Paint()..color = const Color(0xFFFDE68A),
      );
      canvas.drawCircle(Offset(0, -r * 0.3), r * 0.03, Paint()..color = const Color(0xFFFEF3C7));
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, r * 0.07, Paint()..shader = const RadialGradient(colors: [Color(0xFFFFFBEB), Color(0xFFD97706)]).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 0.07)));
    canvas.restore();

    // Ball.
    final b = ball;
    if (b != null && ballR != null) {
      final a = -math.pi / 2 + b;
      final p = c + Offset(math.cos(a), math.sin(a)) * r * ballR!;
      final br = r * 0.036;
      canvas.drawCircle(p + Offset(br * 0.3, br * 0.4), br, Paint()..color = Colors.black54..maskFilter = MaskFilter.blur(BlurStyle.normal, br * 0.4));
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
      old.wheel != wheel || old.ball != ball || old.ballR != ballR || old.highlight != highlight;
}

/// The betting table, vertical (0 at the top, 12 rows of 3, column bets at
/// the bottom; dozens and even-money bets down the left side). Tap a number
/// for a straight bet, the line between two numbers for a split, a crossing
/// for a corner, the left edge of a row for a street.
class _RouletteTable extends StatelessWidget {
  const _RouletteTable({required this.game, required this.onPlace, required this.glow});
  final RouletteGame game;
  final ValueChanged<BetSpot> onPlace;
  final double glow;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return LayoutBuilder(
      builder: (context, box) {
        final geo = _TableGeo.fit(box.biggest);
        final chips = <Widget>[];
        for (final e in game.bets.entries) {
          final p = geo.anchor(e.key);
          final won = game.phase == RoulettePhase.result && game.winningSpots.contains(e.key);
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
                          boxShadow: [BoxShadow(color: AuraColors.green.withValues(alpha: 0.5 + 0.4 * glow), blurRadius: 14, spreadRadius: 2)],
                        )
                      : null,
                  child: CasinoChip(value: e.value, size: cs),
                ),
              ),
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
                        win: game.phase == RoulettePhase.result ? game.result : null,
                        glow: glow,
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
  _TableGeo(this.side, this.cw, this.rh);

  /// Width of each of the two side columns, a number cell, a row.
  final double side, cw, rh;

  static _TableGeo fit(Size s) {
    final side = s.width * 0.135;
    final cw = (s.width - 2 * side) / 3;
    final rh = math.min(s.height / 14, cw * 0.62);
    return _TableGeo(side, cw, rh);
  }

  double get width => 2 * side + 3 * cw;
  double get height => 14 * rh;
  double get x0 => 2 * side;
  double get y0 => rh;

  Rect get zero => Rect.fromLTWH(x0, 0, 3 * cw, rh);
  Rect number(int n) {
    final (row, col) = RouletteRules.cellOf(n);
    return Rect.fromLTWH(x0 + col * cw, y0 + row * rh, cw, rh);
  }

  Rect column(int c) => Rect.fromLTWH(x0 + c * cw, y0 + 12 * rh, cw, rh);
  Rect dozen(int d) => Rect.fromLTWH(side, y0 + d * 4 * rh, side, 4 * rh);

  /// Even-money spots top to bottom: 1–18, EVEN, RED, BLACK, ODD, 19–36.
  static final evenMoney = [BetSpot.lowBet, BetSpot.evenBet, BetSpot.redBet, BetSpot.blackBet, BetSpot.oddBet, BetSpot.highBet];
  Rect even(int i) => Rect.fromLTWH(0, y0 + i * 2 * rh, side, 2 * rh);

  BetSpot? spotAt(Offset p) {
    if (zero.contains(p)) return BetSpot.straight(0);
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
      if (x >= side) return BetSpot.dozen(((y - y0) / (4 * rh)).floor().clamp(0, 2));
      return evenMoney[((y - y0) / (2 * rh)).floor().clamp(0, 5)];
    }
    if (y >= y0 + 12 * rh && x >= x0) return BetSpot.column(((x - x0) / cw).floor().clamp(0, 2));
    return null;
  }

  /// Where a spot's chips sit.
  Offset anchor(BetSpot s) {
    switch (s.kind) {
      case BetKind.straight:
        return s.index == 0 ? zero.center : number(s.index).center;
      case BetKind.split:
        final a = s.numbers.reduce(math.min), b = s.numbers.reduce(math.max);
        final ra = number(a);
        return b == a + 1 ? Offset(ra.right, ra.center.dy) : Offset(ra.center.dx, ra.bottom);
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

class _TablePainter extends CustomPainter {
  _TablePainter({required this.geo, required this.labels, required this.win, required this.glow});
  final _TableGeo geo;
  final (String, String, String, String) labels;
  final int? win;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final felt = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)).inflate(4);
    canvas.drawRRect(
      felt,
      Paint()
        ..shader = const RadialGradient(
          radius: 1.2,
          colors: [Color(0xFF15803D), Color(0xFF14532D), Color(0xFF052E16)],
        ).createShader(felt.outerRect),
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFFDE68A).withValues(alpha: 0.75);

    void cell(Rect r, Color fill, String text, {bool vertical = false, double font = 0.42, Color textColor = Colors.white}) {
      final rr = RRect.fromRectAndRadius(r.deflate(1.5), const Radius.circular(4));
      canvas.drawRRect(rr, Paint()..color = fill);
      canvas.drawRRect(rr, line);
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: textColor,
            fontSize: geo.rh * font,
            fontWeight: FontWeight.w800,
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

    cell(geo.zero, _green, '0', font: 0.5);
    for (var n = 1; n <= 36; n++) {
      cell(geo.number(n), RouletteRules.isRed(n) ? _redPocket : _blackPocket, '$n', font: 0.48);
    }
    for (var c = 0; c < 3; c++) {
      cell(geo.column(c), Colors.transparent, '2:1', font: 0.4);
    }
    const dozens = ['1–12', '13–24', '25–36'];
    for (var d = 0; d < 3; d++) {
      cell(geo.dozen(d), Colors.transparent, dozens[d], vertical: true, font: 0.42);
    }
    final evens = ['1–18', labels.$4, '', '', labels.$3, '19–36'];
    for (var i = 0; i < 6; i++) {
      final r = geo.even(i);
      if (i == 2 || i == 3) {
        cell(r, Colors.transparent, '');
        // Red / black diamonds.
        final d = Path()
          ..moveTo(r.center.dx, r.center.dy - r.height * 0.3)
          ..lineTo(r.center.dx + r.width * 0.3, r.center.dy)
          ..lineTo(r.center.dx, r.center.dy + r.height * 0.3)
          ..lineTo(r.center.dx - r.width * 0.3, r.center.dy)
          ..close();
        canvas.drawPath(d, Paint()..color = i == 2 ? _redPocket : _blackPocket);
        canvas.drawPath(d, line);
      } else {
        cell(r, Colors.transparent, evens[i], vertical: true, font: 0.4);
      }
    }
    // The winning number glows.
    final w = win;
    if (w != null) {
      final r = w == 0 ? geo.zero : geo.number(w);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.deflate(1), const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = AuraColors.amber.withValues(alpha: 0.6 + 0.4 * glow),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.inflate(2), const Radius.circular(6)),
        Paint()
          ..color = AuraColors.amber.withValues(alpha: 0.35 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  @override
  bool shouldRepaint(_TablePainter old) => true;
}

class _ResultsStrip extends StatelessWidget {
  const _ResultsStrip({required this.results});
  final List<int> results;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 26,
    child: results.isEmpty
        ? Center(child: Text(context.l10n.lastResults, style: AuraText.caption))
        : ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: results.length,
            separatorBuilder: (_, _) => const SizedBox(width: 5),
            itemBuilder: (_, i) => AnimatedScale(
              scale: 1,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: pocketColor(results[i]),
                  border: i == 0 ? Border.all(color: AuraColors.amber, width: 2) : null,
                ),
                child: Text(
                  '${results[i]}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
  );
}

class _ChipBar extends StatelessWidget {
  const _ChipBar({required this.selected, required this.balance, required this.onPick});
  final int selected;
  final int balance;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      for (final v in _chipValues)
        GestureDetector(
          onTap: () => onPick(v),
          child: Opacity(
            opacity: v <= balance ? 1 : 0.35,
            child: CasinoChip(value: v, size: 42, selected: v == selected),
          ),
        ),
    ],
  );
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Container(
        width: 58,
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
            style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontWeight: FontWeight.w700),
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
