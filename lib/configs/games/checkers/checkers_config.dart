import '../core/game_config.dart';
import '../core/game_id.dart';

/// Checkers — checkers-service on its own port (WS `/ws` verified reachable).
/// Game area not built yet; player counts to confirm when it is.
const checkersConfig = GameConfig(
  id: GameId.checkers,
  displayName: 'Checkers',
  icon: '⛀',
  port: 31282,
  socketPath: '/ws',
  minPlayers: 2, // TODO: confirm
  maxPlayers: 2, // TODO: confirm
  wsUrlOverride: String.fromEnvironment('CHECKERS_WS_URL'),
);
