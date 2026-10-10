import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/chess/chess_config.dart';
import 'package:snakeladder/game/chess/chess_engine.dart';
import 'package:snakeladder/game/chess/chess_pieces.dart';
import 'package:snakeladder/game/chess/screens/chess_online_screen.dart';
import 'package:snakeladder/game/chess/screens/chess_screen.dart';
import 'package:snakeladder/game/chess/screens/chess_setup_screen.dart';
import 'package:snakeladder/game/chess/screens/chess_vs_computer_screen.dart';

/// Chess route names (owned by this module).
abstract final class ChessRoutes {
  static const board = '/game/chess';
  static const vsComputer = '/game/chess-vs-computer';
  static const setup = '/game/chess-setup';
  static const online = '/game/chess-online';
}

/// Chess: Quick Play vs computer, online quick match / rooms over the chess
/// socket, White/Black side choice.
final chessModule = GameModule(
  config: chessConfig,
  practiceRoute: ChessRoutes.setup,
  onlineRoute: ChessRoutes.online,
  demoBoardRoute: ChessRoutes.board,
  onlineSides: [
    OnlineSide(
      value: 'white',
      label: 'White',
      sub: 'You move first',
      icon: (s) => ChessPiece(piece: const Piece(PieceColor.white, PieceType.king), size: s),
    ),
    OnlineSide(
      value: 'black',
      label: 'Black',
      sub: 'You reply',
      icon: (s) => ChessPiece(piece: const Piece(PieceColor.black, PieceType.king), size: s),
    ),
  ],
  routes: {
    ChessRoutes.board: (_) => const ChessScreen(),
    ChessRoutes.vsComputer: (_) => const ChessVsComputerScreen(),
    ChessRoutes.setup: (_) => const ChessSetupScreen(),
    ChessRoutes.online: (a) {
      final args = a as Map<String, dynamic>?;
      return ChessOnlineScreen(
        stake: args?['stake'] as int? ?? 0,
        tokens: args?['tokens'] as bool? ?? true,
        mode: switch (args?['mode'] as String?) {
          'create' => ChessEntryMode.create,
          'join' => ChessEntryMode.join,
          _ => ChessEntryMode.match,
        },
        joinCode: args?['code'] as String?,
        preferredColor: switch (args?['color'] as String?) {
          'white' => PieceColor.white,
          'black' => PieceColor.black,
          _ => null,
        },
      );
    },
  },
);
