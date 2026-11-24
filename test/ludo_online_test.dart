// Online Ludo (docs/services/ludo.md): parsing the doc's frames, the server
// board layout, and the controller through lobby → room → game → result,
// plus reconnects ending in game.state_sync / game.final_state.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/ludo/ludo_engine.dart';
import 'package:snakeladder/game/ludo/online/ludo_catalogue.dart';
import 'package:snakeladder/game/ludo/online/ludo_controller.dart';
import 'package:snakeladder/game/ludo/online/ludo_models.dart';
import 'package:snakeladder/services/socket/socket_client.dart';

const a = 'a397bea2-550b-4702-bfe3-5a336b68831b';
const b = 'a1164ecb-e4ff-4db2-8125-b29b4691146c';

Map<String, dynamic> pawn(int id, String type, [int value = 0]) => {'id': id, 'position_type': type, 'position_value': value};

Map<String, dynamic> stateJson({
  String turn = a,
  bool pending = false,
  int? dice,
  List<Map<String, dynamic>>? aPawns,
  List<Map<String, dynamic>>? bPawns,
  String status = 'in_progress',
  String? winner,
  int? aPlace,
  int? bPlace,
  bool bForfeited = false,
  int? deadline,
}) => {
  'match_id': 'm1',
  'status': status,
  'track_size': 52,
  'home_stretch_size': 6,
  'current_turn_user_id': turn,
  'turn_number': 0,
  'turn_deadline': deadline,
  'match_deadline': null,
  'pending_pawn_selection': pending,
  'last_dice_value': dice,
  'winner': winner,
  'players': [
    {'user_id': a, 'seat': 0, 'team': null, 'score': 0, 'place': aPlace, 'forfeited': false, 'pawns': aPawns ?? [for (var i = 0; i < 4; i++) pawn(i, 'at_base')]},
    {'user_id': b, 'seat': 2, 'team': null, 'score': 0, 'place': bPlace, 'forfeited': bForfeited, 'pawns': bPawns ?? [for (var i = 0; i < 4; i++) pawn(i, 'at_base')]},
  ],
  'rules': {'safe_squares': true},
};

// The real room.created reply from the doc.
const roomCreated = {
  'room_id': '1865dd5d-a808-430f-8bf0-a070fe833b1b',
  'room_code': '1865dd5d',
  'seat': 0,
  'color': 'red',
  'max_players': 2,
  'mode_code': 'friends_room',
  'mode_name': 'Play with Friends',
  'variant': 'classic',
  'listed': false,
  'currency': null,
  'bet_amount': null,
  'rules': {'rematch': true, 'safe_squares': true},
  'players': [
    {'user_id': a, 'username': 'fdoc7419', 'seat': 0, 'color': 'red', 'balance_tokens': 100, 'balance_gold': 500, 'avatar_url': null, 'is_bot': false},
  ],
};

/// The controller against a scripted server.
class Harness {
  Harness({void Function()? onWalletChanged, void Function(String, String)? onModeError}) {
    c = LudoController(
      request: _request,
      events: events.stream,
      myUserId: a,
      onWalletChanged: onWalletChanged,
      onModeError: onModeError,
      resyncWait: const Duration(milliseconds: 20),
    );
  }

  final events = StreamController<SocketMessage>.broadcast();
  late final LudoController c;
  final sent = <(String, Map<String, dynamic>)>[];

  /// event → reply (data), or a SocketError to throw.
  final replies = <String, Object Function(Map<String, dynamic>)>{};

  Future<SocketMessage> _request(String event, Map<String, dynamic> data) async {
    sent.add((event, data));
    final r = replies[event];
    if (r == null) return SocketMessage(event: '$event.ok', data: const {});
    final out = r(data);
    if (out is SocketError) throw out;
    return SocketMessage(id: 'x', event: event, data: out as Map<String, dynamic>);
  }

  Future<void> push(String event, Map<String, dynamic> data) async {
    events.add(SocketMessage(event: event, data: data));
    await Future<void>.delayed(Duration.zero);
  }
}

void expectSent((String, Map<String, dynamic>) sent, String event, Map<String, dynamic> data) {
  expect(sent.$1, event);
  expect(sent.$2, data);
}

void main() {
  group('frames', () {
    test('room.created / room.joined parse (real frames)', () {
      final r = LudoRoom.fromJson(roomCreated);
      expect((r.roomCode, r.seat, r.maxPlayers, r.modeCode, r.staked, r.color), ('1865dd5d', 0, 2, 'friends_room', false, LudoColor.red));
      expect(r.players.single.username, 'fdoc7419');
      expect(r.players.single.balanceTokens, 100);
      final joined = LudoRoom.fromJson({
        'room_id': 'r', 'room_code': '1865dd5d', 'seat': 2, 'max_players': 2, 'rejoined': true, 'match_id': 'm1',
        'players': [
          {'user_id': a, 'username': 'fdoc7419', 'seat': 0, 'ready': false, 'balance_tokens': null},
          {'user_id': b, 'username': 'gfdoc7419', 'seat': 2, 'ready': true, 'balance_tokens': '0'},
        ],
        'tournament': {'tournament_id': 't1', 'round': 2, 'table_number': 5},
      });
      expect(joined.color, LudoColor.yellow);
      expect(joined.players.first.balanceTokens, isNull);
      expect(joined.players.last.ready, isTrue);
      expect((joined.rejoined, joined.matchId, joined.tournament!.round, joined.tournament!.table), (true, 'm1', 2, 5));
    });

    test('game state, roll ack, move result and last_action parse', () {
      final st = LudoState.fromJson({...stateJson(deadline: 1795507748111), 'player_names': {b: 'gfdoc7419'}});
      expect((st.currentTurnUserId, st.players.length, st.turnDeadline!.millisecondsSinceEpoch, st.playerNames[b]), (a, 2, 1795507748111, 'gfdoc7419'));
      final roll = LudoRollResult.fromJson({
        'dice_value': 5, 'must_select_pawn': false, 'moveable_pawns': [], 'auto_move': null,
        'turn_forfeited': false, 'next_turn_user_id': b, 'game_over': false, 'turn_deadline': 1795507725596,
      })!;
      expect((roll.diceValue, roll.mustSelectPawn, roll.nextTurnUserId), (5, false, b));
      final move = LudoMoveResult.fromJson({
        'pawn_id': 0, 'dice_value': 6, 'move_type': 'entered', 'from_position': 'at_base', 'to_position': 'on_board:start',
        'captured_player_seat': null, 'captured_pawn_id': null, 'next_turn_user_id': a, 'game_over': false,
      })!;
      expect((move.moveType, move.captured, ludoProgressOf(0, move.fromPosition), ludoProgressOf(0, move.toPosition)),
          ('entered', false, LudoRules.base, 0));
      final last = LudoLastAction.fromJson({
        'action_type': 'roll_dice', 'user_id': a, 'auto_play': true, 'dice_value': 5, 'move_type': 'no_move',
        'roll_result': {'dice_value': 5, 'must_select_pawn': false, 'moveable_pawns': []}, 'move_result': null,
      })!;
      expect((last.autoPlay, last.diceValue, last.moveType, last.moveResult), (true, 5, 'no_move', null));
    });

    test('wallet update, chat and gifts parse; amounts may be strings', () {
      final w = LudoWalletUpdate.fromJson({
        'match_id': 'c0a8', 'pot_amount': 20, 'rake_amount': '1',
        'payouts': [
          {'user_id': a, 'amount': 19, 'result': 'win'},
          {'user_id': b, 'amount': '0', 'result': 'loss'},
        ],
      });
      expect((w.pot, w.rake, w.payoutFor(a)!.amount, w.payoutFor(b)!.result), (20, 1, 19, 'loss'));
      final line = LudoChatLine.fromJson({'from_user_id': a, 'message': 'Good game!', 'timestamp': 1795507713054, 'username': 'fdoc7419'});
      expect((line.message, line.username), ('Good game!', 'fdoc7419'));
      expect(ludoQuickChat, hasLength(12));
      final g = LudoGift.fromJson({'gift_id': 'g', 'sender_id': a, 'sender_name': 'fdoc7419', 'receiver_id': b, 'item_type': 'rose', 'amount': '5', 'currency': 'gold'});
      expect((g.amount, g.itemType, g.currency), (5, 'rose', 'gold'));
    });
  });

  group('the board (server numbering)', () {
    test('positions → progress per colour', () {
      expect(ludoProgress(0, 'on_board', 0), 0); // red start
      expect(ludoProgress(0, 'on_board', 51), 51); // red's last track square
      expect(ludoProgress(1, 'on_board', 13), 0); // green start
      expect(ludoProgress(1, 'on_board', 12), 51); // green's last
      expect(ludoProgress(3, 'on_board', 38), 51); // blue's last
      expect(ludoProgress(2, 'home_stretch', 0), 52);
      expect(ludoProgress(2, 'home_stretch', 5), 57);
      expect(ludoProgress(2, 'home', 0), LudoLayout.server.home);
      expect(ludoProgress(2, 'at_base', 0), LudoRules.base);
      expect(ludoProgressOf(0, 'on_board:8'), 8);
      expect(ludoProgressOf(1, 'home_stretch:3'), 55);
    });

    test('cells: the shared track and a 6-square home lane (the 6th on the centre edge)', () {
      const s = LudoLayout.server;
      expect(s.cellOf(LudoColor.red, 0), LudoRules.track[0]);
      expect(s.cellOf(LudoColor.red, 51), LudoRules.track[51]);
      expect(s.cellOf(LudoColor.green, 0), LudoRules.track[13]);
      expect(s.cellOf(LudoColor.red, 52), (1, 7));
      expect(s.cellOf(LudoColor.red, 57), (6, 7));
      expect(s.cellOf(LudoColor.blue, 57), (7, 8));
      expect(s.cellOf(LudoColor.red, s.home), isNull);
      // Quick Play keeps its classic layout.
      expect(LudoLayout.classic.home, LudoRules.home);
    });
  });

  group('controller', () {
    test('a chat line (no reply) does not lock rolling while it waits', () async {
      final h = Harness();
      final never = Completer<SocketMessage>();
      final c = LudoController(
        request: (e, d) => never.future, // chat.send never gets a reply
        events: h.events.stream,
        myUserId: a,
      );
      unawaited(c.sendChat(ludoQuickChat.first));
      await Future<void>.delayed(Duration.zero);
      expect(c.busy, isFalse);
      c.dispose();
    });

    test('create → room code, someone joins, ready, game.started → game', () async {
      final h = Harness()..replies['room.create'] = (_) => roomCreated;
      expect(await h.c.createRoom(modeCode: 'friends_room', maxPlayers: 2), isTrue);
      expectSent(h.sent.single, 'room.create', {'mode_code': 'friends_room', 'max_players': 2});
      expect(h.c.phase, LudoPhase.room);
      expect(h.c.room!.roomCode, '1865dd5d');

      await h.push('room.user_joined', {'user_id': b, 'username': 'gfdoc7419', 'seat': 2, 'color': 'yellow', 'room_full': true});
      expect(h.c.room!.players.map((p) => p.username), ['fdoc7419', 'gfdoc7419']);

      // The ready reply and the room broadcast are the same update.
      h.replies['player.ready'] = (_) => {'ready': true, 'user_id': a};
      await h.c.ready();
      await h.push('player.ready_update', {'ready': true, 'user_id': a});
      expect(h.c.room!.players.first.ready, isTrue);

      await h.push('game.started', {'match_id': 'm1', 'turn_order': [a, b], 'current_turn': 0, 'state': stateJson()});
      expect(h.c.phase, LudoPhase.game);
      expect(h.c.board!.colors, [LudoColor.red, LudoColor.yellow]);
      expect(h.c.board!.layout, LudoLayout.server);
      expect(h.c.myTurn, isTrue);
      expect(h.c.canRoll, isTrue);
    });

    test('roll → pick a highlighted pawn → the move animates from the server frame', () async {
      final h = Harness();
      await h.push('game.started', {'match_id': 'm1', 'state': stateJson()});
      h.replies['game.action'] = (d) => d['action_type'] == 'roll_dice'
          ? {'action_type': 'roll_dice', 'result': {'dice_value': 6, 'must_select_pawn': true, 'moveable_pawns': [0, 1, 2, 3]}}
          : {'action_type': 'move_pawn', 'result': {'pawn_id': 1}};
      await h.c.roll();
      expectSent(h.sent.last, 'game.action', {'action_type': 'roll_dice'});
      // Everyone, the sender too, gets the state update.
      await h.push('game.state_update', {
        'game_over': false,
        'last_action': {'action_type': 'roll_dice', 'user_id': a, 'dice_value': 6, 'move_type': null,
          'roll_result': {'dice_value': 6, 'must_select_pawn': true, 'moveable_pawns': [0, 1, 2, 3]}},
        'state': stateJson(pending: true, dice: 6),
      });
      expect(h.c.canMove, isTrue);
      expect(h.c.moveable, [0, 1, 2, 3]);
      expect(h.c.board!.lastRoll, 6);
      expect(h.c.board!.movable, [0, 1, 2, 3]);

      await h.c.move(1);
      expectSent(h.sent.last, 'game.action', {'action_type': 'move_pawn', 'pawn_id': 1});
      await h.push('game.state_update', {
        'game_over': false,
        'last_action': {'action_type': 'move_pawn', 'user_id': a, 'dice_value': 6, 'move_type': 'entered', 'pawn_id': 1,
          'move_result': {'pawn_id': 1, 'dice_value': 6, 'move_type': 'entered', 'from_position': 'at_base', 'to_position': 'on_board:start', 'next_turn_user_id': a}},
        'state': stateJson(aPawns: [pawn(0, 'at_base'), pawn(1, 'on_board', 0), pawn(2, 'at_base'), pawn(3, 'at_base')]),
      });
      final m = h.c.board!.pending!;
      expect((m.color, m.token, m.from, m.to, m.leavesBase), (LudoColor.red, 1, LudoRules.base, 0, true));
      expect(h.c.board!.tokens[LudoColor.red], [LudoRules.base, 0, LudoRules.base, LudoRules.base]);
      h.c.board!.clearPending();
      expect(h.c.canRoll, isTrue, reason: 'a six: the same player rolls again');
    });

    test('a capture animates the victim from its square back to base', () async {
      final h = Harness();
      await h.push('game.started', {'match_id': 'm1', 'state': stateJson(
        aPawns: [pawn(0, 'on_board', 3), pawn(1, 'at_base'), pawn(2, 'at_base'), pawn(3, 'at_base')],
        bPawns: [pawn(0, 'on_board', 5), pawn(1, 'at_base'), pawn(2, 'at_base'), pawn(3, 'at_base')],
      )});
      await h.push('game.state_update', {
        'last_action': {'action_type': 'move_pawn', 'user_id': a, 'captured': true,
          'move_result': {'pawn_id': 0, 'dice_value': 2, 'move_type': 'captured', 'from_position': 'on_board:3', 'to_position': 'on_board:5',
            'captured_player_seat': 2, 'captured_pawn_id': 0}},
        'state': stateJson(turn: a,
          aPawns: [pawn(0, 'on_board', 5), pawn(1, 'at_base'), pawn(2, 'at_base'), pawn(3, 'at_base')]),
      });
      final m = h.c.board!.pending!;
      expect((m.from, m.to), (3, 5));
      expect(m.path, [4, 5]);
      expect(m.captured, [(LudoColor.yellow, 0)]);
      // Yellow's start is 26: square 5 is progress 31 for yellow.
      expect(m.capturedFrom[(LudoColor.yellow, 0)], 31);
    });

    test("time's up: counted per player, a warning before the last strike", () async {
      final h = Harness();
      await h.push('game.started', {'match_id': 'm1', 'state': stateJson()});
      for (var i = 0; i < 2; i++) {
        await h.push('game.state_update', {
          'last_action': {'action_type': 'roll_dice', 'user_id': a, 'auto_play': true, 'dice_value': 3, 'move_type': 'no_move'},
          'state': stateJson(turn: b),
        });
      }
      expect(h.c.timeouts[a], 2);
      expect(h.c.notice!.text, contains("you'll be removed"));
      expect(h.c.board!.lastText, startsWith("Time's up"));
    });

    test('forfeit ending → result with places, then the payout and a rematch offer', () async {
      final h = Harness()..replies['room.create'] = (_) => {...roomCreated, 'bet_amount': 10, 'currency': 'gold'};
      await h.c.createRoom();
      await h.push('game.started', {'match_id': 'm1', 'state': stateJson()});
      await h.push('game.player_forfeited', {'game_over': true, 'reason': 'manual', 'user_id': b, 'winner_id': a});
      await h.push('game.state_update', {
        'game_over': true,
        'last_action': {'action_type': 'forfeit', 'auto_play': false, 'reason': 'manual', 'user_id': b},
        'state': stateJson(status: 'completed', winner: a, aPlace: 1, bPlace: 2, bForfeited: true),
      });
      expect(h.c.phase, LudoPhase.result);
      expect(h.c.iWon, isTrue);
      expect(h.c.standings.map((p) => p.place), [1, 2]);
      await h.push('game.wallet_update', {'match_id': 'm1', 'pot_amount': 20, 'rake_amount': 1, 'payouts': [{'user_id': a, 'amount': 19, 'result': 'win'}]});
      expect(h.c.walletUpdate!.payoutFor(a)!.amount, 19);

      await h.push('game.rematch_offered', {'from_user_id': b, 'room_id': 'r2', 'room_code': 'c0a8012e'});
      h.replies['room.join'] = (d) => {...roomCreated, 'room_code': d['room_code'], 'seat': 2};
      await h.c.acceptRematch();
      expect(h.sent.map((s) => s.$1).toList().sublist(h.sent.length - 2), ['room.leave', 'room.join']);
      expect(h.sent.last.$2, {'room_code': 'c0a8012e'});
      expect(h.c.phase, LudoPhase.room);
    });

    test('reconnect ending in game.state_sync: back in the game, names restored', () async {
      final h = Harness();
      await h.push('game.state_sync', {'match_id': 'm1', 'state': {...stateJson(turn: b), 'player_names': {b: 'gfdoc7419'}}});
      expect(h.c.phase, LudoPhase.game);
      expect(h.c.readOnly, isFalse);
      expect(h.c.nameOf(b), 'gfdoc7419');
      expect(h.c.myTurn, isFalse);
    });

    test('reconnect ending in game.final_state: the result, read-only', () async {
      final h = Harness();
      await h.push('game.final_state', {'match_id': 'm1', 'room_id': 'r', 'read_only': true,
        'state': stateJson(status: 'completed', winner: b, aPlace: 2, bPlace: 1)});
      expect(h.c.phase, LudoPhase.result);
      expect(h.c.readOnly, isTrue);
      expect(h.c.iWon, isFalse);
    });

    test('a 2 animates exactly 2 hops, even when the move text leaves out the square', () async {
      final h = Harness();
      await h.push(LudoEvent.gameStarted, {'state': stateJson(aPawns: [pawn(0, 'on_board', 50), pawn(1, 'at_base'), pawn(2, 'at_base'), pawn(3, 'at_base')])});
      // Red at 50 rolls 2 → the lane's 1st square. `to_position` has no number.
      await h.push(LudoEvent.stateUpdate, {
        'last_action': {'action_type': 'move_pawn', 'user_id': a, 'dice_value': 2,
          'move_result': {'pawn_id': 0, 'dice_value': 2, 'move_type': 'moved', 'from_position': 'on_board:50', 'to_position': 'home_stretch'}},
        'state': stateJson(turn: b, aPawns: [pawn(0, 'home_stretch', 0), pawn(1, 'at_base'), pawn(2, 'at_base'), pawn(3, 'at_base')],
          bPawns: [pawn(0, 'on_board', 26), pawn(1, 'at_base'), pawn(2, 'at_base'), pawn(3, 'at_base')]),
      });
      final m = h.c.board!.pending!;
      expect((m.from, m.to, m.path.length), (50, 52, 2));

      // A wrong `from_position` (or a missed frame) never shows more hops than the dice.
      await h.push(LudoEvent.stateUpdate, {
        'last_action': {'action_type': 'move_pawn', 'user_id': b, 'dice_value': 2,
          'move_result': {'pawn_id': 0, 'dice_value': 2, 'move_type': 'moved', 'from_position': 'on_board:26', 'to_position': 'on_board:33'}},
        'state': stateJson(turn: a, aPawns: [pawn(0, 'home_stretch', 0), pawn(1, 'at_base'), pawn(2, 'at_base'), pawn(3, 'at_base')],
          bPawns: [pawn(0, 'on_board', 33), pawn(1, 'at_base'), pawn(2, 'at_base'), pawn(3, 'at_base')]),
      });
      expect(h.c.board!.pending!.path.length, 2);
    });

    test('2 squares from home online: two real lane squares are left on the board', () {
      // The online lane has 6 squares; the 6th is drawn (not hidden in the centre).
      const l = LudoLayout.server;
      for (final c in LudoColor.values) {
        expect(l.cellOf(c, l.home - 1), LudoLayout.innerCell(c));
        expect(l.cellOf(c, l.home - 2), LudoRules.homeColumn[c]!.last);
      }
    });

    test('back mid-pick after a reconnect: the pawns that can move are tappable', () async {
      final h = Harness();
      // Rolled a 3 before the drop: two pawns out, two at base.
      await h.push('game.state_sync', {'match_id': 'm1', 'state': stateJson(pending: true, dice: 3,
        aPawns: [pawn(0, 'on_board', 5), pawn(1, 'on_board', 10), pawn(2, 'at_base'), pawn(3, 'at_base')])});
      expect(h.c.canMove, isTrue);
      expect(h.c.moveable, [0, 1]);
      await h.c.move(1);
      expectSent(h.sent.last, LudoEvent.action, {'action_type': 'move_pawn', 'pawn_id': 1});
    });

    test('reconnect with chat history: missed lines load without locking the board', () async {
      final h = Harness();
      h.replies[LudoEvent.chatHistory] = (_) => {'messages': [{'from_user_id': b, 'username': 'gfdoc7419', 'message': 'Good game!', 'timestamp': 1}]};
      await h.push('game.state_sync', {'match_id': 'm1', 'state': stateJson()});
      await Future<void>.delayed(Duration.zero);
      expect(h.c.chat.single.message, 'Good game!');
      expect(h.c.busy, isFalse);
    });

    test('leaving a resumed game tells the server (it is a forfeit)', () async {
      final h = Harness();
      await h.push('game.state_sync', {'match_id': 'm1', 'state': stateJson()});
      expect(h.c.room, isNull);
      await h.c.leave();
      expect(h.sent.map((x) => x.$1), contains(LudoEvent.roomLeave));
      expect(h.c.phase, LudoPhase.lobby);
      // A late frame of that game doesn't pull the lobby back to a result.
      await h.push(LudoEvent.stateUpdate, {'state': stateJson(status: 'completed', winner: b), 'game_over': true});
      expect(h.c.phase, LudoPhase.lobby);
    });

    test('signed in again with no game to go back to → the lobby', () async {
      final h = Harness();
      await h.push('game.state_sync', {'match_id': 'm1', 'state': stateJson()});
      await h.push('auth.login_success', {'user_id': a});
      expect(h.c.phase, LudoPhase.game);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(h.c.phase, LudoPhase.lobby);

      // …but a state_sync that follows keeps the player in the game.
      final h2 = Harness();
      await h2.push('game.state_sync', {'match_id': 'm1', 'state': stateJson()});
      await h2.push('auth.login_success', {'user_id': a});
      await h2.push('game.state_sync', {'match_id': 'm1', 'state': stateJson(turn: b)});
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(h2.c.phase, LudoPhase.game);
    });

    test('joining a finished game shows its result; already seated → back into the waiting room', () async {
      // final_state as the reply to room.join
      final h1 = Harness();
      final c1 = LudoController(
        request: (e, d) async => SocketMessage(id: 'x', event: LudoEvent.finalState,
            data: {'match_id': 'm1', 'room_id': 'r', 'read_only': true, 'state': stateJson(status: 'completed', winner: a, aPlace: 1, bPlace: 2)}),
        events: h1.events.stream,
        myUserId: a,
      );
      await c1.joinRoom('abc');
      expect(c1.phase, LudoPhase.result);
      expect(c1.readOnly, isTrue);
      c1.dispose();

      final h2 = Harness();
      var joins = 0;
      h2.replies[LudoEvent.roomJoin] = (_) => ++joins == 1 ? const SocketError('already_in_room', 'x') : roomCreated;
      expect(await h2.c.joinRoom('1865DD5D'), isTrue);
      expect(h2.sent.map((x) => x.$1), [LudoEvent.roomJoin, LudoEvent.roomLeave, LudoEvent.roomJoin]);
      expect(h2.c.phase, LudoPhase.room);
      expect(h2.c.notice, isNull, reason: 'no error toast for already_in_room');
    });

    test('the turn ring uses the mode time, else the turn length seen', () async {
      final h = Harness();
      final now = DateTime.now().millisecondsSinceEpoch;
      await h.push(LudoEvent.gameStarted, {'state': stateJson(deadline: now + 10000)});
      expect(h.c.turnRingMs, inInclusiveRange(9800, 10000));
      h.c.turnMs = 20000;
      expect(h.c.turnRingMs, 20000);
    });

    test('an automatic roll and its automatic move count as one timed-out turn', () async {
      final h = Harness();
      await h.push(LudoEvent.gameStarted, {'state': stateJson()});
      final autoRoll = {'action_type': 'roll_dice', 'user_id': a, 'auto_play': true, 'dice_value': 6,
        'roll_result': {'dice_value': 6, 'must_select_pawn': true, 'moveable_pawns': [0]}};
      await h.push(LudoEvent.stateUpdate, {'last_action': autoRoll, 'state': stateJson(pending: true, dice: 6)});
      await h.push(LudoEvent.stateUpdate, {'last_action': {'action_type': 'move_pawn', 'user_id': a, 'auto_play': true},
        'state': stateJson(turn: b)});
      expect(h.c.timeouts[a], 1);
    });

    test('a payout re-reads the wallet; invalid_mode and kill switch reach the catalogue', () async {
      var wallet = 0;
      final codes = <String>[];
      final h = Harness(onWalletChanged: () => wallet++, onModeError: (c, _) => codes.add(c));
      await h.push(LudoEvent.walletUpdate, {'match_id': 'm1', 'currency': 'token', 'pot': 20, 'payouts': []});
      expect(wallet, 1);
      h.replies[LudoEvent.matchFind] = (_) => const SocketError('invalid_mode', 'x');
      await h.c.quickMatch(modeCode: 'gone');
      h.replies[LudoEvent.roomCreate] = (_) => const SocketError('kill_switch_engaged', 'Paused for maintenance');
      await h.c.createRoom();
      expect(codes, ['invalid_mode', 'kill_switch_engaged']);
    });

    test('a dropped player shows as away mid-game, and is back on reconnected', () async {
      final h = Harness();
      await h.push('game.started', {'match_id': 'm1', 'state': stateJson()});
      await h.push('room.user_left', {'user_id': b, 'reason': 'disconnected'});
      expect(h.c.away.containsKey(b), isTrue);
      await h.push('room.user_joined', {'user_id': b, 'username': 'gfdoc7419', 'seat': 2, 'reconnected': true});
      expect(h.c.away.containsKey(b), isFalse);
    });

    test('error codes show the doc\'s messages; a kill switch disables play', () async {
      final h = Harness()..replies['room.join'] = (_) => const SocketError('not_found', 'no such room');
      expect(await h.c.joinRoom('zzzzzzzz'), isFalse);
      expect(h.c.notice!.text, 'No room with that code.');
      h.replies['match.find'] = (_) => const SocketError('kill_switch_engaged', 'Ludo is paused until 6 pm');
      await h.c.quickMatch(modeCode: 'casual_2p');
      expect(h.c.killSwitchMessage, 'Ludo is paused until 6 pm');
      expect(h.c.phase, LudoPhase.lobby);
      expect(ludoErrorText(const SocketError('insufficient_funds', 'x')), contains('Not enough'));
      expect(ludoErrorText(const SocketError('room_full', 'x')), 'That room is full.');
    });

    test('game.start_error clears ready flags and explains', () async {
      final h = Harness()..replies['room.create'] = (_) => {
            ...roomCreated,
            'players': [
              {'user_id': a, 'username': 'fdoc7419', 'seat': 0, 'ready': true},
              {'user_id': b, 'username': 'gfdoc7419', 'seat': 2, 'ready': true},
            ],
          };
      await h.c.createRoom();
      await h.push('game.start_error', {'error': 'insufficient_funds', 'message': 'One or more players have insufficient funds'});
      expect(h.c.room!.players.every((p) => !p.ready), isTrue);
      expect(h.c.notice!.text, contains('enough'));
    });

    test('quick match: match.find then ready; chat only sends the 12 lines', () async {
      final h = Harness()..replies['match.find'] = (_) => {...roomCreated, 'mode_code': 'casual_2p'};
      await h.c.quickMatch(modeCode: 'casual_2p', playerCount: 2);
      expect(h.sent.map((s) => s.$1), ['match.find', 'player.ready']);
      expect(h.sent.first.$2, {'mode_code': 'casual_2p', 'player_count': 2});
      expect(h.c.room!.quickMatch, isTrue);
      await h.c.sendChat('hello');
      await h.c.sendChat('Good game!');
      expectSent(h.sent.last, 'chat.send', {'message': 'Good game!'});
      await h.push('chat.message', {'from_user_id': b, 'message': 'Nice move!', 'username': 'gfdoc7419'});
      expect(h.c.chat.single.message, 'Nice move!');
    });
  });

  test('catalogue: friends modes have host options; stake tiers per mode and currency', () {
    final friends = LudoMode.fromJson({
      'id': 61, 'code': 'friends_room', 'name': 'Play with Friends', 'player_count': 4, 'min_players': 2, 'turn_timer_seconds': 15,
      'mode_config': {
        'host_can_choose': ['turn_seconds', 'safe_squares'],
        'host_options': {'safe_squares': {'label': 'Safe squares'}},
        'safe_squares': true,
        'timer': {'allowed_turn_seconds': [10, 15, 20], 'max_timeouts': 3},
      },
    });
    final quick = LudoMode.fromJson({'id': 57, 'code': 'casual_2p', 'player_count': 2, 'mode_config': {'timer': {'max_timeouts': 3}}});
    expect((friends.friends, friends.hostOptions.single.label), (true, 'Safe squares'));
    expect(friends.allowedTurnSeconds, [10, 15, 20]);
    expect(quick.friends, isFalse);
    final cat = LudoCatalogue(gameId: 1, modes: [quick, friends], stakes: const [
      LudoStake(modeId: 57, currency: 'gold', amount: 25),
      LudoStake(modeId: 57, currency: 'gold', amount: 10),
      LudoStake(modeId: 57, currency: 'token', amount: 50),
    ]);
    expect(cat.stakesFor(quick, 'gold'), [10, 25]);
    expect(cat.quickModes.single.code, 'casual_2p');
    expect(cat.friendsModes.single.code, 'friends_room');
  });
}
