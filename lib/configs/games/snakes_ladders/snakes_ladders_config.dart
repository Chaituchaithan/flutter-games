import '../core/game_config.dart';
import '../core/game_id.dart';

/// Snakes & Ladders — snake-and-ladder-service on its own port (WS `/ws`
/// verified reachable). Quick Play (vs computer) is built; online play waits
/// for its socket protocol.
const snakesLaddersConfig = GameConfig(
  id: GameId.snakesLadders,
  displayName: 'Snakes & Ladders',
  shortName: 'Snakes',
  icon: '🐍',
  port: 31292,
  socketPath: '/ws',
  minPlayers: 2,
  maxPlayers: 4,
  available: true,
  wsUrlOverride: String.fromEnvironment('SNAKES_WS_URL'),
);
