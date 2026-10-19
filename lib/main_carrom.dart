import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/carrom/carrom_module.dart';

/// The Carrom app — contains only the Carrom game.
///   flutter run -t lib/main_carrom.dart
final carromApp = AppProfile(appName: 'Carrom', modules: [carromModule]);

void main() => runAuraApp(carromApp);
