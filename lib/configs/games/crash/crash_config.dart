import '../core/game_config.dart';
import '../core/game_id.dart';

/// Crash — crash-service on its own port (WS `/ws` verified reachable).
/// Game area not built yet; player counts to confirm when it is.
const crashConfig = GameConfig(
  id: GameId.crash,
  displayName: 'Crash',
  icon: '📈',
  port: 31284,
  socketPath: '/ws',
  minPlayers: 2, // TODO: confirm
  maxPlayers: 2, // TODO: confirm
  wsUrlOverride: String.fromEnvironment('CRASH_WS_URL'),
);
