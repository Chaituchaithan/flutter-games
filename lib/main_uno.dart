import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/uno/uno_module.dart';

/// The Uno app — contains only the Uno game.
///   flutter run -t lib/main_uno.dart
final unoApp = AppProfile(appName: 'Uno', modules: [unoModule]);

void main() => runAuraApp(unoApp);
