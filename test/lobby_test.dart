// Matchmaking and rooms (docs/services/05-matchmaking-and-rooms.md): parsing
// every sample in the doc, the GameLobby frames sent, the LobbyController's
// moves for the three flows, the error codes, and the app-side 60 s
// "no players found" prompt.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/game_catalogue.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/lobby/game_lobby.dart';
import 'package:snakeladder/services/lobby/live_rooms.dart';
import 'package:snakeladder/services/lobby/lobby_controller.dart';
import 'package:snakeladder/services/lobby/lobby_models.dart';
import 'package:snakeladder/services/socket/socket_client.dart';

const a = '6d7ca0a3-9c83-4fde-aee1-5e1d9290f9d8';
const b = '92ac29f6-61d3-4a2d-aad9-41e62c2b06cc';
const bot = '3fb889f3-b6c9-4768-866e-1f6ba6af8e35';

// ── Samples from the doc (real) ──

const casual4p = {
  'id': 1, 'game_id': 1, 'code': 'casual_4p', 'name': 'Casual 4 Players', 'variant_code': 'classic',
  'player_count': 4, 'min_players': 2, 'is_ranked': false, 'is_active': true, 'turn_timer_seconds': 10,
  'limit_label': 'Standard', 'mode_config': {'rule_options': {}, 'timer': {}},
};
const casual2p = {
  'id': 2, 'code': 'casual_2p', 'name': 'Casual 2 Players', 'player_count': 2, 'min_players': 2, 'is_active': true,
  'mode_config': {},
};
const friendsRoom = {
  'id': 5, 'code': 'friends_room', 'name': 'Play with Friends', 'player_count': 4, 'min_players': 2, 'is_active': true,
  'mode_config': {'host_can_choose': ['turn_seconds', 'safe_squares']},
};

const foundAlone = {
  'bet_amount': 0, 'currency': 'token', 'max_players': 2, 'mode_code': 'casual_2p',
  'players': [{'seat': 0, 'user_id': a, 'username': 'w05doca11951'}],
  'room_code': 'c58a7c7b', 'room_id': 'c58a7c7b-a5ca-42fa-93ec-78ea28b03b81', 'seat': 0,
};
const foundFull = {
  'bet_amount': 0, 'currency': 'token', 'max_players': 2, 'mode_code': 'casual_2p',
  'players': [
    {'seat': 0, 'user_id': a, 'username': 'w05doca11951'},
    {'seat': 2, 'user_id': b, 'username': 'w05docb11951'},
  ],
  'room_code': 'c58a7c7b', 'room_id': 'c58a7c7b-a5ca-42fa-93ec-78ea28b03b81', 'seat': 2,
};
const userJoinedB = {
  'avatar_url': null, 'color': 'yellow', 'is_bot': false, 'room_full': true, 'seat': 2, 'user_id': b, 'username': 'w05docb11951',
};
const botJoined = {
  'avatar_url': null, 'color': 'yellow', 'is_bot': true, 'room_full': true, 'seat': 2, 'user_id': bot, 'username': 'SolarWizard',
};
const roomCreated = {
  'bet_amount': null, 'board_layout': 'standard', 'color': 'red', 'currency': null,
  'listed': true, 'max_players': 2, 'mode_code': 'friends_room', 'mode_name': 'Play with Friends',
  'players': [
    {'avatar_url': null, 'balance_gold': 500, 'balance_tokens': 100, 'color': 'red', 'is_bot': false, 'seat': 0, 'user_id': a, 'username': 'w05doca11951'},
  ],
  'room_code': 'c30321b1', 'room_id': 'c30321b1-a356-4c80-ad6b-d8078ca8f5c7', 'rules': {'...': '...'},
};
const roomJoined = {
  'bet_amount': null, 'board_layout': 'standard', 'color': 'yellow', 'currency': null,
  'max_players': 2, 'mode_code': 'friends_room',
  'players': [
    {'avatar_url': null, 'balance_gold': null, 'balance_tokens': null, 'color': 'red', 'is_bot': false, 'ready': false, 'seat': 0, 'user_id': a, 'username': 'w05doca11951'},
    {'avatar_url': null, 'balance_gold': 500, 'balance_tokens': 100, 'color': 'yellow', 'is_bot': false, 'ready': false, 'seat': 2, 'user_id': b, 'username': 'w05docb11951'},
  ],
  'room_code': 'c30321b1', 'room_id': 'c30321b1-a356-4c80-ad6b-d8078ca8f5c7', 'seat': 2, 'tournament': null, 'variant': 'classic',
};
const listResult = {
  'rooms': [
    {'bet_amount': 0, 'created_at': 1795512122054, 'currency': 'token', 'game_type': 'ludo', 'matchmaking': 'random',
     'max_players': 2, 'mode_code': 'casual_2p', 'players': 1, 'room_code': '4408f0e2',
     'room_id': '4408f0e2-bb93-4aed-83f0-1294b924e07c', 'status': 'waiting', 'variant': 'classic'},
    {'bet_amount': null, 'currency': null, 'matchmaking': 'private_room', 'max_players': 4, 'mode_code': 'friends_room',
     'players': 2, 'room_code': 'aaaa1111', 'room_id': 'aaaa1111-0000', 'status': 'waiting'},
    {'bet_amount': '500', 'currency': 'gold', 'matchmaking': 'random', 'max_players': 2, 'mode_code': 'casual_2p',
     'players': 1, 'room_code': 'bbbb2222', 'room_id': 'bbbb2222-0000', 'status': 'waiting'},
  ],
  'total': 3,
};
const liveRoomJson = {
  'id': 'c3ac2140-6187-476b-8de3-5b240ef39e5c', 'name': 'Low Stakes 75-Ball', 'variant': '75ball',
  'currency': 'token', 'is_active': true, 'sort_order': 1,
  'ticket_price': 10, 'min_tickets': 1, 'max_tickets': 4,
  'buying_duration_ms': 20000, 'countdown_duration_ms': 5000, 'results_duration_ms': 3000,
  'call_interval_ms': 1000, 'min_players': 2, 'max_players': 500,
  'rake_pct': 10, 'guaranteed_pool': 0,
  'prize_config': {'prizes': [
    {'code': 'line', 'display_name': 'Line', 'max_winners': 1, 'share_pct': 20},
    {'code': 'four_corners', 'display_name': 'Four Corners', 'max_winners': 1, 'share_pct': 15},
    {'code': 'x_pattern', 'display_name': 'X Pattern', 'max_winners': 1, 'share_pct': 25},
    {'code': 'full_house', 'display_name': 'Full House', 'max_winners': 1, 'share_pct': 40},
  ]},
  'created_at': '2026-11-14T08:35:16.461863Z', 'updated_at': '2026-11-14T08:35:16.461863Z',
};

GameMode mode(Map<String, dynamic> j) => GameMode.fromJson(j);
PlaySelection sel(Map<String, dynamic> j, {int stake = 0, String currency = 'token', Map<String, Object?> picks = const {}}) =>
    PlaySelection(
      gameCode: 'ludo',
      modeCode: '${j['code']}',
      currency: stake > 0 ? currency : null,
      betAmount: stake,
      hostPicks: {for (final e in picks.entries) if (mode(j).hostCanChoose.contains(e.key)) e.key: e.value},
    );

/// A scripted game server.
class Server {
  Server({bool autoReady = true, Duration searchTimeout = const Duration(seconds: 60)}) {
    lobby = SocketGameLobby(gameCode: 'ludo', request: _request, messages: pushes.stream);
    c = LobbyController(
      lobby: lobby,
      myUserId: a,
      searchTimeout: searchTimeout,
      retryDelay: Duration.zero,
      autoReady: autoReady,
    );
  }

  final pushes = StreamController<SocketMessage>.broadcast();
  late final SocketGameLobby lobby;
  late final LobbyController c;
  final sent = <(String, Map<String, dynamic>)>[];

  /// event → reply data, a SocketError, or a list of them (one per call).
  final replies = <String, Object>{};

  Future<SocketMessage> _request(String event, Map<String, dynamic> data) async {
    sent.add((event, data));
    var r = replies[event];
    if (r is List) r = r.isEmpty ? null : r.removeAt(0);
    if (r is SocketError) throw r;
    return SocketMessage(event: event, data: (r as Map?)?.cast<String, dynamic>() ?? const {});
  }

  Future<void> push(String event, [Map<String, dynamic> data = const {}]) async {
    pushes.add(SocketMessage(event: event, data: data));
    await pump();
  }

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  List<String> get events => [for (final s in sent) s.$1];
}

void main() {
  group('parsing the doc samples', () {
    test('modes: quick match vs with friends (host_can_choose)', () {
      final picker = ModePicker([for (final j in [casual4p, friendsRoom, casual2p]) GameMode.fromJson(j)]);
      expect([for (final m in picker.quickMatch) m.code], ['casual_4p', 'casual_2p']);
      expect([for (final m in picker.withFriends) m.code], ['friends_room']);
      final m = picker.byCode('casual_4p')!;
      expect(m.playerCount, 4);
      expect(m.minPlayers, 2);
      expect(m.variantCode, 'classic');
      expect(seatChoices(picker.byCode('friends_room')!), [2, 3, 4]);
      expect(picker.nameOf('casual_4p'), 'Casual 4 Players');
      expect(picker.nameOf('mystery'), 'mystery');
    });

    test('match.found alone and full', () {
      final alone = RoomSeat.fromJson(foundAlone, quickMatch: true);
      expect(alone.roomId, 'c58a7c7b-a5ca-42fa-93ec-78ea28b03b81');
      expect(alone.roomCode, 'c58a7c7b');
      expect(alone.isFull, isFalse);
      expect(alone.isFree, isTrue);
      expect(alone.currency, 'token');
      final full = RoomSeat.fromJson(foundFull, quickMatch: true);
      expect(full.isFull, isTrue);
      expect(full.seat, 2); // seats are not packed
      expect([for (final p in full.players) p.seat], [0, 2]);
    });

    test('room.created / room.joined (free private room: null stake)', () {
      final c = RoomSeat.fromJson(roomCreated);
      expect(c.displayCode, 'C30321B1');
      expect(c.listed, isTrue);
      expect(c.currency, isNull);
      expect(c.stake, isNull);
      expect(c.isFree, isTrue);
      expect(c.modeName, 'Play with Friends');
      expect(c.players.single.color, 'red');
      final j = RoomSeat.fromJson(roomJoined);
      expect(j.seat, 2);
      expect(j.variant, 'classic');
      expect(j.players.every((p) => !p.ready), isTrue);
    });

    test('room.user_joined (human and bot)', () {
      final human = SeatPlayer.fromJson(userJoinedB);
      expect(human.isBot, isFalse);
      expect(human.seat, 2);
      final b0 = SeatPlayer.fromJson(botJoined);
      expect(b0.isBot, isTrue);
      expect(b0.username, 'SolarWizard');
    });

    test('room.list_result rows (string money too)', () {
      final rooms = OpenRoom.listFromJson(listResult);
      expect(rooms, hasLength(3));
      expect(rooms[0].isFree, isTrue);
      expect(rooms[0].isPrivate, isFalse);
      expect(rooms[0].players, 1);
      expect(rooms[0].createdAt, DateTime.fromMillisecondsSinceEpoch(1795512122054));
      expect(rooms[1].isPrivate, isTrue);
      expect(rooms[1].stake, isNull);
      expect(rooms[2].stake, 500);
      expect(OpenRoom.listFromJson(const {'rooms': [], 'total': 0}), isEmpty);
    });

    test('GET /live-rooms row', () {
      final r = LiveRoom.fromJson(liveRoomJson);
      expect(r.id, 'c3ac2140-6187-476b-8de3-5b240ef39e5c');
      expect(r.variantLabel, '75-ball');
      expect(r.priceLabel, '10 tokens a card');
      expect(r.buyingDuration, const Duration(seconds: 20));
      expect(r.maxPlayers, 500);
      expect([for (final p in r.prizes) p.sharePct], [20, 15, 25, 40]);
    });

    test('room codes: any case, 8 characters', () {
      expect(normalizeRoomCode(' C30321B1 '), 'c30321b1');
      expect(isValidRoomCode('C30321B1'), isTrue);
      expect(isValidRoomCode('C30321B'), isFalse);
      expect(isValidRoomCode('C30321B!'), isFalse);
    });
  });

  group('errors', () {
    String text(String code, [String event = 'room.join', String msg = 'dev text']) =>
        LobbyFailure.from(SocketError(code, msg), event: event).text;

    test('every code in the doc maps to a message', () {
      expect(text('invalid_mode', 'match.find'), "This mode isn’t available right now.");
      expect(text('insufficient_funds', 'match.find'), 'Not enough tokens/gold for this table.');
      expect(text('not_found'), 'No room with that code.');
      expect(text('room_full'), 'That room is full.');
      expect(text('game_in_progress'), 'That game has already started.');
      expect(text('invalid_state', 'match.cancel'), 'This is a private room. Leave the room instead.');
      expect(text('invalid_state', 'match.find'), 'You can’t do that right now.');
      expect(text('kill_switch_engaged', 'match.find', 'Back at 6 pm'), 'Back at 6 pm');
      for (final c in ['busy', 'internal_error', 'invalid_request', 'invalid_settings', 'weird']) {
        expect(text(c), 'Something went wrong. Try again.');
      }
      for (final c in ['already_in_room', 'not_your_table']) {
        expect(text(c), isNotEmpty);
      }
      // Developer text is never shown.
      expect(text('not_found', 'room.join', "no room found for code 'zzzzzzzz'"), isNot(contains('zzzz')));
      expect(LobbyFailure.from(TimeoutException('x')).error, LobbyError.network);
    });
  });

  group('GameLobby frames', () {
    test('match.find always sends player_count = the mode\'s', () async {
      final s = Server();
      s.replies['match.find'] = foundAlone;
      await s.lobby.quickMatch(mode(casual4p), sel(casual4p));
      expect(s.sent.single.$1, 'match.find');
      expect(s.sent.single.$2, {'mode_code': 'casual_4p', 'player_count': 4});
      await s.lobby.quickMatch(mode(casual2p), sel(casual2p, stake: 50));
      expect(s.sent.last.$2, {'mode_code': 'casual_2p', 'currency': 'token', 'bet_amount': 50, 'player_count': 2});
    });

    test('room.create sends only host options the mode offers; room.join lower-cases', () async {
      final s = Server();
      s.replies['room.create'] = roomCreated;
      s.replies['room.join'] = roomJoined;
      await s.lobby.createRoom(
        mode(friendsRoom),
        sel(friendsRoom, picks: {'safe_squares': false, 'made_up': true}),
        const RoomOptions(maxPlayers: 2, listed: true),
      );
      expect(s.sent.last.$2, {'mode_code': 'friends_room', 'max_players': 2, 'listed': true, 'safe_squares': false});
      await s.lobby.createRoom(mode(friendsRoom), sel(friendsRoom, stake: 100, currency: 'gold'), const RoomOptions());
      expect(s.sent.last.$2, {'mode_code': 'friends_room', 'currency': 'gold', 'bet_amount': 100, 'max_players': 4});
      await s.lobby.joinByCode('C30321B1');
      expect(s.sent.last.$1, 'room.join');
      expect(s.sent.last.$2, {'room_code': 'c30321b1'});
    });

    test('room.list with a variant', () async {
      final s = Server();
      s.replies['room.list'] = listResult;
      final rooms = await s.lobby.listOpenRooms(variant: 'classic');
      expect(s.sent.single.$1, 'room.list');
      expect(s.sent.single.$2, {'variant': 'classic'});
      expect(rooms, hasLength(3));
    });
  });

  group('Flow A: quick match', () {
    test('alone → searching; a bot joins → waiting room, ready sent; game.started → inGame', () async {
      final s = Server();
      s.replies['match.find'] = foundAlone;
      expect(await s.c.quickMatch(mode(casual2p), sel(casual2p)), isTrue);
      expect(s.c.phase, LobbyPhase.searching);
      expect(s.c.canCancel, isTrue);
      expect(s.c.seat!.roomId, 'c58a7c7b-a5ca-42fa-93ec-78ea28b03b81');

      await s.push('room.user_joined', botJoined);
      expect(s.c.phase, LobbyPhase.waitingRoom);
      expect(s.c.seat!.players.last.isBot, isTrue);
      await s.pump();
      expect(s.events, ['match.find', 'player.ready']);

      await s.push('player.ready_update', {'ready': true, 'user_id': bot});
      await s.push('player.ready_update', {'ready': true, 'user_id': a});
      expect(s.c.iAmReady, isTrue);
      await s.push('game.started', {'state': {'match_id': 'm'}});
      expect(s.c.phase, LobbyPhase.inGame);
      expect(s.c.canCancel, isFalse);
      expect(s.c.leavingForfeits, isTrue);
      expect(s.c.gameData!['state'], {'match_id': 'm'});

      await s.push('game.over', {'winner': a});
      expect(s.c.phase, LobbyPhase.result);
      // After a game: room.leave before searching again.
      await s.c.backToLobby();
      expect(s.events.last, 'room.leave');
      expect(s.c.phase, LobbyPhase.idle);
      expect(s.c.seat, isNull);
    });

    test('an open lobby already matches: seated full at once', () async {
      final s = Server(autoReady: false);
      s.replies['match.find'] = foundFull;
      await s.c.quickMatch(mode(casual2p), sel(casual2p));
      expect(s.c.phase, LobbyPhase.waitingRoom);
      expect(s.events, ['match.find']); // no auto ready
      await s.c.setReady(true);
      expect(s.events.last, 'player.ready');
    });

    test('cancel while searching', () async {
      final s = Server();
      s.replies['match.find'] = foundAlone;
      await s.c.quickMatch(mode(casual2p), sel(casual2p));
      await s.c.cancelSearch();
      expect(s.events.last, 'match.cancel');
      expect(s.c.phase, LobbyPhase.idle);
      expect(s.c.seat, isNull);
    });

    test('no opponent found: the prompt after the search timeout; Keep waiting, then Cancel', () async {
      final s = Server(searchTimeout: const Duration(milliseconds: 40));
      s.replies['match.find'] = foundAlone;
      await s.c.quickMatch(mode(casual2p), sel(casual2p));
      expect(s.c.noPlayersFound, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(s.c.noPlayersFound, isTrue);
      s.c.keepWaiting();
      expect(s.c.noPlayersFound, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(s.c.noPlayersFound, isTrue);
      await s.c.cancelSearch();
      expect(s.events.last, 'match.cancel');
      expect(s.c.phase, LobbyPhase.idle);
    });

    test('someone joining stops the clock', () async {
      final s = Server(searchTimeout: const Duration(milliseconds: 40));
      s.replies['match.find'] = foundAlone;
      await s.c.quickMatch(mode(casual2p), sel(casual2p));
      await s.push('room.user_joined', userJoinedB);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(s.c.noPlayersFound, isFalse);
      expect(s.c.phase, LobbyPhase.waitingRoom);
    });

    test('insufficient funds → idle with the message', () async {
      final s = Server();
      s.replies['match.find'] = const SocketError('insufficient_funds', 'insufficient balance for a stake of 99999999 token');
      expect(await s.c.quickMatch(mode(casual2p), sel(casual2p, stake: 99999999)), isFalse);
      expect(s.c.phase, LobbyPhase.idle);
      expect(s.c.failure!.error, LobbyError.insufficientFunds);
    });

    test('invalid_mode and invalid_state (already seated)', () async {
      final s = Server();
      s.replies['match.find'] = const SocketError('invalid_mode', 'validation error: unknown ludo mode "nope_mode"');
      await s.c.quickMatch(mode(casual2p), sel(casual2p));
      expect(s.c.failure!.text, "This mode isn’t available right now.");
      s.replies['match.find'] = const SocketError('invalid_state', "event 'match.find' not allowed in InRoom state");
      await s.c.quickMatch(mode(casual2p), sel(casual2p));
      expect(s.c.failure!.error, LobbyError.invalidState);
      expect(s.c.phase, LobbyPhase.idle);
    });

    test('busy is retried once, then shown', () async {
      final s = Server();
      s.replies['match.find'] = [const SocketError('busy', ''), foundAlone];
      expect(await s.c.quickMatch(mode(casual2p), sel(casual2p)), isTrue);
      expect(s.events, ['match.find', 'match.find']);

      final t = Server();
      t.replies['match.find'] = [const SocketError('internal_error', ''), const SocketError('internal_error', '')];
      expect(await t.c.quickMatch(mode(casual2p), sel(casual2p)), isFalse);
      expect(t.events, ['match.find', 'match.find']);
      expect(t.c.failure!.text, 'Something went wrong. Try again.');
    });

    test('kill switch disables play with the operator\'s message', () async {
      final s = Server();
      s.replies['match.find'] = const SocketError('kill_switch_engaged', 'Maintenance until 18:00');
      await s.c.quickMatch(mode(casual2p), sel(casual2p));
      expect(s.c.playEnabled, isFalse);
      expect(s.c.canStart, isFalse);
      expect(s.c.killSwitchMessage, 'Maintenance until 18:00');
    });

    test('match.cancel after the game started: Cancel no longer applies', () async {
      final s = Server();
      s.replies['match.find'] = foundAlone;
      await s.c.quickMatch(mode(casual2p), sel(casual2p));
      s.replies['match.cancel'] = const SocketError('invalid_state', "event 'match.cancel' not allowed in InGame state");
      final cancel = s.c.cancelSearch();
      await s.push('game.started', const {'state': {}});
      await cancel;
      expect(s.c.phase, LobbyPhase.inGame);
    });
  });

  group('Flow B: private room', () {
    test('create → share code → friend joins → both ready → start (no bot)', () async {
      final s = Server();
      s.replies['room.create'] = roomCreated;
      expect(await s.c.createRoom(mode(friendsRoom), sel(friendsRoom), const RoomOptions(maxPlayers: 2, listed: true)), isTrue);
      expect(s.c.phase, LobbyPhase.waitingRoom);
      expect(s.c.canCancel, isFalse);
      expect(s.c.seat!.displayCode, 'C30321B1');
      await s.push('room.user_joined', {...userJoinedB});
      expect(s.c.seat!.isFull, isTrue);
      await s.pump();
      expect(s.events, ['room.create']); // a private room: the player taps Ready
      await s.c.setReady(true);
      await s.push('player.ready_update', {'ready': true, 'user_id': a});
      await s.push('player.ready_update', {'ready': true, 'user_id': b});
      expect(s.c.seat!.players.every((p) => p.ready), isTrue);
      await s.push('game.started', const {'state': {}});
      expect(s.c.phase, LobbyPhase.inGame);
    });

    test('join with a wrong code → "No room with that code."', () async {
      final s = Server();
      s.replies['room.join'] = const SocketError('not_found', "no room found for code 'zzzzzzzz'");
      expect(await s.c.joinByCode('ZZZZZZZZ'), isFalse);
      expect(s.c.failure!.text, 'No room with that code.');
      expect(s.c.phase, LobbyPhase.idle);
    });

    test('leave a waiting room; a friend leaving frees their seat', () async {
      final s = Server();
      s.replies['room.join'] = roomJoined;
      await s.c.joinByCode('c30321b1');
      expect(s.c.seat!.players, hasLength(2));
      await s.push('room.user_left', {'user_id': a == s.c.myUserId ? b : a, 'reason': 'left'});
      expect(s.c.seat!.players, hasLength(1));
      await s.c.leave();
      expect(s.events.last, 'room.leave');
      expect(s.c.phase, LobbyPhase.idle);
    });

    test('match.cancel in a private room → room.leave instead', () async {
      final s = Server();
      // A friends mode seated via match.find would search; force the
      // server's private-room refusal on cancel.
      s.replies['match.find'] = foundAlone;
      await s.c.quickMatch(mode(casual2p), sel(casual2p));
      s.replies['match.cancel'] = const SocketError('invalid_state', 'not searching: this is a private room, use room.leave');
      await s.c.cancelSearch();
      expect(s.events, ['match.find', 'match.cancel', 'room.leave']);
      expect(s.c.phase, LobbyPhase.idle);
    });

    test('game.start_error clears ready flags and tells the player', () async {
      final s = Server();
      s.replies['room.join'] = roomJoined;
      await s.c.joinByCode('c30321b1');
      await s.push('player.ready_update', {'ready': true, 'user_id': a});
      await s.push('game.start_error', {'code': 'insufficient_funds', 'message': 'x'});
      expect(s.c.seat!.players.every((p) => !p.ready), isTrue);
      expect(s.c.failure!.error, LobbyError.insufficientFunds);
      expect(s.c.phase, LobbyPhase.waitingRoom);
    });
  });

  group('Flow C: open tables', () {
    test('list, throttle to once per 10 s, hide unaffordable rows', () async {
      var now = DateTime(2026, 11, 24, 12);
      final pushes = StreamController<SocketMessage>.broadcast();
      var calls = 0;
      final lobby = SocketGameLobby(
        gameCode: 'ludo',
        request: (e, d) async {
          calls++;
          return SocketMessage(event: 'room.list_result', data: listResult);
        },
        messages: pushes.stream,
      );
      final c = LobbyController(lobby: lobby, myUserId: a, clock: () => now);
      await c.refreshOpenRooms();
      expect(calls, 1);
      expect(c.openRooms, hasLength(3));
      now = now.add(const Duration(seconds: 5));
      await c.refreshOpenRooms();
      expect(calls, 1); // too soon
      await c.refreshOpenRooms(force: true);
      expect(calls, 2);
      now = now.add(const Duration(seconds: 11));
      await c.refreshOpenRooms();
      expect(calls, 3);
      // Gold 500 is more than the wallet has: hidden. Free rows always show.
      final shown = c.visibleRooms((cur, amount) => cur == 'gold' ? amount <= 100 : true);
      expect([for (final r in shown) r.roomCode], ['4408f0e2', 'aaaa1111']);
    });

    test('a room that filled meanwhile: "That room is full" and the list refreshes', () async {
      final s = Server();
      s.replies['room.list'] = listResult;
      s.replies['room.join'] = const SocketError('room_full', 'full');
      await s.c.refreshOpenRooms();
      expect(await s.c.joinByCode('4408f0e2'), isFalse);
      await s.pump();
      expect(s.c.failure!.text, 'That room is full.');
      expect(s.events, ['room.list', 'room.join', 'room.list']);
    });

    test('room.list only from the lobby state', () async {
      final s = Server();
      s.replies['room.join'] = roomJoined;
      await s.c.joinByCode('c30321b1');
      await s.c.refreshOpenRooms(force: true);
      expect(s.events, ['room.join']);
    });
  });

  group('app hooks (catalogue events, wallet)', () {
    test('invalid_mode / kill switch reach onFailure; a staked game end re-reads the wallet', () async {
      final pushes = StreamController<SocketMessage>.broadcast();
      final failures = <LobbyError>[];
      var walletReads = 0;
      final replies = <Object>[
        const SocketError('invalid_mode', 'x'),
        const SocketError('kill_switch_engaged', 'Paused'),
        foundFull,
      ];
      final c = LobbyController(
        lobby: SocketGameLobby(
          gameCode: 'ludo',
          request: (e, d) async {
            if (e != 'match.find') return SocketMessage(event: e, data: const {});
            final r = replies.removeAt(0);
            if (r is SocketError) throw r;
            return SocketMessage(event: e, data: (r as Map).cast<String, dynamic>());
          },
          messages: pushes.stream,
        ),
        myUserId: a,
        onFailure: (f) => failures.add(f.error),
        onStakedGameEnded: () => walletReads++,
      );
      await c.quickMatch(mode(casual2p), sel(casual2p));
      await c.quickMatch(mode(casual2p), sel(casual2p));
      expect(failures, [LobbyError.invalidMode, LobbyError.killSwitch]);
      c.clearKillSwitch();
      await c.quickMatch(mode(casual2p), sel(casual2p, stake: 100));
      pushes.add(const SocketMessage(event: 'game.started', data: {'state': {}}));
      pushes.add(const SocketMessage(event: 'game.over', data: {}));
      await Future<void>.delayed(Duration.zero);
      expect(c.phase, LobbyPhase.result);
      expect(walletReads, 1);
    });
  });

  group('coming back', () {
    test('game.state_sync after a reconnect → straight to the board', () async {
      final s = Server();
      await s.push('game.state_sync', const {'state': {'match_id': 'm'}});
      expect(s.c.phase, LobbyPhase.inGame);
      await s.push('game.final_state', const {'state': {'match_id': 'm'}});
      expect(s.c.phase, LobbyPhase.result);
      expect(s.c.resumedFinished, isTrue);
    });
  });

  group('GET /live-rooms', () {
    test('sends is_active=true and parses; 404 surfaces as an error', () async {
      final api = ApiClient(dio: Dio(BaseOptions(baseUrl: 'http://x/api/v1/'))..httpClientAdapter = _Adapter());
      final rooms = await LiveRoomsApi(api).list(variant: '75ball');
      expect(_Adapter.lastUri!.path, '/api/v1/live-rooms');
      expect(_Adapter.lastUri!.queryParameters, {'is_active': 'true', 'variant': '75ball'});
      expect(rooms.single.name, 'Low Stakes 75-Ball');
      await expectLater(LiveRoomsApi(api).get('00000000-0000-4000-8000-000000000000'), throwsA(anything));
    });
  });
}

class _Adapter implements HttpClientAdapter {
  static Uri? lastUri;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    lastUri = options.uri;
    if (options.uri.path.endsWith('/live-rooms')) {
      return ResponseBody.fromString(
        '[${_json(liveRoomJson)}]',
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    return ResponseBody.fromString(
      '{"error": "NOT_FOUND", "message": "not found: live room 00000000-0000-4000-8000-000000000000"}',
      404,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

String _json(Object o) => jsonEncode(o);
