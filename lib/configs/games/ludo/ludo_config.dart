import '../core/game_config.dart';
import '../core/game_id.dart';

/// Ludo — ludo-service on its own port (WS `/ws` verified reachable). Quick
/// Play (vs computer) is built; online play waits for the Ludo socket protocol.
const ludoConfig = GameConfig(
  id: GameId.ludo,
  displayName: 'Ludo',
  icon: '🎲',
  port: 31285,
  socketPath: '/ws',
  minPlayers: 2,
  maxPlayers: 4,
  available: true,
  wsUrlOverride: String.fromEnvironment('LUDO_WS_URL'),
);
