import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/bingo/bingo_config.dart';
import 'package:snakeladder/game/bingo/bingo_screen.dart';

/// Bingo route names (owned by this module).
abstract final class BingoRoutes {
  static const board = '/game/bingo';
  static const setup = '/game/bingo-setup';
}

/// Bingo: Quick Play vs computer (online play once its socket protocol is
/// integrated — then set [GameModule.onlineRoute]).
final bingoModule = GameModule(
  config: bingoConfig,
  practiceRoute: BingoRoutes.setup,
  demoBoardRoute: BingoRoutes.board,
  routes: {
    BingoRoutes.board: (_) => const BingoScreen(),
    BingoRoutes.setup: (_) => const BingoSetupScreen(),
  },
);
