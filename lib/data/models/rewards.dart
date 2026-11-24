// Rewards models (docs/services/07-rewards.md): welcome bonus, quests,
// achievements and bonus games. The daily bonus lives in daily_bonus.dart.
//
// Parsing is lenient: unknown fields are ignored, missing ones fall back to
// empty values. Money arrives as numbers (achievements, bonus games, welcome)
// or numeric strings (quests, daily bonus); [parseAmount] reads both.
import 'package:flutter/foundation.dart';

import '../../utils/amount.dart';

Map<String, dynamic> _map(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
List<Object?> _list(Object? v) => v is List ? v : const [];
DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;
String? _str(Object? v) => v == null ? null : '$v';
int? _intOrNull(Object? v) => v == null ? null : parseAmount(v);

/// `balances` in the welcome claim and bonus game play replies (numbers).
@immutable
class RewardBalances {
  const RewardBalances({required this.tokens, required this.gold});
  final int tokens;
  final int gold;

  static RewardBalances? fromJson(Object? v) {
    if (v is! Map) return null;
    return RewardBalances(tokens: parseAmount(v['tokens']), gold: parseAmount(v['gold']));
  }
}

// ── 1. Welcome bonus ─────────────────────────────────────────────────────

/// `{tokens, gold, power_up_qty}` (`claimable_now`, `credited`).
@immutable
class WelcomeAmounts {
  const WelcomeAmounts({this.tokens = 0, this.gold = 0, this.powerUpQty = 0});
  final int tokens;
  final int gold;
  final int powerUpQty;

  bool get isEmpty => tokens + gold + powerUpQty <= 0;

  factory WelcomeAmounts.fromJson(Object? v) {
    final j = _map(v);
    return WelcomeAmounts(
      tokens: parseAmount(j['tokens']),
      gold: parseAmount(j['gold']),
      powerUpQty: parseAmount(j['power_up_qty']),
    );
  }
}

@immutable
class WelcomeInstallment {
  const WelcomeInstallment({required this.seq, this.dueAt, this.amounts = const WelcomeAmounts(), this.creditedAt});
  final int seq;

  /// Null for an after-first-match installment.
  final DateTime? dueAt;
  final WelcomeAmounts amounts;
  final DateTime? creditedAt;

  factory WelcomeInstallment.fromJson(Object? v) {
    final j = _map(v);
    return WelcomeInstallment(
      seq: parseAmount(j['seq']),
      dueAt: _time(j['due_at']),
      amounts: WelcomeAmounts.fromJson(j),
      creditedAt: _time(j['credited_at']),
    );
  }
}

/// A free play the server offers through a trigger: the welcome `free_spin`
/// or a daily claim's `bonus_game`. [trigger] and [triggerRef] go to the play
/// route exactly as given.
@immutable
class BonusGameOffer {
  const BonusGameOffer({
    required this.bonusGameId,
    required this.code,
    required this.trigger,
    this.triggerRef,
    this.playId,
    this.available = true,
    this.blockReason,
  });
  final int bonusGameId;
  final String code;
  final String trigger;
  final String? triggerRef;

  /// Welcome spin only: the play already made, if any.
  final int? playId;

  /// Welcome spin only: may be played now; otherwise see [blockReason]
  /// (`used`, `grant_blocked`, `grant_expired` or a bonus game block code).
  final bool available;
  final String? blockReason;

  static BonusGameOffer? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    return BonusGameOffer(
      bonusGameId: parseAmount(j['bonus_game_id']),
      code: _str(j['code']) ?? '${j['bonus_game_id']}',
      trigger: _str(j['trigger']) ?? '',
      triggerRef: _str(j['trigger_ref']),
      playId: _intOrNull(j['play_id']),
      available: j['available'] != false,
      blockReason: _str(j['block_reason']),
    );
  }
}

@immutable
class WelcomeGrant {
  const WelcomeGrant({
    required this.id,
    required this.status,
    this.blockedReason,
    this.entryGame,
    this.source = 'direct',
    this.wasGuest = false,
    this.tokensTotal = 0,
    this.goldTotal = 0,
    this.powerUpId,
    this.powerUpQty = 0,
    this.delivery = 'once',
    this.expiresAt,
    this.claimedAt,
    this.completedAt,
  });
  final int id;

  /// `pending` · `partial` · `completed` · `expired` · `blocked`.
  final String status;

  /// `device_dupe` · `guest_policy` · `disabled`.
  final String? blockedReason;
  final String? entryGame;
  final String source;
  final bool wasGuest;
  final int tokensTotal;
  final int goldTotal;
  final int? powerUpId;
  final int powerUpQty;

  /// `once` · `split_3d` · `split_7d` · `after_first_match`.
  final String delivery;
  final DateTime? expiresAt;
  final DateTime? claimedAt;
  final DateTime? completedAt;

  factory WelcomeGrant.fromJson(Object? v) {
    final j = _map(v);
    return WelcomeGrant(
      id: parseAmount(j['id']),
      status: _str(j['status']) ?? 'pending',
      blockedReason: _str(j['blocked_reason']),
      entryGame: _str(j['entry_game']),
      source: _str(j['source']) ?? 'direct',
      wasGuest: j['was_guest'] == true,
      tokensTotal: parseAmount(j['tokens_total']),
      goldTotal: parseAmount(j['gold_total']),
      powerUpId: _intOrNull(j['power_up_id']),
      powerUpQty: parseAmount(j['power_up_qty']),
      delivery: _str(j['delivery']) ?? 'once',
      expiresAt: _time(j['expires_at']),
      claimedAt: _time(j['claimed_at']),
      completedAt: _time(j['completed_at']),
    );
  }
}

/// `GET /welcome-bonus/me`.
@immutable
class WelcomeBonus {
  const WelcomeBonus({
    required this.grant,
    this.installments = const [],
    this.claimableNow = const WelcomeAmounts(),
    this.goldHeldForKyc = 0,
    this.nextDueAt,
    this.waitingForFirstMatch = false,
    this.freeSpin,
  });
  final WelcomeGrant grant;
  final List<WelcomeInstallment> installments;
  final WelcomeAmounts claimableNow;
  final int goldHeldForKyc;
  final DateTime? nextDueAt;
  final bool waitingForFirstMatch;
  final BonusGameOffer? freeSpin;

  bool get isLive => grant.status == 'pending' || grant.status == 'partial';
  bool get spinAvailable => freeSpin?.available ?? false;

  /// Red dot rule: something claimable now, or the free spin.
  bool get claimable => (isLive && !claimableNow.isEmpty) || spinAvailable;

  /// Show the welcome sheet (after sign-up / guest create).
  bool get showSheet => claimable;

  /// Every part paid and the spin used (or none): hide the entry for good.
  bool get finished => grant.status == 'completed' && !spinAvailable;

  factory WelcomeBonus.fromJson(Map<String, dynamic> j) => WelcomeBonus(
    grant: WelcomeGrant.fromJson(j['grant']),
    installments: [for (final i in _list(j['installments'])) WelcomeInstallment.fromJson(i)],
    claimableNow: WelcomeAmounts.fromJson(j['claimable_now']),
    goldHeldForKyc: parseAmount(j['gold_held_for_kyc']),
    nextDueAt: _time(j['next_due_at']),
    waitingForFirstMatch: j['waiting_for_first_match'] == true,
    freeSpin: BonusGameOffer.fromJson(j['free_spin']),
  );
}

/// `POST /welcome-bonus/claim`.
@immutable
class WelcomeClaim {
  const WelcomeClaim({
    required this.grantId,
    required this.status,
    this.credited = const WelcomeAmounts(),
    this.powerUpId,
    this.nextDueAt,
    this.waitingForFirstMatch = false,
    this.balances,
  });
  final int grantId;
  final String status;
  final WelcomeAmounts credited;
  final int? powerUpId;
  final DateTime? nextDueAt;
  final bool waitingForFirstMatch;
  final RewardBalances? balances;

  factory WelcomeClaim.fromJson(Map<String, dynamic> j) => WelcomeClaim(
    grantId: parseAmount(j['grant_id']),
    status: _str(j['status']) ?? 'completed',
    credited: WelcomeAmounts.fromJson(j['credited']),
    powerUpId: _intOrNull(j['power_up_id']),
    nextDueAt: _time(j['next_due_at']),
    waitingForFirstMatch: j['waiting_for_first_match'] == true,
    balances: RewardBalances.fromJson(j['balances']),
  );
}

// ── 3. Quests ────────────────────────────────────────────────────────────

/// Quest scopes in tab order.
const questScopes = ['daily', 'weekly', 'onboarding', 'event'];

/// One row of `GET /sensitive/quests/active` (also nested in my-progress).
@immutable
class Quest {
  const Quest({
    required this.id,
    this.code = '',
    this.title = '',
    this.description,
    this.scope = 'daily',
    this.criteria = const {},
    this.rewardTokens = 0,
    this.rewardGold = 0,
    this.rewardPowerUpId,
    this.rewardPowerUpQty = 0,
    this.startsAt,
    this.endsAt,
  });
  final int id;
  final String code;
  final String title;
  final String? description;

  /// `daily` · `weekly` · `onboarding` · `event`.
  final String scope;
  final Map<String, dynamic> criteria;
  final int rewardTokens;
  final int rewardGold;
  final int? rewardPowerUpId;
  final int rewardPowerUpQty;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// The goal number: `criteria.count` or `criteria.distinct_games`, default 1.
  int get target {
    final n = parseAmount(criteria['count'] ?? criteria['distinct_games']);
    return n > 0 ? n : 1;
  }

  /// The game(s) this quest counts, for an icon / Play button.
  List<String> get games => [
    if (criteria['game'] is String) criteria['game'] as String,
    for (final g in _list(criteria['games'])) if (g is String) g,
  ];

  factory Quest.fromJson(Object? v) {
    final j = _map(v);
    return Quest(
      id: parseAmount(j['id']),
      code: _str(j['code']) ?? '',
      title: _str(j['title']) ?? '',
      description: _str(j['description']),
      scope: _str(j['scope']) ?? 'daily',
      criteria: _map(j['criteria']),
      rewardTokens: parseAmount(j['reward_tokens']),
      rewardGold: parseAmount(j['reward_gold']),
      rewardPowerUpId: _intOrNull(j['reward_powerup_id']),
      rewardPowerUpQty: parseAmount(j['reward_powerup_qty']),
      startsAt: _time(j['starts_at']),
      endsAt: _time(j['ends_at']),
    );
  }
}

/// One row of `GET /sensitive/quests/my-progress` (one quest, one period).
@immutable
class QuestProgress {
  const QuestProgress({
    required this.quest,
    required this.periodStart,
    this.count = 0,
    this.games = const [],
    this.target = 1,
    this.status = 'in_progress',
    this.completedAt,
    this.claimedAt,
  });
  final Quest quest;

  /// `YYYY-MM-DD`; compares correctly as a string.
  final String periodStart;
  final int count;
  final List<String> games;
  final int target;

  /// `in_progress` · `completed` (claimable) · `claimed` · `expired`.
  final String status;
  final DateTime? completedAt;
  final DateTime? claimedAt;

  /// `count`, or the number of different games for a distinct-games quest.
  int get current => games.isNotEmpty ? games.length : count;

  factory QuestProgress.fromJson(Object? v) {
    final j = _map(v);
    final quest = Quest.fromJson(j['quest']);
    final p = _map(j['progress']);
    final target = parseAmount(p['target']);
    return QuestProgress(
      quest: quest,
      periodStart: _str(j['period_start']) ?? '',
      count: parseAmount(p['count']),
      games: [for (final g in _list(p['games'])) '$g'],
      target: target > 0 ? target : quest.target,
      status: _str(j['status']) ?? 'in_progress',
      completedAt: _time(j['completed_at']),
      claimedAt: _time(j['claimed_at']),
    );
  }
}

/// An active quest merged with the player's progress (see [mergeQuests]).
@immutable
class QuestRow {
  const QuestRow({required this.quest, this.progress, this.olderClaimable = false});
  final Quest quest;

  /// The current period's row; null = no progress yet (`0 / target`).
  final QuestProgress? progress;

  /// An older period is completed and still unclaimed (Known issue 1): the
  /// claim route pays it, so the quest shows Claim.
  final bool olderClaimable;

  int get target => progress?.target ?? quest.target;
  int get current => (progress?.current ?? 0).clamp(0, target);
  double get fraction => target <= 0 ? 0 : current / target;
  String get status => progress?.status ?? 'in_progress';
  bool get claimable => status == 'completed' || olderClaimable;
  bool get claimed => status == 'claimed' && !olderClaimable;

  QuestRow markClaimed() => QuestRow(
    quest: quest,
    progress: progress == null
        ? null
        : QuestProgress(
            quest: progress!.quest,
            periodStart: progress!.periodStart,
            count: progress!.count,
            games: progress!.games,
            target: progress!.target,
            status: progress!.status == 'completed' ? 'claimed' : progress!.status,
            completedAt: progress!.completedAt,
            claimedAt: DateTime.now(),
          ),
  );
}

/// For each active quest, the row with the same quest id and the newest
/// period; no row → `0 / target`. An older completed, unclaimed period keeps
/// the quest claimable. Order: scope (daily, weekly, onboarding, event), then
/// the server's order.
List<QuestRow> mergeQuests(List<Quest> active, List<QuestProgress> mine) {
  final byQuest = <int, List<QuestProgress>>{};
  for (final p in mine) {
    (byQuest[p.quest.id] ??= []).add(p);
  }
  final rows = <QuestRow>[];
  for (final q in active) {
    final list = [...?byQuest[q.id]]..sort((a, b) => b.periodStart.compareTo(a.periodStart));
    final current = list.isEmpty ? null : list.first;
    final older = list.skip(1).any((p) => p.status == 'completed');
    rows.add(QuestRow(quest: q, progress: current, olderClaimable: older));
  }
  int rank(String s) {
    final i = questScopes.indexOf(s);
    return i < 0 ? questScopes.length : i;
  }

  final indexed = rows.asMap().entries.toList()
    ..sort((a, b) {
      final c = rank(a.value.quest.scope).compareTo(rank(b.value.quest.scope));
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

/// `POST /sensitive/quests/{id}/claim`.
@immutable
class QuestClaim {
  const QuestClaim({required this.questId, this.periodStart, this.tokens = 0, this.gold = 0, this.powerUpId, this.powerUpQty = 0});
  final int questId;
  final String? periodStart;
  final int tokens;
  final int gold;
  final int? powerUpId;
  final int powerUpQty;

  bool get paysMoney => tokens > 0 || gold > 0;

  factory QuestClaim.fromJson(Map<String, dynamic> j) => QuestClaim(
    questId: parseAmount(j['quest_id']),
    periodStart: _str(j['period_start']),
    tokens: parseAmount(j['tokens_awarded']),
    gold: parseAmount(j['gold_awarded']),
    powerUpId: _intOrNull(j['powerup_id']),
    powerUpQty: parseAmount(j['powerup_quantity']),
  );
}

// ── 4. Achievements ──────────────────────────────────────────────────────

/// Tiers in order.
const achievementTiers = ['bronze', 'silver', 'gold', 'royal'];

/// A tier's reward: `tokens` / `gold` (`amount`), `avatar` (`avatarId`) or
/// `title` (`name`).
@immutable
class TierReward {
  const TierReward({required this.kind, this.amount = 0, this.avatarId, this.name});
  final String kind;
  final int amount;
  final int? avatarId;
  final String? name;

  factory TierReward.fromJson(Object? v) {
    final j = _map(v);
    return TierReward(
      kind: _str(j['kind']) ?? '',
      amount: parseAmount(j['amount']),
      avatarId: _intOrNull(j['avatar_id']),
      name: _str(j['name']),
    );
  }
}

@immutable
class AchievementTier {
  const AchievementTier({required this.tier, required this.threshold, required this.reward});
  final String tier;
  final int threshold;
  final TierReward reward;

  factory AchievementTier.fromJson(Object? v) {
    final j = _map(v);
    return AchievementTier(
      tier: _str(j['tier']) ?? '',
      threshold: parseAmount(j['threshold']),
      reward: TierReward.fromJson(j['reward']),
    );
  }
}

/// One badge of `GET /achievements` (catalogue only) or `/achievements/my`
/// (with the player's state).
@immutable
class Achievement {
  const Achievement({
    required this.id,
    this.gameId,
    this.code = '',
    this.name = '',
    this.description,
    this.rewardTokens = 0,
    this.rewardGold = 0,
    this.expReward = 0,
    this.iconUrl,
    this.sortOrder = 0,
    this.tiers = const [],
    this.trigger,
    this.isSecret = false,
    this.progress = const {},
    this.completed = false,
    this.completedAt,
    this.claimedAt,
    this.progressValue,
    this.tierReached,
    this.claimedTiers = const [],
    this.titles = const [],
  });
  final int id;
  final int? gameId;
  final String code;
  final String name;
  final String? description;
  final int rewardTokens;
  final int rewardGold;
  final int expReward;

  /// A server path or null (draw a default badge).
  final String? iconUrl;
  final int sortOrder;
  final List<AchievementTier> tiers;
  final String? trigger;
  final bool isSecret;
  final Map<String, dynamic> progress;
  final bool completed;
  final DateTime? completedAt;
  final DateTime? claimedAt;
  final int? progressValue;
  final String? tierReached;
  final List<String> claimedTiers;
  final List<String> titles;

  bool get tiered => tiers.isNotEmpty;

  /// A secret badge not reached yet: show a locked mystery badge.
  bool get mystery => isSecret && !completed;

  /// Tiered: every tier from bronze up to [tierReached] not yet claimed.
  List<String> get claimableTiers {
    if (!tiered || tierReached == null) return const [];
    final reached = achievementTiers.indexOf(tierReached!);
    if (reached < 0) return const [];
    return [
      for (final t in tiers)
        if (achievementTiers.contains(t.tier) &&
            achievementTiers.indexOf(t.tier) <= reached &&
            !claimedTiers.contains(t.tier))
          t.tier,
    ];
  }

  /// Red dot rule: a flat badge completed and unclaimed, or a reached tier
  /// not yet claimed.
  bool get claimable => tiered ? claimableTiers.isNotEmpty : completed && claimedAt == null;

  /// Flat badge claimed, or every tier claimed.
  bool get fullyClaimed =>
      tiered ? tiers.every((t) => claimedTiers.contains(t.tier)) : claimedAt != null;

  /// Tiered: the first tier not reached yet (the bar's goal), or null.
  AchievementTier? get nextTier {
    final reached = tierReached == null ? -1 : achievementTiers.indexOf(tierReached!);
    for (final t in tiers) {
      if (achievementTiers.indexOf(t.tier) > reached) return t;
    }
    return null;
  }

  AchievementTier? tier(String name) {
    for (final t in tiers) {
      if (t.tier == name) return t;
    }
    return null;
  }

  Achievement copyClaimed({String? tier}) => Achievement(
    id: id,
    gameId: gameId,
    code: code,
    name: name,
    description: description,
    rewardTokens: rewardTokens,
    rewardGold: rewardGold,
    expReward: expReward,
    iconUrl: iconUrl,
    sortOrder: sortOrder,
    tiers: tiers,
    trigger: trigger,
    isSecret: isSecret,
    progress: progress,
    completed: completed,
    completedAt: completedAt,
    claimedAt: DateTime.now(),
    progressValue: progressValue,
    tierReached: tierReached,
    claimedTiers: tier == null ? claimedTiers : [...claimedTiers, tier],
    titles: titles,
  );

  factory Achievement.fromJson(Object? v) {
    final j = _map(v);
    return Achievement(
      id: parseAmount(j['id']),
      gameId: _intOrNull(j['game_id']),
      code: _str(j['code']) ?? '',
      name: _str(j['name']) ?? '',
      description: _str(j['description']),
      rewardTokens: parseAmount(j['reward_tokens']),
      rewardGold: parseAmount(j['reward_gold']),
      expReward: parseAmount(j['exp_reward']),
      iconUrl: _str(j['icon_url']),
      sortOrder: parseAmount(j['sort_order']),
      tiers: [for (final t in _list(j['tiers'])) AchievementTier.fromJson(t)],
      trigger: _str(j['trigger']),
      isSecret: j['is_secret'] == true,
      progress: _map(j['progress']),
      completed: j['completed'] == true,
      completedAt: _time(j['completed_at']),
      claimedAt: _time(j['claimed_at']),
      progressValue: _intOrNull(j['progress_value']),
      tierReached: _str(j['tier_reached']),
      claimedTiers: [for (final t in _list(j['claimed_tiers'])) '$t'],
      titles: [for (final t in _list(j['titles'])) '$t'],
    );
  }
}

/// `POST /achievements/{id}/claim[?tier=]`.
@immutable
class AchievementClaim {
  const AchievementClaim({required this.achievementId, this.tokens = 0, this.gold = 0, this.tier, this.avatarId, this.title});
  final int achievementId;
  final int tokens;
  final int gold;
  final String? tier;
  final int? avatarId;
  final String? title;

  bool get paysMoney => tokens > 0 || gold > 0;

  factory AchievementClaim.fromJson(Map<String, dynamic> j) => AchievementClaim(
    achievementId: parseAmount(j['achievement_id']),
    tokens: parseAmount(j['tokens_awarded']),
    gold: parseAmount(j['gold_awarded']),
    tier: _str(j['tier']),
    avatarId: _intOrNull(j['avatar_id']),
    title: _str(j['title']),
  );
}

// ── 5. Bonus games ───────────────────────────────────────────────────────

@immutable
class BonusPrize {
  const BonusPrize({required this.id, this.label = '', this.prizeType = 'none', this.amount = 0, this.rarity = 'common', this.oddsPct});
  final int id;
  final String label;

  /// `tokens` · `gold` · `powerup` · `mult` (x100) · `ruby` · `cosmetic` · `none`.
  final String prizeType;
  final int amount;

  /// `common` · `rare` · `epic` · `legendary`.
  final String rarity;

  /// Decimal string, null when the odds are hidden.
  final String? oddsPct;

  factory BonusPrize.fromJson(Object? v) {
    final j = _map(v);
    return BonusPrize(
      id: parseAmount(j['id']),
      label: _str(j['label']) ?? '',
      prizeType: _str(j['prize_type']) ?? 'none',
      amount: parseAmount(j['amount']),
      rarity: _str(j['rarity']) ?? 'common',
      oddsPct: _str(j['odds_pct']),
    );
  }
}

/// `me` in a bonus game: the player's limits.
@immutable
class BonusGameLimits {
  const BonusGameLimits({
    this.blockReason,
    this.playsToday = 0,
    this.playsLeftToday = 0,
    this.payoutTodayTokens = 0,
    this.dailyPayoutCapTokens = 0,
    this.cooldownUntil,
    this.pityOpensAfter,
    this.pityOpensSinceRare,
  });

  /// null = may play; else `cooldown` · `max_per_day` · `payout_cap` ·
  /// `global_cap` · `guest` · `paused` · `not_available`.
  final String? blockReason;
  final int playsToday;
  final int playsLeftToday;
  final int payoutTodayTokens;
  final int dailyPayoutCapTokens;
  final DateTime? cooldownUntil;
  final int? pityOpensAfter;
  final int? pityOpensSinceRare;

  /// Chests: opens left until a rare-or-better prize is guaranteed.
  int? get pityLeft =>
      pityOpensAfter == null ? null : (pityOpensAfter! - (pityOpensSinceRare ?? 0)).clamp(0, pityOpensAfter!);

  BonusGameLimits withPlaysLeft(int left) => BonusGameLimits(
    blockReason: left <= 0 ? 'max_per_day' : blockReason,
    playsToday: playsToday + 1,
    playsLeftToday: left,
    payoutTodayTokens: payoutTodayTokens,
    dailyPayoutCapTokens: dailyPayoutCapTokens,
    cooldownUntil: cooldownUntil,
    pityOpensAfter: pityOpensAfter,
    pityOpensSinceRare: pityOpensSinceRare,
  );

  factory BonusGameLimits.fromJson(Object? v) {
    final j = _map(v);
    final pity = _map(j['pity']);
    return BonusGameLimits(
      blockReason: _str(j['block_reason']),
      playsToday: parseAmount(j['plays_today']),
      playsLeftToday: parseAmount(j['plays_left_today']),
      payoutTodayTokens: parseAmount(j['payout_today_tokens']),
      dailyPayoutCapTokens: parseAmount(j['daily_payout_cap_tokens']),
      cooldownUntil: _time(j['cooldown_until']),
      pityOpensAfter: _intOrNull(pity['opens_after']),
      pityOpensSinceRare: _intOrNull(pity['opens_since_rare']),
    );
  }
}

/// `{kind, amount}`: `free` · `tokens` · `gold` · `rewarded_ad`.
@immutable
class BonusCost {
  const BonusCost({this.kind = 'free', this.amount = 0});
  final String kind;
  final int amount;
  bool get free => kind == 'free' || amount <= 0;

  factory BonusCost.fromJson(Object? v) {
    final j = _map(v);
    return BonusCost(kind: _str(j['kind']) ?? 'free', amount: parseAmount(j['amount']));
  }
}

/// `GET /bonus-games` item / `GET /bonus-games/{id or code}`.
@immutable
class BonusGame {
  const BonusGame({
    required this.id,
    required this.code,
    this.name = '',
    this.gameType = 'wheel',
    this.trigger = 'store',
    this.cost = const BonusCost(),
    this.cooldownHours = 0,
    this.maxPlaysPerDay = 0,
    this.slotCount = 0,
    this.showOdds = false,
    this.me = const BonusGameLimits(),
    this.prizes = const [],
  });
  final int id;
  final String code;
  final String name;

  /// `wheel` · `scratch` · `chest` · `flip` · `pick`.
  final String gameType;
  final String trigger;
  final BonusCost cost;
  final int cooldownHours;
  final int maxPlaysPerDay;
  final int slotCount;
  final bool showOdds;
  final BonusGameLimits me;

  /// In slot order.
  final List<BonusPrize> prizes;

  /// `rewarded_ad` cost or trigger, `streak_milestone`: refused by the server.
  bool get supported =>
      cost.kind != 'rewarded_ad' && trigger != 'rewarded_ad' && trigger != 'streak_milestone';

  /// The odds table is shown only when the server sends odds.
  bool get hasOdds => prizes.any((p) => p.oddsPct != null);

  /// Number of slots to draw ([slotCount], else the prize count).
  int get slots => slotCount > 0 ? slotCount : prizes.length;

  BonusGame withLimits(BonusGameLimits limits) => BonusGame(
    id: id,
    code: code,
    name: name,
    gameType: gameType,
    trigger: trigger,
    cost: cost,
    cooldownHours: cooldownHours,
    maxPlaysPerDay: maxPlaysPerDay,
    slotCount: slotCount,
    showOdds: showOdds,
    me: limits,
    prizes: prizes,
  );

  factory BonusGame.fromJson(Object? v) {
    final j = _map(v);
    return BonusGame(
      id: parseAmount(j['id']),
      code: _str(j['code']) ?? '${j['id']}',
      name: _str(j['name']) ?? '',
      gameType: _str(j['game_type']) ?? 'wheel',
      trigger: _str(j['trigger']) ?? 'store',
      cost: BonusCost.fromJson(j['cost']),
      cooldownHours: parseAmount(j['cooldown_hours']),
      maxPlaysPerDay: parseAmount(j['max_plays_per_day']),
      slotCount: parseAmount(j['slot_count']),
      showOdds: j['show_odds'] == true,
      me: BonusGameLimits.fromJson(j['me']),
      prizes: [for (final p in _list(j['prizes'])) BonusPrize.fromJson(p)],
    );
  }
}

/// A wheel the Wheel tab can spin: a server wheel-type bonus game with the
/// [trigger] (and [triggerRef]) its play goes out with. Free spins come from
/// an entitlement (the welcome `free_spin`, a spin-day daily claim); paid
/// spins are the `store` wheels.
@immutable
class WheelSpin {
  const WheelSpin({required this.game, required this.trigger, this.triggerRef, this.entitlement});
  final BonusGame game;
  final String trigger;
  final String? triggerRef;

  /// Tells one free entitlement from the next when [triggerRef] doesn't (the
  /// daily spin goes out without one): the claim time. Not sent.
  final String? entitlement;

  bool get free => trigger != 'store';

  /// Stable across refetches (the selected wheel stays selected), and new
  /// for each free entitlement.
  String get key => '${game.code}|$trigger|${triggerRef ?? ''}|${entitlement ?? ''}';
}

/// The prize in a play reply.
@immutable
class PlayPrize {
  const PlayPrize({
    required this.id,
    this.label = '',
    this.prizeType = 'none',
    this.rarity = 'common',
    this.baseAmount = 0,
    this.amount = 0,
    this.currency,
    this.powerUpId,
    this.avatarId,
    this.nextBonusMultiplier,
  });
  final int id;
  final String label;
  final String prizeType;
  final String rarity;
  final int baseAmount;

  /// What was paid (show this, not [baseAmount]).
  final int amount;

  /// `token` · `gold` for money prizes (a guest's gold is paid as tokens).
  final String? currency;
  final int? powerUpId;
  final int? avatarId;

  /// A `mult` prize: the next daily bonus multiplier (decimal string).
  final String? nextBonusMultiplier;

  bool get isNothing => prizeType == 'none' || (amount <= 0 && prizeType != 'cosmetic');

  factory PlayPrize.fromJson(Object? v) {
    final j = _map(v);
    return PlayPrize(
      id: parseAmount(j['id']),
      label: _str(j['label']) ?? '',
      prizeType: _str(j['prize_type']) ?? 'none',
      rarity: _str(j['rarity']) ?? 'common',
      baseAmount: parseAmount(j['base_amount']),
      amount: parseAmount(j['amount']),
      currency: _str(j['currency']),
      powerUpId: _intOrNull(j['power_up_id']),
      avatarId: _intOrNull(j['avatar_id']),
      nextBonusMultiplier: _str(j['next_bonus_multiplier']),
    );
  }
}

/// `POST /bonus-games/{id or code}/play` (201).
@immutable
class BonusPlayResult {
  const BonusPlayResult({
    required this.playId,
    required this.bonusGameId,
    required this.code,
    required this.prize,
    required this.slotIndex,
    this.multiplierApplied = '1',
    this.prizeTokenValue = 0,
    this.pityTriggered = false,
    this.cost = const BonusCost(),
    this.balances,
    this.serverSeedHash,
    this.serverSeed,
    this.roll,
    this.playsLeftToday = 0,
    this.playedAt,
  });
  final int playId;
  final int bonusGameId;
  final String code;
  final PlayPrize prize;

  /// The slice / cell / card to land on (0-based).
  final int slotIndex;
  final String multiplierApplied;
  final int prizeTokenValue;
  final bool pityTriggered;
  final BonusCost cost;
  final RewardBalances? balances;
  final String? serverSeedHash;
  final String? serverSeed;
  final String? roll;
  final int playsLeftToday;
  final DateTime? playedAt;

  factory BonusPlayResult.fromJson(Map<String, dynamic> j) => BonusPlayResult(
    playId: parseAmount(j['play_id']),
    bonusGameId: parseAmount(j['bonus_game_id']),
    code: _str(j['code']) ?? '',
    prize: PlayPrize.fromJson(j['prize']),
    slotIndex: parseAmount(j['slot_index']),
    multiplierApplied: _str(j['multiplier_applied']) ?? '1',
    prizeTokenValue: parseAmount(j['prize_token_value']),
    pityTriggered: j['pity_triggered'] == true,
    cost: BonusCost.fromJson(j['cost']),
    balances: RewardBalances.fromJson(j['balances']),
    serverSeedHash: _str(j['server_seed_hash']),
    serverSeed: _str(j['server_seed']),
    roll: _str(j['roll']),
    playsLeftToday: parseAmount(j['plays_left_today']),
    playedAt: _time(j['played_at']),
  );
}

/// One row of `GET /bonus-games/plays/me` (prize history).
@immutable
class BonusPlayRecord {
  const BonusPlayRecord({
    required this.id,
    this.code = '',
    this.name = '',
    this.trigger = '',
    this.costCurrency,
    this.costAmount = 0,
    this.prizeLabel = '',
    this.prizeType = 'none',
    this.prizeAmount = 0,
    this.rarity = 'common',
    this.playedAt,
  });
  final int id;
  final String code;
  final String name;
  final String trigger;
  final String? costCurrency;
  final int costAmount;
  final String prizeLabel;
  final String prizeType;
  final int prizeAmount;
  final String rarity;
  final DateTime? playedAt;

  factory BonusPlayRecord.fromJson(Object? v) {
    final j = _map(v);
    return BonusPlayRecord(
      id: parseAmount(j['id']),
      code: _str(j['code']) ?? '',
      name: _str(j['name']) ?? '',
      trigger: _str(j['trigger']) ?? '',
      costCurrency: _str(j['cost_currency']),
      costAmount: parseAmount(j['cost_amount']),
      prizeLabel: _str(j['prize_label']) ?? '',
      prizeType: _str(j['prize_type']) ?? 'none',
      prizeAmount: parseAmount(j['prize_amount']),
      rarity: _str(j['rarity']) ?? 'common',
      playedAt: _time(j['played_at']),
    );
  }
}

/// A cursor page (shape 3 in 00-conventions.md).
@immutable
class CursorPage<T> {
  const CursorPage({required this.items, this.total = 0, this.nextCursor});
  final List<T> items;
  final int total;

  /// Pass back as `?after=`; null = last page.
  final String? nextCursor;

  factory CursorPage.fromJson(Object? v, T Function(Object?) item) {
    final j = _map(v);
    return CursorPage(
      items: [for (final i in _list(j['items'])) item(i)],
      total: parseAmount(j['total']),
      nextCursor: _str(j['next_cursor']),
    );
  }
}

// ── Red dot ──────────────────────────────────────────────────────────────

/// Red dot state per section ("Red dot rules").
@immutable
class RewardsBadge {
  const RewardsBadge({this.welcome = false, this.daily = false, this.quests = false, this.achievements = false});
  final bool welcome;
  final bool daily;
  final bool quests;
  final bool achievements;

  bool get any => welcome || daily || quests || achievements;

  /// Computes the dot from whatever is loaded (null = not loaded / failed).
  factory RewardsBadge.from({
    WelcomeBonus? welcome,
    bool? dailyCanClaim,
    List<QuestRow>? quests,
    List<Achievement>? achievements,
  }) => RewardsBadge(
    welcome: welcome?.claimable ?? false,
    daily: dailyCanClaim ?? false,
    quests: quests?.any((q) => q.claimable) ?? false,
    achievements: achievements?.any((a) => a.claimable) ?? false,
  );
}
