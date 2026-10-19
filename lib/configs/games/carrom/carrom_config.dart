import '../core/game_config.dart';
import '../core/game_id.dart';

/// Carrom. Quick Play (vs computer) is built; there's no game service yet
/// (port 0) — online play comes later.
const carromConfig = GameConfig(
  id: GameId.carrom,
  displayName: 'Carrom',
  icon: '🎯',
  port: 0, // no service yet
  socketPath: '/ws',
  minPlayers: 2,
  maxPlayers: 2,
  available: true,
);
