import 'package:flutter/widgets.dart';

import '../configs/games/games.dart';
import 'game_module.dart';

/// What one installable app contains: its name and the game modules it
/// ships. Each entry point (`lib/main*.dart`) sets [AppProfile.current]
/// before `runApp`:
///
/// | Entry point | App |
/// |---|---|
/// | `lib/main.dart` | all games (development build) |
/// | `lib/main_chess.dart` | Chess only |
/// | `lib/main_ludo.dart` | Ludo only |
/// | `lib/main_snakes.dart` | Snakes & Ladders only |
///
/// Shared code (Home, login, Online Play, results…) reads the games from
/// here — it never imports a game directly.
class AppProfile {
  const AppProfile({
    required this.appName,
    required this.modules,
    this.extraRoutes = const {},
    this.showComingSoon = false,
  }) : assert(modules.length > 0);

  /// Shown as the brand (splash, login, task switcher).
  final String appName;

  /// Games in this app; the first is the default.
  final List<GameModule> modules;

  /// Non-game routes only this app has (e.g. prototype screens in the dev
  /// build).
  final Map<String, GameRouteBuilder> extraRoutes;

  /// Also list the not-yet-built games as "Soon" chips (dev build).
  final bool showComingSoon;

  /// One game → no game picker anywhere.
  bool get singleGame => modules.length == 1;

  GameModule? module(GameId id) {
    for (final m in modules) {
      if (m.id == id) return m;
    }
    return null;
  }

  bool includes(GameId id) => module(id) != null;

  /// The screen for [name] if a game in this app (or [extraRoutes]) owns it.
  Widget? buildRoute(String? name, Object? args) {
    if (name == null) return null;
    for (final m in modules) {
      final b = m.routes[name];
      if (b != null) return b(args);
    }
    return extraRoutes[name]?.call(args);
  }

  /// The running app. Set by the entry point; tests set it as needed.
  static AppProfile? _current;
  static AppProfile get current {
    final p = _current;
    if (p == null) throw StateError('AppProfile.current not set — call it from main() before runApp');
    return p;
  }

  static set current(AppProfile p) => _current = p;
  static bool get isSet => _current != null;
}
