import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/endpoints/api_endpoints.dart';
import '../configs/feature_flags.dart';
import '../data/models/rewards.dart';
import '../data/models/wallet.dart';
import 'api_client.dart';
import 'app_exception.dart';
import 'session.dart';
import 'token_store.dart';
import 'wallet_store.dart';
import 'server_clock.dart';

/// Rewards routes (docs/services/07-rewards.md): welcome bonus, quests,
/// achievements and bonus games. The daily bonus keeps its own source
/// (`lib/data/sources/daily_bonus_source.dart`, same contract §2).
///
/// Every method returns a typed result or throws [AppException]; map a
/// failure to player text with the `*Issue` functions below.
abstract class RewardsApi {
  /// GET /welcome-bonus/me — null when the account has no grant (404).
  Future<WelcomeBonus?> welcomeBonus();

  /// POST /welcome-bonus/claim (device check). Registers the device and
  /// retries once on `conflict: device_required`.
  Future<WelcomeClaim> claimWelcome();

  /// GET /sensitive/quests/active.
  Future<List<Quest>> activeQuests();

  /// GET /sensitive/quests/my-progress (one row per quest and period).
  Future<List<QuestProgress>> myQuestProgress();

  /// POST /sensitive/quests/{id}/claim — the newest completed, unclaimed period.
  Future<QuestClaim> claimQuest(int questId);

  /// GET /achievements[?game_id=] — the catalogue without player state.
  Future<List<Achievement>> achievements({int? gameId});

  /// GET /achievements/my — every active badge with the player's state.
  Future<List<Achievement>> myAchievements();

  /// POST /achievements/{id}/claim[?tier=] — [tier] for a tiered badge.
  Future<AchievementClaim> claimAchievement(int id, {String? tier});

  /// GET /bonus-games[?trigger=].
  Future<List<BonusGame>> bonusGames({String? trigger});

  /// GET /bonus-games/{id or code}.
  Future<BonusGame> bonusGame(String idOrCode);

  /// POST /bonus-games/{id or code}/play (201, device check). The server
  /// draws the prize; the app only animates `slot_index`.
  Future<BonusPlayResult> playBonusGame(String idOrCode, {required String trigger, String? triggerRef});

  /// GET /bonus-games/plays/me — newest first, cursor list.
  Future<CursorPage<BonusPlayRecord>> myBonusPlays({int? per, String? after});
}

Map<String, dynamic> _obj(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
List<Object?> _arr(Object? v) => v is List ? v : (v is Map && v['data'] is List ? v['data'] as List : const []);

/// The live gateway.
class RemoteRewardsApi implements RewardsApi {
  RemoteRewardsApi(this._api, {this.deviceId});
  final ApiClient _api;

  /// This install's device id, for the `device_required` fallback.
  final Future<String> Function()? deviceId;

  @override
  Future<WelcomeBonus?> welcomeBonus() async {
    try {
      return WelcomeBonus.fromJson(_obj(await _api.get(ApiEndpoints.welcomeBonusMe)));
    } on AppException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<WelcomeClaim> claimWelcome() async {
    try {
      return WelcomeClaim.fromJson(_obj(await _api.post(ApiEndpoints.welcomeBonusClaim)));
    } on AppException catch (e) {
      final id = deviceId;
      if (id == null || rewardConflict(e) != 'device_required') rethrow;
      // Sign-up went without a device_id: register this install, claim once more.
      await _api.post(ApiEndpoints.devicesRegister, body: {
        'device_id': await id(),
        'device_name': _deviceName(),
        'platform': _platform(),
      });
      return WelcomeClaim.fromJson(_obj(await _api.post(ApiEndpoints.welcomeBonusClaim)));
    }
  }

  static String _platform() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => 'ios',
      TargetPlatform.android => 'android',
      _ => 'web',
    };
  }

  static String _deviceName() => switch (_platform()) {
    'ios' => 'iPhone',
    'android' => 'Android phone',
    _ => 'Web browser',
  };

  @override
  Future<List<Quest>> activeQuests() async =>
      [for (final q in _arr(await _api.get(ApiEndpoints.questsActive))) Quest.fromJson(q)];

  @override
  Future<List<QuestProgress>> myQuestProgress() async =>
      [for (final p in _arr(await _api.get(ApiEndpoints.questsMyProgress))) QuestProgress.fromJson(p)];

  @override
  Future<QuestClaim> claimQuest(int questId) async =>
      QuestClaim.fromJson(_obj(await _api.post(ApiEndpoints.questClaim(questId))));

  @override
  Future<List<Achievement>> achievements({int? gameId}) async => [
    for (final a in _arr(await _api.get(ApiEndpoints.achievements, query: {'game_id': ?gameId})))
      Achievement.fromJson(a),
  ];

  @override
  Future<List<Achievement>> myAchievements() async =>
      [for (final a in _arr(await _api.get(ApiEndpoints.achievementsMy))) Achievement.fromJson(a)];

  @override
  Future<AchievementClaim> claimAchievement(int id, {String? tier}) async {
    final path = ApiEndpoints.achievementClaim(id);
    // ApiClient.post has no query parameter: the tier goes in the path.
    return AchievementClaim.fromJson(_obj(await _api.post(tier == null ? path : '$path?tier=$tier')));
  }

  @override
  Future<List<BonusGame>> bonusGames({String? trigger}) async => [
    for (final g in _arr(await _api.get(ApiEndpoints.bonusGames, query: {'trigger': ?trigger})))
      BonusGame.fromJson(g),
  ];

  @override
  Future<BonusGame> bonusGame(String idOrCode) async =>
      BonusGame.fromJson(await _api.get(ApiEndpoints.bonusGame(idOrCode)));

  @override
  Future<BonusPlayResult> playBonusGame(String idOrCode, {required String trigger, String? triggerRef}) async {
    final ref = triggerRef == null || triggerRef.isEmpty
        ? null
        : (triggerRef.length > 80 ? triggerRef.substring(0, 80) : triggerRef);
    return BonusPlayResult.fromJson(_obj(await _api.post(
      ApiEndpoints.bonusGamePlay(idOrCode),
      body: {'trigger': trigger, 'trigger_ref': ?ref},
    )));
  }

  @override
  Future<CursorPage<BonusPlayRecord>> myBonusPlays({int? per, String? after}) async => CursorPage.fromJson(
    await _api.get(ApiEndpoints.bonusGamePlaysMe, query: {'per': ?per, 'after': ?after}),
    BonusPlayRecord.fromJson,
  );
}

/// Live when signed in against the real API; the demo otherwise.
final rewardsApiProvider = Provider<RewardsApi>((ref) {
  final live = ref.watch(useRemoteAuthProvider) && ref.watch(sessionProvider.select((u) => u != null));
  if (!live) return DemoRewardsApi();
  final store = ref.watch(tokenStoreProvider);
  return RemoteRewardsApi(ref.watch(apiClientProvider), deviceId: store.deviceId);
});

// ── Wallet ───────────────────────────────────────────────────────────────

/// After a claim or play (07-rewards.md "How a reward reaches the wallet"):
/// show [balances] at once when the reply carries them (welcome claim, bonus
/// play); otherwise re-read GET /wallet/balance ([moneyMoved]).
/// Uses the 03-wallet [WalletStore].
void applyRewardToWallet(WidgetRef ref, {RewardBalances? balances, bool moneyMoved = true}) {
  final wallet = ref.read(walletProvider.notifier);
  if (balances != null) {
    wallet.applyBalance(WalletCurrency.token, balances.tokens);
    wallet.applyBalance(WalletCurrency.gold, balances.gold);
    return;
  }
  if (moneyMoved) wallet.moneyMoved();
}

// ── Errors → what the app does ───────────────────────────────────────────

/// The stable code at the start of a rewards `409 CONFLICT` message
/// (`conflict: completed: …` → `completed`, `conflict: blocked: device_dupe`
/// → `blocked: device_dupe`), or null. Only the welcome claim and the bonus
/// game play document these; elsewhere the message is never read except for
/// the documented quest / achievement messages.
String? rewardConflict(AppException e) {
  if (e.statusCode != 409 || e.code != ApiErrorCode.conflict) return null;
  var m = (e.detail ?? '').trim();
  if (!m.startsWith('conflict:')) return null;
  m = m.substring('conflict:'.length).trim();
  if (m.startsWith('blocked:')) {
    final code = m.substring('blocked:'.length).trim().split(RegExp(r'[\s:]')).first;
    return 'blocked: $code';
  }
  return m.split(RegExp(r'[\s:]')).first;
}

bool _detail(AppException e, String text) => (e.detail ?? '').contains(text);

/// What a failed rewards call means for the screen.
enum RewardIssueKind {
  /// Already done (a second claim): update the row quietly.
  alreadyDone,

  /// Show [RewardIssue.text] and keep the screen.
  message,

  /// The thing is gone or not offered: show the text, then close / refetch.
  gone,

  /// Not enough tokens: offer the shop.
  notEnoughFunds,

  /// The session ended (the client signs out): show the text.
  signIn,
}

@immutable
class RewardIssue {
  const RewardIssue(this.kind, [this.text]);
  final RewardIssueKind kind;

  /// Player-facing text; null = no message.
  final String? text;

  @override
  String toString() => 'RewardIssue($kind, $text)';
}

const _generic = 'Something went wrong. Try again.';
const _notYet = 'Not unlocked yet.';
const _finishFirst = 'Finish the quest first.';
const _unavailable = 'Not available right now.';

/// Shared rules (401, 429, 5xx, offline, kill switch) or null.
RewardIssue? _common(AppException e) {
  if (e.isOffline || e.kind == AppErrorKind.timeout) return RewardIssue(RewardIssueKind.message, e.message);
  if (e.statusCode == 401) return RewardIssue(RewardIssueKind.signIn, e.message);
  if (e.isKillSwitch) return RewardIssue(RewardIssueKind.message, e.message);
  if (e.statusCode == 429) return const RewardIssue(RewardIssueKind.message, 'Too many requests. Wait a moment and try again.');
  if ((e.statusCode ?? 0) >= 500) return const RewardIssue(RewardIssueKind.message, _generic);
  return null;
}

/// "5h 12m" / "12m" / "less than a minute" until [at].
String rewardCountdown(DateTime at, {DateTime? now}) {
  final d = at.difference(now ?? ServerClock.now());
  if (d.inMinutes < 1) return 'less than a minute';
  final days = d.inDays, h = d.inHours % 24, m = d.inMinutes % 60;
  if (days > 0) return '${days}d ${h}h';
  return d.inHours > 0 ? '${d.inHours}h ${m}m' : '${m}m';
}

/// Welcome claim (§1b). [nextDueAt] from the last `me` for `nothing_due`.
RewardIssue welcomeClaimIssue(AppException e, {DateTime? nextDueAt}) {
  final common = _common(e);
  if (common != null) return common;
  if (e.statusCode == 404) return const RewardIssue(RewardIssueKind.gone);
  final c = rewardConflict(e);
  return switch (c) {
    'completed' => const RewardIssue(RewardIssueKind.alreadyDone),
    'nothing_due' => RewardIssue(
      RewardIssueKind.message,
      nextDueAt == null ? 'The next part unlocks soon.' : 'The next part unlocks in ${rewardCountdown(nextDueAt)}.',
    ),
    'expired' => const RewardIssue(RewardIssueKind.gone, 'This welcome bonus has expired.'),
    'blocked: device_dupe' => const RewardIssue(RewardIssueKind.gone, 'This device already received a welcome bonus.'),
    'blocked: guest_policy' || 'blocked: disabled' =>
      const RewardIssue(RewardIssueKind.gone, "The welcome bonus isn't available for this account."),
    'device_required' => const RewardIssue(RewardIssueKind.message, _generic),
    _ when c != null && c.startsWith('blocked:') =>
      const RewardIssue(RewardIssueKind.gone, "The welcome bonus isn't available for this account."),
    _ => const RewardIssue(RewardIssueKind.message, _generic),
  };
}

/// Daily bonus claim (§2b).
RewardIssue dailyClaimIssue(AppException e) {
  final common = _common(e);
  if (common != null) return common;
  return switch (e.statusCode) {
    409 => const RewardIssue(RewardIssueKind.alreadyDone),
    403 => const RewardIssue(RewardIssueKind.message, 'Create an account to collect daily rewards.'),
    404 => const RewardIssue(RewardIssueKind.message, "Daily bonus isn't available right now."),
    _ => const RewardIssue(RewardIssueKind.message, _generic),
  };
}

/// Quest claim (§3c).
RewardIssue questClaimIssue(AppException e) {
  final common = _common(e);
  if (common != null) return common;
  if (e.statusCode == 409) return const RewardIssue(RewardIssueKind.alreadyDone);
  if (e.statusCode == 400) {
    if (_detail(e, 'expired')) return const RewardIssue(RewardIssueKind.gone, 'This quest has ended.');
    return const RewardIssue(RewardIssueKind.message, _finishFirst);
  }
  if (e.statusCode == 404) {
    if (_detail(e, 'progress')) return const RewardIssue(RewardIssueKind.message, _finishFirst);
    return const RewardIssue(RewardIssueKind.gone);
  }
  return const RewardIssue(RewardIssueKind.message, _generic);
}

/// Achievement claim (§4c). The 400s other than "not reached" are app bugs:
/// a generic text.
RewardIssue achievementClaimIssue(AppException e) {
  final common = _common(e);
  if (common != null) return common;
  if (e.statusCode == 409) return const RewardIssue(RewardIssueKind.alreadyDone);
  if (e.statusCode == 400) {
    if (_detail(e, 'not unlocked') || _detail(e, 'not reached')) {
      return const RewardIssue(RewardIssueKind.message, _notYet);
    }
    return const RewardIssue(RewardIssueKind.message, _generic);
  }
  if (e.statusCode == 404) return const RewardIssue(RewardIssueKind.gone);
  return const RewardIssue(RewardIssueKind.message, _generic);
}

/// Bonus game play (§5c). [cooldownUntil] from the game's `me`.
RewardIssue bonusPlayIssue(AppException e, {DateTime? cooldownUntil}) {
  final common = _common(e);
  if (common != null) return common;
  if (e.code == ApiErrorCode.insufficientFunds) {
    return const RewardIssue(RewardIssueKind.notEnoughFunds, 'Not enough tokens.');
  }
  if (e.statusCode == 404) return const RewardIssue(RewardIssueKind.gone, _unavailable);
  final c = rewardConflict(e);
  if (c != null) {
    if (c.startsWith('blocked:')) return blockedText(c.substring('blocked:'.length).trim(), cooldownUntil: cooldownUntil);
    if (c == 'no_entitlement') return const RewardIssue(RewardIssueKind.gone, "This free play isn't available.");
    return const RewardIssue(RewardIssueKind.gone, _unavailable); // unsupported, no_prizes, …
  }
  return const RewardIssue(RewardIssueKind.message, _generic);
}

/// Text for a bonus game `block_reason` (from `me` or a `blocked:` 409).
RewardIssue blockedText(String code, {DateTime? cooldownUntil}) => switch (code) {
  'cooldown' => RewardIssue(
    RewardIssueKind.message,
    cooldownUntil == null ? 'Come back later.' : 'Come back in ${rewardCountdown(cooldownUntil)}.',
  ),
  'max_per_day' || 'payout_cap' || 'global_cap' => const RewardIssue(RewardIssueKind.gone, 'No plays left today.'),
  'guest' => const RewardIssue(RewardIssueKind.gone, 'Create an account to play.'),
  _ => const RewardIssue(RewardIssueKind.gone, _unavailable),
};

// ── Demo ─────────────────────────────────────────────────────────────────

/// Signed-out demo: in-memory state shaped like the gateway's replies. The
/// "draws" are fixed sequences (no randomness), standing in for the server.
class DemoRewardsApi implements RewardsApi {
  DemoRewardsApi();

  bool _welcomeClaimed = false;
  bool _spinUsed = false;
  int _tokens = 5000, _gold = 2000;
  int _draw = 0;
  final _claimedQuests = <int>{};
  final _claimedFlat = <int>{};
  final _claimedTiers = <int, List<String>>{};
  final _plays = <BonusPlayRecord>[];

  static AppException _err(int status, String code, String detail) =>
      AppException(ApiClient.messageFor(kind: AppErrorKind.unknown, status: status, code: code), statusCode: status, code: code, detail: detail);

  @override
  Future<WelcomeBonus?> welcomeBonus() async => WelcomeBonus.fromJson({
    'grant': {
      'id': 1,
      'status': _welcomeClaimed ? 'completed' : 'pending',
      'tokens_total': 500,
      'gold_total': 0,
      'delivery': 'once',
      'expires_at': DateTime.now().add(const Duration(hours: 71)).toUtc().toIso8601String(),
    },
    'claimable_now': {'tokens': _welcomeClaimed ? 0 : 500, 'gold': 0, 'power_up_qty': 0},
    'free_spin': {
      'bonus_game_id': 1,
      'code': 'welcome_wheel',
      'available': !_spinUsed,
      'block_reason': _spinUsed ? 'used' : null,
      'trigger': 'welcome_bonus',
      'trigger_ref': '1',
    },
  });

  @override
  Future<WelcomeClaim> claimWelcome() async {
    if (_welcomeClaimed) throw _err(409, 'CONFLICT', 'conflict: completed: the welcome bonus is fully paid');
    _welcomeClaimed = true;
    _tokens += 500;
    return WelcomeClaim.fromJson({
      'grant_id': 1,
      'status': 'completed',
      'credited': {'tokens': 500, 'gold': 0, 'power_up_qty': 0},
      'balances': {'tokens': _tokens, 'gold': _gold},
    });
  }

  static final _quests = [
    {'id': 1, 'code': 'daily_play_any', 'title': 'Warm-up', 'description': 'Play 1 match in any game', 'scope': 'daily', 'criteria': {'count': 1, 'event': 'match_started'}, 'reward_tokens': '50', 'reward_gold': '0'},
    {'id': 2, 'code': 'daily_win_one', 'title': 'First blood', 'description': 'Win 1 match today', 'scope': 'daily', 'criteria': {'count': 1, 'event': 'match_won'}, 'reward_tokens': '100', 'reward_gold': '0'},
    {'id': 3, 'code': 'daily_two_games', 'title': 'Sampler', 'description': 'Play 2 different games', 'scope': 'daily', 'criteria': {'distinct_games': 2, 'event': 'match_started'}, 'reward_tokens': '150', 'reward_gold': '0'},
    {'id': 4, 'code': 'weekly_win_streak', 'title': 'On a roll', 'description': 'Win 10 matches this week', 'scope': 'weekly', 'criteria': {'count': 10, 'event': 'match_won'}, 'reward_tokens': '500', 'reward_gold': '0'},
    {'id': 5, 'code': 'onboarding_first_5', 'title': 'Getting started', 'description': 'Play your first 5 matches', 'scope': 'onboarding', 'criteria': {'count': 5, 'event': 'match_started', 'lifetime': true}, 'reward_tokens': '200', 'reward_gold': '0'},
  ];

  @override
  Future<List<Quest>> activeQuests() async => [for (final q in _quests) Quest.fromJson(q)];

  @override
  Future<List<QuestProgress>> myQuestProgress() async {
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    Map<String, Object?> row(int i, Map<String, Object?> progress, bool done) => {
      'quest': _quests[i],
      'period_start': i == 4 ? '2000-01-01' : today,
      'progress': progress,
      'status': done ? (_claimedQuests.contains(_quests[i]['id']) ? 'claimed' : 'completed') : 'in_progress',
      'completed': done,
    };
    return [
      QuestProgress.fromJson(row(0, {'count': 1, 'target': 1}, true)),
      QuestProgress.fromJson(row(2, {'games': ['ludo'], 'target': 2}, false)),
      QuestProgress.fromJson(row(3, {'count': 3, 'target': 10}, false)),
      QuestProgress.fromJson(row(4, {'count': 1, 'target': 5}, false)),
    ];
  }

  @override
  Future<QuestClaim> claimQuest(int questId) async {
    if (questId != 1) throw _err(400, 'BAD_REQUEST', 'bad request: quest not yet completed');
    if (!_claimedQuests.add(questId)) throw _err(409, 'CONFLICT', 'conflict: quest reward already claimed');
    _tokens += 50;
    return QuestClaim.fromJson({'quest_id': 1, 'period_start': '', 'tokens_awarded': '50', 'gold_awarded': '0'});
  }

  static final _achievements = [
    {'id': 15, 'game_id': 1, 'code': 'ludo_first_win', 'name': 'First Win', 'description': 'Win your first Ludo match.', 'reward_tokens': 0, 'reward_gold': 0, 'exp_reward': 10, 'tiers': [], 'is_secret': false, 'completed': true},
    {'id': 16, 'game_id': 1, 'code': 'ludo_capture', 'name': 'Hunter', 'description': 'Capture 50 tokens in Ludo.', 'reward_tokens': 100, 'reward_gold': 0, 'exp_reward': 20, 'tiers': [], 'is_secret': false, 'completed': false},
    {'id': 230, 'game_id': 25, 'code': 'sl_dice_roller', 'name': 'Dice Roller', 'description': 'Matches played', 'reward_tokens': 0, 'reward_gold': 0, 'exp_reward': 0, 'trigger': 'matches_played', 'is_secret': false, 'completed': true, 'progress_value': 12, 'tier_reached': 'bronze', 'tiers': [
      {'tier': 'bronze', 'threshold': 10, 'reward': {'kind': 'tokens', 'amount': 50}},
      {'tier': 'silver', 'threshold': 100, 'reward': {'kind': 'tokens', 'amount': 250}},
      {'tier': 'gold', 'threshold': 1000, 'reward': {'kind': 'gold', 'amount': 500}},
      {'tier': 'royal', 'threshold': 10000, 'reward': {'kind': 'title', 'name': 'Dice Roller'}},
    ]},
    {'id': 234, 'game_id': 25, 'code': 'sl_phoenix', 'name': 'Secret achievement', 'description': null, 'reward_tokens': 0, 'reward_gold': 0, 'exp_reward': 0, 'trigger': 'game_event', 'is_secret': true, 'completed': false, 'tiers': [
      {'tier': 'bronze', 'threshold': 1, 'reward': {'kind': 'tokens', 'amount': 200}},
    ]},
  ];

  @override
  Future<List<Achievement>> achievements({int? gameId}) async => [
    for (final a in _achievements)
      if (gameId == null || a['game_id'] == gameId) Achievement.fromJson({...a, 'completed': false, 'tier_reached': null, 'progress_value': null}),
  ];

  @override
  Future<List<Achievement>> myAchievements() async => [
    for (final a in _achievements)
      Achievement.fromJson({
        ...a,
        'claimed_at': _claimedFlat.contains(a['id']) || (_claimedTiers[a['id']]?.isNotEmpty ?? false) ? DateTime.now().toIso8601String() : null,
        'claimed_tiers': _claimedTiers[a['id']] ?? const <String>[],
      }),
  ];

  @override
  Future<AchievementClaim> claimAchievement(int id, {String? tier}) async {
    final a = (await myAchievements()).where((x) => x.id == id).firstOrNull;
    if (a == null) throw _err(404, 'NOT_FOUND', 'not found: achievement $id');
    if (a.tiered) {
      if (tier == null) throw _err(400, 'BAD_REQUEST', 'bad request: tier is required for a tiered achievement');
      if (!a.claimableTiers.contains(tier)) {
        if (a.claimedTiers.contains(tier)) throw _err(409, 'CONFLICT', 'conflict: $tier tier already claimed');
        throw _err(400, 'BAD_REQUEST', 'bad request: $tier tier not reached yet');
      }
      (_claimedTiers[id] ??= []).add(tier);
      final r = a.tier(tier)!.reward;
      if (r.kind == 'tokens') _tokens += r.amount;
      if (r.kind == 'gold') _gold += r.amount;
      return AchievementClaim(
        achievementId: id,
        tier: tier,
        tokens: r.kind == 'tokens' ? r.amount : 0,
        gold: r.kind == 'gold' ? r.amount : 0,
        avatarId: r.avatarId,
        title: r.kind == 'title' ? r.name : null,
      );
    }
    if (!a.completed) throw _err(400, 'BAD_REQUEST', 'bad request: achievement not unlocked yet');
    if (!_claimedFlat.add(id)) throw _err(409, 'CONFLICT', 'conflict: achievement already claimed');
    _tokens += a.rewardTokens;
    _gold += a.rewardGold;
    return AchievementClaim(achievementId: id, tokens: a.rewardTokens, gold: a.rewardGold);
  }

  static Map<String, Object?> _prize(int id, String label, String type, int amount, String rarity, String odds) =>
      {'id': id, 'label': label, 'prize_type': type, 'amount': amount, 'rarity': rarity, 'odds_pct': odds};

  final Map<String, int> _playsToday = {};

  Map<String, Object?> _game(String code) {
    final (id, name, type, trigger, cost, max, prizes) = switch (code) {
      'welcome_wheel' || '1' => (1, 'Welcome wheel', 'wheel', 'welcome_bonus', {'kind': 'free', 'amount': 0}, 1, [
        _prize(8, '50 tokens', 'tokens', 50, 'common', '30'),
        _prize(7, '100 tokens', 'tokens', 100, 'common', '25'),
        _prize(6, '250 tokens', 'tokens', 250, 'common', '15'),
        _prize(5, '10 gold', 'gold', 10, 'common', '12'),
        _prize(4, 'Shield ×1', 'powerup', 1, 'common', '10'),
        _prize(3, '500 tokens', 'tokens', 500, 'rare', '5'),
        _prize(2, '50 gold', 'gold', 50, 'epic', '2.50'),
        _prize(1, '2,000 tokens', 'tokens', 2000, 'legendary', '0.50'),
      ]),
      'daily_spin' || '2' => (2, 'Daily lucky spin', 'wheel', 'daily_bonus_day', {'kind': 'free', 'amount': 0}, 1, [
        _prize(9, '100 tokens', 'tokens', 100, 'common', '40'),
        _prize(10, 'x2 next bonus', 'mult', 200, 'rare', '20'),
        _prize(11, '25 gold', 'gold', 25, 'common', '30'),
        _prize(12, '1,000 tokens', 'tokens', 1000, 'epic', '10'),
      ]),
      'lucky_wheel' || '4' => (4, 'Lucky wheel', 'wheel', 'store', {'kind': 'tokens', 'amount': 100}, 10, [
        _prize(30, '50 tokens', 'tokens', 50, 'common', '30'),
        _prize(31, '20 gold', 'gold', 20, 'common', '20'),
        _prize(32, '150 tokens', 'tokens', 150, 'common', '18'),
        _prize(33, 'Try again', 'none', 0, 'common', '12'),
        _prize(34, '300 tokens', 'tokens', 300, 'rare', '10'),
        _prize(35, '100 gold', 'gold', 100, 'rare', '6'),
        _prize(36, '1,000 tokens', 'tokens', 1000, 'epic', '3.50'),
        _prize(37, '5,000 tokens', 'tokens', 5000, 'legendary', '0.50'),
      ]),
      _ => (3, 'Gold scratch card', 'scratch', 'store', {'kind': 'tokens', 'amount': 200}, 5, [
        _prize(25, 'No match', 'none', 0, 'common', '55'),
        _prize(23, '400 tokens', 'tokens', 400, 'common', '30'),
        _prize(22, '100 gold', 'gold', 100, 'rare', '10'),
        _prize(21, '1,000 tokens', 'tokens', 1000, 'epic', '4.80'),
        _prize(19, '5,000 gold', 'gold', 5000, 'legendary', '0.20'),
      ]),
    };
    final key = '$id';
    final played = _playsToday[key] ?? 0;
    return {
      'id': id,
      'code': switch (id) { 1 => 'welcome_wheel', 2 => 'daily_spin', 4 => 'lucky_wheel', _ => 'scratch_gold' },
      'name': name,
      'game_type': type,
      'trigger': trigger,
      'cost': cost,
      'max_plays_per_day': max,
      'slot_count': type == 'scratch' ? 9 : prizes.length,
      'show_odds': true,
      'me': {'block_reason': played >= max ? 'max_per_day' : null, 'plays_today': played, 'plays_left_today': max - played},
      'prizes': prizes,
    };
  }

  @override
  Future<List<BonusGame>> bonusGames({String? trigger}) async => [
    for (final c in ['welcome_wheel', 'daily_spin', 'scratch_gold', 'lucky_wheel'])
      if (trigger == null || _game(c)['trigger'] == trigger) BonusGame.fromJson(_game(c)),
  ];

  @override
  Future<BonusGame> bonusGame(String idOrCode) async => BonusGame.fromJson(_game(idOrCode));

  @override
  Future<BonusPlayResult> playBonusGame(String idOrCode, {required String trigger, String? triggerRef}) async {
    final g = BonusGame.fromJson(_game(idOrCode));
    if (trigger != g.trigger) throw _err(400, 'BAD_REQUEST', "bad request: trigger: this game is offered on '${g.trigger}'");
    if (g.me.blockReason != null) throw _err(409, 'CONFLICT', 'conflict: blocked: ${g.me.blockReason}');
    if (g.trigger == 'welcome_bonus' && _spinUsed) throw _err(409, 'CONFLICT', 'conflict: no_entitlement: the free spin was used');
    if (g.trigger == 'daily_bonus_day') throw _err(409, 'CONFLICT', 'conflict: no_entitlement: no daily bonus claim');
    if (!g.cost.free) {
      if (_tokens < g.cost.amount) throw _err(409, 'INSUFFICIENT_FUNDS', 'insufficient funds');
      _tokens -= g.cost.amount;
    }
    if (g.trigger == 'welcome_bonus') _spinUsed = true;
    _playsToday['${g.id}'] = (_playsToday['${g.id}'] ?? 0) + 1;
    final slot = (_draw++ * 3) % g.slots;
    final p = g.prizes[slot % g.prizes.length];
    if (p.prizeType == 'tokens') _tokens += p.amount;
    if (p.prizeType == 'gold') _gold += p.amount;
    _plays.insert(0, BonusPlayRecord(
      id: _plays.length + 1,
      code: g.code,
      name: g.name,
      trigger: g.trigger,
      costCurrency: g.cost.free ? null : 'token',
      costAmount: g.cost.amount,
      prizeLabel: p.label,
      prizeType: p.prizeType,
      prizeAmount: p.amount,
      rarity: p.rarity,
      playedAt: DateTime.now(),
    ));
    return BonusPlayResult(
      playId: _plays.length,
      bonusGameId: g.id,
      code: g.code,
      prize: PlayPrize(
        id: p.id,
        label: p.label,
        prizeType: p.prizeType,
        rarity: p.rarity,
        baseAmount: p.amount,
        amount: p.amount,
        currency: p.prizeType == 'tokens' ? 'token' : (p.prizeType == 'gold' ? 'gold' : null),
      ),
      slotIndex: slot,
      cost: g.cost,
      balances: RewardBalances(tokens: _tokens, gold: _gold),
      playsLeftToday: g.me.playsLeftToday - 1,
      playedAt: DateTime.now(),
    );
  }

  @override
  Future<CursorPage<BonusPlayRecord>> myBonusPlays({int? per, String? after}) async =>
      CursorPage(items: List.of(_plays), total: _plays.length);
}
