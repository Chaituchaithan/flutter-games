import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/checkers/checkers_config.dart';
import 'package:snakeladder/game/checkers/checkers_screen.dart';

/// Checkers route names (owned by this module).
abstract final class CheckersRoutes {
  static const board = '/game/checkers';
  static const setup = '/game/checkers-setup';
}

/// Checkers: Quick Play vs computer (online play once its socket protocol is
/// integrated — then set [GameModule.onlineRoute]).
final checkersModule = GameModule(
  config: checkersConfig,
  practiceRoute: CheckersRoutes.setup,
  demoBoardRoute: CheckersRoutes.board,
  routes: {
    CheckersRoutes.board: (_) => const CheckersScreen(),
    CheckersRoutes.setup: (_) => const CheckersSetupScreen(),
  },
);
