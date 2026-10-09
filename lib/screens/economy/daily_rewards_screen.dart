import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Daily rewards / streak screen. See docs/DESIGN_SPEC.md (v2 §Daily Rewards).
class DailyRewardsScreen extends StatefulWidget {
  const DailyRewardsScreen({super.key});

  @override
  State<DailyRewardsScreen> createState() => _DailyRewardsScreenState();
}

class _DailyRewardsScreenState extends State<DailyRewardsScreen> {
  /// Days 1–2 are already claimed; day 3 is today. Set once the user claims it.
  bool _claimedToday = false;
  static const int _todayIndex = 2; // 0-based → Day 3

  static const List<_Day> _base = [
    _Day(day: 1, value: '500', gold: true),
    _Day(day: 2, value: '800', gold: true),
    _Day(day: 3, value: '250', gold: true),
    _Day(day: 4, value: '1,500', gold: false),
    _Day(day: 5, value: '500', gold: true),
    _Day(day: 6, value: '3,000', gold: false),
    _Day(day: 7, value: '2,000', gold: true, mega: true),
  ];

  /// Resolve each day's visual state from the claim progress.
  _DayState _stateFor(int i) {
    final claimedThrough = _claimedToday ? _todayIndex : _todayIndex - 1;
    if (i <= claimedThrough) return _DayState.claimed;
    if (i == claimedThrough + 1) return _DayState.today;
    return _DayState.locked;
  }

  void _claim() {
    if (_claimedToday) return;
    setState(() => _claimedToday = true);
    showAuraToast(context, 'Claimed 250 Gold', kind: AuraToastKind.gold);
  }

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Daily Rewards'),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          const _StreakBanner(),
          const SizedBox(height: 16),
          const _TodayReward(),
          const SizedBox(height: 20),
          const SectionBar('This week'),
          const SizedBox(height: 12),
          _WeekGrid(stateFor: _stateFor, days: _base),
          const SizedBox(height: 20),
          GradientButton(
            label: _claimedToday ? 'Come back tomorrow' : 'Claim Day 3',
            enabled: !_claimedToday,
            onPressed: _claim,
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'Miss a day and your streak resets to Day 1.',
              style: AuraText.cardSub,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// 4-column week grid. Day 7 (mega) spans two columns so the bottom row fills
/// the full width — matches the mockup (`grid-template-columns: repeat(4,1fr)`
/// with `grid-column: span 2` on day 7, gap 10).
class _WeekGrid extends StatelessWidget {
  const _WeekGrid({required this.stateFor, required this.days});
  final _DayState Function(int) stateFor;
  final List<_Day> days;

  static const double _gap = 10;
  static const double _tileH = 94;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final colW = (c.maxWidth - _gap * 3) / 4;
        Widget tile(int i, double w) => SizedBox(
              width: w,
              height: _tileH,
              child: _DayTile(day: days[i], state: stateFor(i)),
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
                tile(6, colW * 2 + _gap), // span 2 columns
              ],
            ),
          ],
        );
      },
    );
  }
}

enum _DayState { claimed, today, locked }

class _Day {
  const _Day({
    required this.day,
    required this.value,
    required this.gold,
    this.mega = false,
  });
  final int day;
  final String value;
  final bool gold;
  final bool mega;
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.day, required this.state});
  final _Day day;
  final _DayState state;

  @override
  Widget build(BuildContext context) {
    final isToday = state == _DayState.today;
    final isClaimed = state == _DayState.claimed;
    final icon = day.gold ? Icons.monetization_on : Icons.diamond;
    final iconColor = day.gold ? AuraColors.gold : AuraColors.gems;
    final amountColor = day.gold ? const Color(0xFFFBBF24) : const Color(0xFF67E8F9);

    Widget tile = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: isToday
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x528B5CF6), Color(0x33EC4899)], // 0.32 / 0.20
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x17FFFFFF), Color(0x08FFFFFF)], // 0.09 / 0.03
              ),
        border: Border.all(
          color: isToday ? AuraColors.accentGlow.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.2),
          width: isToday ? 1.5 : 1,
        ),
        boxShadow: isToday
            ? [
                BoxShadow(
                  color: const Color(0xFFA855F7).withValues(alpha: 0.55),
                  blurRadius: 22,
                  spreadRadius: -4,
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'DAY ${day.day}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 3),
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(height: 3),
            Text(
              day.value,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: amountColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );

    // Clip so overlays/badges stay within the rounded box (overflow: hidden).
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          tile,
          // Claimed: dim veil + centered green check.
          if (isClaimed)
            Container(
              color: const Color(0x8C0A0816), // rgba(10,8,22,0.55)
              alignment: Alignment.center,
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(color: AuraColors.green, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 17),
              ),
            ),
          // Locked: small lock top-right.
          if (state == _DayState.locked)
            Positioned(
              top: 8,
              right: 8,
              child: Icon(Icons.lock, color: Colors.white.withValues(alpha: 0.5), size: 13),
            ),
          // Mega badge (gold pill) top-right.
          if (day.mega)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
                  ),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'MEGA',
                  style: TextStyle(
                    color: Color(0xFF1A1206),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          // Today badge (accent pill) at the bottom.
          if (isToday)
            Positioned(
              bottom: 7,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AuraColors.accentGlow.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'TODAY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
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

class _StreakBanner extends StatelessWidget {
  const _StreakBanner();

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AuraColors.brandOrange.withValues(alpha: 0.22),
          AuraColors.brandPink.withValues(alpha: 0.16),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AuraColors.brandOrange, AuraColors.danger],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.local_fire_department, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '2-Day Streak',
                      style: TextStyle(
                        fontFamily: AuraText.displayFamily,
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      "You're on a roll — keep it going!",
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (int i = 0; i < 7; i++) ...[
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: i < 3 ? AuraGradients.brand : null,
                      color: i < 3 ? null : AuraColors.pagerInactive,
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

class _TodayReward extends StatelessWidget {
  const _TodayReward();

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AuraColors.brandPurple.withValues(alpha: 0.28),
          AuraColors.brandPurple.withValues(alpha: 0.10),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const CurrencyGlyph(kind: Currency.gold, size: 30),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("TODAY'S REWARD", style: AuraText.section.copyWith(color: AuraColors.accentGlow)),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '250',
                    style: TextStyle(
                      fontFamily: AuraText.displayFamily,
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Gold',
                    style: TextStyle(color: AuraColors.textSecondary, fontSize: 15),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
