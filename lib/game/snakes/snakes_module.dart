import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/snakes_ladders/snakes_ladders_config.dart';
import 'package:snakeladder/game/snakes/snakes_ladders_screen.dart';

/// Snakes & Ladders route names (owned by this module).
abstract final class SnakesRoutes {
  static const board = '/game/snakes-ladders';
  static const setup = '/game/snakes-setup';
}

/// Snakes & Ladders: Quick Play vs computer (online play once its socket
/// protocol is integrated — then set [GameModule.onlineRoute]).
final snakesModule = GameModule(
  config: snakesLaddersConfig,
  practiceRoute: SnakesRoutes.setup,
  demoBoardRoute: SnakesRoutes.board,
  routes: {
    SnakesRoutes.board: (_) => const SnakesLaddersScreen(),
    SnakesRoutes.setup: (_) => const SnakesSetupScreen(),
  },
);
