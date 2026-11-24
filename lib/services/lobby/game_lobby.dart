/// The per-game lobby over a game socket (docs/services/05-matchmaking-and-rooms.md
/// "How to structure the app"). One implementation per game; the screens and
/// [LobbyController] are shared.
///
/// Matching, rooms, seats and bots live on each game's own socket. Never call
/// the gateway's `/matchmaking/...` routes: they are retired (`410`).
library;

import 'dart:async';

import '../../data/models/game_catalogue.dart';
import '../socket/socket_client.dart';
import 'lobby_models.dart';

/// Lobby event names shared by the rooms family (doc §5).
abstract final class LobbyEvents {
  static const matchFind = 'match.find';
  static const matchFound = 'match.found';
  static const matchCancel = 'match.cancel';
  static const matchCancelled = 'match.cancelled';
  static const roomCreate = 'room.create';
  static const roomCreated = 'room.created';
  static const roomJoin = 'room.join';
  static const roomJoined = 'room.joined';
  static const roomList = 'room.list';
  static const roomListResult = 'room.list_result';
  static const roomLeave = 'room.leave';
  static const roomLeft = 'room.left';
  static const userJoined = 'room.user_joined';
  static const userLeft = 'room.user_left';
  static const roomDestroyed = 'room.destroyed';
  static const ready = 'player.ready';
  static const unready = 'player.unready';
  static const readyUpdate = 'player.ready_update';
  static const gameStarted = 'game.started';
  static const startError = 'game.start_error';
  static const stateSync = 'game.state_sync';
  static const finalState = 'game.final_state';
  static const gameOver = 'game.over';
  static const gameCompleted = 'game.completed';
  static const gameEnded = 'game.ended';
  static const gameCancelled = 'game.cancelled';
}

/// Sends a request on the game socket and awaits the reply with the same id
/// ([SocketClient.request]); an error reply throws [SocketError].
typedef LobbyRequest = Future<SocketMessage> Function(String event, Map<String, dynamic> data);

abstract class GameLobby {
  /// The catalogue `code` (`ludo`).
  String get gameCode;

  /// Seat changes, ready, game start, errors — while seated.
  Stream<LobbyEvent> get events;

  /// `room.list` → waiting quick-match lobbies and listed private rooms.
  /// Works only in the lobby state (seated: `room.error invalid_state`).
  Future<List<OpenRoom>> listOpenRooms({String? variant, bool includeInPlay = false});

  /// `match.find` with the catalogue [selection] (mode, stake). Always sends
  /// `player_count` = [mode]'s `player_count` (the server defaults to 2
  /// seats otherwise).
  Future<RoomSeat> quickMatch(GameMode mode, PlaySelection selection);

  /// `match.cancel` — only while searching (a private room answers
  /// `match.cancel_error invalid_state`: use [leaveRoom]).
  Future<void> cancelSearch();

  /// `room.create` → `room.created` (with the `room_code` to share).
  /// [selection] carries the mode, stake and host picks.
  Future<RoomSeat> createRoom(GameMode mode, PlaySelection selection, RoomOptions options);

  /// `room.join {room_code}` (any case).
  Future<RoomSeat> joinByCode(String roomCode);

  /// `room.leave` — frees the seat (mid-game: a forfeit; ask first).
  Future<void> leaveRoom();

  /// `player.ready` / `player.unready`.
  Future<void> setReady(bool ready);
}

/// The rooms-family lobby every game shares (Ludo is the reference). A game
/// adds its own `match.find` / `room.create` fields through [findExtras] and
/// [createExtras]; the screens stay shared.
class SocketGameLobby implements GameLobby {
  SocketGameLobby({
    required this.gameCode,
    required LobbyRequest request,
    required Stream<SocketMessage> messages,
    this.findExtras,
    this.createExtras,
  }) // Named params can't be private initializing formals.
  // ignore: prefer_initializing_formals
  : _request = request {
    _sub = messages.listen(_onMessage);
  }

  /// On the app's shared socket.
  factory SocketGameLobby.onSocket(String gameCode, SocketClient socket) => SocketGameLobby(
    gameCode: gameCode,
    request: socket.request,
    messages: socket.broadcasts,
  );

  @override
  final String gameCode;
  final LobbyRequest _request;

  /// Game-specific `match.find` fields (a chess time control, …).
  final Map<String, dynamic> Function(GameMode mode)? findExtras;

  /// Game-specific `room.create` fields (Ludo's `color`, `turn_seconds`, …).
  final Map<String, dynamic> Function(GameMode mode, RoomOptions options)? createExtras;

  late final StreamSubscription<SocketMessage> _sub;
  final _events = StreamController<LobbyEvent>.broadcast();

  @override
  Stream<LobbyEvent> get events => _events.stream;

  Future<SocketMessage> _send(String event, Map<String, dynamic> data) async {
    try {
      return await _request(event, data);
    } on Object catch (e) {
      throw LobbyFailure.from(e, event: event);
    }
  }

  @override
  Future<List<OpenRoom>> listOpenRooms({String? variant, bool includeInPlay = false}) async {
    final m = await _send(LobbyEvents.roomList, {'variant': ?variant, if (includeInPlay) 'include_in_play': true});
    return OpenRoom.listFromJson(m.data);
  }

  @override
  Future<RoomSeat> quickMatch(GameMode mode, PlaySelection selection) async {
    final m = await _send(LobbyEvents.matchFind, {
      ...selection.toSocketData(),
      'player_count': mode.playerCount,
      ...?findExtras?.call(mode),
    });
    return RoomSeat.fromJson(m.data, quickMatch: true);
  }

  @override
  Future<void> cancelSearch() => _send(LobbyEvents.matchCancel, const {});

  @override
  Future<RoomSeat> createRoom(GameMode mode, PlaySelection selection, RoomOptions options) async {
    final m = await _send(LobbyEvents.roomCreate, {
      ...selection.toSocketData(),
      'max_players': options.maxPlayers ?? mode.playerCount,
      if (options.listed) 'listed': true,
      ...?createExtras?.call(mode, options),
    });
    return RoomSeat.fromJson(m.data);
  }

  @override
  Future<RoomSeat> joinByCode(String roomCode) async {
    final m = await _send(LobbyEvents.roomJoin, {'room_code': normalizeRoomCode(roomCode)});
    return RoomSeat.fromJson(m.data);
  }

  @override
  Future<void> leaveRoom() => _send(LobbyEvents.roomLeave, const {});

  @override
  Future<void> setReady(bool ready) => _send(ready ? LobbyEvents.ready : LobbyEvents.unready, const {});

  void _onMessage(SocketMessage m) {
    if (_events.isClosed) return;
    final d = m.data;
    final LobbyEvent? e = switch (m.event) {
      LobbyEvents.matchFound => SeatFound(RoomSeat.fromJson(d, quickMatch: true)),
      LobbyEvents.userJoined => PlayerJoined(
        SeatPlayer.fromJson(d),
        roomFull: d['room_full'] == true,
        reconnected: d['reconnected'] == true,
      ),
      LobbyEvents.userLeft => PlayerLeft('${d['user_id'] ?? ''}', reason: d['reason'] as String?),
      LobbyEvents.readyUpdate => ReadyChanged('${d['user_id'] ?? ''}', d['ready'] == true),
      LobbyEvents.gameStarted => GameStarted(d),
      LobbyEvents.stateSync => GameResumed(d),
      LobbyEvents.finalState => GameResumed(d, finished: true),
      LobbyEvents.gameOver || LobbyEvents.gameCompleted || LobbyEvents.gameEnded => GameEnded(d),
      LobbyEvents.startError => StartFailed(LobbyFailure.from(errorFromData(m), event: m.event)),
      LobbyEvents.roomDestroyed || LobbyEvents.gameCancelled => RoomClosed(reason: d['reason'] as String?),
      _ => null,
    };
    if (e != null) _events.add(e);
  }

  void dispose() {
    _sub.cancel();
    _events.close();
  }
}

/// Codes are not case sensitive; the server's are lower case.
String normalizeRoomCode(String code) => code.trim().replaceAll(RegExp(r'\s'), '').toLowerCase();

/// A room code as typed: 8 letters or digits.
bool isValidRoomCode(String code, {int length = 8}) =>
    RegExp('^[A-Za-z0-9]{$length}\$').hasMatch(code.trim());

/// `royalearcade://join/<game_code>/<room_code>` (doc Flow B, app-side only):
/// the game code and room code, or null.
({String gameCode, String roomCode})? parseJoinLink(Uri uri) {
  if (uri.scheme != 'royalearcade' || uri.host != 'join') return null;
  final seg = uri.pathSegments;
  if (seg.length != 2 || !isValidRoomCode(seg[1])) return null;
  return (gameCode: seg[0], roomCode: normalizeRoomCode(seg[1]));
}
