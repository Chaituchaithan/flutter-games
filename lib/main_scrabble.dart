import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/scrabble/scrabble_module.dart';

/// The Scrabble app — contains only the Scrabble game.
///   flutter run -t lib/main_scrabble.dart
final scrabbleApp = AppProfile(appName: 'Scrabble', modules: [scrabbleModule]);

void main() => runAuraApp(scrabbleApp);
