// The game catalogue contract (docs/services/04-game-catalogue.md): parsing
// every sample, the stake shapes, caching/refetch rules, GAME_NOT_FOUND,
// invalid_mode, the stake picker and the socket hand-off. Dio runs against a
// stand-in adapter that answers like the gateway and records each request.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/app/app_profile.dart';
import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/configs.dart';
import 'package:snakeladder/configs/games/core/game_codes.dart';
import 'package:snakeladder/game/ludo/online/ludo_catalogue.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/catalogue_service.dart';

class _Req {
  _Req(this.method, this.path, this.query, this.headers);
  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, dynamic> headers;
}

typedef _Handler = FutureOr<(int, Object?)> Function(_Req);

class _Gateway implements HttpClientAdapter {
  _Gateway(this.routes);
  final Map<String, _Handler> routes;
  final List<_Req> log = [];

  int count(String route) =>
      log.where((r) => '${r.method} ${r.path}' == route).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final req = _Req(
      o.method,
      o.uri.path.replaceFirst('/api/v1', ''),
      o.uri.queryParameters,
      Map.of(o.headers),
    );
    log.add(req);
    final handler = routes['${req.method} ${req.path}'];
    final (status, json) = handler == null
        ? (
            404,
            {
              'error': 'NOT_FOUND',
              'message':
                  'not found: no route for ${req.method} /api/v1${req.path}',
            },
          )
        : await handler(req);
    return ResponseBody.fromString(
      jsonEncode(json),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(_Gateway g) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://test/api/v1/',
      contentType: 'application/json',
    ),
  )..httpClientAdapter = g;
  return ApiClient(dio: dio)..authToken = 'acc1';
}

(int, Object?) _err(int status, String code, String message) =>
    (status, {'error': code, 'message': message});

class _MemDisk implements CatalogueDiskCache {
  String? saved;
  @override
  Future<String?> read() async => saved;
  @override
  Future<void> write(String json) async => saved = json;
}

// ── Real samples from the doc (24 Nov 2026) ──

const _snl = {
  'id': 25,
  'code': 'snake-and-ladder',
  'name': 'Snake & Ladder',
  'description':
      'Roll dice, climb ladders, dodge snakes -- race to the finish.',
  'icon_url': '/assets/games/snl/icon.svg',
  'min_players': 2,
  'max_players': 4,
  'supports_bots': true,
  'has_per_player_clock': false,
  'has_hidden_information': false,
  'is_real_time': false,
  'is_house_banked': false,
  'is_active': true,
  'sort_order': 1,
  'created_at': '2026-11-14T08:35:16.461863Z',
  'updated_at': '2026-11-14T08:35:16.461863Z',
};

const _ludo = {
  'id': 1,
  'code': 'ludo',
  'name': 'Ludo Royale',
  'description': 'Classic race game with four pawns.',
  'icon_url': null,
  'min_players': 2,
  'max_players': 4,
  'supports_bots': true,
  'has_per_player_clock': false,
  'has_hidden_information': false,
  'is_real_time': false,
  'is_house_banked': false,
  'is_active': true,
  'sort_order': 2,
  'created_at': '2026-11-14T08:35:16.461863Z',
  'updated_at': '2026-11-14T08:35:16.461863Z',
};

const _variants = [
  {
    'id': 16,
    'code': 'classic',
    'name': 'Classic',
    'description': '4 tokens home · full board',
    'is_default': true,
    'rules_config': {
      'capture_extra_turn': true,
      'pawns_per_player': 4,
      'safe_squares': [0, 8, 13],
      'track_size': 52,
    },
    'design_key': 'classic',
  },
  {
    'id': 88,
    'code': 'rush',
    'name': 'Rush',
    'description': '6-minute clock · most progress wins',
    'is_default': false,
    'rules_config': {
      'auto_roll': true,
      'engine_variant': 'classic',
      'match_clock_ms': 360000,
      'win_by': 'progress',
    },
    'design_key': 'rush',
  },
];

const _modes = [
  {
    'id': 57,
    'game_id': 1,
    'code': 'casual_2p',
    'name': 'Casual 2 Players',
    'description': null,
    'player_count': 2,
    'min_players': 2,
    'turn_timer_seconds': 10,
    'is_ranked': false,
    'is_active': true,
    'mode_config': {
      'rule_options': [
        {
          'default': true,
          'engine': 'has',
          'key': 'extra_turn_on_six',
          'label': 'Bonus roll on six',
          'type': 'bool',
        },
        {
          'default': true,
          'engine': 'has',
          'key': 'powerups_allowed',
          'label': 'Power-ups allowed',
          'type': 'bool',
        },
        {
          'default': 'random',
          'engine': 'pending',
          'key': 'grid_order',
          'label': 'Grid order',
          'type': 'choice',
        },
      ],
      'timer': {
        'max_timeouts': 3,
        'time_bank_ms': 0,
        'turn_ms': 10000,
        'type': 'turn',
      },
    },
    'variant_id': 16,
    'variant_code': 'classic',
    'limit_label': 'Standard',
  },
  {
    'id': 61,
    'game_id': 1,
    'code': 'friends_room',
    'name': 'Play with Friends',
    'description': null,
    'player_count': 4,
    'min_players': 2,
    'turn_timer_seconds': 15,
    'is_ranked': false,
    'is_active': true,
    'mode_config': {
      'capture_extra_turn': true,
      'extra_turn_on_six': true,
      'host_can_choose': [
        'turn_seconds',
        'extra_turn_on_six',
        'capture_extra_turn',
        'three_sixes_lose_turn',
        'safe_squares',
        'powerups_allowed',
      ],
      'host_options': {
        'capture_extra_turn': {'label': 'Capture bonus roll'},
        'extra_turn_on_six': {'label': 'Bonus roll on six'},
        'powerups_allowed': {'label': 'Power-ups allowed'},
        'safe_squares': {'label': 'Safe squares'},
        'three_sixes_lose_turn': {'label': 'Three sixes forfeit'},
        'turn_seconds': {'label': 'Turn timer'},
      },
      'powerups_allowed': true,
      'rule_options': [
        {
          'default': true,
          'engine': 'has',
          'key': 'extra_turn_on_six',
          'label': 'Bonus roll on six',
          'type': 'bool',
        },
      ],
      'safe_squares': true,
      'three_sixes_lose_turn': true,
      'timer': {
        'allowed_turn_seconds': [10, 15, 20],
        'max_timeouts': 3,
        'time_bank_ms': 0,
        'turn_ms': 15000,
        'type': 'turn',
      },
    },
    'variant_id': 16,
    'variant_code': 'classic',
    'limit_label': 'Standard',
  },
  {
    'id': 90,
    'game_id': 1,
    'code': 'rush_2p',
    'name': 'Rush',
    'player_count': 2,
    'min_players': 2,
    'turn_timer_seconds': null,
    'is_ranked': true,
    'is_active': true,
    'mode_config': {
      'min_tier': 'silver',
      'subscription_gate': {
        'rated_per_day': {'free': 5, 'silver': 50, 'gold': null},
      },
      'timer': {
        'first_move_ms': 30000,
        'increment_ms': 2000,
        'initial_ms': 180000,
        'type': 'clock',
      },
    },
    'variant_id': 88,
    'variant_code': 'rush',
    'limit_label': null,
  },
];

const _stakes = [
  {
    'id': 338,
    'game_id': 1,
    'mode_id': 57,
    'currency': 'gold',
    'stake_amount': 10,
    'min_stake_amount': null,
    'max_stake_amount': null,
    'stake_step': null,
    'base_payout_multiplier': 2.0,
    'is_active': true,
    'stake_label': 'Entry',
    'tier_label': '10',
    'tier_order': 1,
    'small_blind': null,
    'big_blind': null,
    'point_value': null,
  },
  {
    'id': 337,
    'game_id': 1,
    'mode_id': 57,
    'currency': 'gold',
    'stake_amount': 25,
    'min_stake_amount': null,
    'max_stake_amount': null,
    'stake_step': null,
    'base_payout_multiplier': 2.0,
    'is_active': true,
    'stake_label': 'Entry',
    'tier_label': '25',
    'tier_order': 2,
    'small_blind': null,
    'big_blind': null,
    'point_value': null,
  },
  {
    'id': 57,
    'game_id': 1,
    'mode_id': 57,
    'currency': 'token',
    'stake_amount': null,
    'min_stake_amount': 50,
    'max_stake_amount': 5000,
    'stake_step': 50,
    'base_payout_multiplier': 1.9,
    'is_active': true,
    'stake_label': null,
    'tier_label': null,
    'tier_order': null,
    'small_blind': null,
    'big_blind': null,
    'point_value': null,
  },
  // From code: the shapes not active today.
  {
    'id': 900,
    'game_id': 1,
    'mode_id': 57,
    'currency': 'token',
    'stake_amount': 20,
    'min_stake_amount': null,
    'max_stake_amount': null,
    'stake_step': null,
    'base_payout_multiplier': 2.0,
    'is_active': true,
    'stake_label': 'Blinds',
    'tier_label': '1/2',
    'tier_order': 3,
    'small_blind': 1,
    'big_blind': 2,
    'point_value': null,
  },
  {
    'id': 901,
    'game_id': 1,
    'mode_id': 57,
    'currency': 'gold',
    'stake_amount': null,
    'min_stake_amount': null,
    'max_stake_amount': null,
    'stake_step': null,
    'base_payout_multiplier': null,
    'is_active': true,
    'stake_label': 'Point value',
    'tier_label': '0.25 /pt',
    'tier_order': 4,
    'small_blind': null,
    'big_blind': null,
    'point_value': 0.25,
  },
  // A numeric string amount (00-conventions.md "Money").
  {
    'id': 339,
    'game_id': 1,
    'mode_id': 61,
    'currency': 'gold',
    'stake_amount': '50',
    'is_active': true,
    'stake_label': 'Entry',
    'tier_label': '50',
    'tier_order': 1,
  },
];

const _powerUps = [
  {
    'id': 28,
    'game_id': 1,
    'code': 'shield',
    'name': 'Shield',
    'description': 'Block the three-consecutive-sixes penalty this turn.',
    'icon_url': 'powerups/shield.svg',
    'effect_config': {
      'effect': 'block_consecutive_sixes',
      'trigger': 'pre_roll',
    },
    'price_currency': 'token',
    'price_amount': 50,
    'is_consumable': true,
    'max_per_match': 2,
    'is_active': true,
    'sort_order': 1,
  },
];

const _config = {
  'game_id': 1,
  'config': {
    'board': {
      'player_colors': ['#d92a4a', '#1f8a5b', '#3a4a8a', '#c9a24a'],
      'theme': {'default': 'classic_red_green_blue_yellow'},
    },
    'dice': {'roll_animation_ms': 800},
  },
  'version': 1,
  'updated_at': '2026-11-14T08:35:16.461863Z',
};

const _achievements = [
  {
    'id': 15,
    'game_id': 1,
    'code': 'ludo_first_win',
    'name': 'First Win',
    'description': 'Win your first Ludo match.',
    'criteria': {'count': 1, 'event': 'match_end', 'result': 'win'},
    'reward_tokens': 0,
    'reward_gold': 0,
    'exp_reward': 10,
    'icon_url': '/assets/achievements/ludo/first_win.svg',
    'sort_order': 0,
    'tiers': [],
    'trigger': null,
    'is_secret': false,
  },
  {
    'id': 234,
    'game_id': 25,
    'code': 'sl_phoenix',
    'name': 'Secret achievement',
    'description': null,
    'criteria': {},
    'reward_tokens': 0,
    'reward_gold': 0,
    'exp_reward': 0,
    'icon_url': null,
    'sort_order': 8,
    'tiers': [
      {
        'tier': 'bronze',
        'threshold': 1,
        'reward': {'kind': 'tokens', 'amount': 200},
      },
      {
        'tier': 'gold',
        'threshold': 100,
        'reward': {'kind': 'gold', 'amount': 2500},
      },
      {
        'tier': 'royal',
        'threshold': 500,
        'reward': {'kind': 'title', 'name': 'Secret achievement'},
      },
    ],
    'trigger': 'game_event',
    'is_secret': true,
  },
];

const _notFound = (
  404,
  {'error': 'GAME_NOT_FOUND', 'message': 'game not found: 1'},
);

Map<String, _Handler> _routes({int ludoId = 1}) => {
  'GET /games': (_) => (
    200,
    [
      _snl,
      {..._ludo, 'id': ludoId},
    ],
  ),
  'GET /games/$ludoId': (_) => (200, _ludo),
  'GET /games/$ludoId/variants': (_) => (200, _variants),
  'GET /games/$ludoId/modes': (_) => (200, _modes),
  'GET /games/$ludoId/stakes': (_) => (200, _stakes),
  'GET /games/$ludoId/power-ups': (_) => (200, _powerUps),
  'GET /games/$ludoId/config': (_) => (200, _config),
  'GET /games/$ludoId/achievements': (_) => (200, _achievements),
};

void main() {
  group('parsing the samples', () {
    test('games list, one game', () async {
      final g = _Gateway(_routes());
      final api = RemoteCatalogueApi(_client(g));
      final games = await api.games();
      expect(games.map((x) => x.code), ['snake-and-ladder', 'ludo']);
      final snl = games.first;
      expect(
        (
          snl.id,
          snl.name,
          snl.minPlayers,
          snl.maxPlayers,
          snl.supportsBots,
          snl.sortOrder,
          snl.playersLabel,
        ),
        (25, 'Snake & Ladder', 2, 4, true, 1, '2-4'),
      );
      expect(snl.iconUrl, '/assets/games/snl/icon.svg');
      // Always asks for active games, with the bearer token.
      expect(g.log.single.query, {'is_active': 'true'});
      expect(g.log.single.headers['Authorization'], 'Bearer acc1');

      final one = await api.game(1);
      expect((one.code, one.isActive, one.iconUrl), ('ludo', true, null));
    });

    test('variants: default, engine_variant', () async {
      final v = await RemoteCatalogueApi(_client(_Gateway(_routes())))
          .variants(1);
      expect(v.map((x) => x.code), ['classic', 'rush']);
      expect(v.first.isDefault, isTrue);
      expect(v.first.description, '4 tokens home · full board');
      expect(v.first.rulesConfig['track_size'], 52);
      expect(v.last.engineVariant, 'classic');
      expect(v.first.engineVariant, isNull);
    });

    test('modes: timers, rule options, host options, gates', () async {
      final m = await RemoteCatalogueApi(_client(_Gateway(_routes()))).modes(1);
      final casual = m[0], friends = m[1], rush = m[2];

      expect(
        (
          casual.id,
          casual.code,
          casual.playerCount,
          casual.turnTimerSeconds,
          casual.limitLabel,
          casual.variantId,
        ),
        (57, 'casual_2p', 2, 10, 'Standard', 16),
      );
      expect(casual.timer.type, ModeTimerType.turn);
      expect(
        (
          casual.timer.turnMs,
          casual.timer.maxTimeouts,
          casual.timer.shortLabel,
        ),
        (10000, 3, '10s'),
      );
      // Only rules the server applies.
      expect(casual.ruleOptions, hasLength(3));
      expect(casual.appliedRules.map((r) => r.key), [
        'extra_turn_on_six',
        'powerups_allowed',
      ]);
      expect(casual.isPrivateRoom, isFalse);
      expect(casual.hostOptions, isEmpty);
      expect(casual.subscriptionGate, isNull);

      expect(friends.isPrivateRoom, isTrue);
      expect((friends.minPlayers, friends.playerCount), (2, 4));
      final turn = friends.hostOptions.firstWhere((o) => o.isTurnTimer);
      expect((turn.label, turn.current), ('Turn timer', 15));
      expect(turn.values, [10, 15, 20]);
      final safe = friends.hostOptions.firstWhere(
        (o) => o.key == 'safe_squares',
      );
      expect((safe.label, safe.current), ('Safe squares', true));
      expect(friends.powerUpsAllowed, isTrue);

      expect(rush.timer.type, ModeTimerType.clock);
      expect(rush.timer.shortLabel, '3+2');
      expect(rush.turnTimerSeconds, isNull);
      expect(rush.isRanked, isTrue);
      expect(rush.minTier, 'silver');
      expect(
        (
          rush.subscriptionGate!.free,
          rush.subscriptionGate!.silver,
          rush.subscriptionGate!.gold,
        ),
        (5, 50, null),
      );
      expect(rush.subscriptionGate!.capFor('royal'), isNull);
      // The original game-specific row is kept.
      expect(rush.json['code'], 'rush_2p');
    });

    test(
      'subscription gate: the flat shape; null gate; round and missing timers',
      () {
        expect(
          SubscriptionGate.fromJson({
            'free_rated_per_day': 5,
            'silver_rated_per_day': 50,
            'gold_rated_per_day': null,
          })!.capFor('free'),
          5,
        );
        expect(SubscriptionGate.fromJson(null), isNull);
        final round = GameMode.fromJson({
          'id': 1,
          'code': 'royale',
          'mode_config': {
            'timer': {
              'countdown_ms': 3000,
              'duration_ms': 90000,
              'type': 'round',
            },
          },
        });
        expect(
          (round.timer.type, round.timer.shortLabel),
          (ModeTimerType.round, '90s'),
        );
        final none = GameMode.fromJson({
          'id': 2,
          'code': 'live',
          'mode_config': {
            'timer': null,
            'subscription_gate': null,
            'min_tier': null,
          },
        });
        expect(
          (
            none.timer.type,
            none.timer.shortLabel,
            none.minTier,
            none.subscriptionGate,
          ),
          (ModeTimerType.none, null, null, null),
        );
        final untyped = GameMode.fromJson({
          'id': 3,
          'code': 'x',
          'mode_config': {
            'timer': {'duration_ms': 180000},
          },
        });
        expect(untyped.timer.type, ModeTimerType.none);
      },
    );

    test('stakes: the four shapes, money as number or string', () async {
      final s = await RemoteCatalogueApi(_client(_Gateway(_routes())))
          .stakes(1);
      expect(s.map((x) => x.shape), [
        StakeShape.fixed,
        StakeShape.fixed,
        StakeShape.range,
        StakeShape.blinds,
        StakeShape.points,
        StakeShape.fixed,
      ]);
      expect(s.map((x) => x.isSupported), [
        true,
        true,
        true,
        false,
        false,
        true,
      ]);
      final gold10 = s[0];
      expect(
        (
          gold10.currency,
          gold10.stakeAmount,
          gold10.stakeLabel,
          gold10.tierLabel,
          gold10.tierOrder,
          gold10.displayLabel,
        ),
        ('gold', 10, 'Entry', '10', 1, '10'),
      );
      final range = s[2];
      expect(
        (
          range.minStakeAmount,
          range.maxStakeAmount,
          range.stakeStep,
          range.displayLabel,
        ),
        (50, 5000, 50, '50-5000'),
      );
      expect(range.allows(150), isTrue);
      expect(range.allows(175), isFalse);
      expect(range.allows(5050), isFalse);
      expect((s[3].smallBlind, s[3].bigBlind), (1, 2));
      expect(s[4].pointValue, 0.25);
      expect(s[5].stakeAmount, 50);
    });

    test('power-ups, config, achievements', () async {
      final api = RemoteCatalogueApi(_client(_Gateway(_routes())));
      final p = (await api.powerUps(1)).single;
      expect(
        (
          p.code,
          p.priceCurrency,
          p.priceAmount,
          p.isConsumable,
          p.maxPerMatch,
          p.isForSale,
        ),
        ('shield', 'token', 50, true, 2, true),
      );

      final c = (await api.config(1))!;
      expect((c.gameId, c.version), (1, 1));
      expect(c.at('dice.roll_animation_ms'), 800);
      expect(c.at('board.player_colors'), hasLength(4));
      expect(c.at('nope.deeper'), isNull);

      final a = await api.achievements(1);
      expect(
        (a[0].code, a[0].isTiered, a[0].expReward, a[0].isSecret),
        ('ludo_first_win', false, 10, false),
      );
      expect(a[1].isSecret, isTrue);
      expect(a[1].tiers.map((t) => (t.tier, t.threshold, t.rewardKind)), [
        ('bronze', 1, 'tokens'),
        ('gold', 100, 'gold'),
        ('royal', 500, 'title'),
      ]);
      expect(a[1].tiers.last.rewardName, 'Secret achievement');
    });

    test('config may be null', () async {
      final g = _Gateway({'GET /games/7/config': (_) => (200, null)});
      expect(await RemoteCatalogueApi(_client(g)).config(7), isNull);
    });
  });

  group('errors', () {
    test('GAME_NOT_FOUND gets the app text and keeps the code', () async {
      final g = _Gateway({
        'GET /games/999999/modes': (_) =>
            _err(404, 'GAME_NOT_FOUND', 'game not found: 999999'),
      });
      await expectLater(
        RemoteCatalogueApi(_client(g)).modes(999999),
        throwsA(
          isA<AppException>()
              .having((e) => e.code, 'code', ApiErrorCode.gameNotFound)
              .having((e) => e.statusCode, 'status', 404)
              .having((e) => e.message, 'message', gameUnavailableMessage),
        ),
      );
    });

    test(
      'BAD_REQUEST, NOT_FOUND and server errors map to AppException',
      () async {
        final g = _Gateway({
          'GET /games': (_) =>
              _err(400, 'BAD_REQUEST', 'bad request: Query deserialize error'),
          'GET /games/1/achievements': (_) =>
              _err(500, 'INTERNAL_ERROR', 'boom'),
        });
        final api = RemoteCatalogueApi(_client(g));
        await expectLater(
          api.games(),
          throwsA(
            isA<AppException>().having(
              (e) => e.code,
              'code',
              ApiErrorCode.badRequest,
            ),
          ),
        );
        await expectLater(
          api.powerUps(1),
          throwsA(
            isA<AppException>().having(
              (e) => e.code,
              'code',
              ApiErrorCode.notFound,
            ),
          ),
        );
        await expectLater(
          api.achievements(1),
          throwsA(
            isA<AppException>().having(
              (e) => e.kind,
              'kind',
              AppErrorKind.server,
            ),
          ),
        );
      },
    );
  });

  group('repository', () {
    test('ids are looked up by code; variants, modes and stakes load together and are cached', () async {
      final g = _Gateway(_routes(ludoId: 41));
      final repo = CatalogueRepository(RemoteCatalogueApi(_client(g)));
      final cat = await repo.details('ludo');
      expect(cat.game.id, 41);
      expect(
        g.log.map((r) => r.path),
        containsAll([
          '/games/41/variants',
          '/games/41/modes',
          '/games/41/stakes',
        ]),
      );
      await repo.details('ludo');
      await repo.modes('ludo');
      expect(g.count('GET /games/41/modes'), 1);
      expect(g.count('GET /games'), 1);
    });

    test('a game home reopened after 10 minutes refetches', () async {
      var now = DateTime(2026, 11, 24, 10);
      final g = _Gateway(_routes());
      final repo = CatalogueRepository(
        RemoteCatalogueApi(_client(g)),
        now: () => now,
      );
      await repo.details('ludo');
      now = now.add(const Duration(minutes: 9));
      await repo.details('ludo');
      expect(g.count('GET /games/1/modes'), 1);
      now = now.add(const Duration(minutes: 2));
      await repo.details('ludo');
      expect(g.count('GET /games/1/modes'), 2);
      expect(repo.shouldRefreshAfter(const Duration(minutes: 10)), isTrue);
      expect(repo.shouldRefreshAfter(const Duration(minutes: 3)), isFalse);
    });

    test(
      'GAME_NOT_FOUND on a sub-route removes the game from the cached list',
      () async {
        final routes = _routes()..['GET /games/1/stakes'] = (_) => _notFound;
        final repo = CatalogueRepository(
          RemoteCatalogueApi(_client(_Gateway(routes))),
        );
        final changes = <List<String>>[];
        repo.onGamesChanged = (l) => changes.add([for (final x in l) x.code]);
        await repo.games();
        await expectLater(
          repo.details('ludo'),
          throwsA(
            isA<AppException>().having(
              (e) => e.code,
              'code',
              ApiErrorCode.gameNotFound,
            ),
          ),
        );
        expect(repo.cachedGames!.map((x) => x.code), ['snake-and-ladder']);
        expect(changes.last, ['snake-and-ladder']);
        // Unknown now: no further call reaches the gateway.
        await expectLater(
          repo.powerUps('ludo'),
          throwsA(
            isA<AppException>().having(
              (e) => e.code,
              'code',
              ApiErrorCode.gameNotFound,
            ),
          ),
        );
      },
    );

    test('GAME_NOT_FOUND on the power-ups tab also removes the game', () async {
      final routes = _routes()..['GET /games/1/power-ups'] = (_) => _notFound;
      final repo = CatalogueRepository(
        RemoteCatalogueApi(_client(_Gateway(routes))),
      );
      await expectLater(repo.powerUps('ludo'), throwsA(isA<AppException>()));
      expect(repo.cachedGames!.any((x) => x.code == 'ludo'), isFalse);
    });

    test('a socket invalid_mode refetches modes and stakes', () async {
      final g = _Gateway(_routes());
      var modes = [..._modes];
      g.routes['GET /games/1/modes'] = (_) => (200, modes);
      final repo = CatalogueRepository(RemoteCatalogueApi(_client(g)));
      expect((await repo.details('ludo')).mode('rush_2p'), isNotNull);
      modes = [_modes[0], _modes[1]]; // the operator switched rush off
      repo.invalidateGame('ludo');
      final fresh = await repo.details('ludo');
      expect(fresh.mode('rush_2p'), isNull);
      expect(
        (g.count('GET /games/1/modes'), g.count('GET /games/1/stakes')),
        (2, 2),
      );
    });

    test(
      'CatalogueEvents.invalidMode refetches through the providers',
      () async {
        final g = _Gateway(_routes());
        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(_client(g)),
            useRemoteCatalogueProvider.overrideWithValue(true),
            catalogueDiskCacheProvider.overrideWithValue(null),
          ],
        );
        addTearDown(container.dispose);
        final sub = container.listen(gameCatalogueProvider('ludo'), (_, _) {});
        await container.read(gameCatalogueProvider('ludo').future);
        await container.read(catalogueEventsProvider).invalidMode('ludo');
        expect(g.count('GET /games/1/modes'), 2);
        sub.close();
      },
    );

    test('the games list is kept on disk and drawn from it; a failed refetch keeps it', () async {
      final disk = _MemDisk();
      final repo = CatalogueRepository(
        RemoteCatalogueApi(_client(_Gateway(_routes()))),
        disk: disk,
      );
      await repo.games();
      await Future<void>.delayed(Duration.zero);
      expect(disk.saved, contains('snake-and-ladder'));

      final offline = _Gateway({
        'GET /games': (_) => _err(503, 'DATABASE_ERROR', 'down'),
      });
      final next = CatalogueRepository(
        RemoteCatalogueApi(_client(offline)),
        disk: disk,
      );
      expect((await next.loadFromDisk())!.map((x) => x.code), [
        'snake-and-ladder',
        'ludo',
      ]);
      await expectLater(
        next.games(refresh: true),
        throwsA(isA<AppException>()),
      );
      expect(next.cachedGames!.length, 2);
    });

    test('switched-off rows are dropped even without the filter', () async {
      final g = _Gateway({
        'GET /games': (_) => (
          200,
          [
            _snl,
            {..._ludo, 'is_active': false},
          ],
        ),
      });
      final repo = CatalogueRepository(RemoteCatalogueApi(_client(g)));
      expect((await repo.games()).map((x) => x.code), ['snake-and-ladder']);
      expect(await repo.gameByCode('ludo'), isNull);
    });

    test('the demo catalogue works offline from the local registry', () async {
      final repo = CatalogueRepository(const DemoCatalogueApi());
      final games = await repo.games();
      expect(games.map((g) => g.code), contains('ludo'));
      final ludo = await repo.details('ludo');
      expect(ludo.modes.map((m) => m.code), ['casual_2p', 'friends_room']);
      expect(
        ludo
            .stakesFor(ludo.modes.first, currency: StakeCurrency.token)
            .map((s) => s.stakeAmount),
        [50, 100, 200, 500],
      );
      expect(
        LudoCatalogue.fromShared(ludo).friendsModes.single.allowedTurnSeconds,
        [10, 15, 20],
      );
    });
  });

  group('game home', () {
    late GameCatalogue cat;
    setUp(() {
      cat = GameCatalogue(
        game: CatalogueGame.fromJson(_ludo),
        variants: [for (final v in _variants) GameVariant.fromJson(v)],
        modes: [for (final m in _modes) GameMode.fromJson(m)],
        stakes: [for (final s in _stakes) Stake.fromJson(s)],
      );
    });

    test(
      'modes grouped by variant; default variant preselected (else the first)',
      () {
        final groups = cat.modesByVariant;
        expect(groups.keys.map((v) => v?.code), ['classic', 'rush']);
        expect(groups.values.first.map((m) => m.code), [
          'casual_2p',
          'friends_room',
        ]);
        expect(cat.defaultVariant!.code, 'classic');
        final noDefault = GameCatalogue(
          game: cat.game,
          variants: [
            GameVariant.fromJson({..._variants[0], 'is_default': false}),
            GameVariant.fromJson(_variants[1]),
          ],
        );
        expect(noDefault.defaultVariant!.code, 'classic');
      },
    );

    test('the stake picker: by currency in reply order, blinds/points hidden, greyed above the balance', () {
      final casual = cat.mode('casual_2p')!;
      expect(cat.currenciesFor(casual), ['gold', 'token']);
      expect(cat.stakesFor(casual, currency: 'gold').map((s) => s.id), [
        338,
        337,
      ]); // point row hidden
      expect(cat.stakesFor(casual, currency: 'token').map((s) => s.id), [
        57,
      ]); // blinds row hidden
      final opts = cat.stakeOptions(casual, 'gold', balance: 20);
      expect(opts.map((o) => (o.stake.stakeAmount, o.enabled)), [
        (10, true),
        (25, false),
      ]);
      // A range row is pickable from its minimum.
      expect(
        cat.stakeOptions(casual, 'token', balance: 49).single.enabled,
        isFalse,
      );
      expect(
        cat.stakeOptions(casual, 'token', balance: 50).single.enabled,
        isTrue,
      );
      // Unknown balance: nothing greyed.
      expect(cat.stakeOptions(casual, 'gold').every((o) => o.enabled), isTrue);
      expect(cat.isFreeOnly(cat.mode('rush_2p')!), isTrue);
    });

    test('PlaySelection sends codes and amounts, never ids', () {
      final casual = cat.mode('casual_2p')!;
      final friends = cat.mode('friends_room')!;
      final gold10 = cat.stakesFor(casual, currency: 'gold').first;
      final range = cat.stakesFor(casual, currency: 'token').single;

      expect(
        PlaySelection.from(
          game: cat.game,
          mode: casual,
          stake: gold10,
        ).toSocketData(),
        {'mode_code': 'casual_2p', 'currency': 'gold', 'bet_amount': 10},
      );
      expect(
        PlaySelection.from(
          game: cat.game,
          mode: casual,
          stake: range,
          amount: 300,
        ).toSocketData(),
        {'mode_code': 'casual_2p', 'currency': 'token', 'bet_amount': 300},
      );
      expect(
        () => PlaySelection.from(
          game: cat.game,
          mode: casual,
          stake: range,
          amount: 310,
        ),
        throwsArgumentError,
      );
      expect(
        () => PlaySelection.from(game: cat.game, mode: friends, stake: gold10),
        throwsArgumentError,
      );
      final blinds = cat.stakes.firstWhere((s) => s.shape == StakeShape.blinds);
      expect(
        () => PlaySelection.from(game: cat.game, mode: casual, stake: blinds),
        throwsArgumentError,
      );

      // The doc's Ludo example: friends room, free, 15 s turns (unknown picks dropped).
      final free = PlaySelection.from(
        game: cat.game,
        mode: friends,
        hostPicks: {'turn_seconds': 15, 'not_allowed': 1},
      );
      expect(free.isFree, isTrue);
      expect(free.toSocketData(), {
        'mode_code': 'friends_room',
        'turn_seconds': 15,
      });
      // A shared socket also gets game_code.
      expect(
        PlaySelection.from(
          game: CatalogueGame.fromJson(const {
            'id': 7,
            'code': 'tombola',
            'name': 'Tombola',
          }),
          mode: casual,
          sharedSocket: true,
        ).toSocketData(),
        {'game_code': 'tombola', 'mode_code': 'casual_2p'},
      );
    });

    test('LudoCatalogue keeps working from the shared catalogue (fixed tiers only)', () {
      final ludo = LudoCatalogue.fromShared(cat);
      expect(ludo.gameId, 1);
      expect(
        ludo.friendsModes.single.hostOptions.map((o) => o.key),
        contains('safe_squares'),
      );
      expect(ludo.stakesFor(ludo.mode('casual_2p')!, 'gold'), [10, 25]);
      expect(ludo.currenciesFor(ludo.mode('casual_2p')!), {
        'gold',
      }); // the token range is left out
      expect(ludo.stakesFor(ludo.mode('friends_room')!, 'gold'), [50]);
    });

    test('LudoGateway asks for active games and finds Ludo by code', () async {
      final g = _Gateway(_routes(ludoId: 41));
      final ludo = await LudoGateway(_client(g)).catalogue();
      expect(ludo.gameId, 41);
      expect(g.log.first.query, {'is_active': 'true'});
    });
  });

  group('home game picker', () {
    final profile = AppProfile(
      appName: 'Test',
      modules: [
        GameModule(config: ludoConfig, routes: const {}),
        GameModule(config: chessConfig, routes: const {}),
      ],
    );
    final devProfile = AppProfile(
      appName: 'Dev',
      modules: [GameModule(config: ludoConfig, routes: const {})],
      showComingSoon: true,
    );
    final catalogue = [
      CatalogueGame.fromJson(const {
        'id': 39,
        'code': 'roulette',
        'name': 'Roulette Royale',
        'sort_order': 0,
      }),
      CatalogueGame.fromJson(_snl),
      CatalogueGame.fromJson(_ludo),
      CatalogueGame.fromJson(const {
        'id': 7,
        'code': 'tombola',
        'name': 'Tombola',
        'sort_order': 8,
      }),
    ];

    test('offline: the local registry', () {
      final home = homeGamesFor(null, profile);
      expect(home.map((h) => (h.code, h.playable)), [
        ('ludo', true),
        ('chess', true),
      ]);
    });

    test("the catalogue's games in reply order; this app's games playable; chess switched off is left out", () {
      final home = homeGamesFor(catalogue, profile);
      expect(home.map((h) => (h.code, h.name, h.playable)), [
        ('ludo', 'Ludo Royale', true),
      ]);
    });

    test('dev builds list the rest as coming soon, with app icons', () {
      final home = homeGamesFor(catalogue, devProfile);
      expect(home.map((h) => (h.code, h.playable)), [
        ('roulette', false),
        ('snake-and-ladder', false),
        ('ludo', true),
        ('tombola', false),
      ]);
      expect(home.last.id, isNull);
      expect(home.last.icon, GameCodes.info('tombola')!.icon);
    });

    test(
      "a catalogue without any of this app's games falls back to the registry",
      () {
        expect(
          homeGamesFor([
            CatalogueGame.fromJson(_snl),
          ], profile).map((h) => h.code),
          ['ludo', 'chess'],
        );
      },
    );

    test('the app table maps every catalogue code once, with LAN ports from the doc', () {
      final codes = GameCodes.all.map((g) => g.code).toList();
      expect(codes.toSet().length, codes.length);
      expect(codes, hasLength(26));
      expect(GameCodes.codeOf(GameId.snakesLadders), 'snake-and-ladder');
      expect(GameCodes.info('ludo')!.port - 30000, 1285);
      expect(GameCodes.info('word_rush')!.sharedSocket, isTrue);
    });
  });

  group('kill switches', () {
    test("keeps the operator's banner for a few minutes", () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final now = DateTime(2026, 11, 24, 10);
      c
          .read(killSwitchesProvider.notifier)
          .engage('ludo', 'Back at 11:00', now: now);
      final ks = c.read(killSwitchesProvider.notifier);
      expect(
        ks.banner('ludo', now: now.add(const Duration(minutes: 1))),
        'Back at 11:00',
      );
      expect(
        ks.banner('ludo', now: now.add(const Duration(minutes: 6))),
        isNull,
      );
      expect(ks.banner('chess', now: now), isNull);
    });
  });
}
