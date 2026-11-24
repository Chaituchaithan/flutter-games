// The progress and history contract (docs/services/08-progress-and-history.md):
// model parsing of the live replies (including the all-null stats and the
// empty lists), the XP bar maths, the history "load more" loop with
// duplicates dropped, leaderboard paging and the "You" row with a null rank,
// the after-game re-read (one retry) and the error mapping. Dio runs against
// a stand-in adapter that answers like the gateway.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/progress.dart';
import 'package:snakeladder/screens/profile/progress_ui.dart' show levelUpTriggerRef, ratingText;
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/progress_service.dart';

class _Req {
  _Req(this.method, this.path, this.query);
  final String method;
  final String path;
  final Map<String, dynamic> query;
}

typedef _Handler = FutureOr<(int, Object?)> Function(_Req);

class _Gateway implements HttpClientAdapter {
  _Gateway(this.routes);
  final Map<String, _Handler> routes;
  final List<_Req> log = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final req = _Req(o.method, o.uri.path.replaceFirst('/api/v1', ''), o.uri.queryParameters);
    log.add(req);
    final handler = routes['${req.method} ${req.path}'];
    final (status, json) = handler == null ? (404, {'error': 'NOT_FOUND', 'message': 'no route'}) : await handler(req);
    if (status == 0) throw DioException.connectionError(requestOptions: o, reason: 'offline');
    return ResponseBody.fromString(json == null ? '' : jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

RemoteProgressApi _api(_Gateway g) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1/', contentType: 'application/json'))..httpClientAdapter = g;
  return RemoteProgressApi(ApiClient(dio: dio)..authToken = 'acc');
}

(int, Object?) _err(int status, String code, [Map<String, Object?> extra = const {}]) =>
    (status, {'error': code, 'message': 'developer text: $code', ...extra});

// ── Live replies (24 Nov 2026) ──
const _a = '107a8edf-6a2d-415e-b292-f756bc04cd4a';
const _c = '7120bc7c-ae1d-4f47-8ac8-96346f93cccd';
const _levelA = {'user_id': _a, 'game_id': 1, 'level': 2, 'xp': 100, 'updated_at': '2026-11-24T09:44:19.002106Z'};
const _ratingA = {
  'user_id': _a, 'game_id': 1, 'rating': 1016.0, 'wins': 2, 'losses': 0, 'draws': 0, 'updated_at': '2026-11-24T09:44:19.002106Z',
};
const _statsA = {
  'level': _levelA,
  'rating': _ratingA,
  'mmr': {'user_id': _a, 'game_id': 1, 'mmr': 1016, 'peak_mmr': 1016, 'games_played': 1, 'updated_at': '2026-11-24T09:44:19.002106Z'},
};
const _ranked = {
  'id': 'e3b14b75-1a6c-4093-acce-28d1a44a4028', 'game_id': 1, 'mode_id': 59, 'status': 'completed',
  'server_seed': null, 'server_seed_hash': null,
  'created_at': '2026-11-24T09:44:18.978802Z', 'started_at': '2026-11-24T09:44:18.978802Z', 'ended_at': '2026-11-24T09:44:19.002106Z',
  'participants': [
    {
      'id': 19802, 'match_id': 'e3b14b75-1a6c-4093-acce-28d1a44a4028', 'user_id': _a, 'is_bot': false, 'seat': 0,
      'stake_amount': 0, 'payout_amount': 0, 'result': 'win', 'rating_before': 1000, 'rating_after': 1016, 'final_rank': 1, 'score': null,
      'custom_stats': {
        'all_pawns_homed': false, 'captures': 0, 'consecutive_sixes': 0, 'finished': false, 'forfeited': false,
        'pawns_lost': 0, 'place': 1, 'safe_square_landings': 0, 'sixes': 0, 'total_turns': 0, 'future_key': [1, 2],
      },
    },
    {
      'id': 19803, 'match_id': 'e3b14b75-1a6c-4093-acce-28d1a44a4028', 'user_id': _c, 'is_bot': false, 'seat': 2,
      'stake_amount': 0, 'payout_amount': 0, 'result': 'forfeit', 'rating_before': 1000, 'rating_after': 984, 'final_rank': 2,
      'score': null, 'custom_stats': null,
    },
  ],
};

Map<String, Object?> _row(String id, {String status = 'completed', String? result = 'win', int stake = 0, int payout = 0}) => {
      'match_id': id, 'game_id': 1, 'mode_id': 61, 'status': status, 'result': result,
      'stake_amount': stake, 'payout_amount': payout,
      'created_at': '2026-11-24T09:44:08.131695Z', 'ended_at': status == 'completed' ? '2026-11-24T09:44:09.592033Z' : null,
      'game_code': 'ludo', 'game_name': 'Ludo Royale', 'mode_code': 'friends_room', 'mode_name': 'Play with Friends', 'bets': [],
    };

void main() {
  group('models', () {
    test('levels: empty list, live rows, XP bar', () async {
      final g = _Gateway({
        'GET /progression/levels': (_) => (200, [
              {'user_id': '9ee1b34f-0fd6-44de-b4f9-2b8b52bdf0cf', 'game_id': 1, 'level': 1, 'xp': 10, 'updated_at': '2026-11-24T09:44:09.592033Z'},
              _levelA,
            ]),
      });
      final levels = await _api(g).levels();
      expect(levels.first.level, 2, reason: 'highest level first');
      expect(levels.first.xp, 100);
      expect(levels.first.xpNeeded, 200);
      expect(levels.first.fraction, 0.5);
      expect(levels.last.fraction, closeTo(0.1, 1e-9));
      expect(levels.first.updatedAt, DateTime.parse('2026-11-24T09:44:19.002106Z'));

      final empty = _Gateway({'GET /progression/levels': (_) => (200, []), 'GET /progression/ratings': (_) => (200, [])});
      expect(await _api(empty).levels(), isEmpty);
      expect(await _api(empty).ratings(), isEmpty);
    });

    test('XP maths: 100 × level, lifetime totals, table, exp_to_next_level preferred', () {
      expect(xpForNextLevel(1), 100);
      expect(xpForNextLevel(3), 300);
      expect(lifetimeXp(1, 0), 0);
      expect(lifetimeXp(2, 0), 100);
      expect(lifetimeXp(3, 50), 350);
      expect([for (final r in ['win', 'draw', 'loss', 'forfeit', 'quit', null]) xpForResult(r)], [100, 50, 25, 10, null, null]);
      expect(const GameLevel(gameId: 1, level: 2, xp: 0).fraction, 0);
      expect(GameLevel.fromJson({'game_id': 1, 'level': 4, 'xp': 900}).fraction, 1.0, reason: 'clamped');
      expect(GameLevel.fromJson({'game_id': 1, 'level': 2, 'xp': 50, 'exp_to_next_level': 500}).xpNeeded, 500);
      expect(GameLevel.fromJson(const {}).level, 1);
    });

    test('ratings: fraction numbers shown whole; Unranked', () async {
      final g = _Gateway({'GET /progression/ratings': (_) => (200, [_ratingA])});
      final r = (await _api(g).ratings()).single;
      expect(r.rating, 1016.0);
      expect(r.whole, 1016);
      expect((r.wins, r.losses, r.draws), (2, 0, 0));
      expect(ratingText(r), 'Rating 1016');
      expect(ratingText(null), 'Unranked');
      expect(ratingText(r, mmr: const GameMmr(gameId: 1, mmr: 1016, peakMmr: 1040)), 'Rating 1016 (best 1040)');
    });

    test('stats: all null, level only, all three', () async {
      var reply = <String, Object?>{'level': null, 'rating': null, 'mmr': null};
      final g = _Gateway({'GET /progression/1/stats': (_) => (200, reply), 'GET /progression/99999/stats': (_) => (200, reply)});
      var s = await _api(g).gameStats(99999);
      expect((s.level, s.rating, s.mmr), (null, null, null));
      expect(s.ranked, isFalse);

      reply = {'level': _levelA, 'rating': null, 'mmr': null};
      s = await _api(g).gameStats(1);
      expect(s.level!.level, 2);
      expect(s.ranked, isFalse);

      reply = _statsA;
      s = await _api(g).gameStats(1);
      expect(s.rating!.whole, 1016);
      expect(s.mmr!.mmr, 1016);
      expect(s.mmr!.peakMmr, 1016);
      expect(s.mmr!.gamesPlayed, 1);
    });

    test('leaderboard rows and my-rank (null and set)', () async {
      final g = _Gateway({
        'GET /leaderboards/1/wins': (_) => (200, [
              {'rank': 1, 'user_id': '92ac29f6-61d3-4a2d-aad9-41e62c2b06cc', 'score': 4.0, 'username': 'w05docb11951', 'avatar_url': null},
              {'rank': 2, 'user_id': '0481e998-3ff0-458e-b171-77df0b825ec8', 'score': 2.0, 'username': null, 'avatar_url': null},
            ]),
        'GET /leaderboards/1/wins/my-rank': (_) => (200, {'rank': null, 'score': null}),
        'GET /leaderboards/1/rating/my-rank': (_) => (200, {'rank': 1, 'score': 1016.0}),
      });
      final api = _api(g);
      final rows = await api.leaderboard(1, LeaderboardMetric.wins, limit: 3);
      expect(g.log.last.query, {'limit': '3', 'offset': '0'});
      expect(rows.first.whole, 4);
      expect(rows.last.name, 'Player', reason: 'a gone account');
      final off = await api.myRank(1, LeaderboardMetric.wins);
      expect(off.onBoard, isFalse);
      expect(off.score, isNull);
      final on = await api.myRank(1, LeaderboardMetric.rating);
      expect((on.rank, on.score), (1, 1016.0));
      expect(LeaderboardMetric.rating.offBoardText, contains('ranked'));
    });

    test('history page: in-progress row, completed rows, bets', () async {
      final p = HistoryPage.fromJson({
        'data': [
          _row('2816e39e-61f6-44e1-8485-5d7483447f1c', status: 'in_progress', result: null),
          {
            ..._row('5b0d1c2e-7f3a-4e8b-9c6d-2a1b3c4d5e6f', stake: 200, payout: 150),
            'game_code': 'crash',
            'bets': [
              {'bet_index': 0, 'amount': 100, 'auto_cashout_at': 2.0, 'cashout_multiplier': 1.5, 'payout_amount': 150, 'outcome': 'won'},
              {'bet_index': 1, 'amount': '100', 'auto_cashout_at': null, 'cashout_multiplier': null, 'payout_amount': 0, 'outcome': 'lost'},
            ],
          },
        ],
        'total': 2, 'page': 1, 'per_page': 20, 'total_pages': 1,
      });
      final running = p.data.first;
      expect(running.inProgress, isTrue);
      expect(running.chip, MatchChip.playing);
      expect(running.endedAt, isNull);
      expect(running.staked, isFalse);
      final crash = p.data.last;
      expect(crash.chip, MatchChip.won);
      expect(crash.net, -50);
      expect(crash.bets.map((b) => (b.amount, b.won, b.cashoutMultiplier)), [(100, true, 1.5), (100, false, null)]);
      expect(p.hasMore, isFalse);
      // Empty history (live).
      final empty = HistoryPage.fromJson({'data': [], 'total': 0, 'page': 1, 'per_page': 20, 'total_pages': 0});
      expect(empty.data, isEmpty);
      expect((empty.total, empty.hasMore), (0, false));
    });

    test('chips: every result and status, unknown values never fail', () {
      expect(matchChip('completed', 'win'), MatchChip.won);
      expect(matchChip('completed', 'loss'), MatchChip.lost);
      expect(matchChip('completed', 'draw'), MatchChip.draw);
      expect(matchChip('completed', 'forfeit'), MatchChip.forfeit);
      expect(matchChip('in_progress', null), MatchChip.playing);
      expect(matchChip('cancelled', null), MatchChip.cancelled);
      expect(matchChip('abandoned', null), MatchChip.cancelled);
      expect(matchChip('settling', 'surrender'), MatchChip.finished);
      expect(matchChip(null, null).label, 'Finished');
    });

    test('match detail: seats by place, rating change, Ludo stats, unknown keys', () {
      final m = MatchDetail.fromJson(_ranked);
      expect(m.participants.length, 2);
      expect(m.byPlace.map((p) => p.userId), [_a, _c]);
      expect(m.seatOf(_a)!.ratingChange, 16);
      expect(m.seatOf(_c)!.ratingChange, -16);
      expect(m.ratingMoved, isTrue);
      expect(m.length, const Duration(microseconds: 23304));
      expect(ludoStatLines(m.seatOf(_a)!.customStats).map((e) => e.$1), ['Captures', 'Pawns lost', 'Sixes', 'Turns']);
      expect(ludoStatLines(null), isEmpty);
      // Running: everything unsettled is null.
      final running = MatchDetail.fromJson({
        'id': 'x', 'game_id': 1, 'mode_id': 61, 'status': 'in_progress', 'ended_at': null,
        'participants': [
          {'id': 19800, 'user_id': _a, 'is_bot': false, 'seat': 0, 'result': null, 'rating_before': null, 'rating_after': null,
            'final_rank': null, 'score': null, 'custom_stats': null},
          {'id': 19801, 'user_id': null, 'is_bot': true, 'seat': null},
        ],
      });
      expect(running.inProgress, isTrue);
      expect(running.length, isNull);
      expect(running.participants.first.ratingChange, isNull);
      expect(running.participants.last.isBot, isTrue);
      // Unranked: equal before and after.
      final casual = MatchDetail.fromJson({
        'id': 'y', 'participants': [{'id': 1, 'user_id': _a, 'rating_before': 1000, 'rating_after': 1000, 'result': 'win'}],
      });
      expect(casual.ratingMoved, isFalse);
    });
  });

  group('requests', () {
    test('paths use numeric ids and clamp page sizes', () async {
      final g = _Gateway({
        'GET /matches/my-history': (_) => (200, {'data': [], 'total': 0, 'page': 1, 'per_page': 20, 'total_pages': 0}),
        'GET /leaderboards/7/tokens_earned': (_) => (200, []),
      });
      final api = _api(g);
      await api.history(page: 0, perPage: 0);
      expect(g.log.last.query, {'page': '1', 'per_page': '1'}, reason: 'never per_page=0 or page 0');
      await api.history(perPage: 500);
      expect(g.log.last.query['per_page'], '100');
      await api.leaderboard(7, LeaderboardMetric.tokensEarned, limit: 0, offset: -5);
      expect(g.log.last.query, {'limit': '1', 'offset': '0'});
    });
  });

  group('errors', () {
    test('MATCH_NOT_FOUND, bad id, offline, rate limit, 5xx', () async {
      final g = _Gateway({
        'GET /matches/00000000-0000-4000-8000-000000000000': (_) =>
            _err(404, 'MATCH_NOT_FOUND', {'message': 'match not found: 00000000-0000-4000-8000-000000000000'}),
        'GET /matches/nope': (_) => _err(400, 'BAD_REQUEST'),
        'GET /progression/levels': (_) => (0, null),
        'GET /progression/ratings': (_) => _err(429, 'RATE_LIMITED'),
        'GET /progression/1/stats': (_) => _err(500, 'INTERNAL_ERROR'),
        'GET /leaderboards/1/wins': (_) => _err(400, 'VALIDATION_ERROR', {'field': 'limit'}),
      });
      final api = _api(g);
      Future<AppException> fail(Future<Object?> f) async {
        try {
          await f;
        } on AppException catch (e) {
          return e;
        }
        throw StateError('no error');
      }

      final gone = await fail(api.match('00000000-0000-4000-8000-000000000000'));
      expect((gone.statusCode, gone.code, gone.message), (404, ApiErrorCode.matchNotFound, 'This match is no longer available.'));
      expect((await fail(api.match('nope'))).message, progressLoadFailed);
      expect((await fail(api.levels())).message, "Can't reach the server. Check your connection.");
      expect((await fail(api.ratings())).message, 'Too many requests. Try again in a minute.');
      expect((await fail(api.gameStats(1))).message, progressLoadFailed);
      final v = await fail(api.leaderboard(1, LeaderboardMetric.wins));
      expect((v.code, v.field, v.message), (ApiErrorCode.validation, 'limit', progressLoadFailed));
    });
  });

  group('history load more', () {
    test('pages until total_pages, drops rows already shown, refresh reloads page 1', () async {
      // Page 2 repeats the last row of page 1: a new match arrived on top.
      final pages = {
        '1': [_row('m1'), _row('m2')],
        '2': [_row('m2'), _row('m3')],
        '3': [_row('m4')],
      };
      final g = _Gateway({
        'GET /matches/my-history': (r) {
          final p = r.query['page']!;
          return (200, {'data': pages[p], 'total': 5, 'page': int.parse(p), 'per_page': 2, 'total_pages': 3});
        },
      });
      final pager = HistoryPager(_api(g), perPage: 2);
      await pager.refresh();
      expect(pager.items.map((e) => e.matchId), ['m1', 'm2']);
      expect(pager.hasMore, isTrue);
      await pager.loadMore();
      expect(pager.items.map((e) => e.matchId), ['m1', 'm2', 'm3']);
      await pager.loadMore();
      expect(pager.items.map((e) => e.matchId), ['m1', 'm2', 'm3', 'm4']);
      expect(pager.hasMore, isFalse);
      await pager.loadMore(); // no request past the last page
      expect(g.log.map((r) => r.query['page']), ['1', '2', '3']);
      expect(g.log.every((r) => r.query['per_page'] == '2'), isTrue);
      await pager.refresh();
      expect(pager.items.map((e) => e.matchId), ['m1', 'm2']);
    });

    test('a failed page keeps the rows and shows the text', () async {
      var fail = false;
      final g = _Gateway({
        'GET /matches/my-history': (r) => fail
            ? _err(503, 'CIRCUIT_OPEN')
            : (200, {'data': [_row('m1')], 'total': 2, 'page': 1, 'per_page': 1, 'total_pages': 2}),
      });
      final pager = HistoryPager(_api(g), perPage: 1);
      await pager.refresh();
      fail = true;
      await pager.loadMore();
      expect(pager.items.length, 1);
      expect(pager.error, progressLoadFailed);
      expect(pager.hasMore, isTrue);
    });
  });

  group('leaderboard pager', () {
    test('offset paging until a short page; You row when not on the board', () async {
      Map<String, Object?> e(int rank) => {'rank': rank, 'user_id': 'u$rank', 'score': 100.0 - rank, 'username': 'p$rank', 'avatar_url': null};
      final g = _Gateway({
        'GET /leaderboards/1/rating': (r) {
          final off = int.parse(r.query['offset']!);
          final n = off == 0 ? 2 : 1;
          return (200, [for (var i = 0; i < n; i++) e(off + i + 1)]);
        },
        'GET /leaderboards/1/rating/my-rank': (_) => (200, {'rank': null, 'score': null}),
      });
      final pager = LeaderboardPager(_api(g), gameId: 1, metric: LeaderboardMetric.rating, limit: 2);
      await pager.refresh();
      expect(pager.rows.map((r) => r.rank), [1, 2]);
      expect(pager.me!.onBoard, isFalse);
      expect(pager.hasMore, isTrue);
      await pager.loadMore();
      expect(pager.rows.map((r) => r.rank), [1, 2, 3]);
      expect(g.log.last.query, {'limit': '2', 'offset': '2'});
      expect(pager.hasMore, isFalse, reason: 'short page = end');
    });
  });

  group('after a game', () {
    setUp(() => ProgressStore.retryDelay = Duration.zero);

    ProviderContainer container(ProgressApi api) {
      final c = ProviderContainer(overrides: [progressApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      return c;
    }

    test('first win: +100 XP and a level-up from no row; ranked +16', () async {
      var stats = <String, Object?>{'level': null, 'rating': null, 'mmr': null};
      final g = _Gateway({
        'GET /progression/levels': (_) => (200, []),
        'GET /progression/ratings': (_) => (200, []),
        'GET /progression/1/stats': (_) => (200, stats),
      });
      final c = container(_api(g));
      final store = c.read(progressStoreProvider.notifier);
      await store.ensureLoaded();
      expect(c.read(progressStoreProvider).loaded, isTrue);
      stats = {
        'level': {'game_id': 1, 'level': 2, 'xp': 0},
        'rating': {'game_id': 1, 'rating': 1016.0, 'wins': 1},
        'mmr': {'game_id': 1, 'mmr': 1016, 'peak_mmr': 1016, 'games_played': 1},
      };
      final d = (await store.afterGame(1))!;
      expect(d.xpGained, 100);
      expect(d.leveledUp, isTrue);
      expect(d.newLevel, 2);
      expect(d.ratingChange, 16, reason: 'a first rating starts at 1000');
      expect(d.summary, '+100 XP  ·  +16 rating');
      final s = c.read(progressStoreProvider);
      expect(s.levelFor(1)!.level, 2);
      expect(s.ratingFor(1)!.whole, 1016);
      expect(s.lastDelta, same(d));
      expect(s.revision, 1);
      expect(levelUpTriggerRef(1, d.newLevel!), '1:2');
    });

    test('unchanged at first: one retry, then what is there; no third read', () async {
      var reads = 0;
      final g = _Gateway({
        'GET /progression/levels': (_) => (200, [_levelA]),
        'GET /progression/ratings': (_) => (200, [_ratingA]),
        'GET /progression/1/stats': (_) {
          reads++;
          return (200, reads == 1 ? _statsA : {'level': {'game_id': 1, 'level': 2, 'xp': 110}, 'rating': _ratingA, 'mmr': null});
        },
      });
      final c = container(_api(g));
      final store = c.read(progressStoreProvider.notifier);
      await store.refresh();
      final d = (await store.afterGame(1, result: 'forfeit'))!;
      expect(reads, 2);
      expect(d.xpGained, 10, reason: 'from the XP table for the result');
      expect(d.leveledUp, isFalse);
      expect(d.ratingChange, isNull, reason: 'unranked game: the rating did not move');
      // A second frame for the same game end: no new read.
      expect(await store.afterGame(1), isNull);
      expect(reads, 2);
    });

    test('nothing moved after the retry: no change shown', () async {
      var reads = 0;
      final g = _Gateway({
        'GET /progression/levels': (_) => (200, [_levelA]),
        'GET /progression/ratings': (_) => (200, []),
        'GET /progression/1/stats': (_) {
          reads++;
          return (200, {'level': _levelA, 'rating': null, 'mmr': null});
        },
      });
      final c = container(_api(g));
      final store = c.read(progressStoreProvider.notifier);
      await store.refresh();
      final d = (await store.afterGame(1))!;
      expect(reads, 2);
      expect(d.changed, isFalse);
    });

    test('a failed re-read keeps the held values', () async {
      final g = _Gateway({
        'GET /progression/levels': (_) => (200, [_levelA]),
        'GET /progression/ratings': (_) => (200, []),
        'GET /progression/1/stats': (_) => _err(503, 'CIRCUIT_OPEN'),
      });
      final c = container(_api(g));
      final store = c.read(progressStoreProvider.notifier);
      await store.refresh();
      expect(await store.afterGame(1), isNull);
      expect(c.read(progressStoreProvider).levelFor(1)!.xp, 100);
    });

    test('a failed list read keeps the cached lists and the text', () async {
      var fail = false;
      final g = _Gateway({
        'GET /progression/levels': (_) => fail ? _err(500, 'INTERNAL_ERROR') : (200, [_levelA]),
        'GET /progression/ratings': (_) => (200, []),
      });
      final c = container(_api(g));
      final store = c.read(progressStoreProvider.notifier);
      await store.refresh();
      fail = true;
      await store.refresh(force: true);
      final s = c.read(progressStoreProvider);
      expect(s.levels.single.level, 2);
      expect(s.error, progressLoadFailed);
    });
  });

  group('demo', () {
    test('demo data answers every route; unknown match is MATCH_NOT_FOUND', () async {
      final api = DemoProgressApi(myId: 'me');
      expect((await api.levels()).length, 2);
      expect((await api.gameStats(2)).level, isNull);
      expect((await api.myRank(1, LeaderboardMetric.tokensEarned)).onBoard, isFalse);
      expect((await api.myRank(1, LeaderboardMetric.rating)).rank, isNotNull);
      final p1 = await api.history();
      expect((p1.data.length, p1.totalPages), (20, 2));
      final m = await api.match(p1.data.first.matchId);
      expect(m.seatOf('me'), isNotNull);
      await expectLater(api.match('nope'), throwsA(isA<AppException>().having((e) => e.code, 'code', ApiErrorCode.matchNotFound)));
    });
  });
}
