import '../core/game_config.dart';
import '../core/game_id.dart';

/// Uno-style colour card game. Quick Play (vs computer, 2–4 players) is
/// built; there's no game service yet (port 0) — online play comes later.
///
/// Note: "UNO" is a Mattel trademark — rename [displayName] before a store
/// release.
const unoConfig = GameConfig(
  id: GameId.uno,
  displayName: 'Uno',
  icon: '🃏',
  port: 0, // no service yet
  socketPath: '/ws',
  minPlayers: 2,
  maxPlayers: 4,
  available: true,
);
