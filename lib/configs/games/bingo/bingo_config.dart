import '../core/game_config.dart';
import '../core/game_id.dart';

/// Bingo — bingo-service on its own port (WS `/ws` verified reachable).
/// Quick Play (vs computer, 2–4 players) is built; online play waits for its
/// socket protocol.
const bingoConfig = GameConfig(
  id: GameId.bingo,
  displayName: 'Bingo',
  icon: '🔢',
  port: 31281,
  socketPath: '/ws',
  minPlayers: 2,
  maxPlayers: 4,
  available: true,
  wsUrlOverride: String.fromEnvironment('BINGO_WS_URL'),
);
