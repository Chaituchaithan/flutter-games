import '../core/game_config.dart';
import '../core/game_id.dart';

/// Othello — othello-service on its own port (WS `/ws` verified reachable).
/// Game area not built yet.
const othelloConfig = GameConfig(
  id: GameId.othello,
  displayName: 'Othello',
  icon: '⚫',
  port: 31286,
  socketPath: '/ws',
  minPlayers: 2,
  maxPlayers: 2,
  wsUrlOverride: String.fromEnvironment('OTHELLO_WS_URL'),
);
