import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/chess/chess_module.dart';
import 'game/ludo/ludo_module.dart';
import 'game/prototypes/prototype_routes.dart';
import 'game/snakes/snakes_module.dart';

/// Development build: every game, with a game picker on Home and the
/// not-yet-built games shown as "Soon". Single-game apps: `main_chess.dart`,
/// `main_ludo.dart`, `main_snakes.dart`.
final allGamesApp = AppProfile(
  appName: 'Aura Games',
  modules: [chessModule, snakesModule, ludoModule],
  extraRoutes: prototypeRoutes,
  showComingSoon: true,
);

void main() => runAuraApp(allGamesApp);
