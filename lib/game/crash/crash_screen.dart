import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../l10n/l10n.dart';
import '../../widgets/aura.dart';
import '../common/board_frame.dart';
import 'crash_engine.dart';

/// Crash ("Aviator" style), practice chips only: the flight view, recent
/// results, two bet panels with auto cash-out, and the live bets of the
/// other players. Rounds run continuously; leave with the back button.
class CrashScreen extends StatefulWidget {
  const CrashScreen({super.key, @visibleForTesting this.game, this.live = true});

  /// A prepared game (tests); null = a new one.
  final CrashGame? game;

  /// Run the round clock (false = render a fixed frame, tests).
  final bool live;

  @override
  State<CrashScreen> createState() => _CrashScreenState();
}

class _CrashScreenState extends State<CrashScreen> with SingleTickerProviderStateMixin {
  late final CrashGame _game = widget.game ?? CrashGame();
  late final Ticker _ticker = createTicker((_) => _game.tick(DateTime.now()));

  @override
  void initState() {
    super.initState();
    _game.addListener(_onChange);
    if (widget.live) _ticker.start();
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

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final g = _game;
    final broke = g.balance < 10 && g.bets.every((b) => !b.active && !b.queued);
    return AuraScaffold(
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GameHeader(
            title: '✈️ Crash',
            subtitle: l.practiceChips,
            pot: '0',
            leading: GlassIconButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).maybePop()),
            trailing: _BalancePill(balance: g.balance),
          ),
          const SizedBox(height: 10),
          _History(history: g.history),
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: 16 / 11,
            child: GameBoardFrame(child: CustomPaint(painter: _FlightPainter(g, l))),
          ),
          const SizedBox(height: 12),
          if (broke) ...[_TopUp(onTap: _game.refill), const SizedBox(height: 10)],
          for (var i = 0; i < 2; i++) ...[_BetPanel(game: g, index: i), const SizedBox(height: 10)],
          _LiveBets(game: g),
          const SizedBox(height: 8),
          Center(child: Text(l.crashNote, style: AuraText.caption)),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
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
        Text(
          _fmt(balance),
          style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
String _x(double m) => '${m.toStringAsFixed(2)}x';

/// Recent crash points: blue < 2×, violet < 10×, pink ≥ 10×.
Color _crashColor(double m) => m < 2
    ? const Color(0xFF38BDF8)
    : m < 10
    ? const Color(0xFFA855F7)
    : const Color(0xFFEC4899);

class _History extends StatelessWidget {
  const _History({required this.history});
  final List<double> history;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 28,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: history.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (_, i) {
        final c = _crashColor(history[i]);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: c.withValues(alpha: 0.16),
            border: Border.all(color: c.withValues(alpha: 0.5)),
          ),
          child: Text(
            _x(history[i]),
            style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        );
      },
    ),
  );
}

/// The flight: sky + rays, the rising curve with a glowing fill, the plane
/// at its tip, the big multiplier; "FLEW AWAY!" after a crash; the next-round
/// countdown between rounds.
class _FlightPainter extends CustomPainter {
  _FlightPainter(this.g, this.l);
  final CrashGame g;
  final AppLocalizations l;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.6, 0.8),
          radius: 1.4,
          colors: [Color(0xFF2A1856), Color(0xFF110C24), Color(0xFF070510)],
        ).createShader(rect),
    );
    // Slowly turning light rays from the bottom-left.
    final origin = Offset(0, size.height);
    final turn = DateTime.now().millisecondsSinceEpoch / 9000;
    final rays = Paint()..color = Colors.white.withValues(alpha: 0.025);
    for (var i = 0; i < 12; i++) {
      final a = -math.pi / 2 + (i / 12) * math.pi / 2 + math.sin(turn) * 0.05;
      final r = size.width * 1.6;
      canvas.drawPath(
        Path()
          ..moveTo(origin.dx, origin.dy)
          ..lineTo(origin.dx + r * math.cos(a - 0.03), origin.dy + r * math.sin(a - 0.03))
          ..lineTo(origin.dx + r * math.cos(a + 0.03), origin.dy + r * math.sin(a + 0.03))
          ..close(),
        rays,
      );
    }
    // Grid.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (var i = 1; i < 5; i++) {
      canvas.drawLine(Offset(0, size.height * i / 5), Offset(size.width, size.height * i / 5), grid);
    }

    final pad = EdgeInsets.fromLTRB(14, 24, 24, 18);
    final w = size.width - pad.horizontal, h = size.height - pad.vertical;
    final base = Offset(pad.left, size.height - pad.bottom);

    if (g.phase == CrashPhase.betting) {
      _plane(canvas, base + const Offset(18, -10), -0.15, 1);
      _centerText(canvas, size, l.nextRoundIn(g.bettingLeft.toStringAsFixed(1)), 15, Colors.white70, dy: -14);
      // Countdown bar.
      final barW = size.width * 0.5;
      final bar = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2 + 14), width: barW, height: 5);
      canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(3)), Paint()..color = Colors.white12);
      final frac = (g.bettingLeft / CrashRules.bettingSeconds).clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(bar.left, bar.top, barW * frac, 5), const Radius.circular(3)),
        Paint()..color = const Color(0xFFE11D48),
      );
      return;
    }

    // Flight curve (time on x, log multiplier on y).
    final t = g.phase == CrashPhase.flying ? g.elapsed : CrashRules.secondsFor(g.crashPoint);
    final window = math.max(8.0, t * 1.15);
    // Linear height (as in Aviator): the curve bends upward as it speeds up.
    final top = math.max(2.0, g.multiplier * 1.2) - 1;
    Offset pt(double s) {
      final m = CrashRules.multiplierAt(s);
      return Offset(base.dx + s / window * w, base.dy - (m - 1) / top * h);
    }

    final path = Path()..moveTo(base.dx, base.dy);
    const steps = 60;
    for (var i = 1; i <= steps; i++) {
      final p = pt(t * i / steps);
      path.lineTo(p.dx, p.dy);
    }
    final tip = pt(t);
    final fill = Path.from(path)
      ..lineTo(tip.dx, base.dy)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFFE11D48).withValues(alpha: 0.45), const Color(0xFFE11D48).withValues(alpha: 0.02)],
        ).createShader(rect),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFF43F5E),
    );

    final before = pt(math.max(0, t - 0.3));
    final angle = math.atan2(tip.dy - before.dy, tip.dx - before.dx);
    if (g.phase == CrashPhase.flying) {
      _plane(canvas, tip, angle, 1);
      final m = g.multiplier;
      _centerText(canvas, size, _x(m), 44, m >= 2 ? const Color(0xFFFBBF24) : Colors.white, dy: -size.height * 0.12);
    } else {
      // Flew away: the plane zooms off up-right and fades.
      final u = (g.elapsed / 0.9).clamp(0.0, 1.0);
      _plane(canvas, tip + Offset(size.width * 0.7 * u, -size.height * 0.8 * u), -0.6, 1 - u);
      _centerText(canvas, size, l.flewAway, 20, const Color(0xFFF43F5E), dy: -size.height * 0.2);
      _centerText(canvas, size, _x(g.crashPoint), 44, const Color(0xFFF43F5E), dy: -size.height * 0.04);
    }
  }

  /// A small red propeller plane pointing along [angle].
  void _plane(Canvas canvas, Offset at, double angle, double opacity) {
    if (opacity <= 0) return;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    final red = Paint()..color = const Color(0xFFE11D48).withValues(alpha: opacity);
    final dark = Paint()..color = const Color(0xFF9F1239).withValues(alpha: opacity);
    // Fuselage.
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-26, -5, 34, 10), const Radius.circular(5)), red);
    // Wings + tail.
    canvas.drawPath(
      Path()
        ..moveTo(-6, -2)
        ..lineTo(-14, -18)
        ..lineTo(-8, -18)
        ..lineTo(4, -2)
        ..close(),
      dark,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-6, 2)
        ..lineTo(-12, 13)
        ..lineTo(-7, 13)
        ..lineTo(3, 2)
        ..close(),
      dark,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-24, -4)
        ..lineTo(-30, -13)
        ..lineTo(-25, -13)
        ..lineTo(-18, -4)
        ..close(),
      red,
    );
    // Cockpit + spinning propeller blur.
    canvas.drawCircle(const Offset(0, -2), 3, Paint()..color = Colors.white.withValues(alpha: 0.8 * opacity));
    canvas.drawOval(
      const Rect.fromLTWH(8, -10, 3, 20),
      Paint()..color = Colors.white.withValues(alpha: 0.35 * opacity),
    );
    canvas.restore();
  }

  void _centerText(Canvas canvas, Size size, String text, double fontSize, Color color, {double dy = 0}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AuraText.displayFamily,
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          shadows: [Shadow(color: color.withValues(alpha: 0.6), blurRadius: 18)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height / 2 - tp.height / 2 + dy));
  }

  @override
  bool shouldRepaint(_FlightPainter old) => true;
}

/// One bet slot: amount (− / + and quick chips), auto cash-out, and the
/// big Bet / Cancel / Cash out button.
class _BetPanel extends StatelessWidget {
  const _BetPanel({required this.game, required this.index});
  final CrashGame game;
  final int index;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final b = game.bets[index];
    final locked = b.active || b.queued;
    final flying = game.phase == CrashPhase.flying;

    final (String label, List<Color> colors, VoidCallback? onTap) = switch (true) {
      _ when flying && b.active && b.cashedAt == null => (
        l.cashOutAmount((b.amount * game.multiplier).floor()),
        const [Color(0xFFFB923C), Color(0xFFF59E0B)],
        () => game.cashOut(index),
      ),
      _ when b.active && b.cashedAt != null => (l.wonAmount(b.win), const [Color(0xFF34D399), Color(0xFF059669)], null),
      _ when game.phase == CrashPhase.betting && b.active => (
        l.cancel,
        const [Color(0xFFF43F5E), Color(0xFFBE123C)],
        () => game.toggleBet(index),
      ),
      _ when game.phase == CrashPhase.betting => (
        l.betAmount(b.amount),
        const [Color(0xFF22C55E), Color(0xFF15803D)],
        () => game.toggleBet(index),
      ),
      _ when b.queued => (l.cancelNextRound, const [Color(0xFFF43F5E), Color(0xFFBE123C)], () => game.toggleBet(index)),
      _ => (l.nextRoundBet, const [Color(0xFF22C55E), Color(0xFF15803D)], () => game.toggleBet(index)),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AuraGlass.decoration(radius: 18, shadow: false),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _Step(icon: Icons.remove, onTap: locked ? null : () => game.setAmount(index, b.amount - 10)),
                    Expanded(
                      child: Text(
                        _fmt(b.amount),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AuraText.displayFamily,
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _Step(icon: Icons.add, onTap: locked ? null : () => game.setAmount(index, b.amount + 10)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final q in const [10, 50, 100, 500]) ...[
                      if (q != 10) const SizedBox(width: 4),
                      Expanded(
                        child: GestureDetector(
                          onTap: locked ? null : () => game.setAmount(index, q),
                          child: Container(
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white.withValues(alpha: b.amount == q ? 0.18 : 0.07),
                            ),
                            child: Text('$q', style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      height: 22,
                      width: 36,
                      child: FittedBox(
                        child: Switch(
                          value: b.autoCashOut != null,
                          activeTrackColor: AuraColors.brandPurple,
                          onChanged: (on) => game.setAuto(index, on ? 2.0 : null),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(l.autoCashOut, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                    ),
                    if (b.autoCashOut != null) ...[
                      _Step(icon: Icons.remove, small: true, onTap: () => game.setAuto(index, b.autoCashOut! - 0.1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          _x(b.autoCashOut!),
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                      _Step(icon: Icons.add, small: true, onTap: () => game.setAuto(index, b.autoCashOut! + 0.1)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            height: 92,
            child: Opacity(
              opacity: onTap == null ? 0.85 : 1,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTap,
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
                      boxShadow: [
                        BoxShadow(color: colors.first.withValues(alpha: 0.35), blurRadius: 14, spreadRadius: -4),
                      ],
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: AuraText.displayFamily,
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap, this.small = false});
  final IconData icon;
  final VoidCallback? onTap;
  final bool small;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: small ? 22 : 30,
      height: small ? 22 : 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: onTap == null ? 0.04 : 0.1),
      ),
      child: Icon(
        icon,
        size: small ? 13 : 16,
        color: Colors.white.withValues(alpha: onTap == null ? 0.3 : 0.9),
      ),
    ),
  );
}

/// The other players this round and how they did.
class _LiveBets extends StatelessWidget {
  const _LiveBets({required this.game});
  final CrashGame game;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final reached = game.phase == CrashPhase.betting ? 0.0 : game.multiplier;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AuraGlass.decoration(radius: 18, shadow: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(l.liveBets, style: AuraText.cardTitle.copyWith(fontSize: 14))),
              Text(l.playersCount(game.bots.length), style: AuraText.caption),
            ],
          ),
          const SizedBox(height: 8),
          for (final b in game.bots) ...[
            Row(
              children: [
                Expanded(
                  child: Text(b.name, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    _fmt(b.amount),
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    reached >= b.target ? '${_x(b.target)}  +${_fmt((b.amount * b.target).floor())}' : '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: reached >= b.target ? AuraColors.green : Colors.white38,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
          ],
        ],
      ),
    );
  }
}

class _TopUp extends StatelessWidget {
  const _TopUp({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: AuraGlass.decoration(radius: 18, shadow: false),
    child: Row(
      children: [
        Expanded(child: Text(context.l10n.outOfChips, style: AuraText.cardSub)),
        TextButton(onPressed: onTap, child: Text(context.l10n.topUp)),
      ],
    ),
  );
}
