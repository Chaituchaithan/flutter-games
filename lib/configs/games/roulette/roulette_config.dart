import '../core/game_config.dart';
import '../core/game_id.dart';

/// Roulette — roulette-service on its own port (WS `/ws` verified reachable).
/// Practice table (European, single zero, practice chips) is built; online
/// play (shared table, real stakes) waits for its socket protocol.
const rouletteConfig = GameConfig(
  id: GameId.roulette,
  displayName: 'Roulette',
  icon: '🎡',
  port: 31289,
  socketPath: '/ws',
  minPlayers: 1, // everyone bets on the same spin
  maxPlayers: 1,
  available: true,
  wsUrlOverride: String.fromEnvironment('ROULETTE_WS_URL'),
);
