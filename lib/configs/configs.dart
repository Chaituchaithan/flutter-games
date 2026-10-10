/// App configuration — import this one file.
///
/// ```
/// lib/configs/
///   app_config.dart        resolved values (entry point)
///   environment.dart       dev / staging / prod → server
///   server_config.dart     host, gateway port, schemes (pure Dart)
///   proxy_config.dart      dev proxy switch + host
///   network_config.dart    timeouts, ping, backoff
///   feature_flags.dart     socket / remote-data switches
///   build_overrides.dart   every --dart-define
///   endpoints/             REST paths + per-game socket URLs
///   games/                 core/ (GameId, GameConfig, registry, active game) + one folder per game
/// ```
library;

export 'app_config.dart';
export 'build_overrides.dart';
export 'endpoints/api_endpoints.dart';
export 'endpoints/game_endpoints.dart';
export 'environment.dart';
export 'feature_flags.dart';
export 'games/games.dart';
export 'network_config.dart';
export 'proxy_config.dart';
export 'server_config.dart';
