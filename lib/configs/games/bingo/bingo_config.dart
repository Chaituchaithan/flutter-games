import '../core/game_config.dart';
import '../core/game_id.dart';

/// Bingo — bingo-service on its own port (WS `/ws` verified reachable).
/// Game area not built yet; player counts to confirm when it is.
const bingoConfig = GameConfig(
  id: GameId.bingo,
  displayName: 'Bingo',
  icon: '🔢',
  port: 31281,
  socketPath: '/ws',
  minPlayers: 2, // TODO: confirm
  maxPlayers: 2, // TODO: confirm
  wsUrlOverride: String.fromEnvironment('BINGO_WS_URL'),
);
