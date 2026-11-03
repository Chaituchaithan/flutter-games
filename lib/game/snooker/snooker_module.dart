import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/snooker/snooker_config.dart';
import 'package:snakeladder/game/snooker/snooker_screen.dart';

/// Snooker route names (owned by this module).
abstract final class SnookerRoutes {
  static const board = '/game/snooker';
  static const setup = '/game/snooker-setup';
}

/// Snooker: Quick Play vs computer (online play once its socket protocol is
/// integrated — then set [GameModule.onlineRoute]).
final snookerModule = GameModule(
  config: snookerConfig,
  practiceRoute: SnookerRoutes.setup,
  demoBoardRoute: SnookerRoutes.board,
  routes: {SnookerRoutes.board: (_) => const SnookerScreen(), SnookerRoutes.setup: (_) => const SnookerSetupScreen()},
);
