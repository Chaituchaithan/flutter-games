import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/scrabble/scrabble_config.dart';
import 'package:snakeladder/game/scrabble/scrabble_screen.dart';

/// Scrabble route names (owned by this module).
abstract final class ScrabbleRoutes {
  static const board = '/game/scrabble';
  static const setup = '/game/scrabble-setup';
}

/// Scrabble: Quick Play vs computer (online play once its socket protocol is
/// integrated — then set [GameModule.onlineRoute]).
final scrabbleModule = GameModule(
  config: scrabbleConfig,
  practiceRoute: ScrabbleRoutes.setup,
  demoBoardRoute: ScrabbleRoutes.board,
  routes: {
    ScrabbleRoutes.board: (_) => const ScrabbleScreen(),
    ScrabbleRoutes.setup: (_) => const ScrabbleSetupScreen(),
  },
);
