import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/ludo/ludo_config.dart';
import 'package:snakeladder/game/ludo/ludo_screen.dart';

/// Ludo route names (owned by this module).
abstract final class LudoRoutes {
  static const board = '/game/ludo';
  static const setup = '/game/ludo-setup';
}

/// Ludo: Quick Play vs computer (online play once the Ludo socket protocol is
/// integrated — then set [GameModule.onlineRoute]).
final ludoModule = GameModule(
  config: ludoConfig,
  practiceRoute: LudoRoutes.setup,
  demoBoardRoute: LudoRoutes.board,
  routes: {LudoRoutes.board: (_) => const LudoScreen(), LudoRoutes.setup: (_) => const LudoSetupScreen()},
);
