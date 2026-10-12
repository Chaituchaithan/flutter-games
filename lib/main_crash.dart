import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/crash/crash_module.dart';

/// The Crash app — contains only the Crash game.
///   flutter run -t lib/main_crash.dart
final crashApp = AppProfile(appName: 'Crash', modules: [crashModule]);

void main() => runAuraApp(crashApp);
