import '../core/game_config.dart';
import '../core/game_id.dart';

/// Rummy — rummy-service on its own port (WS `/ws` verified reachable).
/// Quick Play (13-card points rummy vs computer, 2–4 players) is built;
/// online play waits for its socket protocol.
const rummyConfig = GameConfig(
  id: GameId.rummy,
  displayName: 'Rummy',
  icon: '🀄',
  port: 31290,
  socketPath: '/ws',
  minPlayers: 2,
  maxPlayers: 4,
  available: true,
  wsUrlOverride: String.fromEnvironment('RUMMY_WS_URL'),
);
