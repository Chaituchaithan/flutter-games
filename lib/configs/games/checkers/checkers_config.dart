import '../core/game_config.dart';
import '../core/game_id.dart';

/// Checkers — checkers-service on its own port (WS `/ws` verified reachable).
/// Quick Play (vs computer) is built; online play waits for its socket protocol.
const checkersConfig = GameConfig(
  id: GameId.checkers,
  displayName: 'Checkers',
  icon: '⛀',
  port: 31282,
  socketPath: '/ws',
  minPlayers: 2,
  maxPlayers: 2,
  available: true,
  wsUrlOverride: String.fromEnvironment('CHECKERS_WS_URL'),
);
