import '../core/game_config.dart';
import '../core/game_id.dart';

/// Scrabble — scrabble-service on its own port (WS `/ws` verified reachable).
/// Quick Play (vs computer, 2 players) is built; online play waits for its
/// socket protocol.
const scrabbleConfig = GameConfig(
  id: GameId.scrabble,
  displayName: 'Scrabble',
  icon: '🔤',
  port: 31291,
  socketPath: '/ws',
  minPlayers: 2,
  maxPlayers: 2,
  available: true,
  wsUrlOverride: String.fromEnvironment('SCRABBLE_WS_URL'),
);
