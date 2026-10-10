import '../core/game_config.dart';
import '../core/game_id.dart';

/// Rummy — rummy-service on its own port (WS `/ws` verified reachable).
/// Game area not built yet; player counts to confirm when it is.
const rummyConfig = GameConfig(
  id: GameId.rummy,
  displayName: 'Rummy',
  icon: '🀄',
  port: 31290,
  socketPath: '/ws',
  minPlayers: 2, // TODO: confirm
  maxPlayers: 2, // TODO: confirm
  wsUrlOverride: String.fromEnvironment('RUMMY_WS_URL'),
);
