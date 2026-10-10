import '../core/game_config.dart';
import '../core/game_id.dart';

/// Racing — racing-service on its own port (WS `/ws` verified reachable).
/// Game area not built yet; player counts to confirm when it is.
const racingConfig = GameConfig(
  id: GameId.racing,
  displayName: 'Racing',
  icon: '🏎️',
  port: 31288,
  socketPath: '/ws',
  minPlayers: 2, // TODO: confirm
  maxPlayers: 2, // TODO: confirm
  wsUrlOverride: String.fromEnvironment('RACING_WS_URL'),
);
