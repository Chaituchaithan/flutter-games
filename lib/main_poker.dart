import 'app/app_profile.dart';
import 'app/bootstrap.dart';
import 'game/poker/poker_module.dart';

/// The Poker app — contains only the Poker game.
///   flutter run -t lib/main_poker.dart
final pokerApp = AppProfile(appName: 'Poker', modules: [pokerModule]);

void main() => runAuraApp(pokerApp);
