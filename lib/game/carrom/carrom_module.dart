import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/carrom/carrom_config.dart';
import 'package:snakeladder/game/carrom/carrom_screen.dart';

/// Carrom route names (owned by this module).
abstract final class CarromRoutes {
  static const board = '/game/carrom';
  static const setup = '/game/carrom-setup';
}

/// Carrom: Quick Play vs computer (online play once its socket protocol is
/// integrated — then set [GameModule.onlineRoute]).
final carromModule = GameModule(
  config: carromConfig,
  practiceRoute: CarromRoutes.setup,
  demoBoardRoute: CarromRoutes.board,
  routes: {CarromRoutes.board: (_) => const CarromScreen(), CarromRoutes.setup: (_) => const CarromSetupScreen()},
);
