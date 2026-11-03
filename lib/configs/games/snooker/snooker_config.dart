import '../core/game_config.dart';
import '../core/game_id.dart';

/// Snooker. Quick Play (vs computer) is built; there's no game service yet
/// (port 0) — online play comes later.
const snookerConfig = GameConfig(
  id: GameId.snooker,
  displayName: 'Snooker',
  icon: '🎱',
  port: 0, // no service yet
  socketPath: '/ws',
  minPlayers: 2,
  maxPlayers: 2,
  available: true,
);
