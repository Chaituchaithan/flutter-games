import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/poker/poker_config.dart';
import 'package:snakeladder/game/poker/poker_screen.dart';

/// Poker route names (owned by this module).
abstract final class PokerRoutes {
  static const board = '/game/poker';
  static const setup = '/game/poker-setup';
}

/// Texas Hold'em: Quick Play vs computer (online play once its socket
/// protocol is integrated — then set [GameModule.onlineRoute]).
final pokerModule = GameModule(
  config: pokerConfig,
  practiceRoute: PokerRoutes.setup,
  demoBoardRoute: PokerRoutes.board,
  routes: {
    PokerRoutes.board: (_) => const PokerScreen(),
    PokerRoutes.setup: (_) => const PokerSetupScreen(),
  },
);
