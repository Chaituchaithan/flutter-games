import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/racing/racing_module.dart';

/// The Racing app — contains only the Racing game.
///   flutter run -t lib/main_racing.dart
final racingApp = AppProfile(appName: 'Racing', modules: [racingModule]);

void main() => runAuraApp(racingApp);
