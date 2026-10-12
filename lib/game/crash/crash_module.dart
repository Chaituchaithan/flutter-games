import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/crash/crash_config.dart';
import 'package:snakeladder/game/crash/crash_screen.dart';

/// Crash route names (owned by this module).
abstract final class CrashRoutes {
  static const play = '/game/crash';
}

/// Crash (Aviator style): practice rounds with practice chips (online play
/// once its socket protocol is integrated — then set
/// [GameModule.onlineRoute]).
final crashModule = GameModule(
  config: crashConfig,
  practiceRoute: CrashRoutes.play,
  demoBoardRoute: CrashRoutes.play,
  routes: {CrashRoutes.play: (_) => const CrashScreen()},
);
