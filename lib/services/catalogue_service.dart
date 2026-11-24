/// The game catalogue service (docs/services/04-game-catalogue.md).
///
/// * [CatalogueApi] — one method per `/games` route: [RemoteCatalogueApi]
///   (the gateway) and [DemoCatalogueApi] (offline / demo builds, built from
///   the app's own registry).
/// * [CatalogueRepository] — in-memory cache (+ the games list on disk),
///   lookups by `code`, and the refetch rules of "Caching and refetching".
/// * Providers: [catalogueRepositoryProvider], [catalogueGamesProvider]
///   (the home list), [gameCatalogueProvider] (a game home's variants, modes
///   and stakes), [gamePowerUpsProvider], [gameAchievementsProvider],
///   [gameSettingsProvider], [homeGamesProvider] (catalogue merged with the
///   app's table) and [catalogueEventsProvider] (`GAME_NOT_FOUND`,
///   `invalid_mode`, `kill_switch_engaged`, pull to refresh).
///
/// Other features (matchmaking, rooms) read modes and stakes from here and
/// hand a [PlaySelection] to the game socket — never a numeric id.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_profile.dart';
import '../configs/configs.dart';
import '../configs/games/core/game_codes.dart';
import '../data/models/game_catalogue.dart';
import 'api_client.dart';
import 'app_exception.dart';
import 'app_prefs.dart';
import 'session.dart';

export '../data/models/game_catalogue.dart';

/// User text for a game that was switched off (or is unknown).
const gameUnavailableMessage = "This game isn't available right now.";

// ── API ──

abstract class CatalogueApi {
  /// `GET /games?is_active=true` (pass null to list switched-off games too).
  Future<List<CatalogueGame>> games({bool? isActive = true});

  /// `GET /games/{id}` — also returns a switched-off game (`isActive` false).
  Future<CatalogueGame> game(int id);
  Future<List<GameVariant>> variants(int id);
  Future<List<GameMode>> modes(int id);
  Future<List<Stake>> stakes(int id);
  Future<List<PowerUp>> powerUps(int id);

  /// Null when the game has no settings.
  Future<GameSettings?> config(int id);
  Future<List<GameAchievement>> achievements(int id);
}

class RemoteCatalogueApi implements CatalogueApi {
  const RemoteCatalogueApi(this._api);
  final ApiClient _api;

  static List<Map<String, dynamic>> _rows(Object? data) => data is List
      ? [
          for (final e in data)
            if (e is Map) e.cast<String, dynamic>(),
        ]
      : const [];

  /// A `GAME_NOT_FOUND` gets the app's own text (the code is kept).
  Future<dynamic> _get(String path, {Map<String, dynamic>? query}) async {
    try {
      return await _api.get(path, query: query);
    } on AppException catch (e) {
      if (e.code != ApiErrorCode.gameNotFound) rethrow;
      throw AppException(
        gameUnavailableMessage,
        kind: e.kind,
        statusCode: e.statusCode,
        code: e.code,
      );
    }
  }

  @override
  Future<List<CatalogueGame>> games({bool? isActive = true}) async => [
    for (final j in _rows(
      await _get(
        ApiEndpoints.games,
        query: isActive == null ? null : {'is_active': '$isActive'},
      ),
    ))
      CatalogueGame.fromJson(j),
  ];

  @override
  Future<CatalogueGame> game(int id) async {
    final j = await _get(ApiEndpoints.game(id));
    if (j is! Map) throw const AppException('Something went wrong. Try again.');
    return CatalogueGame.fromJson(j.cast<String, dynamic>());
  }

  @override
  Future<List<GameVariant>> variants(int id) async => [
    for (final j in _rows(await _get(ApiEndpoints.gameVariants(id))))
      GameVariant.fromJson(j),
  ];

  @override
  Future<List<GameMode>> modes(int id) async => [
    for (final j in _rows(await _get(ApiEndpoints.gameModes(id))))
      if (j['is_active'] != false) GameMode.fromJson(j),
  ];

  @override
  Future<List<Stake>> stakes(int id) async => [
    for (final j in _rows(await _get(ApiEndpoints.gameStakes(id))))
      if (j['is_active'] != false) Stake.fromJson(j),
  ];

  @override
  Future<List<PowerUp>> powerUps(int id) async => [
    for (final j in _rows(await _get(ApiEndpoints.gamePowerUps(id))))
      if (j['is_active'] != false) PowerUp.fromJson(j),
  ];

  @override
  Future<GameSettings?> config(int id) async =>
      GameSettings.fromJson(await _get(ApiEndpoints.gameConfig(id)));

  @override
  Future<List<GameAchievement>> achievements(int id) async => [
    for (final j in _rows(await _get(ApiEndpoints.gameAchievements(id))))
      GameAchievement.fromJson(j),
  ];
}

/// Offline / demo catalogue from the app's own registry: every game this
/// build has, one variant, a 2-player casual mode and a friends room, with a
/// small token ladder. Ids are local (1-based registry order).
class DemoCatalogueApi implements CatalogueApi {
  const DemoCatalogueApi();

  static List<CatalogueGame> get _games {
    var i = 0;
    return [
      for (final info in GameCodes.all)
        if (info.id != null)
          () {
            final c = GameRegistry.of(info.id!);
            i++;
            return CatalogueGame(
              id: i,
              code: info.code,
              name: c.displayName,
              minPlayers: c.minPlayers,
              maxPlayers: c.maxPlayers,
              sortOrder: i,
            );
          }(),
    ];
  }

  CatalogueGame _byId(int id) => _games.firstWhere(
    (g) => g.id == id,
    orElse: () => throw const AppException(
      gameUnavailableMessage,
      kind: AppErrorKind.notFound,
      statusCode: 404,
      code: ApiErrorCode.gameNotFound,
    ),
  );

  @override
  Future<List<CatalogueGame>> games({bool? isActive = true}) async => _games;

  @override
  Future<CatalogueGame> game(int id) async => _byId(id);

  @override
  Future<List<GameVariant>> variants(int id) async {
    _byId(id);
    return const [
      GameVariant(id: 1, code: 'classic', name: 'Classic', isDefault: true),
    ];
  }

  @override
  Future<List<GameMode>> modes(int id) async {
    final g = _byId(id);
    final seats = g.maxPlayers.clamp(2, 4);
    return [
      GameMode(
        id: id * 10 + 1,
        gameId: id,
        code: 'casual_2p',
        name: 'Casual',
        playerCount: 2,
        minPlayers: 2,
        variantId: 1,
        variantCode: 'classic',
      ),
      GameMode(
        id: id * 10 + 2,
        gameId: id,
        code: 'friends_room',
        name: 'Play with Friends',
        playerCount: seats,
        minPlayers: 2,
        variantId: 1,
        variantCode: 'classic',
        timer: const ModeTimer(
          type: ModeTimerType.turn,
          turnMs: 15000,
          allowedTurnSeconds: [10, 15, 20],
        ),
        hostCanChoose: const ['turn_seconds'],
        hostOptions: const [
          HostOption(
            key: 'turn_seconds',
            label: 'Turn timer',
            values: [10, 15, 20],
            current: 15,
          ),
        ],
      ),
    ];
  }

  @override
  Future<List<Stake>> stakes(int id) async {
    _byId(id);
    var n = 0;
    return [
      for (final mode in [id * 10 + 1, id * 10 + 2])
        for (final amount in const [50, 100, 200, 500])
          Stake(
            id: ++n,
            gameId: id,
            modeId: mode,
            currency: StakeCurrency.token,
            stakeAmount: amount,
          ),
    ];
  }

  @override
  Future<List<PowerUp>> powerUps(int id) async => const [];

  @override
  Future<GameSettings?> config(int id) async => null;

  @override
  Future<List<GameAchievement>> achievements(int id) async => const [];
}

// ── Disk copy of the games list ──

/// Where the games list is kept between starts (draws Home at once).
abstract class CatalogueDiskCache {
  Future<String?> read();
  Future<void> write(String json);
}

class PrefsCatalogueDiskCache implements CatalogueDiskCache {
  const PrefsCatalogueDiskCache(this._prefs);
  final AppPrefs _prefs;
  static const _key = 'catalogue.games';

  @override
  Future<String?> read() => _prefs.get(_key);

  @override
  Future<void> write(String json) => _prefs.set(_key, json);
}

// ── Repository ──

class _Stamped<T> {
  _Stamped(this.value, this.at);
  final T value;
  final DateTime at;
}

/// In-memory catalogue with the refetch rules of 04-game-catalogue.md
/// "Caching and refetching". Never polls; each call counts against the
/// player's 100 requests a minute.
class CatalogueRepository {
  CatalogueRepository(
    this.api, {
    this.disk,
    DateTime Function()? now,
    this.maxAge = const Duration(minutes: 10),
  }) : _now = now ?? DateTime.now;

  final CatalogueApi api;
  final CatalogueDiskCache? disk;
  final DateTime Function() _now;

  /// How long a game's details count as fresh (a game home reopened later
  /// refetches), and how long the app may sit in the background before the
  /// games list is refetched on resume.
  final Duration maxAge;

  List<CatalogueGame>? _games;
  Future<List<CatalogueGame>>? _gamesLoading;
  final _details = <String, _Stamped<GameCatalogue>>{};
  final _detailsLoading = <String, Future<GameCatalogue>>{};
  final _powerUps = <String, _Stamped<List<PowerUp>>>{};
  final _achievements = <String, _Stamped<List<GameAchievement>>>{};
  final _settings = <String, _Stamped<GameSettings?>>{};

  /// Called whenever the games list changes (a game removed, a refetch).
  void Function(List<CatalogueGame> games)? onGamesChanged;

  /// The games list in memory (null = not loaded yet).
  List<CatalogueGame>? get cachedGames => _games;

  /// The last games list saved on disk (null = none or unreadable). Sets the
  /// in-memory list when nothing newer is loaded.
  Future<List<CatalogueGame>?> loadFromDisk() async {
    try {
      final raw = await disk?.read();
      if (raw == null || raw.isEmpty) return null;
      final list = jsonDecode(raw);
      if (list is! List) return null;
      final games = [
        for (final j in list)
          if (j is Map) CatalogueGame.fromJson(j.cast<String, dynamic>()),
      ].where((g) => g.isActive).toList();
      return _games ??= games;
    } catch (_) {
      return null;
    }
  }

  /// `GET /games?is_active=true`, in reply (`sort_order`) order. Cached in
  /// memory; [refresh] refetches (app start, resume, pull to refresh).
  Future<List<CatalogueGame>> games({bool refresh = false}) {
    if (!refresh && _games != null) return Future.value(_games!);
    return _gamesLoading ??= () async {
      try {
        // Ask for active games only; drop any switched-off row anyway.
        final list = [
          for (final g in await api.games(isActive: true))
            if (g.isActive) g,
        ];
        _setGames(list);
        unawaited(_save(list));
        return list;
      } finally {
        _gamesLoading = null;
      }
    }();
  }

  Future<void> _save(List<CatalogueGame> list) async {
    try {
      await disk?.write(jsonEncode([for (final g in list) g.toJson()]));
    } catch (_) {
      /* best effort */
    }
  }

  void _setGames(List<CatalogueGame> list) {
    _games = List.unmodifiable(list);
    onGamesChanged?.call(_games!);
  }

  /// The game with [code] (ids differ per server: always looked up by code).
  /// Loads the list when needed; null when the game isn't active.
  Future<CatalogueGame?> gameByCode(String code) async =>
      (await games()).where((g) => g.code == code).firstOrNull;

  Future<CatalogueGame> _require(String code) async {
    final g = await gameByCode(code);
    if (g == null) {
      throw const AppException(
        gameUnavailableMessage,
        kind: AppErrorKind.notFound,
        statusCode: 404,
        code: ApiErrorCode.gameNotFound,
      );
    }
    return g;
  }

  /// Drops [code] from the cached list (and its details): the gateway said
  /// `GAME_NOT_FOUND`, or the game is otherwise gone.
  void removeGame(String code) {
    _forget(code);
    final list = _games;
    if (list != null && list.any((g) => g.code == code)) {
      _setGames([
        for (final g in list)
          if (g.code != code) g,
      ]);
      unawaited(_save(_games!));
    }
  }

  void _forget(String code) {
    _details.remove(code);
    _powerUps.remove(code);
    _achievements.remove(code);
    _settings.remove(code);
  }

  /// Runs a game sub-route; `GAME_NOT_FOUND` removes the game, then rethrows.
  Future<T> _guard<T>(String code, Future<T> Function() run) async {
    try {
      return await run();
    } on AppException catch (e) {
      if (e.code == ApiErrorCode.gameNotFound) removeGame(code);
      rethrow;
    }
  }

  bool _fresh(_Stamped<Object?>? s) =>
      s != null && _now().difference(s.at) < maxAge;

  /// The game home's variants, modes and stakes, loaded together (3 calls).
  /// Kept per game; refetched when older than [maxAge], after
  /// [invalidateGame] (socket `invalid_mode`) or with [refresh].
  Future<GameCatalogue> details(String code, {bool refresh = false}) {
    final hit = _details[code];
    if (!refresh && _fresh(hit)) return Future.value(hit!.value);
    return _detailsLoading[code] ??= () async {
      try {
        final game = await _require(code);
        final out = await _guard(code, () async {
          // Together; the first failure (e.g. GAME_NOT_FOUND) is rethrown.
          final r = await Future.wait<Object>([
            api.variants(game.id),
            api.modes(game.id),
            api.stakes(game.id),
          ]);
          return GameCatalogue(
            game: game,
            variants: r[0] as List<GameVariant>,
            modes: r[1] as List<GameMode>,
            stakes: r[2] as List<Stake>,
          );
        });
        _details[code] = _Stamped(out, _now());
        return out;
      } finally {
        _detailsLoading.remove(code);
      }
    }();
  }

  Future<List<GameVariant>> variants(String code) async =>
      (await details(code)).variants;
  Future<List<GameMode>> modes(String code) async =>
      (await details(code)).modes;
  Future<List<Stake>> stakes(String code) async => (await details(code)).stakes;

  /// The cached details, if any (no call).
  GameCatalogue? cachedDetails(String code) => _details[code]?.value;

  Future<T> _cached<T>(
    Map<String, _Stamped<T>> cache,
    String code,
    bool refresh,
    Future<T> Function(int id) load,
  ) async {
    final hit = cache[code];
    if (!refresh && _fresh(hit)) return hit!.value;
    final game = await _require(code);
    final v = await _guard(code, () => load(game.id));
    cache[code] = _Stamped(v, _now());
    return v;
  }

  /// When the Power-ups tab opens.
  Future<List<PowerUp>> powerUps(String code, {bool refresh = false}) =>
      _cached(_powerUps, code, refresh, api.powerUps);

  /// When the Achievements tab opens.
  Future<List<GameAchievement>> achievements(
    String code, {
    bool refresh = false,
  }) => _cached(_achievements, code, refresh, api.achievements);

  /// When the game home opens (only for games whose file uses config keys).
  /// [GameSettings.version] tells callers whether anything changed.
  Future<GameSettings?> settings(String code, {bool refresh = false}) =>
      _cached(_settings, code, refresh, api.config);

  /// A socket `invalid_mode` (or pull to refresh on a game home): the next
  /// [details] refetches modes and stakes.
  void invalidateGame(String code) => _forget(code);

  /// The app came back after [away] in the background: true when the games
  /// list should be refetched (10 minutes or more).
  bool shouldRefreshAfter(Duration away) => away >= maxAge;
}

// ── Kill switches (seen on the game socket only) ──

/// Games paused by an operator, as learnt from a socket
/// `kill_switch_engaged`: play stays disabled for the rest of the visit
/// (or [pauseFor]), the operator's banner is kept for display.
class KillSwitches
    extends Notifier<Map<String, ({String message, DateTime until})>> {
  static const pauseFor = Duration(minutes: 5);

  @override
  Map<String, ({String message, DateTime until})> build() => const {};

  void engage(String gameCode, String message, {DateTime? now}) {
    state = {
      ...state,
      gameCode: (
        message: message,
        until: (now ?? DateTime.now()).add(pauseFor),
      ),
    };
  }

  void clear(String gameCode) => state = {...state}..remove(gameCode);

  /// The operator's banner while [gameCode] is paused, else null.
  String? banner(String gameCode, {DateTime? now}) {
    final e = state[gameCode];
    if (e == null) return null;
    return (now ?? DateTime.now()).isBefore(e.until) ? e.message : null;
  }
}

final killSwitchesProvider =
    NotifierProvider<
      KillSwitches,
      Map<String, ({String message, DateTime until})>
    >(KillSwitches.new);

// ── Providers ──

/// Live catalogue (gateway) vs the offline demo one. Follows the auth switch
/// (demo auth has no token the gateway would accept). Override in tests.
final useRemoteCatalogueProvider = Provider<bool>(
  (ref) => ref.watch(useRemoteAuthProvider),
);

final catalogueApiProvider = Provider<CatalogueApi>((ref) {
  if (!ref.watch(useRemoteCatalogueProvider)) return const DemoCatalogueApi();
  return RemoteCatalogueApi(ref.watch(apiClientProvider));
});

final catalogueDiskCacheProvider = Provider<CatalogueDiskCache?>(
  (ref) => PrefsCatalogueDiskCache(ref.watch(appPrefsProvider)),
);

/// One repository per signed-in player (ids are looked up again each session).
final catalogueRepositoryProvider = Provider<CatalogueRepository>((ref) {
  ref.watch(sessionProvider.select((u) => u?.id));
  final remote = ref.watch(useRemoteCatalogueProvider);
  return CatalogueRepository(
    ref.watch(catalogueApiProvider),
    disk: remote ? ref.watch(catalogueDiskCacheProvider) : null,
  );
});

/// The home list (`GET /games?is_active=true`, reply order). Draws the disk
/// copy at once and refetches behind it; refetched on resume after 10
/// minutes, on pull to refresh ([CatalogueGames.refresh]) and after a
/// `GAME_NOT_FOUND` (the game is dropped). Not loaded while signed out.
class CatalogueGames extends AsyncNotifier<List<CatalogueGame>> {
  DateTime? _hiddenAt;

  @override
  Future<List<CatalogueGame>> build() async {
    final repo = ref.watch(catalogueRepositoryProvider);
    final signedIn = ref.watch(sessionProvider.select((u) => u != null));
    repo.onGamesChanged = (games) {
      if (ref.mounted) state = AsyncData(games);
    };
    _watchLifecycle();
    if (!signedIn && ref.watch(useRemoteCatalogueProvider)) {
      // No token yet: only the copy from the last session, if any.
      final saved = await repo.loadFromDisk();
      if (saved != null) return saved;
      throw const AppException(
        'Sign in to see the games.',
        kind: AppErrorKind.unauthorized,
      );
    }
    if (repo.cachedGames == null) {
      final saved = await repo.loadFromDisk();
      if (saved != null) {
        // Show the saved list now; the fresh one replaces it (or, offline,
        // the saved one stays).
        unawaited(
          repo.games(refresh: true).then((_) {}, onError: (Object _) {}),
        );
        return saved;
      }
    }
    return repo.games();
  }

  void _watchLifecycle() {
    try {
      final listener = AppLifecycleListener(
        onHide: () => _hiddenAt = DateTime.now(),
        onShow: () {
          final at = _hiddenAt;
          _hiddenAt = null;
          if (at != null &&
              ref
                  .read(catalogueRepositoryProvider)
                  .shouldRefreshAfter(DateTime.now().difference(at))) {
            unawaited(refresh().then((_) {}, onError: (Object _) {}));
          }
        },
      );
      ref.onDispose(listener.dispose);
    } catch (_) {
      // No widgets binding (plain unit tests): no resume refetch.
    }
  }

  /// Pull to refresh / app start. Keeps the shown list when the call fails.
  Future<void> refresh() async {
    final repo = ref.read(catalogueRepositoryProvider);
    try {
      await repo.games(refresh: true);
    } on AppException catch (e, st) {
      if (!state.hasValue) state = AsyncError(e, st);
      rethrow;
    }
  }
}

final catalogueGamesProvider =
    AsyncNotifierProvider<CatalogueGames, List<CatalogueGame>>(
      CatalogueGames.new,
    );

/// A game home's variants, modes and stakes by game `code`. Reopening the
/// game home re-reads it (autoDispose); the repository refetches when older
/// than 10 minutes. A `GAME_NOT_FOUND` error removes the game from the list.
final gameCatalogueProvider = FutureProvider.autoDispose
    .family<GameCatalogue, String>(
      (ref, code) => ref.watch(catalogueRepositoryProvider).details(code),
    );

final gamePowerUpsProvider = FutureProvider.autoDispose
    .family<List<PowerUp>, String>(
      (ref, code) => ref.watch(catalogueRepositoryProvider).powerUps(code),
    );

final gameAchievementsProvider = FutureProvider.autoDispose
    .family<List<GameAchievement>, String>(
      (ref, code) => ref.watch(catalogueRepositoryProvider).achievements(code),
    );

final gameSettingsProvider = FutureProvider.autoDispose
    .family<GameSettings?, String>(
      (ref, code) => ref.watch(catalogueRepositoryProvider).settings(code),
    );

/// The catalogue events other features report.
class CatalogueEvents {
  CatalogueEvents(this._ref);
  final Ref _ref;

  CatalogueRepository get _repo => _ref.read(catalogueRepositoryProvider);

  /// A socket `invalid_mode`: refetch modes and stakes (go back to the mode
  /// picker). Returns the fresh catalogue.
  Future<GameCatalogue> invalidMode(String gameCode) {
    _repo.invalidateGame(gameCode);
    _ref.invalidate(gameCatalogueProvider(gameCode));
    return _ref.read(gameCatalogueProvider(gameCode).future);
  }

  /// A `GAME_NOT_FOUND` seen elsewhere: drop the game.
  void gameNotFound(String gameCode) => _repo.removeGame(gameCode);

  /// A socket `kill_switch_engaged`: keep the operator's banner, disable
  /// play for the game.
  void killSwitch(String gameCode, String message) =>
      _ref.read(killSwitchesProvider.notifier).engage(gameCode, message);

  /// Pull to refresh on a game home.
  void refreshGame(String gameCode) {
    _repo.invalidateGame(gameCode);
    _ref.invalidate(gameCatalogueProvider(gameCode));
    _ref.invalidate(gamePowerUpsProvider(gameCode));
    _ref.invalidate(gameAchievementsProvider(gameCode));
    _ref.invalidate(gameSettingsProvider(gameCode));
  }

  /// Pull to refresh on Home.
  Future<void> refreshGames() =>
      _ref.read(catalogueGamesProvider.notifier).refresh();
}

final catalogueEventsProvider = Provider<CatalogueEvents>(CatalogueEvents.new);

// ── Home list: catalogue × the app's table ──

/// One entry of the home game picker.
class HomeGame {
  const HomeGame({
    required this.code,
    required this.name,
    required this.icon,
    this.config,
    this.game,
    this.playable = false,
  });

  /// Catalogue code (or the app's own code when offline).
  final String code;

  /// The catalogue's branded name (the app's name when offline).
  final String name;
  final String icon;

  /// The app's game for this code, when the app ships it.
  final GameConfig? config;

  /// The catalogue row (null = offline, from the local registry).
  final CatalogueGame? game;

  /// This app build has a screen for it; others show "Coming soon".
  final bool playable;

  GameId? get id => config?.id;
}

/// The home game picker: the catalogue's games in reply order when loaded
/// (this app's games playable, the rest "Coming soon" in dev builds that list
/// them); the local registry otherwise (offline, demo, still loading).
/// A game of this app that the catalogue doesn't list is switched off and
/// left out — unless that would leave nothing to show.
List<HomeGame> homeGamesFor(
  List<CatalogueGame>? catalogue,
  AppProfile profile,
) {
  HomeGame local(GameConfig c, {required bool playable}) {
    final code =
        GameCodes.all.where((g) => g.id == c.id).firstOrNull?.code ?? c.id.name;
    return HomeGame(
      code: code,
      name: c.displayName,
      icon: c.icon,
      config: c,
      playable: playable,
    );
  }

  final fallback = [
    for (final m in profile.modules) local(m.config, playable: true),
    if (profile.showComingSoon)
      for (final g in GameRegistry.homeChips)
        if (!profile.includes(g.id)) local(g, playable: false),
  ];
  if (catalogue == null) return fallback;
  final out = <HomeGame>[];
  for (final g in catalogue) {
    final info = GameCodes.info(g.code);
    final id = info?.id;
    final playable = id != null && profile.includes(id);
    if (!playable && !profile.showComingSoon) continue;
    out.add(
      HomeGame(
        code: g.code,
        name: g.name,
        icon: info?.icon ?? (id == null ? '🎮' : GameRegistry.of(id).icon),
        config: id == null ? null : GameRegistry.of(id),
        game: g,
        playable: playable,
      ),
    );
  }
  return out.any((h) => h.playable) ? out : fallback;
}

final homeGamesProvider = Provider<List<HomeGame>>((ref) {
  final games = ref.watch(catalogueGamesProvider).value;
  return homeGamesFor(games, AppProfile.current);
});
