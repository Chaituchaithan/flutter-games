import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/bingo/bingo_module.dart';

/// The Bingo app — contains only the Bingo game.
///   flutter run -t lib/main_bingo.dart
final bingoApp = AppProfile(appName: 'Bingo', modules: [bingoModule]);

void main() => runAuraApp(bingoApp);
