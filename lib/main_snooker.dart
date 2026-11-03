import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/snooker/snooker_module.dart';

/// The Snooker app — contains only the Snooker game.
///   flutter run -t lib/main_snooker.dart
final snookerApp = AppProfile(appName: 'Snooker', modules: [snookerModule]);

void main() => runAuraApp(snookerApp);
