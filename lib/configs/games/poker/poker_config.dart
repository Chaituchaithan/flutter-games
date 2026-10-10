import '../core/game_config.dart';
import '../core/game_id.dart';

/// Poker — poker-service on its own port (WS `/ws` verified reachable).
/// Game area not built yet; player counts to confirm when it is.
const pokerConfig = GameConfig(
  id: GameId.poker,
  displayName: 'Poker',
  icon: '🃏',
  port: 31287,
  socketPath: '/ws',
  minPlayers: 2, // TODO: confirm
  maxPlayers: 2, // TODO: confirm
  wsUrlOverride: String.fromEnvironment('POKER_WS_URL'),
);
