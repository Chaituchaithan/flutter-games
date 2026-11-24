/// Every build-time override (`--dart-define=NAME=value`) the app reads, in one
/// place. Nothing outside `lib/configs` calls `String.fromEnvironment`.
///
/// An empty string means "not set" — the config then falls back to its
/// environment default. Per-game socket overrides (`CHESS_WS_URL`,
/// `LUDO_WS_URL`, …) live on each game's config file.
library;

abstract final class BuildOverrides {
  /// `dev` (default) · `staging` · `prod`.
  static const env = String.fromEnvironment('APP_ENV');

  /// Server IP/host for the dev environment (e.g. a teammate's machine),
  /// replacing the default LAN server's host. Ports stay the same.
  static const serverHost = String.fromEnvironment('SERVER_HOST');

  /// Full REST base, e.g. `http://10.0.2.2:3000/api/v1` (wins over everything).
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// `true` / `false` — overrides the proxy master switch for one run.
  static const useProxy = String.fromEnvironment('USE_PROXY');

  /// `host:port` of the local dev proxy, if not the default.
  static const proxyHost = String.fromEnvironment('PROXY_HOST');

  /// `true` / `false` — overrides the realtime-socket master switch.
  static const socketEnabled = String.fromEnvironment('SOCKET_ENABLED');

  /// Starting game (`chess`, `ludo`, `snakesLadders`, …) — build one game only.
  static const game = String.fromEnvironment('GAME');

}
