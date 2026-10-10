/// A game service's URLs. Each game serves its REST API and its socket on the
/// same port:
///   REST    `http://<host>:<port>/health`, `/metrics`, …
///   socket  `ws://<host>:<port>/ws`
///
/// Resolved the same way for every game:
///   1. socket only: `--dart-define=<GAME>_WS_URL=…` (the game's override) wins;
///   2. proxy ON  → `<proxy>/svc/<port>/…` (the proxy forwards to
///      `<host>:<port>/…` — one proxy for every game service, REST and socket);
///   3. otherwise → `<host>:<port>/…` from the environment.
library;

import '../app_config.dart';
import '../games/core/game_config.dart';
import '../proxy_config.dart';

class GameEndpoints {
  const GameEndpoints(this.game);
  final GameConfig game;

  bool get _hasOverride => game.wsUrlOverride.isNotEmpty;

  /// Whether this game's socket goes through the local dev proxy.
  bool get viaProxy => !_hasOverride && ProxyConfig.enabled;

  /// The socket URL to dial (without auth).
  String get socketUrl {
    if (_hasOverride) return game.wsUrlOverride;
    if (ProxyConfig.enabled) return '${ProxyConfig.wsBase}/svc/${game.port}${game.socketPath}';
    return AppConfig.server.socketUrl(game.port, game.socketPath);
  }

  /// The socket URL with the token as `?token=` — only through the proxy,
  /// because a browser can't set WS headers (the proxy lifts it into a Bearer
  /// header upstream). Direct connections send the token as a header instead
  /// ([socketHeaders]). It also goes in the `auth.login` first frame either way.
  String socketUrlWithToken(String token) {
    if (token.isEmpty || !viaProxy) return socketUrl;
    final sep = socketUrl.contains('?') ? '&' : '?';
    return '$socketUrl${sep}token=${Uri.encodeQueryComponent(token)}';
  }

  /// Upgrade headers for native: `Authorization: Bearer <token>` (web ignores them).
  Map<String, dynamic> socketHeaders(String token) =>
      token.isEmpty ? const {} : {'Authorization': 'Bearer $token'};

  // ── REST (same port as the socket) ──

  /// `http://<host>:<port>` (or `<proxy>/svc/<port>` when the proxy is ON).
  String get apiBase => ProxyConfig.enabled
      ? '${ProxyConfig.httpBase}/svc/${game.port}'
      : AppConfig.server.serviceBase(game.port);

  /// A path on the game's REST API, e.g. `api('/health/deep')`.
  String api(String path) => '$apiBase$path';

  /// Liveness probe — `{"status":"ok","service":"chess-service"}`.
  String get health => api(GamePaths.health);

  /// Readiness probe (database + cache).
  String get healthDeep => api(GamePaths.healthDeep);

  /// Prometheus metrics (text format).
  String get metrics => api(GamePaths.metrics);
}

/// REST paths every game service exposes (Chess API doc · HTTP endpoints).
abstract final class GamePaths {
  static const health = '/health';
  static const healthDeep = '/health/deep';
  static const metrics = '/metrics';
}
