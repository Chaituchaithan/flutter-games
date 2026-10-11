import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/othello/othello_module.dart';

/// The Othello app — contains only the Othello game.
///   flutter run -t lib/main_othello.dart
final othelloApp = AppProfile(appName: 'Othello', modules: [othelloModule]);

void main() => runAuraApp(othelloApp);
