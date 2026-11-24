import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/games/games.dart';

/// Builds a screen for one of a game's routes from the route arguments.
typedef GameRouteBuilder = Widget Function(Object? args);

/// One selectable side for online play (e.g. chess White / Black), sent to
/// the game's online screen as the `color` route argument.
class OnlineSide {
  const OnlineSide({required this.value, required this.label, required this.sub, required this.icon});

  /// Route-argument value, e.g. 'white'.
  final String value;
  final String label;
  final String sub;

  /// The side's picture at [size] (e.g. a king piece).
  final Widget Function(double size) icon;
}

/// A game's stake tiers for the shared online screens: null = the app's
/// default tiers; a list = only these (e.g. the server's catalogue tiers).
typedef OnlineStakeTiers = List<int>? Function(WidgetRef ref, {required int players, required bool tokens, required bool friends});

/// Everything the shared app needs to know about one game. Each game folder
/// (`lib/game/<game>/`) exports exactly one module; an app ships the modules
/// listed in its [AppProfile] and nothing else, so games never reference each
/// other and a single-game app contains only its own game's code.
class GameModule {
  const GameModule({
    required this.config,
    required this.routes,
    this.practiceRoute,
    this.onlineRoute,
    this.demoBoardRoute,
    this.onlineSides = const [],
    this.onlinePlayerCounts = const [2],
    this.friendsPlayerCounts = const [2],
    this.onlineFreePlay = false,
    this.onlineStakeTiers,
    this.roomCodeLength = 6,
  });

  /// Identity, ports, players (from `lib/configs/games/<game>/`).
  final GameConfig config;

  /// The game's own screens by route name (names start with `/game/<id>`).
  final Map<String, GameRouteBuilder> routes;

  /// Quick Play / vs-computer setup (null = none).
  final String? practiceRoute;

  /// Online match screen; takes `{mode, stake, tokens, code, color}` (null =
  /// no online play yet).
  final String? onlineRoute;

  /// Board shown after the offline (socket-off) matchmaking demo.
  final String? demoBoardRoute;

  /// Online Play "Choose your side" options (empty = no side step).
  final List<OnlineSide> onlineSides;

  /// Quick-match sizes offered by Online Play (one = no "How many players?" step).
  final List<int> onlinePlayerCounts;

  /// Seats a friends room can have (one = no seat picker).
  final List<int> friendsPlayerCounts;

  /// Online Play offers a free (no stake) match.
  final bool onlineFreePlay;

  /// The game's own stake tiers (null = the app's default tiers).
  final OnlineStakeTiers? onlineStakeTiers;

  /// Characters in a friends-room code (Chess 6, Ludo 8).
  final int roomCodeLength;

  GameId get id => config.id;
}
