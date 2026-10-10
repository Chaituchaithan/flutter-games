import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/ludo/ludo_module.dart';

/// The Ludo app — contains only the Ludo game.
///   flutter run -t lib/main_ludo.dart
final ludoApp = AppProfile(appName: 'Ludo', modules: [ludoModule]);

void main() => runAuraApp(ludoApp);
