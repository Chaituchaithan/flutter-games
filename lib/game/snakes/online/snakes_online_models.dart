/// Typed Snake & Ladder socket payloads (docs/services/snake-and-ladder.md).
/// The room pieces (seats, rooms, chat, gifts, payouts) are the shared room
/// protocol's (lib/game/common/online_room/room_models.dart). Parsed
/// leniently: unknown fields are ignored, missing ones get safe defaults.
library;

import 'package:flutter/foundation.dart';

import '../../common/online_room/room_models.dart';
import '../snakes_engine.dart';

export '../../common/online_room/room_models.dart';

Map<int, int> _pairsToMap(Object? v) {
  final out = <int, int>{};
  if (v is List) {
    for (final p in v) {
      if (p is List && p.length >= 2) out[roomInt(p[0])] = roomInt(p[1]);
    }
  } else if (v is Map) {
    // room.created's `board`: {"17": 7, ...} (string keys).
    for (final e in v.entries) {
      final k = int.tryParse('${e.key}');
      if (k != null) out[k] = roomInt(e.value);
    }
  }
  return out;
}

Set<int> _intSet(Object? v) => v is List ? {for (final x in v) roomInt(x)} : const {};

/// The boards the server offers today, for a preview before `game.started`
/// when the room reply has no `board` (`match.found`, `room.joined`). The
/// game itself is always drawn from the server's state.
abstract final class SnlBoards {
  static const _classicSnakes = {17: 7, 54: 34, 62: 19, 64: 60, 87: 36, 93: 73, 95: 75, 99: 78};
  static const _classicLadders = {4: 14, 9: 31, 20: 38, 28: 84, 40: 59, 51: 67, 63: 81, 71: 91};

  static const quick50 = SnakesLayout(
    size: 50,
    snakes: {25: 5, 34: 12, 42: 23},
    ladders: {3: 16, 9: 31, 18: 37, 29: 44},
  );
  static const classic100 = SnakesLayout(size: 100, snakes: _classicSnakes, ladders: _classicLadders);
  static const venom100 = SnakesLayout(
    size: 100,
    snakes: {..._classicSnakes, 26: 10, 33: 12, 46: 25, 49: 30, 57: 41, 69: 47, 83: 58, 98: 79},
    ladders: _classicLadders,
    venom: {23, 44, 66, 88},
  );

  /// The board of a `board_layout` / `variant`, if known.
  static SnakesLayout? of(String? variant) => switch (variant) {
    'quick_50' => quick50,
    'classic_100' || 'duel' || 'team' => classic100,
    'venom_100' => venom100,
    _ => null,
  };

  /// `room.created`'s `board`: `{size, snakes {head: tail}, ladders {bottom: top}, venom_tiles?, ladder_multipliers?}`.
  static SnakesLayout? fromRoomBoard(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    final size = roomIntOrNull(j['size']) ?? roomIntOrNull(j['board_size']);
    if (size == null || size <= 0) return null;
    return SnakesLayout(
      size: size,
      snakes: _pairsToMap(j['snakes']),
      ladders: _pairsToMap(j['ladders']),
      venom: _intSet(j['venom_tiles']),
      multipliers: _pairsToMap(j['ladder_multipliers']),
    );
  }

  /// The game state's board (`board_size`, `snakes` [[head, tail]], …).
  static SnakesLayout? fromState(Map<String, dynamic> j) {
    final size = roomIntOrNull(j['board_size']);
    if (size == null || size <= 0) return null;
    return SnakesLayout(
      size: size,
      snakes: _pairsToMap(j['snakes']),
      ladders: _pairsToMap(j['ladders']),
      venom: _intSet(j['venom_tiles']),
      multipliers: _pairsToMap(j['ladder_multipliers']),
    );
  }
}

/// A player in the game state, in turn order.
@immutable
class SnlPlayer {
  const SnlPlayer({
    required this.userId,
    required this.seat,
    this.position = 0,
    this.hasStarted = true,
    this.forfeited = false,
    this.activePowerups = const [],
    this.timeouts = 0,
    this.skipTurns = 0,
    this.bestMultiplier = 0,
    this.team,
  });

  final String userId;
  final int seat;

  /// 0 = not on the board yet.
  final int position;
  final bool hasStarted;
  final bool forfeited;

  /// Boosts on now.
  final List<String> activePowerups;

  /// Timed-out turns in a row.
  final int timeouts;

  /// Turns still to sit out after venom.
  final int skipTurns;
  final int bestMultiplier;

  /// 0 / 1 in a team game.
  final int? team;

  factory SnlPlayer.fromJson(Map<String, dynamic> j) => SnlPlayer(
    userId: '${j['user_id'] ?? ''}',
    seat: roomInt(j['seat']),
    position: roomInt(j['position']),
    hasStarted: j['has_started'] != false,
    forfeited: j['forfeited'] == true,
    activePowerups: j['active_powerups'] is List ? [for (final p in j['active_powerups'] as List) '$p'] : const [],
    timeouts: roomInt(j['timeouts']),
    skipTurns: roomInt(j['skip_turns']),
    bestMultiplier: roomInt(j['best_multiplier']),
    team: roomIntOrNull(j['team']),
  );

  SnlPlayer copyWith({List<String>? activePowerups, bool? forfeited}) => SnlPlayer(
    userId: userId,
    seat: seat,
    position: position,
    hasStarted: hasStarted,
    forfeited: forfeited ?? this.forfeited,
    activePowerups: activePowerups ?? this.activePowerups,
    timeouts: timeouts,
    skipTurns: skipTurns,
    bestMultiplier: bestMultiplier,
    team: team,
  );
}

/// The whole game `state` sent with every game frame (snake-and-ladder.md §4).
@immutable
class SnlState {
  const SnlState({
    required this.matchId,
    required this.status,
    required this.players,
    this.board,
    this.currentTurnUserId,
    this.turnNumber = 0,
    this.turnDeadline,
    this.turnTimeMs,
    this.maxTimeouts,
    this.skippedTurns = const [],
    this.winner,
    this.winners = const [],
    this.places = const [],
    this.royalStakes = false,
    this.diceSeedHash,
    this.diceSeed,
    this.rules = const {},
  });

  final String matchId;

  /// `waiting_for_players` · `in_progress` · `completed`.
  final String status;
  final List<SnlPlayer> players;

  /// Null when the frame carried no board (a shortened state).
  final SnakesLayout? board;
  final String? currentTurnUserId;
  final int turnNumber;

  /// `turn_deadline_ms` on the server clock; null when untimed or over.
  final DateTime? turnDeadline;
  final int? turnTimeMs;
  final int? maxTimeouts;

  /// Players the last roll passed over (venom).
  final List<String> skippedTurns;
  final String? winner;
  final List<String> winners;

  /// Once over: 1st place first.
  final List<String> places;
  final bool royalStakes;
  final String? diceSeedHash;
  final String? diceSeed;
  final Map<String, dynamic> rules;

  bool get completed => status == 'completed';

  SnlPlayer? player(String userId) => players.where((p) => p.userId == userId).firstOrNull;

  factory SnlState.fromJson(Map<String, dynamic> j) => SnlState(
    matchId: '${j['match_id'] ?? ''}',
    status: roomStr(j['status']) ?? 'in_progress',
    players: [for (final p in roomMaps(j['players'])) SnlPlayer.fromJson(p)],
    board: SnlBoards.fromState(j),
    currentTurnUserId: roomStr(j['current_turn_user_id']),
    turnNumber: roomInt(j['turn_number']),
    turnDeadline: roomMs(j['turn_deadline_ms']),
    turnTimeMs: roomIntOrNull(j['turn_time_ms']),
    maxTimeouts: roomIntOrNull(j['max_timeouts']),
    skippedTurns: j['skipped_turns'] is List ? [for (final u in j['skipped_turns'] as List) '$u'] : const [],
    winner: roomStr(j['winner']),
    winners: j['winners'] is List ? [for (final u in j['winners'] as List) '$u'] : const [],
    places: j['places'] is List ? [for (final u in j['places'] as List) '$u'] : const [],
    royalStakes: j['royal_stakes'] == true,
    diceSeedHash: roomStr(j['dice_seed_hash']),
    diceSeed: roomStr(j['dice_seed']),
    rules: roomMap(j['rules']),
  );

  /// The same state with [players] replaced (a boost switched on, a seat out).
  SnlState withPlayers(List<SnlPlayer> next, {String? currentTurnUserId, DateTime? turnDeadline, bool clearDeadline = false}) => SnlState(
    matchId: matchId,
    status: status,
    players: next,
    board: board,
    currentTurnUserId: currentTurnUserId ?? this.currentTurnUserId,
    turnNumber: turnNumber,
    turnDeadline: clearDeadline ? null : (turnDeadline ?? this.turnDeadline),
    turnTimeMs: turnTimeMs,
    maxTimeouts: maxTimeouts,
    skippedTurns: skippedTurns,
    winner: winner,
    winners: winners,
    places: places,
    royalStakes: royalStakes,
    diceSeedHash: diceSeedHash,
    diceSeed: diceSeed,
    rules: rules,
  );
}

/// A roll: the `roll_dice` ack's `result`, or a `game.state_update`'s
/// `last_action` (which adds `user_id` and `auto_roll`).
@immutable
class SnlRoll {
  const SnlRoll({
    required this.actionType,
    this.userId,
    this.autoRoll = false,
    this.diceValue,
    this.secondDiceValue,
    this.moveType,
    this.from,
    this.to,
    this.extraTurn = false,
    this.landingKind,
    this.landingSquare,
    this.venom = false,
    this.multiplier,
    this.rerolledFrom,
    this.captured = const [],
    this.carried = const [],
    this.overshot,
    this.snakeCharm,
    this.gameOver = false,
    this.winner,
    this.nextTurnUserId,
    this.activePowerups = const [],
  });

  /// `roll_dice` (also `forfeit` on some servers).
  final String actionType;
  final String? userId;

  /// The turn ran out and the server rolled ("Time's up").
  final bool autoRoll;

  /// The roll (with Double Dice: the sum of both dice).
  final int? diceValue;

  /// Double Dice: the second die (ack only).
  final int? secondDiceValue;

  /// `moved`, `climbed_ladder`, `bit_by_snake`, `extra_turn`, `overshot`,
  /// `lost_turn_consecutive_max`, `won`, `waiting_to_start`.
  final String? moveType;
  final int? from;
  final int? to;
  final bool extraTurn;

  /// `snake` / `ladder`: the snake head or ladder bottom the token hit.
  final String? landingKind;
  final int? landingSquare;

  /// Ended on a venom tile: sits out the next turn.
  final bool venom;
  final int? multiplier;
  final int? rerolledFrom;

  /// Sent back to 0 by this move.
  final List<String> captured;

  /// Partners who climbed the same ladder (team games).
  final List<String> carried;

  /// With `exact_finish`: where the roll would have gone past the finish.
  final int? overshot;

  /// `{code, head, tail}` when Anti-Snake or Snake Charmer acted.
  final Map<String, dynamic>? snakeCharm;
  final bool gameOver;
  final String? winner;
  final String? nextTurnUserId;

  /// The boosts that acted (ack only).
  final List<String> activePowerups;

  bool get isRoll => actionType == 'roll_dice' || diceValue != null;

  static List<String> _ids(Object? v) => v is List ? [for (final x in v) '$x'] : const [];

  static SnlRoll? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    final landing = roomMap(j['landing']);
    return SnlRoll(
      actionType: roomStr(j['action_type']) ?? 'roll_dice',
      userId: roomStr(j['user_id']),
      autoRoll: j['auto_roll'] == true,
      diceValue: roomIntOrNull(j['dice_value']),
      secondDiceValue: roomIntOrNull(j['second_dice_value']),
      moveType: roomStr(j['move_type']),
      from: roomIntOrNull(j['from_position']),
      to: roomIntOrNull(j['to_position']),
      extraTurn: j['extra_turn'] == true,
      landingKind: roomStr(landing['kind']),
      landingSquare: roomIntOrNull(landing['square']),
      venom: j['venom'] == true,
      multiplier: roomIntOrNull(j['multiplier']),
      rerolledFrom: roomIntOrNull(j['rerolled_from']),
      captured: _ids(j['captured']),
      carried: _ids(j['carried']),
      overshot: roomIntOrNull(j['overshot']),
      snakeCharm: j['snake_charm'] is Map ? roomMap(j['snake_charm']) : null,
      gameOver: j['game_over'] == true,
      winner: roomStr(j['winner']),
      nextTurnUserId: roomStr(j['next_turn_user_id']),
      activePowerups: _ids(j['active_powerups']),
    );
  }
}

/// One bet of `wallet.bet_options`.
@immutable
class SnlBet {
  const SnlBet(this.amount, {this.locked = false});
  final int amount;

  /// Not offered at the player's balance (shown disabled).
  final bool locked;
}

/// `wallet.bet_options`'s `offer`: the bets the bet ladder offers at the
/// player's balance, for the private-room stake picker.
@immutable
class SnlBetOffer {
  const SnlBetOffer({required this.currency, required this.bets, this.balance, this.defaultBet, this.maxBet});
  final String currency;
  final List<SnlBet> bets;
  final int? balance;
  final int? defaultBet;
  final int? maxBet;

  List<int> get unlocked => [for (final b in bets) if (!b.locked) b.amount];

  /// Null when no bet ladder is set (any stake the wallet covers is taken).
  static SnlBetOffer? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    return SnlBetOffer(
      currency: roomStr(j['currency']) ?? 'token',
      balance: roomIntOrNull(j['balance']),
      defaultBet: roomIntOrNull(j['default']),
      maxBet: roomIntOrNull(j['max_bet']),
      bets: [for (final b in roomMaps(j['bets'])) SnlBet(roomInt(b['amount']), locked: b['locked'] == true)],
    );
  }
}

/// The boosts' player-facing names (the catalogue's names win when loaded).
String snlBoostName(String code) => switch (code) {
  'shield' => 'Shield',
  'double_dice' => 'Double Dice',
  'extra_turn' => 'Extra Turn',
  'ladder_boost' => 'Ladder Boost',
  'sl_antivenom' => 'Anti-Venom',
  'sl_reroll' => 'Reroll',
  'sl_grease' => 'Grease',
  'sl_anti_snake' => 'Anti-Snake',
  'sl_snake_charmer' => 'Snake Charmer',
  _ => code.replaceAll('_', ' '),
};
