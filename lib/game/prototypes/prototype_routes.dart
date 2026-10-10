import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/game/prototypes/othello_screen.dart';
import 'package:snakeladder/game/prototypes/scrabble_screen.dart';
import 'package:snakeladder/game/prototypes/trivia_screen.dart';

/// Static mockup screens of games not built yet (no logic). Only the
/// all-games development build includes them.
const prototypeRoutes = <String, GameRouteBuilder>{
  '/game/othello': _othello,
  '/game/scrabble-2p': _scrabble2,
  '/game/scrabble-4p': _scrabble4,
  '/game/trivia-2p': _trivia2,
  '/game/trivia-4p': _trivia4,
};

OthelloScreen _othello(Object? _) => const OthelloScreen();
ScrabbleScreen _scrabble2(Object? _) => const ScrabbleScreen(players: 2);
ScrabbleScreen _scrabble4(Object? _) => const ScrabbleScreen(players: 4);
TriviaScreen _trivia2(Object? _) => const TriviaScreen(players: 2);
TriviaScreen _trivia4(Object? _) => const TriviaScreen(players: 4);
