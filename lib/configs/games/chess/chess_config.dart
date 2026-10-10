import '../core/game_config.dart';
import '../core/game_id.dart';

/// Chess — chess-service on its own port (WS `/ws`, verified: sends
/// `connection.established`).
const chessConfig = GameConfig(
  id: GameId.chess,
  displayName: 'Chess',
  icon: '♞',
  port: 31283,
  socketPath: '/ws',
  minPlayers: 2,
  maxPlayers: 2,
  turnTimeMs: 30000,
  wsUrlOverride: String.fromEnvironment('CHESS_WS_URL'),
  available: true,
);

/// Seat numbers the chess service uses for each colour (`match.find` `seat`,
/// and `seat` in room/match replies).
///
/// Chess API doc (confirmed): **seat 0 = White, seat 1 = Black**.
abstract final class ChessSeats {
  static const int white = 0;
  static const int black = 1;
}
