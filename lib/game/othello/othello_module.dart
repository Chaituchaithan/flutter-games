import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/othello/othello_config.dart';
import 'package:snakeladder/game/othello/othello_screen.dart';

/// Othello route names (owned by this module).
abstract final class OthelloRoutes {
  static const board = '/game/othello';
  static const setup = '/game/othello-setup';
}

/// Othello: Quick Play vs computer (online play once its socket protocol is
/// integrated — then set [GameModule.onlineRoute]).
final othelloModule = GameModule(
  config: othelloConfig,
  practiceRoute: OthelloRoutes.setup,
  demoBoardRoute: OthelloRoutes.board,
  routes: {
    OthelloRoutes.board: (_) => const OthelloScreen(),
    OthelloRoutes.setup: (_) => const OthelloSetupScreen(),
  },
);
