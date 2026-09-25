import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Daily rewards / streak screen. See docs/DESIGN_SPEC.md (v2 §Daily Rewards).
class DailyRewardsScreen extends StatelessWidget {
  const DailyRewardsScreen({super.key});

  static const List<_Day> _days = [
    _Day(day: 1, value: '500', gold: true, state: _DayState.claimed),
    _Day(day: 2, value: '800', gold: true, state: _DayState.claimed),
    _Day(day: 3, value: '250', gold: true, state: _DayState.today),
    _Day(day: 4, value: '1,500', gold: false, state: _DayState.locked),
    _Day(day: 5, value: '500', gold: true, state: _DayState.locked),
    _Day(day: 6, value: '3,000', gold: false, state: _DayState.locked),
    _Day(day: 7, value: '2,000', gold: true, state: _DayState.locked, mega: true),
  ];

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
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 12.0;
              final tileW = (constraints.maxWidth - spacing * 3) / 4;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final d in _days)
                    SizedBox(width: tileW, child: _DayTile(day: d)),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Builder(
            builder: (context) => GradientButton(
              label: 'Claim Day 3',
              onPressed: () => showAuraToast(context, 'Claimed 250 Gold', kind: AuraToastKind.gold),
            ),
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

enum _DayState { claimed, today, locked }

class _Day {
  const _Day({
    required this.day,
    required this.value,
    required this.gold,
    required this.state,
    this.mega = false,
  });
  final int day;
  final String value;
  final bool gold;
  final _DayState state;
  final bool mega;
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.day});
  final _Day day;

  @override
  Widget build(BuildContext context) {
    final isToday = day.state == _DayState.today;
    final dimmed = day.state != _DayState.today;
    final icon = day.gold ? Icons.monetization_on : Icons.diamond;
    final iconColor = day.gold ? AuraColors.gold : AuraColors.gems;

    Widget tile = Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        // Opaque fills (a translucent gradient here would let the today
        // gradient-border wrapper show straight through — see match_setup).
        color: isToday ? const Color(0xFF241A3D) : AuraColors.bgRaised,
        borderRadius: BorderRadius.circular(16),
        border: isToday ? null : Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'DAY ${day.day}',
            style: const TextStyle(
              color: AuraColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Opacity(
            opacity: dimmed ? 0.5 : 1,
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 6),
          Opacity(
            opacity: dimmed && day.state != _DayState.claimed ? 0.6 : 1,
            child: Text(
              day.value,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    // Gradient border highlight for today.
    if (isToday) {
      tile = Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          gradient: AuraGradients.brand,
          borderRadius: BorderRadius.circular(17),
        ),
        child: tile,
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        tile,
        if (day.state == _DayState.claimed)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: AuraColors.green,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 12),
            ),
          ),
        if (day.state == _DayState.locked)
          const Positioned(
            top: 8,
            right: 8,
            child: Icon(Icons.lock, color: AuraColors.textSecondary, size: 13),
          ),
        if (isToday)
          Positioned(
            top: -8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  gradient: AuraGradients.brand,
                  borderRadius: BorderRadius.circular(8),
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
        if (day.mega)
          Positioned(
            bottom: -8,
            left: 0,
            right: 0,
            child: Center(
              child: AuraBadge('MEGA', color: AuraColors.amber),
            ),
          ),
      ],
    );
  }
}
