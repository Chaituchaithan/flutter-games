/// All games, looked up by [GameId]. Adding a game = a `<game>/` folder with
/// its `<game>_config.dart` + one line here (and a GameId).
library;

import '../bingo/bingo_config.dart';
import '../checkers/checkers_config.dart';
import '../chess/chess_config.dart';
import '../crash/crash_config.dart';
import '../ludo/ludo_config.dart';
import '../othello/othello_config.dart';
import '../poker/poker_config.dart';
import '../racing/racing_config.dart';
import '../roulette/roulette_config.dart';
import '../rummy/rummy_config.dart';
import '../scrabble/scrabble_config.dart';
import '../snakes_ladders/snakes_ladders_config.dart';
import 'game_config.dart';
import 'game_id.dart';

abstract final class GameRegistry {
  /// Every game service (ports 31281–31292 on the game host).
  static const List<GameConfig> all = [
    chessConfig,
    snakesLaddersConfig,
    ludoConfig,
    othelloConfig,
    scrabbleConfig,
    checkersConfig,
    bingoConfig,
    pokerConfig,
    rummyConfig,
    crashConfig,
    racingConfig,
    rouletteConfig,
  ];

  /// The Home game-chip row (the mockup's board games). Other services stay
  /// in [all] — reachable by config — until they get a place in the UI.
  static const List<GameConfig> homeChips = [
    chessConfig,
    snakesLaddersConfig,
    ludoConfig,
    othelloConfig,
    scrabbleConfig,
    checkersConfig,
  ];

  static GameConfig of(GameId id) => all.firstWhere((g) => g.id == id);

  /// Games shipped in THIS app (set by the app profile at startup, first =
  /// default). Null = every built game (tests / tools).
  static List<GameId>? _appGames;
  static void setAppGames(List<GameId> ids) => _appGames = List.unmodifiable(ids);

  /// Games playable in this app.
  static List<GameConfig> get available =>
      _appGames == null ? [for (final g in all) if (g.available) g] : [for (final id in _appGames!) of(id)];

  static bool isAvailable(GameId id) => available.any((g) => g.id == id);

  /// Parses a `GameId` name (e.g. from `--dart-define=GAME=ludo`); null if unknown.
  static GameId? parse(String name) {
    for (final id in GameId.values) {
      if (id.name.toLowerCase() == name.toLowerCase()) return id;
    }
    return null;
  }
}
