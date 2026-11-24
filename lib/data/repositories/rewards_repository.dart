import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/app_exception.dart';
import '../../services/rewards_service.dart';
import '../../services/server_clock.dart';
import '../models/daily_bonus.dart';
import '../models/rewards.dart';
import 'daily_bonus_repository.dart';

/// Rewards state (docs/services/07-rewards.md). Kept for the session (not
/// auto-disposed) and re-read by invalidation: on app start / resume, when a
/// rewards screen opens, after a game ends ([refreshRewardsAfterGame]), after
/// every claim or play, and when a countdown reaches zero. Nothing is pushed
/// by the server. No silent auto-retry.

/// GET /welcome-bonus/me; null = the account has no grant.
final welcomeBonusProvider = FutureProvider<WelcomeBonus?>(
  (ref) => ref.watch(rewardsApiProvider).welcomeBonus(),
  retry: (_, _) => null,
);

/// Active quests merged with my progress (rows for quests without progress
/// show `0 / target`).
final questsProvider = FutureProvider<List<QuestRow>>(
  (ref) async {
    final api = ref.watch(rewardsApiProvider);
    final (active, mine) = await (api.activeQuests(), api.myQuestProgress()).wait;
    return mergeQuests(active, mine);
  },
  retry: (_, _) => null,
);

/// GET /achievements/my.
final myAchievementsProvider = FutureProvider<List<Achievement>>(
  (ref) async {
    final list = await ref.watch(rewardsApiProvider).myAchievements();
    return [...list]..sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.id.compareTo(b.id));
  },
  retry: (_, _) => null,
);

/// GET /bonus-games[?trigger=] (null = all).
final bonusGamesProvider = FutureProvider.autoDispose.family<List<BonusGame>, String?>(
  (ref, trigger) => ref.watch(rewardsApiProvider).bonusGames(trigger: trigger),
  retry: (_, _) => null,
);

/// GET /bonus-games/{id or code}.
final bonusGameProvider = FutureProvider.autoDispose.family<BonusGame, String>(
  (ref, idOrCode) => ref.watch(rewardsApiProvider).bonusGame(idOrCode),
  retry: (_, _) => null,
);

/// GET /bonus-games/plays/me, first page (prize history).
final bonusPlaysProvider = FutureProvider.autoDispose<CursorPage<BonusPlayRecord>>(
  (ref) => ref.watch(rewardsApiProvider).myBonusPlays(),
  retry: (_, _) => null,
);

/// The free spins the player is entitled to now (07-rewards.md §5: free
/// games are offered only through their trigger, never from the list):
/// - the welcome `free_spin` while it is `available`;
/// - the latest spin-day daily claim's spin (no `trigger_ref`: the latest
///   claim), unless [plays] already has a `daily_bonus_day` play since that
///   claim. The server stays the judge: a used spin answers `no_entitlement`.
List<BonusGameOffer> freeSpinOffers({WelcomeBonus? welcome, DailyBonusStatus? daily, List<BonusPlayRecord> plays = const []}) {
  final offers = <BonusGameOffer>[];
  final spin = welcome?.freeSpin;
  if (spin != null && spin.available) offers.add(spin);
  final last = daily == null || daily.currentStreak <= 0 ? null : daily.rewardFor(daily.currentStreak);
  final id = last?.bonusGameId;
  final claimedAt = daily?.lastClaimedAt;
  if (id != null && claimedAt != null) {
    final played = plays.any((p) => p.trigger == 'daily_bonus_day' && p.playedAt != null && !p.playedAt!.isBefore(claimedAt));
    if (!played) offers.add(BonusGameOffer(bonusGameId: id, code: '$id', trigger: 'daily_bonus_day'));
  }
  return offers;
}

/// The Wheel tab's wheels: the free spins from [freeSpinOffers] whose game is
/// a wheel, then the paid `store` wheels. Every prize, slice and cost comes
/// from the server.
final wheelSpinsProvider = FutureProvider.autoDispose<List<WheelSpin>>(
  (ref) async {
    // Watch everything first: a claim or play elsewhere re-reads the list.
    final welcomeF = ref.watch(welcomeBonusProvider.future);
    final dailyF = ref.watch(dailyBonusStatusProvider.future);
    final storeF = ref.watch(bonusGamesProvider('store').future);
    // History only hides a used daily spin; without it the server decides.
    final playsF = ref
        .watch(bonusPlaysProvider.future)
        .then((p) => p.items, onError: (Object _) => const <BonusPlayRecord>[]);
    // Future.wait listens to all three (no stray unhandled error).
    final got = await Future.wait<Object?>([welcomeF, dailyF, storeF]);
    final welcome = got[0] as WelcomeBonus?;
    final daily = got[1] as DailyBonusStatus;
    final store = got[2] as List<BonusGame>;
    final plays = await playsF;
    final spins = <WheelSpin>[];
    for (final o in freeSpinOffers(welcome: welcome, daily: daily, plays: plays)) {
      final BonusGame g;
      try {
        g = await ref.watch(bonusGameProvider(o.code).future);
      } on AppException catch (e) {
        if (e.statusCode == 404) continue; // unpublished: nothing to offer
        rethrow;
      }
      if (g.gameType == 'wheel' && g.supported && g.trigger == o.trigger) {
        spins.add(WheelSpin(
          game: g,
          trigger: o.trigger,
          triggerRef: o.triggerRef,
          entitlement: o.trigger == 'daily_bonus_day' ? daily.lastClaimedAt?.toIso8601String() : null,
        ));
      }
    }
    for (final g in store) {
      if (g.gameType == 'wheel' && g.supported) spins.add(WheelSpin(game: g, trigger: 'store'));
    }
    return spins;
  },
  retry: (_, _) => null,
);

/// Re-read the Wheel tab's sources (Retry, and after a play).
void refreshWheelSpins(WidgetRef ref) {
  ref.invalidate(welcomeBonusProvider);
  ref.invalidate(dailyBonusStatusProvider);
  ref.invalidate(bonusGamesProvider);
  ref.invalidate(bonusGameProvider);
  ref.invalidate(bonusPlaysProvider);
}

/// The red dot ("Red dot rules"): on when anything can be claimed. Built
/// from whatever has loaded; a failed or loading section counts as off.
final rewardsBadgeProvider = Provider<RewardsBadge>((ref) {
  return RewardsBadge.from(
    welcome: ref.watch(welcomeBonusProvider).value,
    dailyCanClaim: ref.watch(dailyBonusStatusProvider).value?.canClaim,
    quests: ref.watch(questsProvider).value,
    achievements: ref.watch(myAchievementsProvider).value,
  );
});

/// Re-read every rewards section (app start, resume, the Rewards screens).
void refreshRewardsFrom(WidgetRef ref) {
  ref.invalidate(welcomeBonusProvider);
  ref.invalidate(dailyBonusStatusProvider);
  ref.invalidate(questsProvider);
  ref.invalidate(myAchievementsProvider);
}

/// After a game ends: wait for the game server to settle the match (about
/// 2 seconds), then re-read quest progress and achievements.
Future<void> refreshRewardsAfterGame(WidgetRef ref, {Duration settle = const Duration(seconds: 2)}) async {
  await Future<void>.delayed(settle);
  try {
    ref.invalidate(questsProvider);
    ref.invalidate(myAchievementsProvider);
  } on Object catch (_) {
    // The widget went away meanwhile: nothing to refresh for.
  }
}

/// The next free wheel the daily bonus unlocks, for a locked Wheel tab:
/// which wheel, on which streak day, and when (server clock).
class WheelUnlock {
  const WheelUnlock({required this.game, required this.day, required this.claimToday, this.at});

  /// The spin day's wheel (its real slices, shown locked).
  final BonusGame game;

  /// The daily-bonus streak day that grants it.
  final int day;

  /// Today's claim grants it: claim now to spin.
  final bool claimToday;

  /// When that day's claim opens, if the player claims every day; null with
  /// [claimToday].
  final DateTime? at;
}

/// Days from the next claimable day ([from]) to the first spin day at or
/// after it in a [cycle]-day cycle (wrapping round), or null with none.
({int day, int ahead})? nextSpinDay(List<DailyReward> rewards, {required int from, required int cycle}) {
  final spins = [for (final r in rewards) if (r.isSpinDay && r.isEnabled) r.dayNumber]..sort();
  if (spins.isEmpty) return null;
  for (final d in spins) {
    if (d >= from) return (day: d, ahead: d - from);
  }
  final d = spins.first;
  return (day: d, ahead: cycle - from + d);
}

/// The Wheel tab's "next free spin" while nothing is spinnable.
final nextWheelUnlockProvider = FutureProvider.autoDispose<WheelUnlock?>((ref) async {
  final daily = await ref.watch(dailyBonusStatusProvider.future);
  final next = nextSpinDay(daily.rewards, from: daily.nextReward.dayNumber, cycle: daily.cycleLength);
  if (next == null) return null;
  final id = daily.rewardFor(next.day)?.bonusGameId;
  if (id == null) return null;
  final BonusGame g;
  try {
    g = await ref.watch(bonusGameProvider('$id').future);
  } on AppException {
    return null; // unpublished: nothing to show
  }
  if (g.gameType != 'wheel' || !g.supported) return null;
  final claimToday = daily.canClaim && next.ahead == 0;
  final base = daily.canClaim ? ServerClock.now() : (daily.nextClaimAt ?? ServerClock.now());
  return WheelUnlock(
    game: g,
    day: next.day,
    claimToday: claimToday,
    at: claimToday ? null : base.add(Duration(days: next.ahead)),
  );
}, retry: (_, _) => null);
