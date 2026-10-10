import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/snakes/snakes_module.dart';

/// The Snakes & Ladders app — contains only the Snakes & Ladders game.
///   flutter run -t lib/main_snakes.dart
final snakesApp = AppProfile(appName: 'Snakes & Ladders', modules: [snakesModule]);

void main() => runAuraApp(snakesApp);
