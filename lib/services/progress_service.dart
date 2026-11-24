import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/configs.dart';
import '../configs/games/core/game_codes.dart';
import '../data/models/progress.dart';
import 'api_client.dart';
import 'app_exception.dart';
import 'catalogue_service.dart';
import 'session.dart';

/// Progress and history routes (docs/services/08-progress-and-history.md):
/// levels, ratings, one game's stats, leaderboards, match history and one
/// past match. All reads; never polled. Every method returns a typed result
/// or throws [AppException] with this file's player text ([progressErrorText]).
abstract class ProgressApi {
  /// `GET /progression/levels` — games the player finished a match of.
  Future<List<GameLevel>> levels();

  /// `GET /progression/ratings` — games with at least one ranked match.
  Future<List<GameRating>> ratings();

  /// `GET /progression/{game_id}/stats` — all `null` for an unplayed game.
  Future<GameStats> gameStats(int gameId);

  /// `GET /leaderboards/{game_id}/{metric}?limit=&offset=` ([limit] 1-100).
  Future<List<LeaderboardEntry>> leaderboard(int gameId, LeaderboardMetric metric, {int limit = 20, int offset = 0});

  /// `GET /leaderboards/{game_id}/{metric}/my-rank`.
  Future<MyRank> myRank(int gameId, LeaderboardMetric metric);

  /// `GET /matches/my-history?page=&per_page=` — newest first. [page] ≥ 1,
  /// [perPage] 1-100 (the server checks neither: Known issues 5).
  Future<HistoryPage> history({int page = 1, int perPage = 20});

  /// `GET /matches/{match_id}`.
  Future<MatchDetail> match(String matchId);
}

/// History page size, always 1-100 (`per_page=0` breaks the server).
int clampPerPage(int perPage) => perPage.clamp(1, 100);

/// Leaderboard page size, 1-100.
int clampLimit(int limit) => limit.clamp(1, 100);

Map<String, dynamic> _obj(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
List<Map<String, dynamic>> _rows(Object? v) => [
      for (final r in (v is List ? v : const []))
        if (r is Map) r.cast<String, dynamic>(),
    ];

/// The live gateway.
class RemoteProgressApi implements ProgressApi {
  RemoteProgressApi(this._api);
  final ApiClient _api;

  Future<T> _guard<T>(Future<T> Function() run, {bool match = false}) async {
    try {
      return await run();
    } on AppException catch (e) {
      throw progressError(e, match: match);
    }
  }

  @override
  Future<List<GameLevel>> levels() => _guard(() async {
        final list = [for (final r in _rows(await _api.get(ApiEndpoints.progressionLevels))) GameLevel.fromJson(r)];
        // Highest level first (the server's order; kept if it ever changes).
        return list..sort((a, b) => b.lifetime.compareTo(a.lifetime));
      });

  @override
  Future<List<GameRating>> ratings() => _guard(() async =>
      [for (final r in _rows(await _api.get(ApiEndpoints.progressionRatings))) GameRating.fromJson(r)]);

  @override
  Future<GameStats> gameStats(int gameId) =>
      _guard(() async => GameStats.fromJson(_obj(await _api.get(ApiEndpoints.progressionStats(gameId)))));

  @override
  Future<List<LeaderboardEntry>> leaderboard(int gameId, LeaderboardMetric metric, {int limit = 20, int offset = 0}) =>
      _guard(() async => [
            for (final r in _rows(await _api.get(
              ApiEndpoints.leaderboardBoard(gameId, metric.wire),
              query: {'limit': clampLimit(limit), 'offset': offset.clamp(0, 1000000)},
            )))
              LeaderboardEntry.fromJson(r),
          ]);

  @override
  Future<MyRank> myRank(int gameId, LeaderboardMetric metric) =>
      _guard(() async => MyRank.fromJson(_obj(await _api.get(ApiEndpoints.leaderboardMyRank(gameId, metric.wire)))));

  @override
  Future<HistoryPage> history({int page = 1, int perPage = 20}) => _guard(() async => HistoryPage.fromJson(_obj(
        await _api.get(ApiEndpoints.myMatchHistory, query: {'page': page < 1 ? 1 : page, 'per_page': clampPerPage(perPage)}),
      )));

  @override
  Future<MatchDetail> match(String matchId) =>
      _guard(() async => MatchDetail.fromJson(_obj(await _api.get(ApiEndpoints.match(matchId)))), match: true);
}

// ── Errors ────────────────────────────────────────────────────────────────

const progressLoadFailed = "Couldn't load. Pull to refresh.";
const matchGoneText = 'This match is no longer available.';

/// The player's text for a failed progress read. Every route here is a read:
/// 400s are app bugs and 5xx are "Couldn't load"; the cached data stays.
String progressErrorText(AppException e, {bool match = false}) {
  if (e.isOffline || e.kind == AppErrorKind.timeout) return "Can't reach the server. Check your connection.";
  if (e.code == ApiErrorCode.matchNotFound || (match && e.statusCode == 404)) return matchGoneText;
  if (e.statusCode == 401) return e.message; // the client signs out
  if (e.isKillSwitch && e.message.isNotEmpty) return e.message;
  if (e.isRateLimited) return 'Too many requests. Try again in a minute.';
  return progressLoadFailed;
}

/// [e] with [progressErrorText]; keeps the status and code for callers.
AppException progressError(AppException e, {bool match = false}) {
  final text = progressErrorText(e, match: match);
  if (text == e.message) return e;
  return AppException(text, kind: e.kind, statusCode: e.statusCode, code: e.code, field: e.field, until: e.until, detail: e.detail);
}

// ── Demo ──────────────────────────────────────────────────────────────────

/// Signed-out demo: fixed data shaped like the gateway's replies. Game ids
/// follow the demo catalogue (Ludo 1, Snake & Ladder 2, Chess 3).
class DemoProgressApi implements ProgressApi {
  DemoProgressApi({this.myId = 'demo-user', this.myName = 'You'});
  final String myId;
  final String myName;

  static final _now = DateTime.now().toUtc();

  @override
  Future<List<GameLevel>> levels() async => [
        GameLevel(gameId: 1, level: 3, xp: 120, userId: myId, updatedAt: _now),
        GameLevel(gameId: 3, level: 2, xp: 40, userId: myId, updatedAt: _now),
      ];

  @override
  Future<List<GameRating>> ratings() async => [
        GameRating(gameId: 1, rating: 1032.0, wins: 5, losses: 2, userId: myId, updatedAt: _now),
      ];

  @override
  Future<GameStats> gameStats(int gameId) async {
    final l = (await levels()).where((e) => e.gameId == gameId).firstOrNull;
    final r = (await ratings()).where((e) => e.gameId == gameId).firstOrNull;
    return GameStats(
      level: l,
      rating: r,
      mmr: r == null ? null : GameMmr(gameId: gameId, mmr: r.whole, peakMmr: r.whole + 8, gamesPlayed: 4, userId: myId),
    );
  }

  static const _names = ['KaiStorm', 'ZeroCool', 'LunaWolf', 'NovaByte', 'EchoRay', 'PixelFox', 'SoloAce', 'RiftWalker'];

  List<LeaderboardEntry> _board(int gameId, LeaderboardMetric metric) {
    if (gameId != 1 && gameId != 3) return const [];
    final mine = (metric == LeaderboardMetric.rating) ? 1032 : (metric == LeaderboardMetric.wins ? 5 : null);
    final rows = <LeaderboardEntry>[];
    for (var i = 0; i < _names.length; i++) {
      final score = switch (metric) {
        LeaderboardMetric.wins => 24 - i * 3,
        LeaderboardMetric.rating => 1180 - i * 24,
        LeaderboardMetric.tokensEarned => 4800 - i * 520,
      };
      rows.add(LeaderboardEntry(rank: 0, userId: 'demo-u$i', score: score.toDouble(), username: _names[i]));
    }
    if (mine != null) rows.add(LeaderboardEntry(rank: 0, userId: myId, score: mine.toDouble(), username: myName));
    rows.sort((a, b) => b.score.compareTo(a.score));
    return [
      for (var i = 0; i < rows.length; i++)
        LeaderboardEntry(rank: i + 1, userId: rows[i].userId, score: rows[i].score, username: rows[i].username),
    ];
  }

  @override
  Future<List<LeaderboardEntry>> leaderboard(int gameId, LeaderboardMetric metric, {int limit = 20, int offset = 0}) async =>
      _board(gameId, metric).skip(offset).take(clampLimit(limit)).toList();

  @override
  Future<MyRank> myRank(int gameId, LeaderboardMetric metric) async {
    final me = _board(gameId, metric).where((e) => e.userId == myId).firstOrNull;
    return MyRank(rank: me?.rank, score: me?.score);
  }

  static final List<HistoryEntry> _history = () {
    const games = [(1, 'ludo', 'Ludo Royale'), (3, 'chess', 'Chess')];
    const modes = [('ranked_2p', 'Ranked 2 Players'), ('friends_room', 'Play with Friends'), ('classic', 'Classic')];
    const results = ['win', 'loss', 'win', 'draw', 'forfeit', 'win', 'loss'];
    return [
      for (var i = 0; i < 26; i++)
        () {
          final g = games[i % 2], m = modes[i % 3], r = results[i % results.length];
          final stake = i % 3 == 2 ? 50 : 0;
          final at = _now.subtract(Duration(hours: i * 7 + 1));
          return HistoryEntry(
            matchId: i == 0 ? 'demo-match' : 'demo-match-$i',
            gameId: g.$1,
            modeId: 50 + i % 3,
            status: 'completed',
            result: r,
            stakeAmount: stake,
            payoutAmount: stake > 0 && r == 'win' ? 95 : (stake > 0 && r == 'draw' ? 50 : 0),
            createdAt: at,
            endedAt: at.add(const Duration(minutes: 9)),
            gameCode: g.$2,
            gameName: g.$3,
            modeCode: m.$1,
            modeName: m.$2,
          );
        }(),
    ];
  }();

  @override
  Future<HistoryPage> history({int page = 1, int perPage = 20}) async {
    final per = clampPerPage(perPage), p = page < 1 ? 1 : page;
    final total = _history.length;
    return HistoryPage(
      data: _history.skip((p - 1) * per).take(per).toList(),
      total: total,
      page: p,
      perPage: per,
      totalPages: (total + per - 1) ~/ per,
    );
  }

  @override
  Future<MatchDetail> match(String matchId) async {
    final h = _history.where((e) => e.matchId == matchId).firstOrNull;
    if (h == null) {
      throw progressError(
        const AppException('', kind: AppErrorKind.notFound, statusCode: 404, code: ApiErrorCode.matchNotFound),
        match: true,
      );
    }
    final ranked = h.modeCode == 'ranked_2p';
    final won = h.result == 'win';
    final draw = h.result == 'draw';
    final theirs = switch (h.result) { 'win' => 'loss', 'loss' => 'win', 'forfeit' => 'win', _ => h.result };
    Map<String, dynamic> ludo(bool homed, int caps) => {
          'place': homed ? 1 : 2, 'captures': caps, 'sixes': 4 + caps, 'pawns_lost': 1, 'total_turns': 38, 'all_pawns_homed': homed,
        };
    return MatchDetail(
      id: h.matchId,
      gameId: h.gameId,
      modeId: h.modeId,
      status: h.status,
      createdAt: h.createdAt,
      startedAt: h.createdAt,
      endedAt: h.endedAt,
      participants: [
        MatchParticipant(
          id: 1, userId: myId, seat: 0, stakeAmount: h.stakeAmount, payoutAmount: h.payoutAmount, result: h.result,
          ratingBefore: 1016, ratingAfter: ranked && !draw ? (won ? 1032 : 1000) : 1016,
          finalRank: won || draw ? 1 : 2, customStats: h.gameId == 1 ? ludo(won, 3) : null,
        ),
        MatchParticipant(
          id: 2, userId: 'demo-u1', seat: 2, stakeAmount: h.stakeAmount, payoutAmount: theirs == 'win' ? h.stakeAmount * 2 - 5 : 0,
          result: theirs, ratingBefore: 1010, ratingAfter: ranked && !draw ? (won ? 994 : 1026) : 1010,
          finalRank: won || draw ? 2 : 1, customStats: h.gameId == 1 ? ludo(!won, 1) : null,
        ),
      ],
    );
  }
}

/// Live when signed in against the real API; the demo otherwise.
final progressApiProvider = Provider<ProgressApi>((ref) {
  if (ref.watch(progressLiveProvider)) return RemoteProgressApi(ref.watch(apiClientProvider));
  final me = ref.watch(currentUserProvider);
  return DemoProgressApi(myId: me.id, myName: me.displayName);
});

// ── Catalogue lookups ─────────────────────────────────────────────────────

/// Live progress reads (signed in against the real API) vs the demo.
final progressLiveProvider = Provider<bool>(
  (ref) => ref.watch(useRemoteAuthProvider) && ref.watch(sessionProvider.select((u) => u != null)),
);

/// The games to name progress rows by: the live catalogue when signed in,
/// the demo catalogue (whose ids the demo data uses) otherwise.
final progressGamesProvider = FutureProvider<List<CatalogueGame>>((ref) {
  if (!ref.watch(progressLiveProvider)) return const DemoCatalogueApi().games();
  return ref.watch(catalogueGamesProvider.future);
});

/// The numeric game id for [code] (never hard-coded: ids differ per server).
Future<int?> progressGameId(Ref ref, String code) async {
  try {
    if (!ref.read(progressLiveProvider)) {
      return (await const DemoCatalogueApi().games()).where((g) => g.code == code).firstOrNull?.id;
    }
    return (await ref.read(catalogueRepositoryProvider).gameByCode(code))?.id;
  } on AppException catch (_) {
    return null;
  }
}

/// The catalogue game with numeric [id] from the loaded list, or null.
CatalogueGame? catalogueGameById(List<CatalogueGame>? games, int? id) =>
    id == null ? null : games?.where((g) => g.id == id).firstOrNull;

/// The numeric id of [code] (catalogue).
final progressGameIdProvider = FutureProvider.autoDispose.family<int?, String>((ref, code) {
  ref.watch(progressLiveProvider);
  return progressGameId(ref, code);
});

/// One game's level, rating and MMR (game page header). Re-read when the
/// [ProgressStore] changes (after a game).
final gameStatsProvider = FutureProvider.autoDispose.family<GameStats, int>((ref, gameId) {
  ref.watch(progressStoreProvider.select((s) => s.revision));
  return ref.watch(progressApiProvider).gameStats(gameId);
});

/// One past match. Not cached: a running match changes.
final matchDetailProvider = FutureProvider.autoDispose.family<MatchDetail, String>(
  (ref, id) => ref.watch(progressApiProvider).match(id),
);

// ── ProgressStore ─────────────────────────────────────────────────────────

@immutable
class ProgressState {
  const ProgressState({
    this.levels = const [],
    this.ratings = const [],
    this.loaded = false,
    this.loading = false,
    this.error,
    this.lastDelta,
    this.revision = 0,
  });

  final List<GameLevel> levels;
  final List<GameRating> ratings;

  /// Read at least once for this user (else "before" values are unknown).
  final bool loaded;
  final bool loading;

  /// The last read failed ([progressErrorText]); the held lists stay.
  final String? error;

  /// What the last finished match changed (result screen, level-up).
  final ProgressDelta? lastDelta;

  /// Bumped after every game: history, leaderboards and stats re-read.
  final int revision;

  GameLevel? levelFor(int gameId) => levels.where((l) => l.gameId == gameId).firstOrNull;
  GameRating? ratingFor(int gameId) => ratings.where((r) => r.gameId == gameId).firstOrNull;

  ProgressState copyWith({
    List<GameLevel>? levels,
    List<GameRating>? ratings,
    bool? loaded,
    bool? loading,
    String? error,
    bool clearError = false,
    ProgressDelta? lastDelta,
    int? revision,
  }) =>
      ProgressState(
        levels: levels ?? this.levels,
        ratings: ratings ?? this.ratings,
        loaded: loaded ?? this.loaded,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        lastDelta: lastDelta ?? this.lastDelta,
        revision: revision ?? this.revision,
      );
}

/// The signed-in player's levels and ratings (one store per user). Read at
/// start, on pull to refresh and on resume; after a game, [afterGame] re-reads
/// the one game and works out what changed. Never polls.
class ProgressStore extends Notifier<ProgressState> {
  /// Wait before the one re-read when the stats look unchanged.
  @visibleForTesting
  static Duration retryDelay = const Duration(seconds: 2);

  /// Re-reads closer together than this are skipped (Limits: 10 s).
  static const minGap = Duration(seconds: 10);
  DateTime? _lastRead;
  Future<void>? _loading;
  final _afterGameAt = <int, DateTime>{};

  @override
  ProgressState build() {
    ref.watch(sessionProvider.select((u) => u?.id));
    return const ProgressState();
  }

  ProgressApi get _api => ref.read(progressApiProvider);

  /// Loads once (no-op when already loaded or loading).
  Future<void> ensureLoaded() => state.loaded ? Future.value() : refresh();

  /// Re-reads levels and ratings. [force] = pull to refresh (else at most
  /// once every 10 seconds).
  Future<void> refresh({bool force = false}) {
    final last = _lastRead;
    if (!force && state.loaded && last != null && DateTime.now().difference(last) < minGap) return Future.value();
    return _loading ??= () async {
      state = state.copyWith(loading: true);
      try {
        final (levels, ratings) = await (_api.levels(), _api.ratings()).wait;
        _lastRead = DateTime.now();
        if (ref.mounted) state = state.copyWith(levels: levels, ratings: ratings, loaded: true, loading: false, clearError: true);
      } on ParallelWaitError<dynamic, dynamic> catch (e) {
        final err = [e.errors.$1, e.errors.$2].whereType<AsyncError>().firstOrNull?.error;
        if (ref.mounted) {
          state = state.copyWith(loading: false, error: err is AppException ? err.message : progressLoadFailed);
        }
      } on AppException catch (e) {
        if (ref.mounted) state = state.copyWith(loading: false, error: e.message);
      } finally {
        _loading = null;
      }
    }();
  }

  /// After a game of [gameId] ends: one `stats` read (one more after
  /// [retryDelay] if nothing moved yet), compared with the values held
  /// before. [result] (`win` …) picks the "+N XP" from the XP table when
  /// known. Returns the change, or null when the read failed.
  Future<ProgressDelta?> afterGame(int gameId, {String? result}) async {
    // One game end can arrive as several frames: one re-read per game per
    // 10 seconds (Limits).
    final now = DateTime.now();
    final last = _afterGameAt[gameId];
    if (last != null && now.difference(last) < minGap) return null;
    _afterGameAt[gameId] = now;
    final known = state.loaded;
    final before = state.levelFor(gameId);
    final ratingBefore = known ? (state.ratingFor(gameId)?.rating ?? 1000) : null;
    bool unchanged(GameStats s) {
      final l = s.level;
      if (l == null) return true;
      if (before == null) return !known; // a first row is a change
      return l.level == before.level && l.xp == before.xp;
    }

    final api = _api;
    GameStats stats;
    try {
      stats = await api.gameStats(gameId);
      if (unchanged(stats)) {
        await Future<void>.delayed(retryDelay);
        stats = await api.gameStats(gameId);
      }
    } on AppException catch (_) {
      return null;
    }
    if (!ref.mounted) return null;
    final delta = ProgressDelta(
      gameId: gameId,
      before: known ? before : stats.level,
      after: stats,
      ratingBefore: stats.rating == null ? null : ratingBefore,
      result: result,
    );
    final levels = [
      for (final l in state.levels)
        if (l.gameId != gameId) l,
      ?stats.level,
    ]..sort((a, b) => b.lifetime.compareTo(a.lifetime));
    final ratings = [
      for (final r in state.ratings)
        if (r.gameId != gameId) r,
      ?stats.rating,
    ]..sort((a, b) => b.rating.compareTo(a.rating));
    state = state.copyWith(levels: levels, ratings: ratings, lastDelta: delta, revision: state.revision + 1);
    return delta;
  }
}

final progressStoreProvider = NotifierProvider<ProgressStore, ProgressState>(ProgressStore.new);

// ── Paged lists ───────────────────────────────────────────────────────────

/// Match history with "load more" (`page` + 1 until `total_pages`), dropping
/// rows already shown (new matches shift the pages).
class HistoryPager extends ChangeNotifier {
  HistoryPager(this._api, {int perPage = 20}) : perPage = clampPerPage(perPage);
  final ProgressApi _api;
  final int perPage;

  final List<HistoryEntry> items = [];
  final Set<String> _ids = {};
  int _page = 0;
  int _totalPages = 0;
  int total = 0;
  bool loading = false;
  bool loaded = false;

  /// The last failure's text; the rows already shown stay.
  String? error;

  bool get hasMore => loaded && _page < _totalPages;

  /// Pull to refresh: page 1 again.
  Future<void> refresh() => _load(1, replace: true);

  Future<void> loadMore() async {
    if (!hasMore || loading) return;
    await _load(_page + 1);
  }

  Future<void> _load(int page, {bool replace = false}) async {
    loading = true;
    notifyListeners();
    try {
      final p = await _api.history(page: page, perPage: perPage);
      if (replace) {
        items.clear();
        _ids.clear();
      }
      for (final e in p.data) {
        if (_ids.add(e.matchId)) items.add(e);
      }
      _page = p.page < 1 ? page : p.page;
      _totalPages = p.totalPages;
      total = p.total;
      loaded = true;
      error = null;
    } on AppException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

/// One leaderboard tab: rows by `offset` (until a short page) and the
/// pinned "You" row from `my-rank`.
class LeaderboardPager extends ChangeNotifier {
  LeaderboardPager(this._api, {required this.gameId, required this.metric, int limit = 20}) : limit = clampLimit(limit);
  final ProgressApi _api;
  final int gameId;
  final LeaderboardMetric metric;
  final int limit;

  final List<LeaderboardEntry> rows = [];
  MyRank? me;
  bool loading = false;
  bool loaded = false;
  bool _more = true;
  String? error;

  bool get hasMore => loaded && _more;

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      final (page, mine) = await (_api.leaderboard(gameId, metric, limit: limit), _api.myRank(gameId, metric)).wait;
      rows
        ..clear()
        ..addAll(page);
      me = mine;
      _more = page.length >= limit;
      loaded = true;
      error = null;
    } on ParallelWaitError<dynamic, dynamic> catch (e) {
      final err = [e.errors.$1, e.errors.$2].whereType<AsyncError>().firstOrNull?.error;
      error = err is AppException ? err.message : progressLoadFailed;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (!hasMore || loading) return;
    loading = true;
    notifyListeners();
    try {
      final page = await _api.leaderboard(gameId, metric, limit: limit, offset: rows.length);
      final seen = {for (final r in rows) r.userId};
      rows.addAll(page.where((r) => !seen.contains(r.userId)));
      _more = page.length >= limit;
      error = null;
    } on AppException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

// ── Profile summary (matches, wins, streak, rank) ──

/// The profile's headline numbers for one game, worked out from what the
/// server sends (08-progress-and-history.md has no single "stats" route):
/// finished matches and W/D/L/forfeits from match history, the current win
/// streak from the newest finished matches, and the rank on the wins board.
@immutable
class ProfileStats {
  const ProfileStats({
    this.matches = 0,
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.forfeits = 0,
    this.streak = 0,
    this.rank,
  });

  final int matches;
  final int wins;
  final int losses;
  final int draws;
  final int forfeits;

  /// Wins in a row, from the newest finished match.
  final int streak;

  /// Place on the game's wins leaderboard; null when not on it.
  final int? rank;

  /// 0..1; 0 with no finished matches.
  double get winRate => matches == 0 ? 0 : wins / matches;

  /// From history rows, newest first ([gameId] null = every game).
  factory ProfileStats.fromHistory(Iterable<HistoryEntry> rows, {int? gameId, int? rank}) {
    var w = 0, l = 0, d = 0, f = 0, streak = 0;
    var streakOpen = true;
    for (final r in rows) {
      if (gameId != null && r.gameId != null && r.gameId != gameId) continue;
      final res = r.result;
      if (res == null) continue; // still running, cancelled or abandoned
      switch (res) {
        case 'win':
          w++;
        case 'loss':
          l++;
        case 'draw':
          d++;
        case 'forfeit':
          f++;
        default:
          continue;
      }
      if (streakOpen) {
        if (res == 'win') {
          streak++;
        } else {
          streakOpen = false;
        }
      }
    }
    return ProfileStats(matches: w + l + d + f, wins: w, losses: l, draws: d, forfeits: f, streak: streak, rank: rank);
  }
}

/// History pages read for the profile summary (100 each).
const _statsMaxPages = 10;

/// The active game's [ProfileStats]; re-read after each game (the progress
/// store's revision moves) and on pull to refresh.
final profileStatsProvider = FutureProvider.autoDispose<ProfileStats>((ref) async {
  ref.watch(progressStoreProvider.select((s) => s.revision));
  final api = ref.watch(progressApiProvider);
  final gameId = await progressGameId(ref, GameCodes.codeOf(ref.watch(activeGameProvider)));
  final rows = <HistoryEntry>[];
  for (var page = 1; page <= _statsMaxPages; page++) {
    final p = await api.history(page: page, perPage: 100);
    rows.addAll(p.data);
    if (page >= p.totalPages || p.data.isEmpty) break;
  }
  int? rank;
  if (gameId != null) {
    try {
      rank = (await api.myRank(gameId, LeaderboardMetric.wins)).rank;
    } on AppException {
      rank = null; // the board is optional for this summary
    }
  }
  return ProfileStats.fromHistory(rows, gameId: gameId, rank: rank);
});

/// The active game's level and XP for the Home bar (no account-wide level
/// exists, 08 "What does not exist"). Level 1 / 0 XP before the first game.
final activeGameLevelProvider = Provider.autoDispose<GameLevel>((ref) {
  final code = GameCodes.codeOf(ref.watch(activeGameProvider));
  final gameId = ref.watch(progressGameIdProvider(code)).value;
  if (gameId == null) return const GameLevel(gameId: 0);
  return ref.watch(progressStoreProvider).levelFor(gameId) ?? GameLevel(gameId: gameId);
});

/// The player's level for unlocks (avatars, 11-store.md §6b): their highest
/// level in any game; 1 before the first finished game.
final playerLevelProvider = Provider<int>((ref) {
  final levels = ref.watch(progressStoreProvider).levels;
  var best = 1;
  for (final l in levels) {
    if (l.level > best) best = l.level;
  }
  return best;
});
