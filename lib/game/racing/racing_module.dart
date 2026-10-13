import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/racing/racing_config.dart';
import 'package:snakeladder/game/racing/racing_screen.dart';

/// Racing route names (owned by this module).
abstract final class RacingRoutes {
  static const play = '/game/racing';
}

/// Virtual car racing: practice races with practice chips (online play once
/// its socket protocol is integrated — then set [GameModule.onlineRoute]).
final racingModule = GameModule(
  config: racingConfig,
  practiceRoute: RacingRoutes.play,
  demoBoardRoute: RacingRoutes.play,
  routes: {RacingRoutes.play: (_) => const RacingScreen()},
);
