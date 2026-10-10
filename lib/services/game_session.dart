/// The contract every game's online session implements (ChessSession today;
/// LudoSession, SnakesLaddersSession, … later). Shared flows — matchmaking,
/// friends rooms, the lobby, pause/forfeit, results — talk to this, so they
/// work for every game unchanged. Only the in-game actions (a chess move, a
/// dice roll) are game-specific and live on the concrete session.
///
/// Protocol (shared envelope, SOCKET_HOOKS.md): auth.login → room.create /
/// room.join / match.find → player.ready → game.started → game.action ↔
/// game.state_update → game.completed.
library;

import 'package:flutter/foundation.dart';

import '../configs/games/core/game_config.dart';

abstract interface class GameSession implements Listenable {
  /// Which game this session plays (port, path, player counts).
  GameConfig get config;

  /// Open the socket and authenticate (`auth.login`).
  Future<void> start({required String token, String? username});

  /// Quick match: join a waiting room with the same stake, or open one.
  /// [seat] = preferred seat/side (game-specific; null = no preference).
  Future<void> findMatch({required String currency, required int betAmount, int? seat});

  /// Leave the matchmaking queue (`match.cancel`).
  Future<void> cancelMatch();

  /// Private room: create (get a code) or join by code.
  Future<void> createRoom({required String currency, required int betAmount});
  Future<void> joinRoom(String code);

  Future<void> ready();
  Future<void> leave();

  /// Forfeit the match (counts as a defeat).
  Future<void> resign();

  /// In-game quick chat.
  void sendChat(String message);

  void dispose();
}
