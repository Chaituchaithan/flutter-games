/// Timeouts and retry timings shared by the REST client and the sockets.
library;

abstract final class NetworkConfig {
  // REST (ApiClient / Dio)
  // 15 s for HTTP calls (00-conventions.md "Errors").
  static const connectTimeout = Duration(seconds: 15);
  static const receiveTimeout = Duration(seconds: 15);

  /// `503 DATABASE_BUSY` answers `Retry-After: 1`: one retry after this.
  static const busyRetryDelay = Duration(seconds: 1);

  /// Refresh the access token when it expires within this window.
  static const refreshAhead = Duration(seconds: 60);

  /// `User-Agent: <product>/<version> (<platform>)` — the gateway names the
  /// device in the player's session list from it. Keep in step with pubspec.
  static const userAgentProduct = 'RoyaleArcade';
  static const appVersion = '1.0.0';

  // Realtime sockets (SocketClient)
  static const socketRequestTimeout = Duration(seconds: 8);
  /// The server pings every 5 s and closes a socket silent for 10 s.
  static const socketPingInterval = Duration(seconds: 5);
}
