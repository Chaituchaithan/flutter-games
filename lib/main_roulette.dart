import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/roulette/roulette_module.dart';

/// The Roulette app — contains only the Roulette game.
///   flutter run -t lib/main_roulette.dart
final rouletteApp = AppProfile(appName: 'Roulette', modules: [rouletteModule]);

void main() => runAuraApp(rouletteApp);
