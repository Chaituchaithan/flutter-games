/// Game-agnostic matchmaking and rooms (docs/services/05-matchmaking-and-rooms.md).
///
/// Parsed from the shared "rooms family" lobby frames every game socket sends:
/// `match.found`, `room.created`, `room.joined`, `room.list_result`,
/// `room.user_joined`. Parsing is lenient: unknown fields are ignored, money
/// accepts numbers and numeric strings.
library;

import 'package:flutter/foundation.dart';

import '../../data/models/game_catalogue.dart';
import '../../utils/amount.dart';
import '../socket/socket_client.dart';

int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);

/// A stake amount (`bet_amount`): null stays null (a free private room).
int? _amount(Object? v) => v == null ? null : parseAmount(v);

// ── Modes (doc §1 "Choosing a mode") ──

/// Splits a game's catalogue modes ([gameCatalogueProvider]) into the two
/// lists the app offers. The catalogue has no flag, so the rule is
/// `mode_config.host_can_choose` ([GameMode.isPrivateRoom]) → Play with
/// friends (`room.create`), else Quick match (`match.find`). The servers
/// accept either kind on either path (Known gaps 2): offer each list only its
/// own modes.
@immutable
class ModePicker {
  const ModePicker(this.modes);

  factory ModePicker.of(GameCatalogue catalogue) => ModePicker(catalogue.modes);

  /// Playable modes, in the server's order.
  final List<GameMode> modes;

  /// For `match.find`.
  List<GameMode> get quickMatch => [for (final m in modes) if (!m.isPrivateRoom) m];

  /// For `room.create`.
  List<GameMode> get withFriends => [for (final m in modes) if (m.isPrivateRoom) m];

  GameMode? byCode(String? code) => modes.where((m) => m.code == code).firstOrNull;

  /// The mode's name for an open-tables row (falls back to the code).
  String nameOf(String modeCode) => byCode(modeCode)?.name ?? modeCode;
}

/// Seat counts a host may pick on `room.create`: `min_players`..`player_count`.
List<int> seatChoices(GameMode m) => [for (var n = m.minPlayers.clamp(1, m.playerCount); n <= m.playerCount; n++) n];

// ── Seats and rooms ──

/// One seat at a table (`players[]`, `room.user_joined`).
@immutable
class SeatPlayer {
  const SeatPlayer({
    required this.userId,
    required this.username,
    required this.seat,
    this.isBot = false,
    this.ready = false,
    this.avatarUrl,
    this.color,
  });

  final String userId;
  final String username;

  /// Not packed: in a 2-seat Ludo game the second player sits at seat 2.
  final int seat;

  /// A normal seat; whether to badge it is a design choice.
  final bool isBot;
  final bool ready;
  final String? avatarUrl;

  /// Game-specific (Ludo's colour); null elsewhere.
  final String? color;

  SeatPlayer copyWith({bool? ready}) => SeatPlayer(
    userId: userId,
    username: username,
    seat: seat,
    isBot: isBot,
    ready: ready ?? this.ready,
    avatarUrl: avatarUrl,
    color: color,
  );

  factory SeatPlayer.fromJson(Map<String, dynamic> j) => SeatPlayer(
    userId: '${j['user_id'] ?? ''}',
    username: '${j['username'] ?? 'Player'}',
    seat: _int(j['seat']) ?? 0,
    isBot: j['is_bot'] == true,
    ready: j['ready'] == true,
    avatarUrl: j['avatar_url'] as String?,
    color: j['color'] as String?,
  );
}

/// The player's seat at a table: from `match.found`, `room.created` or
/// `room.joined`.
@immutable
class RoomSeat {
  const RoomSeat({
    required this.roomId,
    required this.roomCode,
    required this.seat,
    required this.maxPlayers,
    required this.modeCode,
    required this.players,
    this.currency,
    this.stake,
    this.listed = false,
    this.quickMatch = false,
    this.modeName,
    this.variant,
    this.raw = const {},
  });

  /// Also the match id.
  final String roomId;

  /// 8 characters (the first 8 of [roomId]); not case sensitive.
  final String roomCode;

  /// The player's own seat.
  final int seat;
  final int maxPlayers;
  final String modeCode;

  /// Null on a free private room.
  final String? currency;

  /// `bet_amount`; null or 0 = free.
  final int? stake;
  final List<SeatPlayer> players;

  /// Shown in other players' open tables list.
  final bool listed;

  /// Seated by `match.found` (a quick-match lobby, where bots may join).
  final bool quickMatch;
  final String? modeName;
  final String? variant;

  /// The whole reply, for the game's own fields (Ludo's `rules`, `color`, …).
  final Map<String, dynamic> raw;

  bool get isFree => (stake ?? 0) == 0;
  bool get isFull => players.length >= maxPlayers;

  /// The code as shown and shared (upper case).
  String get displayCode => roomCode.toUpperCase();

  RoomSeat withPlayers(List<SeatPlayer> ps) => RoomSeat(
    roomId: roomId,
    roomCode: roomCode,
    seat: seat,
    maxPlayers: maxPlayers,
    modeCode: modeCode,
    players: [...ps]..sort((a, b) => a.seat.compareTo(b.seat)),
    currency: currency,
    stake: stake,
    listed: listed,
    quickMatch: quickMatch,
    modeName: modeName,
    variant: variant,
    raw: raw,
  );

  factory RoomSeat.fromJson(Map<String, dynamic> j, {bool quickMatch = false}) {
    final id = '${j['room_id'] ?? ''}';
    final code = '${j['room_code'] ?? (id.length >= 8 ? id.substring(0, 8) : id)}';
    final players = [for (final p in (j['players'] as List? ?? const [])) if (p is Map) SeatPlayer.fromJson(p.cast<String, dynamic>())]
      ..sort((a, b) => a.seat.compareTo(b.seat));
    return RoomSeat(
      roomId: id,
      roomCode: code,
      seat: _int(j['seat']) ?? 0,
      maxPlayers: _int(j['max_players']) ?? 2,
      modeCode: '${j['mode_code'] ?? ''}',
      currency: j['currency'] as String?,
      stake: _amount(j['bet_amount']),
      players: players,
      listed: j['listed'] == true,
      quickMatch: quickMatch,
      modeName: j['mode_name'] as String?,
      variant: j['variant'] as String?,
      raw: j,
    );
  }
}

/// One row of the open tables list (`room.list_result.rooms[]`).
@immutable
class OpenRoom {
  const OpenRoom({
    required this.roomId,
    required this.roomCode,
    required this.modeCode,
    required this.players,
    required this.maxPlayers,
    this.currency,
    this.stake,
    this.status = 'waiting',
    this.matchmaking = 'random',
    this.variant,
    this.gameType,
    this.createdAt,
  });

  final String roomId;
  final String roomCode;
  final String modeCode;

  /// Seated count.
  final int players;
  final int maxPlayers;
  final String? currency;
  final int? stake;

  /// `waiting` or `in_progress` (with `include_in_play`).
  final String status;

  /// `random` (a quick-match lobby) or `private_room` (a listed private room).
  final String matchmaking;
  final String? variant;
  final String? gameType;
  final DateTime? createdAt;

  bool get isFree => (stake ?? 0) == 0;
  bool get isPrivate => matchmaking == 'private_room';
  bool get isWaiting => status == 'waiting';

  factory OpenRoom.fromJson(Map<String, dynamic> j) {
    final created = _int(j['created_at']);
    return OpenRoom(
      roomId: '${j['room_id'] ?? ''}',
      roomCode: '${j['room_code'] ?? ''}',
      modeCode: '${j['mode_code'] ?? ''}',
      players: _int(j['players']) ?? (j['players'] is List ? (j['players'] as List).length : 0),
      maxPlayers: _int(j['max_players']) ?? 2,
      currency: j['currency'] as String?,
      stake: _amount(j['bet_amount']),
      status: '${j['status'] ?? 'waiting'}',
      matchmaking: '${j['matchmaking'] ?? 'random'}',
      variant: j['variant'] as String?,
      gameType: j['game_type'] as String?,
      createdAt: created == null ? null : DateTime.fromMillisecondsSinceEpoch(created),
    );
  }

  static List<OpenRoom> listFromJson(Map<String, dynamic> data) =>
      [for (final r in (data['rooms'] as List? ?? const [])) if (r is Map) OpenRoom.fromJson(r.cast<String, dynamic>())];
}

/// The host's picks for `room.create`. Mode, stake and host options come
/// from the catalogue's [PlaySelection] (its `toSocketData()`).
@immutable
class RoomOptions {
  const RoomOptions({this.maxPlayers, this.listed = false});

  /// Between the mode's `min_players` and `player_count`; null = the mode's.
  final int? maxPlayers;

  /// Also show the room in open tables (default: code only).
  final bool listed;
}

// ── Errors (doc "Errors": game socket) ──

/// Every game's lobby refusal codes, mapped to one set.
enum LobbyError {
  notFound,
  roomFull,
  gameInProgress,
  alreadyInRoom,
  notYourTable,
  insufficientFunds,
  invalidMode,
  invalidSettings,
  invalidRequest,
  killSwitch,
  invalidState,
  busy,
  internal,
  network,
  unknown;

  static LobbyError fromCode(String code) => switch (code) {
    'not_found' => notFound,
    'room_full' => roomFull,
    'game_in_progress' => gameInProgress,
    'already_in_room' => alreadyInRoom,
    'not_your_table' => notYourTable,
    'insufficient_funds' || 'insufficient_balance' => insufficientFunds,
    'invalid_mode' => invalidMode,
    'invalid_settings' => invalidSettings,
    'invalid_request' => invalidRequest,
    'kill_switch_engaged' => killSwitch,
    'invalid_state' => invalidState,
    'busy' => busy,
    'internal_error' => internal,
    'disconnected' || 'connect_failed' || 'connect_timeout' || 'timeout' => network,
    _ => unknown,
  };

  /// Worth one retry ("Something went wrong. Try again.").
  bool get retryable => this == busy || this == internal;
}

/// A refused lobby request. [message] is the server's text, kept only for a
/// kill switch (the operator's words); other messages are developer text.
class LobbyFailure implements Exception {
  const LobbyFailure(this.error, {this.code = '', this.event, this.operatorMessage});

  final LobbyError error;

  /// The server's snake_case code (for logs and tests).
  final String code;

  /// The request that was refused (`match.find`, `room.join`, …).
  final String? event;

  /// `kill_switch_engaged` only.
  final String? operatorMessage;

  factory LobbyFailure.from(Object e, {String? event}) {
    if (e is LobbyFailure) return e;
    if (e is SocketError) {
      final err = LobbyError.fromCode(e.code);
      return LobbyFailure(err, code: e.code, event: event, operatorMessage: err == LobbyError.killSwitch ? e.message : null);
    }
    return LobbyFailure(LobbyError.network, code: e.runtimeType.toString(), event: event);
  }

  /// Player-facing text (doc "Errors" table).
  String get text => switch (error) {
    LobbyError.notFound => 'No room with that code.',
    LobbyError.roomFull => 'That room is full.',
    LobbyError.gameInProgress => 'That game has already started.',
    LobbyError.alreadyInRoom => 'You are already at a table. Leave it first.',
    LobbyError.notYourTable => 'That table isn’t yours to join.',
    LobbyError.insufficientFunds => 'Not enough tokens/gold for this table.',
    LobbyError.invalidMode => 'This mode isn’t available right now.',
    LobbyError.killSwitch =>
      (operatorMessage?.isNotEmpty ?? false) ? operatorMessage! : 'New games are paused for a moment. Try again soon.',
    LobbyError.invalidState => event == 'match.cancel'
        ? 'This is a private room. Leave the room instead.'
        : 'You can’t do that right now.',
    LobbyError.network => 'Can’t reach the game server. Check your connection.',
    // App bugs (bad stake, seat count or host option) and server faults.
    LobbyError.invalidSettings ||
    LobbyError.invalidRequest ||
    LobbyError.busy ||
    LobbyError.internal ||
    LobbyError.unknown => 'Something went wrong. Try again.',
  };

  @override
  String toString() => 'LobbyFailure($code${event == null ? '' : ' on $event'})';
}

// ── Pushed lobby events ──

/// What the lobby hears from the socket while seated (doc "How to structure
/// the app": seat changes, ready, game.started, errors).
sealed class LobbyEvent {
  const LobbyEvent();
}

/// `match.found` pushed while searching (some games seat you later).
class SeatFound extends LobbyEvent {
  const SeatFound(this.seat);
  final RoomSeat seat;
}

/// `room.user_joined` — a human or a bot (`is_bot`) took a seat.
class PlayerJoined extends LobbyEvent {
  const PlayerJoined(this.player, {this.roomFull = false, this.reconnected = false});
  final SeatPlayer player;
  final bool roomFull;
  final bool reconnected;
}

/// `room.user_left` — `reason` is `left`, `disconnected`, ….
class PlayerLeft extends LobbyEvent {
  const PlayerLeft(this.userId, {this.reason});
  final String userId;
  final String? reason;
}

/// `player.ready_update`.
class ReadyChanged extends LobbyEvent {
  const ReadyChanged(this.userId, this.ready);
  final String userId;
  final bool ready;
}

/// `game.started` (the full state is in [data], the game's own shape).
class GameStarted extends LobbyEvent {
  const GameStarted(this.data);
  final Map<String, dynamic> data;
}

/// `game.state_sync` after a reconnect or a cold start: back to the board.
class GameResumed extends LobbyEvent {
  const GameResumed(this.data, {this.finished = false});
  final Map<String, dynamic> data;

  /// `game.final_state`: the game ended while away.
  final bool finished;
}

/// `game.over` / `game.completed` / `game.ended`.
class GameEnded extends LobbyEvent {
  const GameEnded(this.data);
  final Map<String, dynamic> data;
}

/// `game.start_error`: stakes couldn't be taken; ready flags are cleared.
class StartFailed extends LobbyEvent {
  const StartFailed(this.failure);
  final LobbyFailure failure;
}

/// The room closed under the player (`room.destroyed`, `game.cancelled`).
class RoomClosed extends LobbyEvent {
  const RoomClosed({this.reason});
  final String? reason;
}
