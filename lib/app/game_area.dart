/// Which screens each game opens — answered by the running app's game
/// modules ([AppProfile.current]). Shared screens (Home, Friends, results, …)
/// ask this instead of naming a game's screen, so they work unchanged in a
/// single-game app or the all-games build.
library;

import '../configs/games/core/game_id.dart';
import 'app_profile.dart';
import 'game_module.dart';

abstract final class GameArea {
  static GameModule? module(GameId id) => AppProfile.current.module(id);

  /// Quick Play / vs-computer setup (null = game has none, or isn't in this app).
  static String? practiceRoute(GameId id) => module(id)?.practiceRoute;

  /// Online match screen; takes `{mode, stake, tokens, code, color}` arguments.
  static String? onlineRoute(GameId id) => module(id)?.onlineRoute;

  /// Board shown after the offline matchmaking demo.
  static String? demoBoardRoute(GameId id) => module(id)?.demoBoardRoute;

  /// Online "Choose your side" options for the game (empty = no side step).
  static List<OnlineSide> onlineSides(GameId id) => module(id)?.onlineSides ?? const [];

  static List<int> onlinePlayerCounts(GameId id) => module(id)?.onlinePlayerCounts ?? const [2];
  static List<int> friendsPlayerCounts(GameId id) => module(id)?.friendsPlayerCounts ?? const [2];
  static bool onlineFreePlay(GameId id) => module(id)?.onlineFreePlay ?? false;
  static OnlineStakeTiers? onlineStakeTiers(GameId id) => module(id)?.onlineStakeTiers;
  static int roomCodeLength(GameId id) => module(id)?.roomCodeLength ?? 6;

  /// Whose socket service the app signs in to at login: the active game's
  /// when it has online play, else the first game in this app that does
  /// (null = no online game in this app → no socket step).
  static GameId? socketGame(GameId active) {
    if (onlineRoute(active) != null) return active;
    for (final m in AppProfile.current.modules) {
      if (m.onlineRoute != null) return m.id;
    }
    return null;
  }
}
