import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/chess/chess_module.dart';

/// The Chess app — contains only the Chess game.
///   flutter run -t lib/main_chess.dart
final chessApp = AppProfile(appName: 'Chess', modules: [chessModule]);

void main() => runAuraApp(chessApp);
