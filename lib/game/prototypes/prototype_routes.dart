import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/game/prototypes/trivia_screen.dart';

/// Static mockup screens of games not built yet (no logic). Only the
/// all-games development build includes them.
const prototypeRoutes = <String, GameRouteBuilder>{
  '/game/trivia-2p': _trivia2,
  '/game/trivia-4p': _trivia4,
};

TriviaScreen _trivia2(Object? _) => const TriviaScreen(players: 2);
TriviaScreen _trivia4(Object? _) => const TriviaScreen(players: 4);
