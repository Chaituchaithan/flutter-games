/// The app-side table per catalogue game `code` (04-game-catalogue.md, "What
/// to build" step 3): the gateway sends neither the socket port, nor a
/// category, nor whether this app build has a screen for the game.
library;

import '../../app_config.dart';
import 'game_config.dart';
import 'game_id.dart';
import 'game_registry.dart';

/// Home-screen grouping (`category` is not in the gateway's reply).
enum GameCategory { dice, board, card, casino, word, arcade, bingo }

class GameCodeInfo {
  const GameCodeInfo({
    required this.code,
    required this.port,
    required this.category,
    required this.icon,
    this.id,
    this.sharedSocket = false,
  });

  /// The catalogue's `code`, used as is (`snake-and-ladder`, `teen_patti`).
  final String code;

  /// The app's own game, when this build has one (null = no screen yet).
  final GameId? id;

  /// Socket port in the same convention as [GameConfig.port] (cloud port;
  /// the environment's offset maps it to the LAN port, e.g. 31285 → 1285).
  final int port;
  final GameCategory category;

  /// Chip glyph (game icons ship in the app, keyed by code).
  final String icon;

  /// The socket hosts several games: send `game_code` too.
  final bool sharedSocket;

  /// `ws://<host>:<port>/ws` for this game's server.
  String get socketUrl => AppConfig.server.socketUrl(port, '/ws');
}

abstract final class GameCodes {
  /// Development defaults from 04-game-catalogue.md "Game servers" (+30000).
  static const List<GameCodeInfo> all = [
    GameCodeInfo(
      code: 'ludo',
      id: GameId.ludo,
      port: 31285,
      category: GameCategory.dice,
      icon: '🎲',
    ),
    GameCodeInfo(
      code: 'snake-and-ladder',
      id: GameId.snakesLadders,
      port: 31292,
      category: GameCategory.dice,
      icon: '🐍',
    ),
    GameCodeInfo(
      code: 'chess',
      id: GameId.chess,
      port: 31283,
      category: GameCategory.board,
      icon: '♞',
    ),
    GameCodeInfo(
      code: 'carrom',
      id: GameId.carrom,
      port: 31295,
      category: GameCategory.board,
      icon: '⚪',
    ),
    GameCodeInfo(
      code: 'checkers',
      id: GameId.checkers,
      port: 31282,
      category: GameCategory.board,
      icon: '⛀',
    ),
    GameCodeInfo(
      code: 'othello',
      id: GameId.othello,
      port: 31286,
      category: GameCategory.board,
      icon: '⚫',
    ),
    GameCodeInfo(
      code: 'scrabble',
      id: GameId.scrabble,
      port: 31291,
      category: GameCategory.word,
      icon: '🔤',
    ),
    GameCodeInfo(
      code: 'crash',
      id: GameId.crash,
      port: 31284,
      category: GameCategory.casino,
      icon: '🚀',
    ),
    GameCodeInfo(
      code: 'roulette',
      id: GameId.roulette,
      port: 31289,
      category: GameCategory.casino,
      icon: '🎡',
    ),
    GameCodeInfo(
      code: 'snooker',
      id: GameId.snooker,
      port: 31296,
      category: GameCategory.board,
      icon: '🎱',
    ),
    GameCodeInfo(
      code: 'uno',
      id: GameId.uno,
      port: 31293,
      category: GameCategory.card,
      icon: '🃏',
    ),
    GameCodeInfo(
      code: 'poker',
      id: GameId.poker,
      port: 31287,
      category: GameCategory.card,
      icon: '♠',
    ),
    GameCodeInfo(
      code: 'rummy',
      id: GameId.rummy,
      port: 31290,
      category: GameCategory.card,
      icon: '🂡',
    ),
    GameCodeInfo(
      code: 'teen_patti',
      port: 31294,
      category: GameCategory.card,
      icon: '🂮',
    ),
    GameCodeInfo(
      code: 'bingo',
      id: GameId.bingo,
      port: 31281,
      category: GameCategory.bingo,
      icon: '🔢',
      sharedSocket: true,
    ),
    GameCodeInfo(
      code: 'tombola',
      port: 31281,
      category: GameCategory.bingo,
      icon: '🎟',
      sharedSocket: true,
    ),
    GameCodeInfo(
      code: 'word_duel',
      port: 31297,
      category: GameCategory.word,
      icon: '📝',
      sharedSocket: true,
    ),
    GameCodeInfo(
      code: 'word_rush',
      port: 31297,
      category: GameCategory.word,
      icon: '⚡',
      sharedSocket: true,
    ),
    GameCodeInfo(
      code: 'spelling_bee',
      port: 31297,
      category: GameCategory.word,
      icon: '🐝',
      sharedSocket: true,
    ),
    GameCodeInfo(
      code: 'guess_royale',
      port: 31297,
      category: GameCategory.word,
      icon: '❓',
      sharedSocket: true,
    ),
    GameCodeInfo(
      code: 'fighting',
      port: 31385,
      category: GameCategory.arcade,
      icon: '🥊',
    ),
    GameCodeInfo(
      code: 'hill_climb',
      port: 31395,
      category: GameCategory.arcade,
      icon: '⛰',
    ),
    GameCodeInfo(
      code: 'arena_shooter',
      port: 31386,
      category: GameCategory.arcade,
      icon: '🎯',
      sharedSocket: true,
    ),
    GameCodeInfo(
      code: 'zombie_survival',
      port: 31386,
      category: GameCategory.arcade,
      icon: '🧟',
      sharedSocket: true,
    ),
    GameCodeInfo(
      code: 'battle_royale',
      port: 31386,
      category: GameCategory.arcade,
      icon: '🪂',
      sharedSocket: true,
    ),
    GameCodeInfo(
      code: 'racing',
      id: GameId.racing,
      port: 31288,
      category: GameCategory.arcade,
      icon: '🏎',
    ),
  ];

  static GameCodeInfo? info(String code) =>
      all.where((g) => g.code == code).firstOrNull;

  /// The catalogue code of an app game.
  static String codeOf(GameId id) => all.firstWhere((g) => g.id == id).code;

  /// The app game for a catalogue code (null = no screen in any build).
  static GameId? idOf(String code) => info(code)?.id;

  /// The app's config for a catalogue code, when this app has the game.
  static GameConfig? configOf(String code) {
    final id = idOf(code);
    return id == null ? null : GameRegistry.of(id);
  }
}
