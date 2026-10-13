import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/roulette/roulette_config.dart';
import 'package:snakeladder/game/roulette/roulette_screen.dart';

/// Roulette route names (owned by this module).
abstract final class RouletteRoutes {
  static const play = '/game/roulette';
}

/// European roulette: practice table with practice chips (online play once
/// its socket protocol is integrated — then set [GameModule.onlineRoute]).
final rouletteModule = GameModule(
  config: rouletteConfig,
  practiceRoute: RouletteRoutes.play,
  demoBoardRoute: RouletteRoutes.play,
  routes: {RouletteRoutes.play: (_) => const RouletteScreen()},
);
