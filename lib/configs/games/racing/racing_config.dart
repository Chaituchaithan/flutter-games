import '../core/game_config.dart';
import '../core/game_id.dart';

/// Racing — racing-service on its own port (WS `/ws` verified reachable).
/// Practice races (six cars, Win / Top 3 bets, practice chips) are built;
/// online play waits for its socket protocol.
const racingConfig = GameConfig(
  id: GameId.racing,
  displayName: 'Racing',
  icon: '🏎️',
  port: 31288,
  socketPath: '/ws',
  minPlayers: 1, // everyone bets on the same race
  maxPlayers: 1,
  available: true,
  wsUrlOverride: String.fromEnvironment('RACING_WS_URL'),
);
