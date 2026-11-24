/// The room protocol shared by the rooms-family game sockets (Ludo,
/// Snake & Ladder: docs/services/ludo.md, docs/services/snake-and-ladder.md):
/// event names, seats, rooms, open rooms, chat, gifts and payouts. Parsed
/// leniently: unknown fields are ignored, missing ones get safe defaults.
library;

import 'package:flutter/foundation.dart';

import '../../../utils/amount.dart';

/// Socket event names of the room protocol.
abstract final class RoomEvent {
  static const roomList = 'room.list';
  static const roomListResult = 'room.list_result';
  static const matchFind = 'match.find';
  static const matchFound = 'match.found';
  static const matchCancel = 'match.cancel';
  static const matchCancelled = 'match.cancelled';
  static const roomCreate = 'room.create';
  static const roomCreated = 'room.created';
  static const roomJoin = 'room.join';
  static const roomJoined = 'room.joined';
  static const roomLeave = 'room.leave';
  static const roomLeft = 'room.left';
  static const userJoined = 'room.user_joined';
  static const userLeft = 'room.user_left';
  static const ready = 'player.ready';
  static const unready = 'player.unready';
  static const readyUpdate = 'player.ready_update';
  static const gameStarted = 'game.started';
  static const startError = 'game.start_error';
  static const action = 'game.action';
  static const stateUpdate = 'game.state_update';
  static const stateSync = 'game.state_sync';
  static const finalState = 'game.final_state';
  static const playerForfeited = 'game.player_forfeited';
  static const powerupUsed = 'game.powerup_used';
  static const walletUpdate = 'game.wallet_update';
  static const rematch = 'game.rematch';
  static const rematchOffered = 'game.rematch_offered';
  static const cancelled = 'game.cancelled';
  static const chatSend = 'chat.send';
  static const chatMessage = 'chat.message';
  static const chatHistory = 'chat.history';
  static const chatHistoryResult = 'chat.history_result';
  static const giftSend = 'gift.send';
  static const giftReceived = 'gift.received';

  /// Snake & Ladder only: the bet ladder for a private room's stake picker.
  static const betOptions = 'wallet.bet_options';
}

/// The 12 quick-chat lines the servers accept, exactly.
const roomQuickChat = [
  'Good game!',
  'Nice move!',
  'Hurry up!',
  'Well played!',
  'Good luck!',
  'Oops!',
  'Wow!',
  'Thanks!',
  'Sorry!',
  'Ha ha!',
  'Oh no!',
  "Let's go!",
];

int roomInt(Object? v, [int fallback = 0]) => v is num ? v.toInt() : int.tryParse('$v') ?? fallback;
int? roomIntOrNull(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
String? roomStr(Object? v) => v is String && v.isNotEmpty ? v : null;
Map<String, dynamic> roomMap(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
List<Map<String, dynamic>> roomMaps(Object? v) =>
    v is List ? [for (final e in v) if (e is Map) e.cast<String, dynamic>()] : const [];

/// Epoch milliseconds (server clock) → time.
DateTime? roomMs(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

/// A short message for the screen to show once (a toast).
@immutable
class RoomNotice {
  const RoomNotice(this.text, {this.error = false, this.seatUserId});
  final String text;
  final bool error;

  /// Shown on that player's seat (e.g. "Time's up").
  final String? seatUserId;
}

/// A seated player in a room (`room.created`, `room.joined`, `match.found`,
/// `room.user_joined`). Snake & Ladder sends only `user_id`, `username`,
/// `seat` and `ready`; the rest stay empty.
@immutable
class RoomSeat {
  const RoomSeat({
    required this.userId,
    required this.username,
    required this.seat,
    this.ready = false,
    this.isBot = false,
    this.avatarUrl,
    this.balanceTokens,
    this.balanceGold,
  });

  final String userId;
  final String username;
  final int seat;
  final bool ready;
  final bool isBot;
  final String? avatarUrl;

  /// Filled for the joining player only; others are null.
  final int? balanceTokens;
  final int? balanceGold;

  factory RoomSeat.fromJson(Map<String, dynamic> j) => RoomSeat(
    userId: '${j['user_id'] ?? ''}',
    username: roomStr(j['username']) ?? 'Player',
    seat: roomInt(j['seat']),
    ready: j['ready'] == true,
    isBot: j['is_bot'] == true,
    avatarUrl: roomStr(j['avatar_url']),
    balanceTokens: j['balance_tokens'] == null ? null : parseAmount(j['balance_tokens']),
    balanceGold: j['balance_gold'] == null ? null : parseAmount(j['balance_gold']),
  );

  RoomSeat copyWith({bool? ready}) => RoomSeat(
    userId: userId,
    username: username,
    seat: seat,
    ready: ready ?? this.ready,
    isBot: isBot,
    avatarUrl: avatarUrl,
    balanceTokens: balanceTokens,
    balanceGold: balanceGold,
  );
}

/// "Round N, Table T" for a tournament table.
@immutable
class RoomTournament {
  const RoomTournament({required this.tournamentId, required this.round, required this.table});
  final String tournamentId;
  final int round;
  final int table;

  static RoomTournament? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    return RoomTournament(
      tournamentId: '${j['tournament_id'] ?? ''}',
      round: roomInt(j['round'], 1),
      table: roomInt(j['table_number'], 1),
    );
  }
}

/// The room the player sits in (`room.created` / `room.joined` /
/// `match.found`).
@immutable
class RoomInfo {
  const RoomInfo({
    required this.roomId,
    required this.roomCode,
    required this.seat,
    required this.maxPlayers,
    required this.players,
    this.modeCode,
    this.modeName,
    this.variant,
    this.currency,
    this.betAmount,
    this.listed = false,
    this.rules = const {},
    this.tournament,
    this.matchId,
    this.rejoined = false,
    this.quickMatch = false,
    this.raw = const {},
  });

  final String roomId;

  /// 8 characters; share it with friends.
  final String roomCode;

  /// This player's seat.
  final int seat;
  final int maxPlayers;
  final List<RoomSeat> players;
  final String? modeCode;
  final String? modeName;

  /// The board / rule set (`variant`, or Snake & Ladder's `board_layout`).
  final String? variant;

  /// `token` / `gold`; null for a free room.
  final String? currency;
  final int? betAmount;
  final bool listed;
  final Map<String, dynamic> rules;
  final RoomTournament? tournament;

  /// Set when rejoining a running game (`rejoined: true`).
  final String? matchId;
  final bool rejoined;

  /// From `match.find` (a quick-match lobby) rather than a private room.
  final bool quickMatch;

  /// The whole reply, for a game's own fields (e.g. Snake & Ladder's `board`).
  final Map<String, dynamic> raw;

  bool get staked => (betAmount ?? 0) > 0;
  bool get full => players.length >= maxPlayers;

  factory RoomInfo.fromJson(Map<String, dynamic> j, {bool quickMatch = false}) => RoomInfo(
    roomId: '${j['room_id'] ?? ''}',
    roomCode: roomStr(j['room_code']) ?? '',
    seat: roomInt(j['seat']),
    maxPlayers: roomInt(j['max_players'], 2),
    players: [for (final p in roomMaps(j['players'])) RoomSeat.fromJson(p)]..sort((a, b) => a.seat.compareTo(b.seat)),
    modeCode: roomStr(j['mode_code']),
    modeName: roomStr(j['mode_name']),
    variant: roomStr(j['variant']) ?? roomStr(j['board_layout']),
    currency: roomStr(j['currency']),
    betAmount: j['bet_amount'] == null ? null : parseAmount(j['bet_amount']),
    listed: j['listed'] == true,
    rules: roomMap(j['rules']),
    tournament: RoomTournament.fromJson(j['tournament']),
    matchId: roomStr(j['match_id']),
    rejoined: j['rejoined'] == true,
    quickMatch: quickMatch,
    raw: j,
  );

  RoomInfo withPlayers(List<RoomSeat> next) => RoomInfo(
    roomId: roomId,
    roomCode: roomCode,
    seat: seat,
    maxPlayers: maxPlayers,
    players: [...next]..sort((a, b) => a.seat.compareTo(b.seat)),
    modeCode: modeCode,
    modeName: modeName,
    variant: variant,
    currency: currency,
    betAmount: betAmount,
    listed: listed,
    rules: rules,
    tournament: tournament,
    matchId: matchId,
    rejoined: rejoined,
    quickMatch: quickMatch,
    raw: raw,
  );
}

/// An open room in `room.list_result`.
@immutable
class RoomSummary {
  const RoomSummary({
    required this.roomId,
    required this.roomCode,
    required this.players,
    required this.maxPlayers,
    this.variant,
    this.modeCode,
    this.status = 'waiting',
    this.currency,
    this.betAmount,
    this.matchmaking,
  });

  final String roomId;
  final String roomCode;
  final int players;
  final int maxPlayers;
  final String? variant;
  final String? modeCode;
  final String status;
  final String? currency;
  final int? betAmount;

  /// `random` (quick-match lobby) or `private_room`.
  final String? matchmaking;

  bool get inPlay => status == 'in_progress';

  factory RoomSummary.fromJson(Map<String, dynamic> j) => RoomSummary(
    roomId: '${j['room_id'] ?? ''}',
    roomCode: roomStr(j['room_code']) ?? '',
    players: j['players'] is List ? (j['players'] as List).length : roomInt(j['players']),
    maxPlayers: roomInt(j['max_players'], 2),
    variant: roomStr(j['variant']) ?? roomStr(j['board_layout']),
    modeCode: roomStr(j['mode_code']),
    status: roomStr(j['status']) ?? 'waiting',
    currency: roomStr(j['currency']),
    betAmount: j['bet_amount'] == null ? null : parseAmount(j['bet_amount']),
    matchmaking: roomStr(j['matchmaking']),
  );
}

/// One payout in `game.wallet_update`.
@immutable
class RoomPayout {
  const RoomPayout({required this.userId, required this.amount, required this.result, this.place});
  final String userId;
  final int amount;

  /// `win` · `loss` · `forfeit` · `draw`.
  final String result;

  /// Snake & Ladder only.
  final int? place;
}

/// `game.wallet_update`: the pot and payouts of a staked game.
@immutable
class RoomWalletUpdate {
  const RoomWalletUpdate({
    required this.matchId,
    required this.pot,
    required this.rake,
    required this.payouts,
    this.royalStakes = false,
  });
  final String matchId;
  final int pot;
  final int rake;
  final List<RoomPayout> payouts;

  /// The pot is shared by place (Snake & Ladder Royale).
  final bool royalStakes;

  RoomPayout? payoutFor(String userId) => payouts.where((p) => p.userId == userId).firstOrNull;

  factory RoomWalletUpdate.fromJson(Map<String, dynamic> j) => RoomWalletUpdate(
    matchId: '${j['match_id'] ?? ''}',
    pot: parseAmount(j['pot_amount']),
    rake: parseAmount(j['rake_amount']),
    royalStakes: j['royal_stakes'] == true,
    payouts: [
      for (final p in roomMaps(j['payouts']))
        RoomPayout(
          userId: '${p['user_id'] ?? ''}',
          amount: parseAmount(p['amount']),
          result: roomStr(p['result']) ?? '',
          place: roomIntOrNull(p['place']),
        ),
    ],
  );
}

/// A quick-chat line (`chat.message`).
@immutable
class RoomChatLine {
  const RoomChatLine({required this.fromUserId, required this.username, required this.message, this.timestamp, this.team = false});
  final String fromUserId;
  final String username;
  final String message;
  final DateTime? timestamp;

  /// Sent to the partner only (team games).
  final bool team;

  factory RoomChatLine.fromJson(Map<String, dynamic> j) => RoomChatLine(
    fromUserId: '${j['from_user_id'] ?? ''}',
    username: roomStr(j['username']) ?? 'Player',
    message: roomStr(j['message']) ?? '',
    timestamp: roomMs(j['timestamp']),
    team: j['team'] == true,
  );
}

/// `gift.received`, shown on the receiver's seat.
@immutable
class RoomGift {
  const RoomGift({
    required this.giftId,
    required this.senderId,
    required this.senderName,
    required this.receiverId,
    required this.amount,
    required this.currency,
    this.itemType = 'gift',
    this.message,
  });

  final String giftId;
  final String senderId;
  final String senderName;
  final String receiverId;
  final int amount;
  final String currency;
  final String itemType;
  final String? message;

  factory RoomGift.fromJson(Map<String, dynamic> j) => RoomGift(
    giftId: '${j['gift_id'] ?? ''}',
    senderId: '${j['sender_id'] ?? ''}',
    senderName: roomStr(j['sender_name']) ?? 'Player',
    receiverId: '${j['receiver_id'] ?? ''}',
    amount: parseAmount(j['amount']),
    currency: roomStr(j['currency']) ?? 'token',
    itemType: roomStr(j['item_type']) ?? 'gift',
    message: roomStr(j['message']),
  );
}
