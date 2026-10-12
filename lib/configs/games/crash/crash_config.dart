import '../core/game_config.dart';
import '../core/game_id.dart';

/// Crash — crash-service on its own port (WS `/ws` verified reachable).
/// Practice rounds (Aviator style, practice chips) are built; online play
/// (shared rounds, real stakes) waits for its socket protocol.
const crashConfig = GameConfig(
  id: GameId.crash,
  displayName: 'Crash',
  icon: '✈️',
  port: 31284,
  socketPath: '/ws',
  minPlayers: 1, // everyone plays the same round
  maxPlayers: 1,
  available: true,
  wsUrlOverride: String.fromEnvironment('CRASH_WS_URL'),
);
