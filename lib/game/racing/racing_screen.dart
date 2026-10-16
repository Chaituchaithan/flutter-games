import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../l10n/l10n.dart';
import '../../widgets/aura.dart';
import '../common/board_frame.dart';
import '../common/playing_cards.dart' show CasinoChip;
import 'racing_engine.dart';

String _fmt(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
String _odds(double o) => o.toStringAsFixed(o < 10 ? 2 : 1);

const _chipValues = [10, 25, 100, 500, 1000];

/// Virtual car racing, practice chips: pick Win / Top 3 bets on six cars,
/// watch the race (camera follows the leader), collect at the podium.
class RacingScreen extends StatefulWidget {
  const RacingScreen({super.key, @visibleForTesting this.game});

  /// A prepared game (tests); null = a new one.
  final RacingGame? game;

  @override
  State<RacingScreen> createState() => _RacingScreenState();
}

class _RacingScreenState extends State<RacingScreen>
    with SingleTickerProviderStateMixin {
  late final RacingGame _game = widget.game ?? RacingGame();
  late final Ticker _ticker = createTicker(_frame);

  /// Seconds into the race.
  double _t = 0;
  int _chip = 25;

  // Commentary.
  String? _call;
  int? _leader;
  bool _calledStretch = false;

  @override
  void initState() {
    super.initState();
    _game.addListener(_onChange);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _game.removeListener(_onChange);
    _game.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _start() {
    _game.start();
    _t = 0;
    _leader = null;
    _calledStretch = false;
    _call = context.l10n.andTheyreOff;
    _ticker.start();
  }

  void _frame(Duration elapsed) {
    final l = context.l10n;
    _t = elapsed.inMicroseconds / 1e6;
    final g = _game;
    final lead = g.standings(_t).first;
    final leadX = g.runs[lead].at(_t);
    if (_t > 1.6 && lead != _leader && leadX < 1) {
      _call = l.takesTheLead(raceField[lead].name);
    }
    _leader = lead;
    if (!_calledStretch && leadX > 0.8) {
      _calledStretch = true;
      _call = l.finalStretch;
    }
    if (_t >= g.runs[g.order.first].finishAt) {
      _call = g.winningMargin < 0.12
          ? '${l.photoFinish} ${l.winsTheRace(raceField[g.order.first].name)}'
          : l.winsTheRace(raceField[g.order.first].name);
    }
    final last = g.runs.map((r) => r.finishAt).reduce(math.max);
    if (_t > last + 0.9) {
      _ticker.stop();
      g.finish();
    }
    setState(() {});
  }

  void _next() {
    _t = 0;
    _call = null;
    _game.nextRace();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final g = _game;
    return AuraScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      scroll: g.phase == RacePhase.betting,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GameHeader(
            title: '🏎️ Racing',
            subtitle: '${l.raceNumber(g.raceNo)} · ${l.practiceChips}',
            pot: '0',
            leading: GlassIconButton(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            trailing: _BalancePill(balance: g.balance),
          ),
          const SizedBox(height: 8),
          _WinnersStrip(history: g.history),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 16 / 10,
            child: GameBoardFrame(
              child: CustomPaint(painter: _TrackPainter(g, _t)),
            ),
          ),
          const SizedBox(height: 10),
          if (g.phase == RacePhase.betting) ..._betting(l, g),
          if (g.phase == RacePhase.racing) ...[
            _Commentary(text: _call ?? ''),
            const SizedBox(height: 8),
            _LiveStandings(game: g, t: _t),
          ],
          if (g.phase == RacePhase.finished) ...[
            _Podium(game: g),
            const SizedBox(height: 12),
            GradientButton(label: l.nextRace, onPressed: _next),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  List<Widget> _betting(AppLocalizations l, RacingGame g) {
    final ranked = [for (var i = 0; i < raceField.length; i++) i]
      ..sort((a, b) => g.strength[b].compareTo(g.strength[a]));
    return [
      Row(
        children: [
          Expanded(child: Text(l.raceBetsHint, style: AuraText.caption)),
          if (g.bets.isNotEmpty)
            TextButton(
              onPressed: g.clearBets,
              child: Text(
                l.clearBets,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
        ],
      ),
      const SizedBox(height: 4),
      for (var i = 0; i < raceField.length; i++) ...[
        _BetRow(
          car: i,
          game: g,
          stars: 5 - (ranked.indexOf(i) * 4 ~/ (raceField.length - 1)),
          onBet: (kind) {
            if (!g.placeBet(i, kind, _chip)) {
              showAuraToast(
                context,
                l.notEnoughChips,
                kind: AuraToastKind.error,
              );
            }
          },
        ),
        const SizedBox(height: 6),
      ],
      const SizedBox(height: 6),
      if (g.balance < _chipValues.first && g.bets.isEmpty)
        Center(
          child: TextButton(onPressed: g.refill, child: Text(l.topUp)),
        )
      else
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final v in _chipValues)
              GestureDetector(
                onTap: () => setState(() => _chip = v),
                child: Opacity(
                  opacity: v <= g.balance ? 1 : 0.35,
                  child: CasinoChip(value: v, size: 40, selected: v == _chip),
                ),
              ),
          ],
        ),
      const SizedBox(height: 10),
      Text(
        l.totalBetAmount(_fmt(g.totalBet)),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: AuraText.displayFamily,
          color: AuraColors.amber,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 8),
      GradientButton(
        label: g.bets.isEmpty ? l.watchRace : l.startRace,
        onPressed: _start,
      ),
      const SizedBox(height: 6),
      Center(child: Text(l.practiceNote, style: AuraText.caption)),
    ];
  }
}

/// The track, side view, scrolling with the leader: grandstand and crowd,
/// six lanes, start and checkered finish lines, distance boards, the cars.
class _TrackPainter extends CustomPainter {
  _TrackPainter(this.g, this.t);
  final RacingGame g;
  final double t;

  /// Visible stretch of track (fraction of the race distance).
  static const window = 0.3;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final racing = g.phase != RacePhase.betting;
    final xs = [
      for (var i = 0; i < raceField.length; i++) racing ? g.runs[i].at(t) : 0.0,
    ];
    final lead = xs.reduce(math.max);
    // Camera: the grid before the start, the leader during the race, held
    // on the finish line at the end.
    final cam = racing
        ? (lead - window * 0.68).clamp(-0.08, 1 - window * 0.55)
        : -0.12;
    double sx(double x) => (x - cam) / window * w;

    final standTop = 0.0, standH = h * 0.17;
    final trackTop = standH + h * 0.03, trackH = h * 0.68;
    final grassTop = trackTop + trackH;

    // Grandstand with the crowd (parallax).
    canvas.drawRect(
      Rect.fromLTWH(0, standTop, w, standH),
      Paint()..color = const Color(0xFF1E1B2E),
    );
    final crowd = math.Random(5);
    final shift = cam * w / window * 0.5;
    for (var i = 0; i < 160; i++) {
      final x = (crowd.nextDouble() * w * 3 - shift) % (w * 1.0);
      final y = standTop + 4 + crowd.nextDouble() * (standH - 8);
      final c = [
        const Color(0xFFF472B6),
        const Color(0xFF60A5FA),
        const Color(0xFFFDE68A),
        Colors.white70,
        const Color(0xFF34D399),
      ][i % 5];
      canvas.drawCircle(
        Offset(x, y),
        1.6,
        Paint()..color = c.withValues(alpha: 0.7),
      );
    }
    // Barrier with sponsor stripes.
    canvas.drawRect(
      Rect.fromLTWH(0, standH, w, h * 0.03),
      Paint()..color = const Color(0xFFE5E7EB),
    );
    for (var i = -1; i < 30; i++) {
      final x = (i * 0.05 - cam % 0.05) / window * w;
      canvas.drawRect(
        Rect.fromLTWH(x, standH, 0.025 / window * w, h * 0.03),
        Paint()..color = const Color(0xFFDC2626),
      );
    }

    // Asphalt + lanes.
    final track = Rect.fromLTWH(0, trackTop, w, trackH);
    canvas.drawRect(
      track,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A3846), Color(0xFF2A2833), Color(0xFF3A3846)],
        ).createShader(track),
    );
    final laneH = trackH / raceField.length;
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.5;
    for (var k = 1; k < raceField.length; k++) {
      final y = trackTop + k * laneH;
      for (var d = (cam / 0.02).floor() * 0.02; d < cam + window; d += 0.02) {
        canvas.drawLine(Offset(sx(d), y), Offset(sx(d + 0.01), y), dash);
      }
    }
    // Distance boards every 10% ("300 m").
    for (var k = 1; k < 10; k++) {
      final x = sx(k / 10);
      if (x < -40 || x > w + 40) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: '${(10 - k) * 100} m',
          style: const TextStyle(
            color: Color(0xFF1F1A2E),
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final board = Rect.fromCenter(
        center: Offset(x, standH - 8),
        width: tp.width + 8,
        height: 13,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(board, const Radius.circular(3)),
        Paint()..color = const Color(0xFFFDE68A),
      );
      tp.paint(canvas, board.center - Offset(tp.width / 2, tp.height / 2));
    }
    // Start line and checkered finish.
    final start = sx(0);
    canvas.drawRect(
      Rect.fromLTWH(start - 2, trackTop, 4, trackH),
      Paint()..color = Colors.white70,
    );
    final fin = sx(1);
    if (fin > -20 && fin < w + 20) {
      const cell = 6.0;
      for (var row = 0; row * cell < trackH; row++) {
        for (var col = 0; col < 3; col++) {
          canvas.drawRect(
            Rect.fromLTWH(
              fin + col * cell - cell * 1.5,
              trackTop + row * cell,
              cell,
              cell,
            ),
            Paint()
              ..color = (row + col).isEven
                  ? Colors.white
                  : const Color(0xFF111827),
          );
        }
      }
    }
    // Grass.
    final grass = Rect.fromLTWH(0, grassTop, w, h - grassTop);
    canvas.drawRect(grass, Paint()..color = const Color(0xFF166534));
    for (var i = -1; i < 20; i++) {
      final x = (i * 0.06 - cam % 0.06) / window * w;
      canvas.drawRect(
        Rect.fromLTWH(x, grassTop, 0.03 / window * w, h - grassTop),
        Paint()..color = const Color(0xFF15803D),
      );
    }

    // Cars (front of the car at its position).
    final carL = 0.042 / window * w;
    for (var i = 0; i < raceField.length; i++) {
      final y = trackTop + (i + 0.5) * laneH;
      final front = sx(xs[i]);
      final speed = racing && xs[i] < 1 ? 1.0 : 0.0;
      paintCar(
        canvas,
        Offset(front - carL / 2, y),
        carL,
        laneH * 0.62,
        raceField[i],
        speed,
        lead: racing && xs[i] == lead && lead > 0.02,
      );
    }

    // Progress strip along the top.
    final bar = Rect.fromLTWH(10, 6, w - 20, 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar, const Radius.circular(2)),
      Paint()..color = Colors.white24,
    );
    for (var i = 0; i < raceField.length; i++) {
      canvas.drawCircle(
        Offset(bar.left + bar.width * xs[i].clamp(0.0, 1.0), bar.center.dy),
        4,
        Paint()..color = raceField[i].color,
      );
    }
  }

  /// A top-down race car pointing right: body, cockpit, wheels, wing, number.
  static void paintCar(
    Canvas canvas,
    Offset c,
    double len,
    double wid,
    RaceCar car,
    double speed, {
    bool lead = false,
  }) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    // Speed streaks behind.
    if (speed > 0) {
      final streak = Paint()
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      for (var k = 0; k < 3; k++) {
        final y = (k - 1) * wid * 0.32;
        streak.color = Colors.white.withValues(alpha: 0.25 - k * 0.05);
        canvas.drawLine(
          Offset(-len * 0.6, y),
          Offset(-len * (1.1 + 0.25 * k), y),
          streak,
        );
      }
    }
    // Shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(1.5, 2.5),
          width: len,
          height: wid * 0.86,
        ),
        Radius.circular(wid * 0.3),
      ),
      Paint()..color = Colors.black45,
    );
    // Wheels.
    final tyre = Paint()..color = const Color(0xFF0B0B0F);
    for (final dx in [-len * 0.28, len * 0.26]) {
      for (final dy in [-wid * 0.5, wid * 0.5]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(dx, dy * 0.92),
              width: len * 0.2,
              height: wid * 0.24,
            ),
            const Radius.circular(2),
          ),
          tyre,
        );
      }
    }
    // Body.
    final body = Path()
      ..moveTo(len * 0.5, 0)
      ..cubicTo(
        len * 0.42,
        -wid * 0.18,
        len * 0.2,
        -wid * 0.38,
        -len * 0.1,
        -wid * 0.4,
      )
      ..lineTo(-len * 0.46, -wid * 0.36)
      ..lineTo(-len * 0.46, wid * 0.36)
      ..lineTo(-len * 0.1, wid * 0.4)
      ..cubicTo(len * 0.2, wid * 0.38, len * 0.42, wid * 0.18, len * 0.5, 0)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(car.color, Colors.white, 0.35)!,
                car.color,
                Color.lerp(car.color, Colors.black, 0.35)!,
              ],
            ).createShader(
              Rect.fromCenter(center: Offset.zero, width: len, height: wid),
            ),
    );
    // Rear wing and cockpit.
    canvas.drawRect(
      Rect.fromLTWH(-len * 0.52, -wid * 0.44, len * 0.08, wid * 0.88),
      Paint()..color = const Color(0xFF111827),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(len * 0.02, 0),
        width: len * 0.24,
        height: wid * 0.34,
      ),
      Paint()..color = const Color(0xFF0F172A),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(len * 0.05, -wid * 0.05),
        width: len * 0.1,
        height: wid * 0.12,
      ),
      Paint()..color = Colors.white38,
    );
    // Number roundel.
    final rc = Offset(-len * 0.24, 0);
    canvas.drawCircle(rc, wid * 0.2, Paint()..color = Colors.white);
    final tp = TextPainter(
      text: TextSpan(
        text: '${car.number}',
        style: TextStyle(
          color: const Color(0xFF111827),
          fontSize: wid * 0.28,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, rc - Offset(tp.width / 2, tp.height / 2));
    if (lead) {
      // Leader marker above the car.
      canvas.drawPath(
        Path()
          ..moveTo(0, -wid * 0.62)
          ..lineTo(-4, -wid * 0.62 - 6)
          ..lineTo(4, -wid * 0.62 - 6)
          ..close(),
        Paint()..color = const Color(0xFFFBBF24),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TrackPainter old) => true;
}

/// A small static car for lists (the same drawing as on the track).
class _CarIcon extends StatelessWidget {
  const _CarIcon({required this.car, this.size = 34});
  final int car;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size * 0.55),
    painter: _CarIconPainter(raceField[car]),
  );
}

class _CarIconPainter extends CustomPainter {
  _CarIconPainter(this.car);
  final RaceCar car;

  @override
  void paint(Canvas canvas, Size size) {
    _TrackPainter.paintCar(
      canvas,
      size.center(Offset.zero),
      size.width * 0.95,
      size.height * 0.95,
      car,
      0,
    );
  }

  @override
  bool shouldRepaint(_CarIconPainter old) => old.car != car;
}

class _BetRow extends StatelessWidget {
  const _BetRow({
    required this.car,
    required this.game,
    required this.stars,
    required this.onBet,
  });
  final int car;
  final RacingGame game;
  final int stars;
  final ValueChanged<RaceBetKind> onBet;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = raceField[car];
    Widget oddsButton(RaceBetKind kind, String label, double odds) {
      final placed = game.bets[(car, kind)];
      return GestureDetector(
        onTap: () => onBet(kind),
        child: SizedBox(
          width: 64,
          height: 46,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: placed != null
                        ? c.color.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.06),
                    border: Border.all(
                      color: placed != null
                          ? c.color
                          : Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _odds(odds),
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: AuraText.displayFamily,
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Your stake on this price.
              if (placed != null)
                Positioned(
                  top: -7,
                  right: -5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AuraColors.amber,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 4),
                      ],
                    ),
                    child: Text(
                      _fmt(placed),
                      style: const TextStyle(
                        color: Color(0xFF1F1A2E),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: AuraGlass.decoration(radius: 16, shadow: false),
      child: Row(
        children: [
          _CarIcon(car: car),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${c.number} ${c.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AuraText.cardTitle.copyWith(fontSize: 14),
                ),
                Row(
                  children: [
                    for (var s = 0; s < 5; s++)
                      Icon(
                        Icons.star_rounded,
                        size: 11,
                        color: s < stars ? AuraColors.amber : Colors.white24,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          oddsButton(RaceBetKind.win, l.winBet, game.winOdds[car]),
          const SizedBox(width: 6),
          oddsButton(RaceBetKind.top3, l.top3Bet, game.top3Odds[car]),
        ],
      ),
    );
  }
}

class _Commentary extends StatelessWidget {
  const _Commentary({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    alignment: Alignment.center,
    decoration: AuraGlass.decoration(radius: 14, shadow: false),
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (c, a) => SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.6),
          end: Offset.zero,
        ).animate(a),
        child: FadeTransition(opacity: a, child: c),
      ),
      child: Row(
        key: ValueKey(text),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.campaign_rounded, size: 18, color: AuraColors.amber),
          const SizedBox(width: 8),
          Text(text, style: AuraText.cardTitle.copyWith(fontSize: 14)),
        ],
      ),
    ),
  );
}

/// Positions during the race; rows slide when cars swap places.
class _LiveStandings extends StatelessWidget {
  const _LiveStandings({required this.game, required this.t});
  final RacingGame game;
  final double t;

  static const rowH = 36.0;

  @override
  Widget build(BuildContext context) {
    final order = game.standings(t);
    return SizedBox(
      height: rowH * raceField.length,
      child: Stack(
        children: [
          for (var i = 0; i < raceField.length; i++)
            AnimatedPositioned(
              key: ValueKey(i),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              top: order.indexOf(i) * rowH,
              height: rowH - 4,
              child: _StandingRow(
                car: i,
                pos: order.indexOf(i) + 1,
                x: game.runs[i].at(t),
                bet: game.bets.keys.any((k) => k.$1 == i),
              ),
            ),
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.car,
    required this.pos,
    required this.x,
    required this.bet,
  });
  final int car;
  final int pos;
  final double x;
  final bool bet;

  @override
  Widget build(BuildContext context) {
    final c = raceField[car];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: pos == 1 ? 0.1 : 0.04),
        border: Border.all(
          color: bet ? c.color.withValues(alpha: 0.7) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$pos',
              style: AuraText.cardTitle.copyWith(
                fontSize: 14,
                color: pos == 1 ? AuraColors.amber : Colors.white,
              ),
            ),
          ),
          _CarIcon(car: car, size: 30),
          const SizedBox(width: 8),
          SizedBox(
            width: 74,
            child: Text(
              c.name,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: x.clamp(0.0, 1.0),
                minHeight: 5,
                color: c.color,
                backgroundColor: Colors.white12,
              ),
            ),
          ),
          if (bet) ...[
            const SizedBox(width: 6),
            const Icon(Icons.toll_rounded, size: 14, color: AuraColors.amber),
          ],
        ],
      ),
    );
  }
}

/// Results: the podium (2 · 1 · 3), then your bets' payout.
class _Podium extends StatelessWidget {
  const _Podium({required this.game});
  final RacingGame game;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final o = game.order;
    Widget step(int place, double height) {
      final car = o[place];
      final colors = [
        const Color(0xFFFBBF24),
        const Color(0xFFCBD5E1),
        const Color(0xFFD97706),
      ];
      return Expanded(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 500 + place * 180),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Transform.translate(
            offset: Offset(0, (1 - v) * 40),
            child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _CarIcon(car: car, size: 44),
              const SizedBox(height: 4),
              Text(
                raceField[car].name,
                style: AuraText.cardTitle.copyWith(fontSize: 13),
              ),
              const SizedBox(height: 4),
              Container(
                height: height,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors[place],
                      colors[place].withValues(alpha: 0.4),
                    ],
                  ),
                ),
                child: Text(
                  '${place + 1}',
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final won = game.lastReturn;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AuraGlass.decoration(radius: 20, shadow: false),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              step(1, 56),
              const SizedBox(width: 8),
              step(0, 78),
              const SizedBox(width: 8),
              step(2, 42),
            ],
          ),
          const SizedBox(height: 14),
          if (game.bets.isNotEmpty)
            Text(
              won > 0 ? l.racePayout(_fmt(won)) : l.noWinThisTime,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: won > 0 ? AuraColors.green : Colors.white70,
                fontSize: won > 0 ? 22 : 15,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _WinnersStrip extends StatelessWidget {
  const _WinnersStrip({required this.history});
  final List<int> history;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 24,
    child: history.isEmpty
        ? Center(child: Text(context.l10n.lastResults, style: AuraText.caption))
        : EdgeBleed(
            gutter: 12,
            builder: (pad) => ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: pad,
              itemCount: history.length,
              separatorBuilder: (_, _) => const SizedBox(width: 5),
              itemBuilder: (_, i) {
                final c = raceField[history[i]];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: c.color.withValues(alpha: 0.2),
                    border: Border.all(color: c.color.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    '#${c.number} ${c.name}',
                    style: TextStyle(
                      color: c.color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              },
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
