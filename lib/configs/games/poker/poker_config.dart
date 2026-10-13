import '../core/game_config.dart';
import '../core/game_id.dart';

/// Poker — poker-service on its own port (WS `/ws` verified reachable).
/// Quick Play (Texas Hold'em vs computer, 2–6 players) is built; online play
/// waits for its socket protocol.
const pokerConfig = GameConfig(
  id: GameId.poker,
  displayName: 'Poker',
  icon: '🃏',
  port: 31287,
  socketPath: '/ws',
  minPlayers: 2,
  maxPlayers: 6,
  available: true,
  wsUrlOverride: String.fromEnvironment('POKER_WS_URL'),
);
