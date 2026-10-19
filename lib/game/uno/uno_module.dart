import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/uno/uno_config.dart';
import 'package:snakeladder/game/uno/uno_screen.dart';

/// Uno route names (owned by this module).
abstract final class UnoRoutes {
  static const board = '/game/uno';
  static const setup = '/game/uno-setup';
}

/// Uno: Quick Play vs computer, 2–4 players (online play once its socket
/// protocol is integrated — then set [GameModule.onlineRoute]).
final unoModule = GameModule(
  config: unoConfig,
  practiceRoute: UnoRoutes.setup,
  demoBoardRoute: UnoRoutes.board,
  routes: {UnoRoutes.board: (_) => const UnoScreen(), UnoRoutes.setup: (_) => const UnoSetupScreen()},
);
