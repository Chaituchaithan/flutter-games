import '../core/game_config.dart';
import '../core/game_id.dart';

/// Snakes & Ladders — snake-and-ladder-service on its own port
/// (`ws://<host>:1292/ws`, docs/services/snake-and-ladder.md). Quick Play
/// (vs computer) and online play (quick match, friends rooms) are built.
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
