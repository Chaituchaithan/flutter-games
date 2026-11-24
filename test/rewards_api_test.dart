// The rewards contract (docs/services/07-rewards.md): RewardsApi requests and
// replies against a stand-in gateway, the model parsers with the doc's live
// samples, the quest merge, the red dot rules and each error's mapping.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/daily_bonus.dart';
import 'package:snakeladder/data/models/rewards.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/rewards_service.dart';

class _Req {
  _Req(this.method, this.path, this.query, this.body);
  final String method;
  final String path;
  final Map<String, String> query;
  final dynamic body;
}

typedef _Handler = FutureOr<(int, Object?)> Function(_Req);

class _Gateway implements HttpClientAdapter {
  _Gateway(this.routes);
  final Map<String, _Handler> routes;
  final List<_Req> log = [];

  int count(String route) => log.where((r) => '${r.method} ${r.path}' == route).length;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final req = _Req(o.method, o.uri.path.replaceFirst('/api/v1', ''), o.uri.queryParameters, o.data);
    log.add(req);
    final handler = routes['${req.method} ${req.path}'];
    final (status, json) = handler == null ? (404, {'error': 'NOT_FOUND', 'message': 'no route'}) : await handler(req);
    return ResponseBody.fromString(json == null ? '' : jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(_Gateway g) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1/', contentType: 'application/json'))..httpClientAdapter = g;
  return ApiClient(dio: dio)..authToken = 'acc';
}

(int, Object?) _err(int status, String code, String message, [Map<String, Object?> extra = const {}]) =>
    (status, {'error': code, 'message': message, ...extra});

Map<String, dynamic> _j(String s) => (jsonDecode(s) as Map).cast<String, dynamic>();

// ── Live samples from the doc ──────────────────────────────────────────

const _welcomeMe = '''
{"grant":{"id":634,"status":"pending","blocked_reason":null,"entry_game":"ludo","source":"direct","tier_at_signup":"free","was_guest":false,"source_multiplier":"1.00","tier_multiplier":"1.00","tokens_total":500,"gold_total":0,"power_up_id":null,"power_up_qty":0,"delivery":"once","expires_at":"2026-11-27T09:21:02.321238Z","claimed_at":null,"completed_at":null,"created_at":"2026-11-24T09:21:02.294869Z"},
 "installments":[{"id":633,"seq":1,"due_at":"2026-11-24T09:21:02.321238Z","tokens":500,"gold":0,"power_up_qty":0,"credited_at":null,"token_ledger_id":null,"gold_ledger_id":null}],
 "claimable_now":{"tokens":500,"gold":0,"power_up_qty":0},"gold_held_for_kyc":0,"next_due_at":null,"waiting_for_first_match":false,
 "free_spin":{"bonus_game_id":1,"code":"welcome_wheel","play_id":null,"available":true,"block_reason":null,"trigger":"welcome_bonus","trigger_ref":"634"}}''';

const _welcomeBlocked = '''
{"grant":{"id":636,"status":"blocked","blocked_reason":"device_dupe","entry_game":null,"source":"direct","tier_at_signup":"free","was_guest":false,"source_multiplier":"1.00","tier_multiplier":"1.00","tokens_total":500,"gold_total":0},"installments":[],"claimable_now":{"tokens":0,"gold":0,"power_up_qty":0},"gold_held_for_kyc":0,"next_due_at":null,"waiting_for_first_match":false,"free_spin":{"bonus_game_id":1,"code":"welcome_wheel","play_id":null,"available":false,"block_reason":"grant_blocked","trigger":"welcome_bonus","trigger_ref":"636"}}''';

const _welcomeClaim = '''
{"grant_id":634,"status":"completed","credited":{"tokens":500,"gold":0,"power_up_qty":0},"power_up_id":null,"gold_held_for_kyc":0,"next_due_at":null,"waiting_for_first_match":false,"balances":{"tokens":600,"gold":500}}''';

const _dailyStatus = '''
{"current_streak":0,"can_claim":true,
 "next_reward":{"day_number":1,"reward_tokens":"0","reward_gold":"100","power_up_id":null,"power_up_quantity":0,"ruby_amount":0,"next_bonus_multiplier":null,"bonus_game_id":null,"label":null,"is_milestone":false,"is_enabled":true},
 "last_claimed_at":null,"next_claim_available_at":null,"total_claims":0,
 "rewards":[
  {"day_number":28,"reward_tokens":"0","reward_gold":"0","power_up_id":null,"power_up_quantity":0,"ruby_amount":0,"next_bonus_multiplier":null,"bonus_game_id":2,"label":"Week 4 reward","is_milestone":true,"is_enabled":true},
  {"day_number":1,"reward_tokens":"0","reward_gold":"100","power_up_id":null,"power_up_quantity":0,"ruby_amount":0,"next_bonus_multiplier":null,"bonus_game_id":null,"label":null,"is_milestone":false,"is_enabled":true},
  {"day_number":3,"reward_tokens":"0","reward_gold":"200","power_up_id":1,"power_up_quantity":1,"ruby_amount":0,"next_bonus_multiplier":null,"bonus_game_id":null,"label":null,"is_milestone":false,"is_enabled":true},
  {"day_number":15,"reward_tokens":"0","reward_gold":"125","power_up_id":null,"power_up_quantity":0,"ruby_amount":0,"next_bonus_multiplier":null,"bonus_game_id":null,"label":null,"is_milestone":false,"is_enabled":false},
  {"day_number":30,"reward_tokens":"0","reward_gold":"500","power_up_id":null,"power_up_quantity":0,"ruby_amount":0,"next_bonus_multiplier":null,"bonus_game_id":null,"label":null,"is_milestone":true,"is_enabled":true}
 ],"tier_multiplier":"1"}''';

const _active = '''
[{"id":1,"code":"daily_play_any","title":"Warm-up","description":"Play 1 match in any game","scope":"daily","criteria":{"count":1,"event":"match_started"},"reward_tokens":"50","reward_gold":"0","reward_powerup_id":null,"reward_powerup_qty":0,"min_user_level":1,"is_active":true,"starts_at":null,"ends_at":null},
 {"id":3,"code":"daily_two_games","title":"Sampler","description":"Play matches in 2 different games","scope":"daily","criteria":{"distinct_games":2,"event":"match_started"},"reward_tokens":"150","reward_gold":"0","reward_powerup_id":null,"reward_powerup_qty":0,"min_user_level":1,"is_active":true,"starts_at":null,"ends_at":null},
 {"id":4,"code":"weekly_win_streak","title":"On a roll","description":"Win 10 matches this week","scope":"weekly","criteria":{"count":10,"event":"match_won"},"reward_tokens":"500","reward_gold":"0","reward_powerup_id":null,"reward_powerup_qty":0,"min_user_level":1,"is_active":true,"starts_at":null,"ends_at":null},
 {"id":5,"code":"onboarding_first_5","title":"Getting started","description":"Play your first 5 matches","scope":"onboarding","criteria":{"count":5,"event":"match_started","lifetime":true},"reward_tokens":"200","reward_gold":"0","reward_powerup_id":null,"reward_powerup_qty":0,"min_user_level":1,"is_active":true,"starts_at":null,"ends_at":null}]''';

const _progress = '''
[{"quest":{"id":1,"code":"daily_play_any","title":"Warm-up","scope":"daily","criteria":{"count":1,"event":"match_started"},"reward_tokens":"50","reward_gold":"0"},"period_start":"2026-11-24","progress":{"count":1,"target":1},"status":"completed","completed":true,"completed_at":"2026-11-24T09:22:30.927267Z","claimed_at":null},
 {"quest":{"id":3,"code":"daily_two_games","title":"Sampler","scope":"daily","criteria":{"distinct_games":2,"event":"match_started"},"reward_tokens":"150","reward_gold":"0"},"period_start":"2026-11-24","progress":{"games":["ludo"],"target":2},"status":"in_progress","completed":false,"completed_at":null,"claimed_at":null},
 {"quest":{"id":4,"code":"weekly_win_streak","title":"On a roll","scope":"weekly","criteria":{"count":10,"event":"match_won"},"reward_tokens":"500","reward_gold":"0"},"period_start":"2026-11-24","progress":{"count":10,"target":10},"status":"claimed","completed":true,"completed_at":"2026-11-24T09:22:30Z","claimed_at":"2026-11-24T09:30:00Z"},
 {"quest":{"id":4,"code":"weekly_win_streak","title":"On a roll","scope":"weekly","criteria":{"count":10,"event":"match_won"},"reward_tokens":"500","reward_gold":"0"},"period_start":"2026-11-17","progress":{"count":10,"target":10},"status":"completed","completed":true,"completed_at":"2026-11-20T09:22:30Z","claimed_at":null}]''';

const _myAchievements = '''
[{"id":15,"game_id":1,"code":"ludo_first_win","name":"First Win","description":"Win your first Ludo match.","criteria":{"count":1,"event":"match_end","result":"win"},"reward_tokens":0,"reward_gold":0,"exp_reward":10,"icon_url":"/assets/achievements/ludo/first_win.svg","sort_order":0,"tiers":[],"trigger":null,"is_secret":false,
  "progress":{"count":1},"completed":true,"completed_at":"2026-11-24T09:22:30.927267Z","claimed_at":null,"progress_value":null,"tier_reached":null,"claimed_tiers":[],"titles":[]},
 {"id":234,"game_id":25,"code":"sl_phoenix","name":"Secret achievement","description":null,"criteria":{},"reward_tokens":0,"reward_gold":0,"exp_reward":0,"icon_url":null,"sort_order":8,"tiers":[
   {"tier":"bronze","threshold":1,"reward":{"kind":"tokens","amount":200}},
   {"tier":"royal","threshold":500,"reward":{"kind":"title","name":"Secret achievement"}}],"trigger":"game_event","is_secret":true,
  "progress":{},"completed":false,"completed_at":null,"claimed_at":null,"progress_value":null,"tier_reached":null,"claimed_tiers":[],"titles":[]},
 {"id":230,"game_id":25,"code":"sl_dice_roller","name":"Dice Roller","description":"Matches played","criteria":{"event":"match_end","game":"snake-and-ladder","measure":"count"},"reward_tokens":0,"reward_gold":0,"exp_reward":0,"icon_url":null,"sort_order":2,"tiers":[
   {"tier":"bronze","threshold":10,"reward":{"kind":"tokens","amount":50}},
   {"tier":"silver","threshold":100,"reward":{"kind":"tokens","amount":250}},
   {"tier":"gold","threshold":1000,"reward":{"kind":"gold","amount":500}},
   {"tier":"royal","threshold":10000,"reward":{"kind":"title","name":"Dice Roller"}}],"trigger":"matches_played","is_secret":false,
  "progress":{"value":150},"completed":true,"completed_at":"2026-11-24T09:22:30Z","claimed_at":"2026-11-24T09:25:00Z","progress_value":150,"tier_reached":"silver","claimed_tiers":["bronze"],"titles":[]}]''';

const _bonusList = '''
[{"id":3,"code":"scratch_gold","name":"Gold scratch card","game_type":"scratch","trigger":"store","cost":{"kind":"tokens","amount":200},"cooldown_hours":0,"max_plays_per_day":5,"slot_count":9,"show_odds":true,
  "me":{"block_reason":null,"plays_today":0,"plays_left_today":5,"payout_today_tokens":0,"daily_payout_cap_tokens":10000,"cooldown_until":null,"pity":null},
  "prizes":[{"id":25,"label":"No match","prize_type":"none","amount":0,"rarity":"common","odds_pct":"55"},{"id":19,"label":"5,000 gold","prize_type":"gold","amount":5000,"rarity":"legendary","odds_pct":"0.20"}]}]''';

const _play = '''
{"play_id":1,"bonus_game_id":1,"code":"welcome_wheel","prize":{"id":8,"label":"50 tokens","prize_type":"tokens","rarity":"common","base_amount":50,"amount":50,"currency":"token","power_up_id":null,"avatar_id":null,"next_bonus_multiplier":null},
 "slot_index":0,"multiplier_applied":"1","prize_token_value":50,"pity_triggered":false,"cost":{"kind":"free","amount":0},"balances":{"tokens":650,"gold":500},
 "server_seed_hash":"2798837fd7b62bc70b0d4121216a1ea4d6969b058edaec597d7f7dfa24b59946","server_seed":"431e4b5fd8329e3d28ee92505b0230a289b41700bf5ecba2f1d61265fe57ddf6","roll":"0.2541756","plays_left_today":0,"played_at":"2026-11-24T09:21:10.698406Z"}''';

const _plays = '''
{"items":[{"id":2,"bonus_game_id":3,"code":"scratch_gold","name":"Gold scratch card","trigger":"store","trigger_ref_table":null,"trigger_ref_id":null,"cost_currency":"token","cost_amount":200,"prize_id":23,"prize_label":"400 tokens","prize_type":"tokens","prize_amount":400,"prize_token_value":400,"rarity":"common","multiplier_applied":"1.00","pity_triggered":false,"server_seed_hash":"248a","roll":"0.77881988","cost_ledger_id":42035,"prize_ledger_id":42036,"played_at":"2026-11-24T09:21:12.229614Z"}],
 "page":1,"pages":1,"total":2,"next_cursor":"abc"}''';

AppException _ex(int status, String code, [String? detail]) =>
    AppException('x', statusCode: status, code: code, detail: detail);

void main() {
  group('models', () {
    test('welcome bonus: pending grant, claimable, free spin → sheet + red dot', () {
      final w = WelcomeBonus.fromJson(_j(_welcomeMe));
      expect(w.grant.id, 634);
      expect(w.grant.status, 'pending');
      expect(w.grant.entryGame, 'ludo');
      expect(w.grant.expiresAt, DateTime.parse('2026-11-27T09:21:02.321238Z'));
      expect(w.claimableNow.tokens, 500);
      expect(w.installments.single.dueAt, isNotNull);
      expect(w.freeSpin!.code, 'welcome_wheel');
      expect(w.freeSpin!.trigger, 'welcome_bonus');
      expect(w.freeSpin!.triggerRef, '634');
      expect(w.showSheet, isTrue);
      expect(w.claimable, isTrue);
      expect(w.finished, isFalse);
    });

    test('welcome bonus: a blocked grant shows no sheet and no dot', () {
      final w = WelcomeBonus.fromJson(_j(_welcomeBlocked));
      expect(w.grant.blockedReason, 'device_dupe');
      expect(w.freeSpin!.available, isFalse);
      expect(w.freeSpin!.blockReason, 'grant_blocked');
      expect(w.showSheet, isFalse);
      expect(w.claimable, isFalse);
    });

    test('welcome claim: credited + balances (numbers)', () {
      final c = WelcomeClaim.fromJson(_j(_welcomeClaim));
      expect(c.status, 'completed');
      expect(c.credited.tokens, 500);
      expect(c.balances!.tokens, 600);
      expect(c.balances!.gold, 500);
    });

    test('daily status: the 30-day calendar, sorted, string amounts, spin and disabled days', () {
      final s = DailyBonusStatus.fromJson(_j(_dailyStatus));
      expect(s.rewards.map((r) => r.dayNumber), [1, 3, 15, 28, 30]);
      expect(s.cycleLength, 30);
      expect(s.rewardFor(3)!.gold, 200);
      expect(s.rewardFor(3)!.powerUpQuantity, 1);
      expect(s.rewardFor(15)!.isEnabled, isFalse);
      final d28 = s.rewardFor(28)!;
      expect(d28.isSpinDay, isTrue);
      expect(d28.bonusGameId, 2);
      expect(d28.isMilestone, isTrue);
      expect(d28.title, 'Week 4 reward');
      expect(s.tierMultiplier, '1');
    });

    test('daily claim: plain day, then a spin day with its bonus game and a multiplier', () {
      final plain = DailyClaim.fromJson(_j(
          '{"granted":true,"tokens_awarded":"0","gold_awarded":"100","power_up_id":null,"power_up_quantity":0,"new_streak":1,"total_claims":1,"multiplier_applied":"1","tier_multiplier":"1","ruby_amount":0,"next_bonus_multiplier":null,"bonus_game_id":null,"label":null,"is_milestone":false,"bonus_game":null}'));
      expect(plain.gold, 100);
      expect(plain.granted, isTrue);
      expect(plain.bonusGame, isNull);
      expect(plain.boost, isNull);
      final spin = DailyClaim.fromJson(_j(
          '{"granted":false,"tokens_awarded":"0","gold_awarded":"0","new_streak":28,"multiplier_applied":"2","is_milestone":true,"label":"Week 4 reward","bonus_game":{"bonus_game_id":2,"code":"daily_spin","trigger":"daily_bonus_day","trigger_ref":"28"}}'));
      expect(spin.granted, isFalse);
      expect(spin.boost, 2);
      expect(spin.bonusGame!.code, 'daily_spin');
      expect(spin.bonusGame!.trigger, 'daily_bonus_day');
      expect(spin.bonusGame!.triggerRef, '28');
    });

    test('quests: targets from criteria; progress count or distinct games', () {
      final active = [for (final q in jsonDecode(_active) as List) Quest.fromJson(q)];
      expect(active.first.rewardTokens, 50);
      expect(active[1].target, 2);
      expect(active[2].target, 10);
      final mine = [for (final p in jsonDecode(_progress) as List) QuestProgress.fromJson(p)];
      expect(mine[1].current, 1);
      expect(mine[1].target, 2);
    });

    test('merge: newest period per quest, no row → 0 / target, an older completed period stays claimable', () {
      final active = [for (final q in jsonDecode(_active) as List) Quest.fromJson(q)];
      final mine = [for (final p in jsonDecode(_progress) as List) QuestProgress.fromJson(p)];
      final rows = mergeQuests(active.reversed.toList(), mine);
      expect(rows.map((r) => r.quest.id), [3, 1, 4, 5], reason: 'grouped by scope, server order kept inside');
      final byId = {for (final r in rows) r.quest.id: r};
      expect(byId[1]!.claimable, isTrue);
      expect(byId[3]!.current, 1);
      expect(byId[3]!.claimable, isFalse);
      expect(byId[5]!.progress, isNull);
      expect(byId[5]!.current, 0);
      expect(byId[5]!.target, 5);
      // The current week is claimed, last week's is completed and unclaimed.
      expect(byId[4]!.progress!.periodStart, '2026-11-24');
      expect(byId[4]!.claimable, isTrue);
      expect(byId[1]!.markClaimed().claimable, isFalse);
    });

    test('achievements: flat, secret mystery, tiered claimable tiers and next tier', () {
      final list = [for (final a in jsonDecode(_myAchievements) as List) Achievement.fromJson(a)];
      final flat = list[0], secret = list[1], tiered = list[2];
      expect(flat.tiered, isFalse);
      expect(flat.claimable, isTrue);
      expect(flat.copyClaimed().claimable, isFalse);
      expect(secret.mystery, isTrue);
      expect(secret.claimable, isFalse);
      expect(tiered.tiers.length, 4);
      expect(tiered.tiers[2].reward.kind, 'gold');
      expect(tiered.tiers[3].reward.name, 'Dice Roller');
      expect(tiered.claimableTiers, ['silver']);
      expect(tiered.claimable, isTrue);
      expect(tiered.nextTier!.tier, 'gold');
      expect(tiered.copyClaimed(tier: 'silver').claimable, isFalse);
    });

    test('bonus game list item and play reply', () {
      final g = BonusGame.fromJson((jsonDecode(_bonusList) as List).first);
      expect(g.gameType, 'scratch');
      expect(g.cost.kind, 'tokens');
      expect(g.cost.amount, 200);
      expect(g.slots, 9);
      expect(g.me.playsLeftToday, 5);
      expect(g.prizes.last.oddsPct, '0.20');
      expect(g.hasOdds, isTrue);
      expect(g.supported, isTrue);
      final p = BonusPlayResult.fromJson(_j(_play));
      expect(p.slotIndex, 0);
      expect(p.prize.amount, 50);
      expect(p.prize.currency, 'token');
      expect(p.balances!.tokens, 650);
      expect(p.playsLeftToday, 0);
    });

    test('red dot rules', () {
      final w = WelcomeBonus.fromJson(_j(_welcomeMe));
      final blocked = WelcomeBonus.fromJson(_j(_welcomeBlocked));
      final achievements = [for (final a in jsonDecode(_myAchievements) as List) Achievement.fromJson(a)];
      expect(const RewardsBadge().any, isFalse);
      expect(RewardsBadge.from(welcome: w).welcome, isTrue);
      expect(RewardsBadge.from(welcome: blocked).any, isFalse);
      expect(RewardsBadge.from(dailyCanClaim: true).any, isTrue);
      expect(RewardsBadge.from(achievements: achievements).achievements, isTrue);
      expect(RewardsBadge.from(achievements: [achievements[1]]).achievements, isFalse);
      final quests = mergeQuests(
        [for (final q in jsonDecode(_active) as List) Quest.fromJson(q)],
        [for (final p in jsonDecode(_progress) as List) QuestProgress.fromJson(p)],
      );
      expect(RewardsBadge.from(quests: quests).quests, isTrue);
      expect(RewardsBadge.from(quests: [quests[1]]).quests, isFalse);
    });
  });

  group('RemoteRewardsApi', () {
    test('welcome: 404 → null; claim body-less POST', () async {
      final g = _Gateway({
        'GET /welcome-bonus/me': (_) => _err(404, 'NOT_FOUND', 'not found'),
        'POST /welcome-bonus/claim': (_) => (200, _j(_welcomeClaim)),
      });
      final api = RemoteRewardsApi(_client(g));
      expect(await api.welcomeBonus(), isNull);
      final c = await api.claimWelcome();
      expect(c.balances!.gold, 500);
      expect(g.log.last.body, isNull);
    });

    test('welcome claim: device_required → registers the device and claims again, once', () async {
      var claims = 0;
      final g = _Gateway({
        'POST /welcome-bonus/claim': (_) => ++claims == 1
            ? _err(409, 'CONFLICT', 'conflict: device_required: register this device (POST /api/v1/devices/register) first')
            : (200, _j(_welcomeClaim)),
        'POST /devices/register': (r) => (201, {'id': 1, 'device_id': (r.body as Map)['device_id']}),
      });
      final api = RemoteRewardsApi(_client(g), deviceId: () async => 'dev-1');
      final c = await api.claimWelcome();
      expect(c.credited.tokens, 500);
      expect(claims, 2);
      final reg = g.log.firstWhere((r) => r.path == '/devices/register').body as Map;
      expect(reg['device_id'], 'dev-1');
      expect(['ios', 'android', 'web'], contains(reg['platform']));
      expect(reg['device_name'], isNotEmpty);
    });

    test('welcome claim: a second device_required is not retried again', () async {
      final g = _Gateway({
        'POST /welcome-bonus/claim': (_) => _err(409, 'CONFLICT', 'conflict: device_required: register'),
        'POST /devices/register': (_) => (201, {'id': 1}),
      });
      final api = RemoteRewardsApi(_client(g), deviceId: () async => 'dev-1');
      await expectLater(api.claimWelcome(), throwsA(isA<AppException>()));
      expect(g.count('POST /welcome-bonus/claim'), 2);
      expect(g.count('POST /devices/register'), 1);
    });

    test('quests: active + my-progress + claim path', () async {
      final g = _Gateway({
        'GET /sensitive/quests/active': (_) => (200, jsonDecode(_active)),
        'GET /sensitive/quests/my-progress': (_) => (200, jsonDecode(_progress)),
        'POST /sensitive/quests/1/claim': (_) => (200, {'quest_id': 1, 'period_start': '2026-11-24', 'tokens_awarded': '50', 'gold_awarded': '0', 'powerup_id': null, 'powerup_quantity': 0}),
      });
      final api = RemoteRewardsApi(_client(g));
      expect((await api.activeQuests()).length, 4);
      expect((await api.myQuestProgress()).length, 4);
      final c = await api.claimQuest(1);
      expect(c.tokens, 50);
      expect(c.paysMoney, isTrue);
    });

    test('achievements: ?game_id, /my, flat claim without tier, tier claim with ?tier=', () async {
      final g = _Gateway({
        'GET /achievements': (_) => (200, jsonDecode(_myAchievements)),
        'GET /achievements/my': (_) => (200, jsonDecode(_myAchievements)),
        'POST /achievements/15/claim': (_) => (200, {'achievement_id': 15, 'tokens_awarded': 0, 'gold_awarded': 0, 'tier': null, 'avatar_id': null, 'title': null}),
        'POST /achievements/230/claim': (r) => (200, {'achievement_id': 230, 'tokens_awarded': 250, 'gold_awarded': 0, 'tier': r.query['tier'], 'avatar_id': null, 'title': null}),
      });
      final api = RemoteRewardsApi(_client(g));
      await api.achievements(gameId: 25);
      expect(g.log.last.query, {'game_id': '25'});
      await api.achievements();
      expect(g.log.last.query, isEmpty);
      expect((await api.myAchievements()).length, 3);
      final flat = await api.claimAchievement(15);
      expect(g.log.last.query, isEmpty);
      expect(flat.paysMoney, isFalse);
      final tier = await api.claimAchievement(230, tier: 'silver');
      expect(g.log.last.query, {'tier': 'silver'});
      expect(tier.tier, 'silver');
      expect(tier.tokens, 250);
    });

    test('bonus games: list with ?trigger, one by code, play body, history with per/after', () async {
      final g = _Gateway({
        'GET /bonus-games': (_) => (200, jsonDecode(_bonusList)),
        'GET /bonus-games/scratch_gold': (_) => (200, (jsonDecode(_bonusList) as List).first),
        'POST /bonus-games/welcome_wheel/play': (_) => (201, _j(_play)),
        'GET /bonus-games/plays/me': (_) => (200, _j(_plays)),
      });
      final api = RemoteRewardsApi(_client(g));
      await api.bonusGames(trigger: 'store');
      expect(g.log.last.query, {'trigger': 'store'});
      expect((await api.bonusGame('scratch_gold')).code, 'scratch_gold');
      final p = await api.playBonusGame('welcome_wheel', trigger: 'welcome_bonus', triggerRef: '634');
      expect(g.log.last.body, {'trigger': 'welcome_bonus', 'trigger_ref': '634'});
      expect(p.balances!.tokens, 650);
      await api.playBonusGame('welcome_wheel', trigger: 'store');
      expect(g.log.last.body, {'trigger': 'store'}, reason: 'trigger_ref left out, not null');
      final page = await api.myBonusPlays(per: 10, after: 'xyz');
      expect(g.log.last.query, {'per': '10', 'after': 'xyz'});
      expect(page.items.single.prizeLabel, '400 tokens');
      expect(page.nextCursor, 'abc');
    });

    test('a 409 keeps the server message as detail for prefix matching', () async {
      final g = _Gateway({'POST /welcome-bonus/claim': (_) => _err(409, 'CONFLICT', 'conflict: blocked: device_dupe')});
      try {
        await RemoteRewardsApi(_client(g)).claimWelcome();
        fail('should throw');
      } on AppException catch (e) {
        expect(rewardConflict(e), 'blocked: device_dupe');
        expect(welcomeClaimIssue(e).text, 'This device already received a welcome bonus.');
        expect(e.message, isNot(contains('conflict')), reason: 'developer text is never the shown message');
      }
    });
  });

  group('errors → player text', () {
    test('welcome claim', () {
      expect(welcomeClaimIssue(_ex(409, 'CONFLICT', 'conflict: completed: the welcome bonus is fully paid')).kind, RewardIssueKind.alreadyDone);
      final due = DateTime.now().add(const Duration(hours: 5, minutes: 30, seconds: 20));
      expect(welcomeClaimIssue(_ex(409, 'CONFLICT', 'conflict: nothing_due'), nextDueAt: due).text, 'The next part unlocks in 5h 30m.');
      expect(welcomeClaimIssue(_ex(409, 'CONFLICT', 'conflict: expired')).text, 'This welcome bonus has expired.');
      expect(welcomeClaimIssue(_ex(409, 'CONFLICT', 'conflict: blocked: guest_policy')).text, "The welcome bonus isn't available for this account.");
      expect(welcomeClaimIssue(_ex(409, 'CONFLICT', 'conflict: blocked: disabled')).text, "The welcome bonus isn't available for this account.");
      expect(welcomeClaimIssue(_ex(404, 'NOT_FOUND')).kind, RewardIssueKind.gone);
      expect(welcomeClaimIssue(_ex(409, 'CONFLICT', 'conflict: something_new')).text, 'Something went wrong. Try again.');
      expect(welcomeClaimIssue(const AppException('op text', statusCode: 503, code: 'KILL_SWITCH_ENGAGED')).text, 'op text');
      expect(welcomeClaimIssue(const AppException('Your session has ended. Please log in again.', statusCode: 401, code: 'FINGERPRINT_MISMATCH')).kind, RewardIssueKind.signIn);
    });

    test('daily claim', () {
      expect(dailyClaimIssue(_ex(409, 'CONFLICT', 'conflict: daily bonus already claimed')).kind, RewardIssueKind.alreadyDone);
      expect(dailyClaimIssue(_ex(403, 'FORBIDDEN')).text, 'Create an account to collect daily rewards.');
      expect(dailyClaimIssue(_ex(404, 'NOT_FOUND')).text, "Daily bonus isn't available right now.");
      expect(dailyClaimIssue(_ex(500, 'DATABASE_ERROR')).text, 'Something went wrong. Try again.');
    });

    test('quest claim', () {
      expect(questClaimIssue(_ex(409, 'CONFLICT', 'conflict: quest reward already claimed')).kind, RewardIssueKind.alreadyDone);
      expect(questClaimIssue(_ex(400, 'BAD_REQUEST', 'bad request: quest not yet completed')).text, 'Finish the quest first.');
      expect(questClaimIssue(_ex(400, 'BAD_REQUEST', 'bad request: quest period expired')).text, 'This quest has ended.');
      expect(questClaimIssue(_ex(404, 'NOT_FOUND', 'not found: quest progress not found')).text, 'Finish the quest first.');
      final unknown = questClaimIssue(_ex(404, 'NOT_FOUND', 'not found: quest not found'));
      expect(unknown.kind, RewardIssueKind.gone);
      expect(unknown.text, isNull);
    });

    test('achievement claim', () {
      expect(achievementClaimIssue(_ex(409, 'CONFLICT', 'conflict: bronze tier already claimed')).kind, RewardIssueKind.alreadyDone);
      expect(achievementClaimIssue(_ex(400, 'BAD_REQUEST', 'bad request: achievement not unlocked yet')).text, 'Not unlocked yet.');
      expect(achievementClaimIssue(_ex(400, 'BAD_REQUEST', 'bad request: bronze tier not reached yet')).text, 'Not unlocked yet.');
      expect(achievementClaimIssue(_ex(400, 'BAD_REQUEST', 'bad request: tier is required for a tiered achievement')).text, 'Something went wrong. Try again.');
      expect(achievementClaimIssue(_ex(404, 'NOT_FOUND', 'not found: achievement 9')).kind, RewardIssueKind.gone);
    });

    test('bonus game play', () {
      final cd = DateTime.now().add(const Duration(minutes: 42, seconds: 30));
      expect(bonusPlayIssue(_ex(409, 'CONFLICT', 'conflict: blocked: cooldown'), cooldownUntil: cd).text, 'Come back in 42m.');
      expect(bonusPlayIssue(_ex(409, 'CONFLICT', 'conflict: blocked: max_per_day')).text, 'No plays left today.');
      expect(bonusPlayIssue(_ex(409, 'CONFLICT', 'conflict: blocked: payout_cap')).text, 'No plays left today.');
      expect(bonusPlayIssue(_ex(409, 'CONFLICT', 'conflict: blocked: guest')).text, 'Create an account to play.');
      expect(bonusPlayIssue(_ex(409, 'CONFLICT', 'conflict: blocked: paused')).text, 'Not available right now.');
      final used = bonusPlayIssue(_ex(409, 'CONFLICT', 'conflict: no_entitlement: the free spin was used'));
      expect(used.kind, RewardIssueKind.gone);
      expect(used.text, "This free play isn't available.");
      expect(bonusPlayIssue(_ex(409, 'CONFLICT', 'conflict: unsupported: rewarded_ad')).text, 'Not available right now.');
      expect(bonusPlayIssue(_ex(409, 'CONFLICT', 'conflict: no_prizes')).text, 'Not available right now.');
      final funds = bonusPlayIssue(_ex(409, 'INSUFFICIENT_FUNDS', 'insufficient funds'));
      expect(funds.kind, RewardIssueKind.notEnoughFunds);
      expect(funds.text, 'Not enough tokens.');
      expect(bonusPlayIssue(_ex(400, 'BAD_REQUEST', "bad request: trigger: this game is offered on 'welcome_bonus'")).text, 'Something went wrong. Try again.');
      expect(bonusPlayIssue(_ex(429, 'RATE_LIMITED')).kind, RewardIssueKind.message);
    });
  });

  group('DemoRewardsApi', () {
    test('welcome claim then spin; a second spin is refused as used', () async {
      final api = DemoRewardsApi();
      expect((await api.welcomeBonus())!.showSheet, isTrue);
      await api.claimWelcome();
      final spin = (await api.welcomeBonus())!.freeSpin!;
      final p = await api.playBonusGame(spin.code, trigger: spin.trigger, triggerRef: spin.triggerRef);
      expect(p.balances, isNotNull);
      final after = (await api.welcomeBonus())!;
      expect(after.finished, isTrue);
      expect(after.showSheet, isFalse);
      await expectLater(api.playBonusGame(spin.code, trigger: spin.trigger), throwsA(isA<AppException>()));
    });
  });
}
