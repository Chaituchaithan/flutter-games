import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/daily_bonus.dart';
import 'package:snakeladder/data/repositories/daily_bonus_repository.dart';
import 'package:snakeladder/data/sources/daily_bonus_source.dart';
import 'package:snakeladder/screens/economy/daily_rewards_screen.dart';

// The live responses (2026-10-10).
const _statusJson = '''
{"current_streak":1,"can_claim":false,
 "next_reward":{"day_number":2,"reward_tokens":"0","reward_gold":"150","power_up_id":null,"power_up_quantity":0},
 "last_claimed_at":"2026-10-10T15:38:03.441146Z","next_claim_available_at":"2026-10-11T15:38:03.441146Z","total_claims":1}''';
const _claimJson = '''
{"tokens_awarded":"0","gold_awarded":"100","power_up_id":null,"power_up_quantity":0,"new_streak":1,"total_claims":1}''';

class _FakeSource implements DailyBonusSource {
  _FakeSource(this.current);
  DailyBonusStatus current;
  int claims = 0;

  @override
  Future<DailyBonusStatus> status() async => current;

  @override
  Future<DailyClaim> claim() async {
    claims++;
    current = DailyBonusStatus.fromJson(jsonDecode(_statusJson) as Map<String, dynamic>);
    return DailyClaim.fromJson(jsonDecode(_claimJson) as Map<String, dynamic>);
  }
}

void main() {
  test('status parses string amounts and dates', () {
    final s = DailyBonusStatus.fromJson(jsonDecode(_statusJson) as Map<String, dynamic>);
    expect(s.currentStreak, 1);
    expect(s.canClaim, isFalse);
    expect(s.nextReward.dayNumber, 2);
    expect(s.nextReward.gold, 150);
    expect(s.nextReward.tokens, 0);
    expect(s.claimedInCycle, 1);
    expect(s.nextClaimAt, DateTime.parse('2026-10-11T15:38:03.441146Z'));
    expect(s.nextReward.label, '150 Gold');
  });

  test('claim parses what was paid', () {
    final c = DailyClaim.fromJson(jsonDecode(_claimJson) as Map<String, dynamic>);
    expect(c.gold, 100);
    expect(c.tokens, 0);
    expect(c.newStreak, 1);
    expect(c.label, '100 Gold');
  });

  Future<void> pump(WidgetTester t, _FakeSource src) async {
    t.view.physicalSize = const Size(411, 891);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(ProviderScope(
      overrides: [dailyBonusSourceProvider.overrideWithValue(src)],
      child: const MaterialApp(home: DailyRewardsScreen()),
    ));
    await t.pump(const Duration(milliseconds: 100));
  }

  testWidgets('claimable: Claim Day 1 → server payout toast → next reward shown', (t) async {
    final src = _FakeSource(const DailyBonusStatus(
      currentStreak: 0,
      canClaim: true,
      nextReward: DailyReward(dayNumber: 1, gold: 100),
    ));
    await pump(t, src);
    expect(find.text('Claim Day 1'), findsOneWidget);
    expect(find.text('No streak yet'), findsOneWidget);

    await t.ensureVisible(find.text('Claim Day 1'));
    await t.tap(find.text('Claim Day 1'));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(src.claims, 1);
    expect(find.text('Claimed 100 Gold · 1-day streak'), findsOneWidget);
    expect(find.text('1-Day Streak'), findsOneWidget);
    expect(find.text('NEXT REWARD'), findsOneWidget);
    expect(find.text('TOMORROW'), findsOneWidget); // day 2 tile
    expect(find.text('Claimed'), findsOneWidget); // day 1 tile
    expect(find.textContaining('Come back in'), findsOneWidget);
  });

  testWidgets('already claimed: button disabled with countdown', (t) async {
    final src = _FakeSource(DailyBonusStatus(
      currentStreak: 1,
      canClaim: false,
      nextReward: const DailyReward(dayNumber: 2, gold: 150),
      nextClaimAt: DateTime.now().add(const Duration(hours: 5, minutes: 30)),
    ));
    await pump(t, src);
    expect(find.textContaining('Come back in 5h'), findsOneWidget);
    expect(find.textContaining('Unlocks in 5h'), findsOneWidget);
    await t.tap(find.textContaining('Come back in'), warnIfMissed: false);
    await t.pump();
    expect(src.claims, 0);
  });
}
