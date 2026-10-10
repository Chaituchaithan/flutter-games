import '../core/game_config.dart';
import '../core/game_id.dart';

/// Roulette — roulette-service on its own port (WS `/ws` verified reachable).
/// Game area not built yet; player counts to confirm when it is.
const rouletteConfig = GameConfig(
  id: GameId.roulette,
  displayName: 'Roulette',
  icon: '🎡',
  port: 31289,
  socketPath: '/ws',
  minPlayers: 2, // TODO: confirm
  maxPlayers: 2, // TODO: confirm
  wsUrlOverride: String.fromEnvironment('ROULETTE_WS_URL'),
);
