// Live check of the rewards contract (docs/services/07-rewards.md) against a
// running gateway. Skipped unless the base URL is given:
//
//   flutter test test/live_rewards_test.dart --dart-define=LIVE_API=http://192.168.0.235:1280/api/v1
//
// Creates a throwaway guest without a device_id (so the welcome claim goes
// through the device_required → register → claim again path), claims the
// welcome bonus, spins the Welcome wheel, claims the daily bonus and reads
// quests, achievements and bonus games. Never prints tokens.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/rewards.dart';
import 'package:snakeladder/data/sources/daily_bonus_source.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/auth_service.dart';
import 'package:snakeladder/services/rewards_service.dart';

const _base = String.fromEnvironment('LIVE_API');

void main() {
  test('rewards against the live gateway', () async {
    final api = ApiClient(dio: Dio(BaseOptions(baseUrl: '$_base/', contentType: 'application/json')));
    await RemoteAuthService(api).loginGuest(extras: const SignUpExtras(entryGame: 'ludo'));
    final n = DateTime.now().millisecondsSinceEpoch;
    final rewards = RemoteRewardsApi(api, deviceId: () async => 'live-rewards-$n');

    // 1. Welcome: a guest's half grant, then claim (registers the device if
    // the server asks), then the free spin.
    final w = (await rewards.welcomeBonus())!;
    expect(w.grant.wasGuest, isTrue);
    expect(w.showSheet, isTrue);
    final claim = await rewards.claimWelcome();
    expect(claim.status, isNotEmpty);
    expect(claim.balances, isNotNull);
    try {
      await rewards.claimWelcome();
      fail('second claim should be refused');
    } on AppException catch (e) {
      expect(welcomeClaimIssue(e).kind, RewardIssueKind.alreadyDone);
    }
    final spin = (await rewards.welcomeBonus())!.freeSpin!;
    final play = await rewards.playBonusGame(spin.code, trigger: spin.trigger, triggerRef: spin.triggerRef);
    final game = await rewards.bonusGame(spin.code);
    expect(play.slotIndex, inInclusiveRange(0, game.slots - 1));
    expect((await rewards.welcomeBonus())!.spinAvailable, isFalse);
    try {
      await rewards.playBonusGame(spin.code, trigger: spin.trigger, triggerRef: spin.triggerRef);
      fail('second spin should be refused');
    } on AppException catch (e) {
      expect(bonusPlayIssue(e).kind, RewardIssueKind.gone);
    }

    // 2. Daily bonus: the 30-day calendar, a claim, then a quiet 409.
    final daily = RemoteDailyBonusSource(api);
    final status = await daily.status();
    expect(status.rewards, isNotEmpty);
    expect(status.canClaim, isTrue);
    final paid = await daily.claim();
    expect(paid.newStreak, 1);
    try {
      await daily.claim();
      fail('second daily claim should be refused');
    } on AppException catch (e) {
      expect(dailyClaimIssue(e).kind, RewardIssueKind.alreadyDone);
    }

    // 3. Quests: merged rows for every active quest; nothing claimable yet.
    final rows = mergeQuests(await rewards.activeQuests(), await rewards.myQuestProgress());
    expect(rows, isNotEmpty);
    expect(rows.any((r) => r.claimable), isFalse);
    try {
      await rewards.claimQuest(rows.first.quest.id);
      fail('an unplayed quest should not be claimable');
    } on AppException catch (e) {
      expect(questClaimIssue(e).text, 'Finish the quest first.');
    }

    // 4. Achievements: flat and tiered; claiming an unreached tier.
    final mine = await rewards.myAchievements();
    final tiered = mine.firstWhere((a) => a.tiered && a.tierReached == null);
    try {
      await rewards.claimAchievement(tiered.id, tier: tiered.tiers.first.tier);
      fail('an unreached tier should not be claimable');
    } on AppException catch (e) {
      expect(achievementClaimIssue(e).text, 'Not unlocked yet.');
    }

    // 5. Bonus games and the prize history.
    final store = await rewards.bonusGames(trigger: 'store');
    expect(store.every((g) => g.trigger == 'store'), isTrue);
    final history = await rewards.myBonusPlays();
    expect(history.items.first.code, spin.code);
  }, skip: _base.isEmpty ? 'set --dart-define=LIVE_API=http://<host>:1280/api/v1' : null);
}
