import '../core/game_config.dart';
import '../core/game_id.dart';

/// Scrabble — scrabble-service on its own port (WS `/ws` verified reachable).
/// Game area not built yet; player counts to confirm when it is.
const scrabbleConfig = GameConfig(
  id: GameId.scrabble,
  displayName: 'Scrabble',
  icon: '🔤',
  port: 31291,
  socketPath: '/ws',
  minPlayers: 2, // TODO: confirm
  maxPlayers: 2, // TODO: confirm
  wsUrlOverride: String.fromEnvironment('SCRABBLE_WS_URL'),
);
