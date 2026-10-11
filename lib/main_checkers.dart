import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/checkers/checkers_module.dart';

/// The Checkers app — contains only the Checkers game.
///   flutter run -t lib/main_checkers.dart
final checkersApp = AppProfile(appName: 'Checkers', modules: [checkersModule]);

void main() => runAuraApp(checkersApp);
