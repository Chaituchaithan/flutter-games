import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/rummy/rummy_module.dart';

/// The Rummy app — contains only the Rummy game.
///   flutter run -t lib/main_rummy.dart
final rummyApp = AppProfile(appName: 'Rummy', modules: [rummyModule]);

void main() => runAuraApp(rummyApp);
