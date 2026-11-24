/// Typed Ludo socket payloads (docs/services/ludo.md). Parsed leniently:
/// unknown fields are ignored, missing ones get safe defaults.
library;

import 'package:flutter/foundation.dart';

import '../../common/online_room/room_models.dart';
import '../ludo_engine.dart';

export '../../common/online_room/room_models.dart';

/// Ludo socket event names (ludo.md): the shared room protocol's.
typedef LudoEvent = RoomEvent;

/// The 12 quick-chat lines the server accepts, exactly (ludo.md §8).
const ludoQuickChat = roomQuickChat;

/// Seat → colour: 0 red, 1 green, 2 yellow, 3 blue.
LudoColor seatColor(int seat) => LudoColor.values[seat.clamp(0, 3)];

int _int(Object? v, [int fallback = 0]) => roomInt(v, fallback);
int? _intOrNull(Object? v) => roomIntOrNull(v);
String? _str(Object? v) => roomStr(v);
Map<String, dynamic> _map(Object? v) => roomMap(v);
List<Map<String, dynamic>> _maps(Object? v) => roomMaps(v);

/// Epoch milliseconds (server clock) → time.
DateTime? _ms(Object? v) => roomMs(v);

/// The room pieces are shared with the other rooms-family games
/// (lib/game/common/online_room/room_models.dart).
typedef LudoSeat = RoomSeat;
typedef LudoTournament = RoomTournament;
typedef LudoRoom = RoomInfo;
typedef LudoRoomSummary = RoomSummary;
typedef LudoPayout = RoomPayout;
typedef LudoWalletUpdate = RoomWalletUpdate;
typedef LudoChatLine = RoomChatLine;
typedef LudoGift = RoomGift;

/// A seat's Ludo colour.
extension LudoSeatColor on RoomSeat {
  LudoColor get color => seatColor(seat);
}

/// This player's Ludo colour in the room.
extension LudoRoomColor on RoomInfo {
  LudoColor get color => seatColor(seat);
}

/// One pawn: `{id, position_type, position_value}` (ludo.md "The board").
@immutable
class LudoPawn {
  const LudoPawn({required this.id, required this.type, required this.value});
  final int id;

  /// `at_base` · `on_board` (shared track 0..51) · `home_stretch` (0..5) · `home`.
  final String type;
  final int value;

  factory LudoPawn.fromJson(Map<String, dynamic> j) =>
      LudoPawn(id: _int(j['id']), type: _str(j['position_type']) ?? 'at_base', value: _int(j['position_value']));

  /// Progress on [LudoLayout.server] for a pawn of seat [seat].
  int progress(int seat) => ludoProgress(seat, type, value);
}

/// Server position → progress on [LudoLayout.server].
int ludoProgress(int seat, String type, int value) {
  final layout = LudoLayout.server;
  return switch (type) {
    'on_board' => (value - LudoRules.startIndex(seatColor(seat))) % 52,
    'home_stretch' => layout.trackSquares + value.clamp(0, layout.stretch - 1),
    'home' => layout.home,
    _ => LudoRules.base,
  };
}

/// A move result's position string (`at_base`, `on_board:N`,
/// `on_board:start`, `home_stretch:N`, `home_stretch`, `home`) → progress.
int ludoProgressOf(int seat, String? pos) {
  if (pos == null || pos == 'at_base') return LudoRules.base;
  final parts = pos.split(':');
  final type = parts.first;
  final arg = parts.length > 1 ? parts[1] : null;
  if (type == 'on_board' && arg == 'start') return 0;
  return ludoProgress(seat, type, int.tryParse(arg ?? '') ?? 0);
}

/// A player in the game state, in turn order.
@immutable
class LudoPlayerState {
  const LudoPlayerState({
    required this.userId,
    required this.seat,
    required this.pawns,
    this.forfeited = false,
    this.place,
    this.score = 0,
    this.team,
    this.magicUsed = const {},
  });

  final String userId;
  final int seat;
  final List<LudoPawn> pawns;
  final bool forfeited;

  /// 1 = winner; null while racing.
  final int? place;

  /// Rush score.
  final int score;

  /// 0 / 1 in a team game.
  final int? team;
  final Map<String, dynamic> magicUsed;

  LudoColor get color => seatColor(seat);
  List<int> get progress => [for (var i = 0; i < 4; i++) i < pawns.length ? pawns[i].progress(seat) : LudoRules.base];
  int get homeCount => pawns.where((p) => p.type == 'home').length;

  factory LudoPlayerState.fromJson(Map<String, dynamic> j) {
    final pawns = [for (final p in _maps(j['pawns'])) LudoPawn.fromJson(p)]..sort((a, b) => a.id.compareTo(b.id));
    return LudoPlayerState(
      userId: '${j['user_id'] ?? ''}',
      seat: _int(j['seat']),
      pawns: pawns,
      forfeited: j['forfeited'] == true,
      place: _intOrNull(j['place']),
      score: _int(j['score']),
      team: _intOrNull(j['team']),
      magicUsed: _map(j['magic_used']),
    );
  }
}

/// The whole game `state` sent with every game frame (ludo.md §4).
@immutable
class LudoState {
  const LudoState({
    required this.matchId,
    required this.status,
    required this.players,
    this.currentTurnUserId,
    this.pendingPawnSelection = false,
    this.lastDiceValue,
    this.turnDeadline,
    this.matchDeadline,
    this.winner,
    this.turnNumber = 0,
    this.diceChoice,
    this.undoUserId,
    this.rules = const {},
    this.playerNames = const {},
  });

  final String matchId;

  /// `waiting_for_players` · `in_progress` · `completed`.
  final String status;
  final List<LudoPlayerState> players;
  final String? currentTurnUserId;
  final bool pendingPawnSelection;
  final int? lastDiceValue;

  /// Server clock; null when no timer runs (e.g. a bot's turn).
  final DateTime? turnDeadline;

  /// Rush only.
  final DateTime? matchDeadline;
  final String? winner;
  final int turnNumber;
  final List<int>? diceChoice;
  final String? undoUserId;
  final Map<String, dynamic> rules;

  /// After a reconnect: `user_id` → `username`.
  final Map<String, String> playerNames;

  bool get completed => status == 'completed';

  LudoPlayerState? player(String userId) => players.where((p) => p.userId == userId).firstOrNull;

  factory LudoState.fromJson(Map<String, dynamic> j) => LudoState(
    matchId: '${j['match_id'] ?? ''}',
    status: _str(j['status']) ?? 'in_progress',
    players: [for (final p in _maps(j['players'])) LudoPlayerState.fromJson(p)],
    currentTurnUserId: _str(j['current_turn_user_id']),
    pendingPawnSelection: j['pending_pawn_selection'] == true,
    lastDiceValue: _intOrNull(j['last_dice_value']),
    turnDeadline: _ms(j['turn_deadline']),
    matchDeadline: _ms(j['match_deadline']),
    winner: _str(j['winner']),
    turnNumber: _int(j['turn_number']),
    diceChoice: j['dice_choice'] is List ? [for (final d in j['dice_choice'] as List) _int(d)] : null,
    undoUserId: _str(j['undo_user_id']),
    rules: _map(j['rules']),
    playerNames: {for (final e in _map(j['player_names']).entries) e.key: '${e.value}'},
  );
}

/// A move (`move_pawn` ack, `auto_move`, `last_action.move_result`).
@immutable
class LudoMoveResult {
  const LudoMoveResult({
    required this.pawnId,
    required this.moveType,
    this.diceValue,
    this.fromPosition,
    this.toPosition,
    this.capturedSeat,
    this.capturedPawnId,
    this.place,
    this.nextTurnUserId,
    this.gameOver = false,
  });

  final int pawnId;

  /// `moved`, `entered`, `captured`, `reached_home`, `won`, `extra_turn:…`, …
  final String moveType;
  final int? diceValue;
  final String? fromPosition;
  final String? toPosition;
  final int? capturedSeat;
  final int? capturedPawnId;
  final int? place;
  final String? nextTurnUserId;
  final bool gameOver;

  bool get captured => capturedSeat != null && capturedPawnId != null;

  static LudoMoveResult? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    if (j['pawn_id'] == null) return null;
    return LudoMoveResult(
      pawnId: _int(j['pawn_id']),
      moveType: _str(j['move_type']) ?? 'moved',
      diceValue: _intOrNull(j['dice_value']),
      fromPosition: _str(j['from_position']),
      toPosition: _str(j['to_position']),
      capturedSeat: _intOrNull(j['captured_player_seat']),
      capturedPawnId: _intOrNull(j['captured_pawn_id']),
      place: _intOrNull(j['place']),
      nextTurnUserId: _str(j['next_turn_user_id']),
      gameOver: j['game_over'] == true,
    );
  }
}

/// A `roll_dice` result.
@immutable
class LudoRollResult {
  const LudoRollResult({
    required this.diceValue,
    this.mustSelectPawn = false,
    this.moveablePawns = const [],
    this.autoMove,
    this.turnForfeited = false,
    this.nextTurnUserId,
    this.gameOver = false,
    this.diceChoice,
  });

  final int diceValue;
  final bool mustSelectPawn;
  final List<int> moveablePawns;

  /// Only one move was possible: the server made it.
  final LudoMoveResult? autoMove;
  final bool turnForfeited;
  final String? nextTurnUserId;
  final bool gameOver;
  final List<int>? diceChoice;

  static LudoRollResult? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    return LudoRollResult(
      diceValue: _int(j['dice_value'], 1),
      mustSelectPawn: j['must_select_pawn'] == true,
      moveablePawns: j['moveable_pawns'] is List ? [for (final p in j['moveable_pawns'] as List) _int(p)] : const [],
      autoMove: LudoMoveResult.fromJson(j['auto_move']),
      turnForfeited: j['turn_forfeited'] == true,
      nextTurnUserId: _str(j['next_turn_user_id']),
      gameOver: j['game_over'] == true,
      diceChoice: j['dice_choice'] is List ? [for (final d in j['dice_choice'] as List) _int(d)] : null,
    );
  }
}

/// `last_action` of a `game.state_update`: what to animate.
@immutable
class LudoLastAction {
  const LudoLastAction({
    required this.actionType,
    this.userId,
    this.autoPlay = false,
    this.diceValue,
    this.moveType,
    this.pawnId,
    this.captured = false,
    this.rollResult,
    this.moveResult,
    this.reason,
  });

  /// `roll_dice`, `move_pawn`, `forfeit`, `pick_die`, `roll_and_move`,
  /// `undo`, `clock_expired`, …
  final String actionType;
  final String? userId;

  /// The turn ran out and the server played it ("Time's up").
  final bool autoPlay;
  final int? diceValue;
  final String? moveType;
  final int? pawnId;
  final bool captured;
  final LudoRollResult? rollResult;
  final LudoMoveResult? moveResult;
  final String? reason;

  static LudoLastAction? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    final roll = LudoRollResult.fromJson(j['roll_result']);
    return LudoLastAction(
      actionType: _str(j['action_type']) ?? '',
      userId: _str(j['user_id']),
      autoPlay: j['auto_play'] == true,
      diceValue: _intOrNull(j['dice_value']) ?? roll?.diceValue,
      moveType: _str(j['move_type']),
      pawnId: _intOrNull(j['pawn_id']),
      captured: j['captured'] == true,
      rollResult: roll,
      moveResult: LudoMoveResult.fromJson(j['move_result']) ?? roll?.autoMove,
      reason: _str(j['reason']),
    );
  }
}
