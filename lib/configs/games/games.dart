/// All game configuration: the shared core (ids, config shape, registry,
/// active game) and one folder per game. Import this one file.
///
/// ```
/// games/
///   core/       game_id · game_config · game_registry · active_game
///   <game>/     <game>_config.dart  (port, socket path, players, turn time, overrides)
/// ```
library;

export 'core/active_game.dart';
export 'core/game_config.dart';
export 'core/game_id.dart';
export 'core/game_registry.dart';
export 'bingo/bingo_config.dart';
export 'checkers/checkers_config.dart';
export 'chess/chess_config.dart';
export 'crash/crash_config.dart';
export 'ludo/ludo_config.dart';
export 'othello/othello_config.dart';
export 'poker/poker_config.dart';
export 'racing/racing_config.dart';
export 'roulette/roulette_config.dart';
export 'rummy/rummy_config.dart';
export 'scrabble/scrabble_config.dart';
export 'snakes_ladders/snakes_ladders_config.dart';
