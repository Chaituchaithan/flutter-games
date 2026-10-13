import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/rummy/rummy_config.dart';
import 'package:snakeladder/game/rummy/rummy_screen.dart';

/// Rummy route names (owned by this module).
abstract final class RummyRoutes {
  static const board = '/game/rummy';
  static const setup = '/game/rummy-setup';
}

/// 13-card points rummy: Quick Play vs computer (online play once its socket
/// protocol is integrated — then set [GameModule.onlineRoute]).
final rummyModule = GameModule(
  config: rummyConfig,
  practiceRoute: RummyRoutes.setup,
  demoBoardRoute: RummyRoutes.board,
  routes: {
    RummyRoutes.board: (_) => const RummyScreen(),
    RummyRoutes.setup: (_) => const RummySetupScreen(),
  },
);
