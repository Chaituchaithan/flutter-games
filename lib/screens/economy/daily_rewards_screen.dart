import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/daily_bonus.dart';
import '../../data/repositories/daily_bonus_repository.dart';
import '../../data/repositories/store_repository.dart';
import '../../services/app_exception.dart';
import '../../state/async_view.dart';
import '../system/loading_skeleton_screen.dart';
import '../../widgets/aura.dart';

/// Daily rewards / streak screen, driven by the daily-bonus service:
/// `GET /sensitive/daily-bonus/status` (streak, today's/next reward, when the
/// next claim opens) and `POST /sensitive/daily-bonus/claim`.
/// The status only describes the next reward, so other days show their state
/// (claimed / locked) without an amount. See docs/SERVICES_AND_REALTIME.md.
///
/// Look: a glowing reward hero (rotating light rays behind a floating chest
/// while the reward is ready), a flickering streak flame, a 7-day path with a
/// pulsing "today" tile, and a coin burst on claim.
class DailyRewardsScreen extends ConsumerStatefulWidget {
  const DailyRewardsScreen({super.key});

  @override
  ConsumerState<DailyRewardsScreen> createState() => _DailyRewardsScreenState();
}

class _DailyRewardsScreenState extends ConsumerState<DailyRewardsScreen> with TickerProviderStateMixin {
  bool _claiming = false;

  /// Re-renders the "next reward in …" countdown; refreshes the status once
  /// the next claim opens.
  Timer? _ticker;

  /// Shared ambient loop: rays, chest float, flame flicker, today pulse.
  late final AnimationController _ambient = AnimationController(vsync: this, duration: const Duration(seconds: 6))
    ..repeat();

  /// Coin burst after a successful claim.
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool _burstGold = true;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final s = ref.read(dailyBonusStatusProvider).asData?.value;
      final at = s?.nextClaimAt;
      if (s != null && !s.canClaim && at != null && DateTime.now().isAfter(at)) {
        ref.invalidate(dailyBonusStatusProvider);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ambient.dispose();
    _burst.dispose();
    super.dispose();
  }

  Future<void> _claim(DailyBonusStatus s) async {
    if (_claiming || !s.canClaim) return;
    setState(() => _claiming = true);
    try {
      final paid = await ref.read(dailyBonusSourceProvider).claim();
      if (!mounted) return;
      // What the server actually paid (falls back to the shown reward).
      final nothing = paid.tokens == 0 && paid.gold == 0 && paid.powerUpQuantity == 0;
      final label = nothing ? s.nextReward.label : paid.label;
      final streak = paid.newStreak > 0 ? ' · ${paid.newStreak}-day streak' : '';
      _burstGold = (nothing ? s.nextReward.gold : paid.gold) > 0;
      _burst.forward(from: 0);
      showAuraToast(context, 'Claimed $label$streak', kind: _burstGold ? AuraToastKind.gold : AuraToastKind.success);
    } on AppException catch (e) {
      if (!mounted) return;
      showAuraToast(
        context,
        e.statusCode == 409 ? 'Already claimed today — come back tomorrow.' : e.message,
        kind: e.statusCode == 409 ? AuraToastKind.info : AuraToastKind.error,
      );
    } on Object catch (_) {
      if (mounted) showAuraToast(context, "Couldn't claim your reward. Try again.", kind: AuraToastKind.error);
    } finally {
      // Fresh streak/next reward and balance either way.
      ref.invalidate(dailyBonusStatusProvider);
      ref.invalidate(walletProvider);
      if (mounted) setState(() => _claiming = false);
    }
  }

  /// "23h 41m" / "12m" until [at].
  static String _until(DateTime at) {
    final d = at.difference(DateTime.now());
    if (d.inMinutes < 1) return 'less than a minute';
    final h = d.inHours, m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(dailyBonusStatusProvider);
    return BusyGuard(
      busy: _claiming,
      child: Stack(
        children: [
          AuraScaffold(
            appBar: const AuraAppBar(title: 'Daily Rewards'),
            scroll: true,
            body: AsyncView<DailyBonusStatus>(
              value: status,
              onRetry: () => ref.invalidate(dailyBonusStatusProvider),
              loading: const _DailySkeleton(),
              data: _content,
            ),
          ),
          // Coin burst over everything (ignores touches).
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _burst,
                builder: (_, _) => _burst.isAnimating
                    ? CustomPaint(painter: _CoinBurstPainter(_burst.value, gold: _burstGold))
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(DailyBonusStatus s) {
    final reward = s.nextReward;
    final waitFor = !s.canClaim && s.nextClaimAt != null ? _until(s.nextClaimAt!) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        _RewardHero(reward: reward, ready: s.canClaim, waitFor: waitFor, ambient: _ambient),
        const SizedBox(height: 14),
        _StreakCard(streak: s.currentStreak, filled: s.claimedInCycle, ambient: _ambient),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(child: SectionBar('This week')),
            Text('${s.claimedInCycle}/7 claimed', style: AuraText.cardSub.copyWith(fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        _WeekGrid(
          ambient: _ambient,
          days: [
            for (var d = 1; d <= 7; d++)
              _Day(
                day: d,
                state: d < reward.dayNumber
                    ? _DayState.claimed
                    : d == reward.dayNumber
                    ? (s.canClaim ? _DayState.today : _DayState.next)
                    : _DayState.locked,
                value: d == reward.dayNumber ? formatAmount(reward.gold > 0 ? reward.gold : reward.tokens) : null,
                gold: reward.gold > 0 || reward.tokens == 0,
                mega: d == 7,
              ),
          ],
        ),
        const SizedBox(height: 22),
        GradientButton(
          label: s.canClaim ? 'Claim Day ${reward.dayNumber}' : 'Come back in ${waitFor ?? 'a bit'}',
          enabled: s.canClaim,
          loading: _claiming,
          onPressed: () => _claim(s),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text('Claim every day to grow your streak.', style: AuraText.cardSub, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

// ── Hero: today's (or the next) reward ─────────────────────────────────────

class _RewardHero extends StatelessWidget {
  const _RewardHero({required this.reward, required this.ready, required this.ambient, this.waitFor});
  final DailyReward reward;
  final bool ready;
  final String? waitFor;
  final Animation<double> ambient;

  bool get _gold => reward.gold > 0 || reward.tokens == 0;

  String get _extras => [
    if (_gold && reward.tokens > 0) '${formatAmount(reward.tokens)} Tokens',
    if (reward.powerUpId != null && reward.powerUpQuantity > 0) '${reward.powerUpQuantity}× power-up',
  ].join(' + ');

  @override
  Widget build(BuildContext context) {
    final accent = _gold ? AuraColors.amber : AuraColors.gems;
    final note = [
      if (_extras.isNotEmpty) '+ $_extras',
      if (waitFor != null) 'Unlocks in $waitFor' else if (ready) "Today's reward is waiting",
    ].join('  ·  ');
    return Container(
      height: 218,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1856), Color(0xFF1A1236), Color(0xFF12101F)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Light rays behind the chest (dimmed while waiting).
            Positioned.fill(
              child: AnimatedBuilder(
                animation: ambient,
                builder: (_, _) => CustomPaint(
                  painter: _RaysPainter(
                    turn: ambient.value,
                    color: accent,
                    strength: ready ? 1 : 0.35,
                    center: const Alignment(0, -0.2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      _Pill(
                        text: ready ? 'READY TO CLAIM' : 'NEXT REWARD',
                        color: ready ? AuraColors.green : AuraColors.accentGlow,
                      ),
                      const Spacer(),
                      _Pill(text: 'DAY ${reward.dayNumber} / 7', color: Colors.white),
                    ],
                  ),
                  const Spacer(),
                  // Floating chest (closed = waiting to be opened).
                  AnimatedBuilder(
                    animation: ambient,
                    builder: (_, child) => Transform.translate(
                      offset: Offset(0, ready ? math.sin(ambient.value * 2 * math.pi * 3) * 4 : 0),
                      child: child,
                    ),
                    child: CustomPaint(
                      size: const Size(84, 70),
                      painter: _ChestPainter(open: !ready, accent: accent),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CurrencyGlyph(kind: _gold ? Currency.gold : Currency.gems, size: 24),
                      const SizedBox(width: 8),
                      ShaderMask(
                        shaderCallback: (r) => LinearGradient(
                          colors: _gold
                              ? const [AuraColors.goldLight, AuraColors.gold]
                              : const [AuraColors.badgeCyan, AuraColors.gems],
                        ).createShader(r),
                        child: Text(
                          formatAmount(_gold ? reward.gold : reward.tokens),
                          style: TextStyle(
                            fontFamily: AuraText.displayFamily,
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _gold ? 'Gold' : 'Tokens',
                        style: const TextStyle(color: AuraColors.textSecondary, fontSize: 15),
                      ),
                    ],
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(note, style: AuraText.cardSub.copyWith(fontSize: 12.5), textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8),
      ),
    );
  }
}

/// Soft rotating light rays + glow from [center].
class _RaysPainter extends CustomPainter {
  _RaysPainter({required this.turn, required this.color, required this.strength, required this.center});
  final double turn;
  final Color color;
  final double strength;
  final Alignment center;

  @override
  void paint(Canvas canvas, Size size) {
    final c = center.alongSize(size);
    final glowR = size.width * 0.5;
    canvas.drawCircle(
      c,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.35 * strength),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: glowR)),
    );
    final r = size.width * 0.75;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.2 * strength),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    for (var i = 0; i < 12; i++) {
      final a = turn * 2 * math.pi + i * math.pi / 6;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + r * math.cos(a - 0.09), c.dy + r * math.sin(a - 0.09))
          ..lineTo(c.dx + r * math.cos(a + 0.09), c.dy + r * math.sin(a + 0.09))
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RaysPainter o) => o.turn != turn || o.strength != strength || o.color != color;
}

/// Drawn treasure chest. Closed (with a lock) = reward waiting; open with the
/// glow spilling out = claimed, next one coming.
class _ChestPainter extends CustomPainter {
  _ChestPainter({required this.open, required this.accent});
  final bool open;
  final Color accent;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final bodyRect = Rect.fromLTWH(w * 0.06, h * 0.42, w * 0.88, h * 0.56);
    final body = RRect.fromRectAndRadius(bodyRect, const Radius.circular(8));
    final band = Paint()
      ..shader = const LinearGradient(colors: [AuraColors.goldLight, AuraColors.gold]).createShader(bodyRect);

    // Ground shadow.
    canvas.drawOval(
      Rect.fromLTWH(w * 0.1, h * 0.9, w * 0.8, h * 0.14),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Glow spilling out of an open chest.
    if (open) {
      canvas.drawOval(
        Rect.fromLTWH(w * 0.1, h * 0.26, w * 0.8, h * 0.26),
        Paint()
          ..color = accent.withValues(alpha: 0.85)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
    }
    // Body + bands.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8B5CF6), Color(0xFF5B21B6)],
        ).createShader(bodyRect),
    );
    canvas.drawRect(Rect.fromLTWH(w * 0.06, h * 0.42, w * 0.88, h * 0.08), band);
    canvas.drawRect(Rect.fromLTWH(w * 0.2, h * 0.42, w * 0.07, h * 0.56), band);
    canvas.drawRect(Rect.fromLTWH(w * 0.73, h * 0.42, w * 0.07, h * 0.56), band);

    // Lid — tilted back around its hinge when open.
    final lidRect = Rect.fromLTWH(w * 0.04, h * 0.1, w * 0.92, h * 0.34);
    canvas.save();
    if (open) {
      final hinge = Offset(w * 0.5, h * 0.44);
      canvas.translate(hinge.dx, hinge.dy - h * 0.1);
      canvas.rotate(-0.28);
      canvas.translate(-hinge.dx, -hinge.dy);
    }
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        lidRect,
        topLeft: const Radius.circular(18),
        topRight: const Radius.circular(18),
        bottomLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFA78BFA), Color(0xFF7C3AED)],
        ).createShader(lidRect),
    );
    canvas.drawRect(Rect.fromLTWH(w * 0.2, h * 0.1, w * 0.07, h * 0.34), band);
    canvas.drawRect(Rect.fromLTWH(w * 0.73, h * 0.1, w * 0.07, h * 0.34), band);
    canvas.restore();

    // Lock on a closed chest.
    if (!open) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.42, h * 0.36, w * 0.16, h * 0.2), const Radius.circular(4)),
        band,
      );
      canvas.drawCircle(Offset(w * 0.5, h * 0.45), w * 0.025, Paint()..color = const Color(0xFF5B21B6));
    }
    // Rim highlight.
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.25),
    );
  }

  @override
  bool shouldRepaint(_ChestPainter o) => o.open != open || o.accent != accent;
}

// ── Streak ────────────────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak, required this.filled, required this.ambient});

  /// Consecutive days claimed.
  final int streak;

  /// Days of this week's cycle already claimed (0–7).
  final int filled;
  final Animation<double> ambient;

  @override
  Widget build(BuildContext context) {
    final lit = streak > 0;
    return AuraCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AuraColors.brandOrange.withValues(alpha: 0.22), AuraColors.brandPink.withValues(alpha: 0.14)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Flickering flame (still when there's no streak).
              AnimatedBuilder(
                animation: ambient,
                builder: (_, child) {
                  final t = ambient.value * 2 * math.pi * 6;
                  final flick = lit ? 1 + 0.06 * math.sin(t) + 0.03 * math.sin(t * 2.7) : 1.0;
                  return Transform.scale(scale: flick, alignment: Alignment.bottomCenter, child: child);
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: lit
                          ? const [AuraColors.brandOrange, AuraColors.danger]
                          : const [Color(0xFF2A2440), Color(0xFF1C1830)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.local_fire_department, color: lit ? Colors.white : Colors.white38, size: 28),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lit ? '$streak-Day Streak' : 'No streak yet',
                      style: TextStyle(
                        fontFamily: AuraText.displayFamily,
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lit ? "You're on a roll — keep it going!" : 'Claim today to start one.',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (int i = 0; i < 7; i++) ...[
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: i < filled ? AuraGradients.brand : null,
                      color: i < filled ? null : AuraColors.pagerInactive,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                if (i < 6) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Week path ─────────────────────────────────────────────────────────────

/// claimed · today (claimable now) · next (tomorrow's, waiting) · locked.
enum _DayState { claimed, today, next, locked }

class _Day {
  const _Day({required this.day, required this.state, this.value, this.gold = true, this.mega = false});
  final int day;
  final _DayState state;

  /// Reward amount; null when the service hasn't said (only the next reward
  /// is known) — the tile then shows a gift.
  final String? value;
  final bool gold;
  final bool mega;
}

/// 4 columns; day 7 (mega) spans two so the bottom row fills the width.
class _WeekGrid extends StatelessWidget {
  const _WeekGrid({required this.days, required this.ambient});
  final List<_Day> days;
  final Animation<double> ambient;

  static const double _gap = 10;
  static const double _tileH = 108;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final colW = (c.maxWidth - _gap * 3) / 4;
        Widget tile(int i, double w) => SizedBox(
          width: w,
          height: _tileH,
          child: _DayTile(day: days[i], ambient: ambient),
        );
        return Column(
          children: [
            Row(
              children: [
                tile(0, colW),
                const SizedBox(width: _gap),
                tile(1, colW),
                const SizedBox(width: _gap),
                tile(2, colW),
                const SizedBox(width: _gap),
                tile(3, colW),
              ],
            ),
            const SizedBox(height: _gap),
            Row(
              children: [
                tile(4, colW),
                const SizedBox(width: _gap),
                tile(5, colW),
                const SizedBox(width: _gap),
                tile(6, colW * 2 + _gap),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// One day. A plain column — top label (DAY n / TODAY / TOMORROW), icon,
/// bottom line (amount / Claimed / lock) — so nothing overlaps; state shows
/// through colour, a check or a lock.
class _DayTile extends StatelessWidget {
  const _DayTile({required this.day, required this.ambient});
  final _Day day;
  final Animation<double> ambient;

  @override
  Widget build(BuildContext context) {
    final state = day.state;
    final isToday = state == _DayState.today;
    final isClaimed = state == _DayState.claimed;
    final isNext = state == _DayState.next;
    final locked = state == _DayState.locked;
    final known = day.value != null;

    final label = switch (state) {
      _DayState.today => 'TODAY',
      _DayState.next => 'TOMORROW',
      _ => 'DAY ${day.day}',
    };
    final labelColor = switch (state) {
      _DayState.today => Colors.white,
      _DayState.next => AuraColors.accentGlow,
      _DayState.claimed => AuraColors.green,
      _DayState.locked => Colors.white.withValues(alpha: 0.45),
    };

    final Widget icon = isClaimed
        ? Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AuraColors.green),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
          )
        : known
        ? CurrencyGlyph(kind: day.gold ? Currency.gold : Currency.gems, size: day.mega ? 34 : 30)
        : Icon(
            day.mega ? Icons.redeem_rounded : Icons.card_giftcard_rounded,
            size: day.mega ? 34 : 28,
            color: day.mega ? AuraColors.amber : Colors.white.withValues(alpha: 0.5),
          );

    final Widget bottom = known && !isClaimed
        ? Text(
            day.value!,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: day.gold ? AuraColors.amber : AuraColors.badgeCyan,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          )
        : isClaimed
        ? Text('Claimed', style: TextStyle(color: AuraColors.green.withValues(alpha: 0.9), fontSize: 11))
        : locked
        ? Icon(Icons.lock_rounded, size: 12, color: Colors.white.withValues(alpha: 0.4))
        : const SizedBox.shrink();

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: TextStyle(color: labelColor, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                ),
              ),
              if (day.mega) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AuraColors.goldLight, AuraColors.gold]),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'MEGA',
                    style: TextStyle(color: Color(0xFF1A1206), fontSize: 8.5, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ],
          ),
          icon,
          SizedBox(height: 16, child: Center(child: bottom)),
        ],
      ),
    );

    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isToday
            ? const [Color(0x668B5CF6), Color(0x40EC4899)]
            : isClaimed
            ? [AuraColors.green.withValues(alpha: 0.16), AuraColors.green.withValues(alpha: 0.05)]
            : day.mega
            ? [AuraColors.gold.withValues(alpha: 0.18), Colors.white.withValues(alpha: 0.03)]
            : [Colors.white.withValues(alpha: 0.09), Colors.white.withValues(alpha: 0.03)],
      ),
      border: Border.all(
        color: isToday
            ? AuraColors.accentGlow.withValues(alpha: 0.85)
            : isNext
            ? AuraColors.accentGlow.withValues(alpha: 0.45)
            : isClaimed
            ? AuraColors.green.withValues(alpha: 0.4)
            : Colors.white.withValues(alpha: 0.16),
        width: isToday ? 1.6 : 1,
      ),
    );

    if (!isToday) return DecoratedBox(decoration: decoration, child: content);

    // Today: a pulsing glow on an opaque base (so it never shows through the
    // translucent fill).
    return AnimatedBuilder(
      animation: ambient,
      builder: (_, child) {
        final p = 0.5 + 0.5 * math.sin(ambient.value * 2 * math.pi * 4);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF1A1236),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFA855F7).withValues(alpha: 0.35 + 0.3 * p),
                blurRadius: 14 + 10 * p,
                spreadRadius: -4,
              ),
            ],
          ),
          child: child,
        );
      },
      child: DecoratedBox(decoration: decoration, child: content),
    );
  }
}

// ── Claim celebration ───────────────────────────────────────────────────────

/// Coins bursting up from the claim button, spinning, and falling away.
class _CoinBurstPainter extends CustomPainter {
  _CoinBurstPainter(this.t, {required this.gold});
  final double t;
  final bool gold;

  static final _rand = math.Random(7);
  static final List<(double, double, double)> _coins = List.generate(
    26,
    (_) => (_rand.nextDouble() * 2 - 1, 0.6 + _rand.nextDouble() * 0.6, _rand.nextDouble()),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.8);
    final fade = t < 0.75 ? 1.0 : 1 - (t - 0.75) / 0.25;
    for (final (dir, speed, spin) in _coins) {
      final x = origin.dx + dir * size.width * 0.45 * t;
      final y = origin.dy - speed * size.height * 0.55 * t + size.height * 0.6 * t * t;
      final r = 7.0 + spin * 4;
      final squash = math.cos((t * 6 + spin) * math.pi).abs().clamp(0.25, 1.0);
      final rect = Rect.fromCenter(center: Offset(x, y), width: r * 2 * squash, height: r * 2);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: gold
                ? [AuraColors.goldLight.withValues(alpha: fade), AuraColors.gold.withValues(alpha: fade)]
                : [AuraColors.badgeCyan.withValues(alpha: fade), AuraColors.gemsDeep.withValues(alpha: fade)],
          ).createShader(rect),
      );
      canvas.drawOval(
        rect.deflate(2.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.5 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_CoinBurstPainter o) => o.t != t;
}

// ── Loading ───────────────────────────────────────────────────────────────

/// Loading placeholder shaped like the screen (hero, streak, grid, button).
class _DailySkeleton extends StatelessWidget {
  const _DailySkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          const SkeletonBox(height: 218, radius: 24),
          const SizedBox(height: 14),
          const SkeletonBox(height: 104, radius: 20),
          const SizedBox(height: 22),
          const SkeletonBox(width: 110, height: 14),
          const SizedBox(height: 12),
          for (var r = 0; r < 2; r++) ...[
            Row(
              children: [
                for (var c = 0; c < 4; c++) ...[
                  const Expanded(child: SkeletonBox(height: 108, radius: 16)),
                  if (c < 3) const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
          const SkeletonBox(height: 54, radius: 16),
        ],
      ),
    );
  }
}
