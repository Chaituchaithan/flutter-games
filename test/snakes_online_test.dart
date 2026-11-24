// Online Snake & Ladder (docs/services/snake-and-ladder.md): parsing the
// doc's real and from-code frames, the server board, and the controller
// through lobby → room → game → result, plus reconnects ending in
// game.state_sync / game.final_state and a game ended by
// game.player_forfeited alone.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/snakes/online/snakes_online_board.dart';
import 'package:snakeladder/game/snakes/online/snakes_online_catalogue.dart';
import 'package:snakeladder/game/snakes/online/snakes_online_controller.dart';
import 'package:snakeladder/game/snakes/online/snakes_online_models.dart';
import 'package:snakeladder/game/snakes/snakes_board_view.dart';
import 'package:snakeladder/game/snakes/snakes_engine.dart';
import 'package:snakeladder/services/socket/socket_client.dart';

const a = '3d0ee3f1-7dfd-4195-befd-6d16fa83dc18';
const b = '010e63de-39c6-4f67-a43b-1bf339396edb';

const rules = {
  'capture_sends_home': true, 'exact_finish': true, 'extra_turn_on_six': true, 'partners_cannot_capture': true,
  'powerups_enabled': true, 'pu_anti_venom': true, 'pu_ladder_boost': true, 'pu_reroll': true, 'ranked': false,
  'rematch_allowed': true, 'shared_ladders': false, 'team_chat': false, 'teams': false, 'three_sixes_lose_turn': true,
};

Map<String, dynamic> player(String id, int seat, {int position = 0, bool forfeited = false, List<String>? on, int timeouts = 0, int skip = 0}) => {
  'user_id': id, 'seat': seat, 'position': position, 'has_started': true, 'forfeited': forfeited,
  'timeouts': timeouts, 'skip_turns': skip, 'best_multiplier': 0, 'active_powerups': ?on,
};

/// A Quick 50 state (real shape from game.started).
Map<String, dynamic> stateJson({
  String turn = a,
  int aPos = 0,
  int bPos = 0,
  String status = 'in_progress',
  String? winner,
  List<String>? places,
  int? deadline = 1795514399333,
  List<String>? aOn,
  int aTimeouts = 0,
  int bSkip = 0,
  List<String>? skipped,
  bool venom = false,
}) => {
  'match_id': 'c98923ad-fa56-4841-8699-72d34efeec2f',
  'status': status,
  'board_size': venom ? 100 : 50,
  'snakes': venom ? [[17, 7], [26, 10]] : [[25, 5], [34, 12], [42, 23]],
  'ladders': venom ? [[4, 14]] : [[3, 16], [9, 31], [18, 37], [29, 44]],
  'venom_tiles': ?(venom ? [23, 44, 66, 88] : null),
  'current_turn_user_id': turn,
  'turn_number': 0,
  'turn_deadline_ms': deadline,
  'turn_time_ms': 20000,
  'max_timeouts': 5,
  'winner': winner,
  'winners': ?(winner == null ? null : [winner]),
  'places': ?places,
  'skipped_turns': ?skipped,
  'royal_stakes': false,
  'dice_seed_hash': 'd7dcdbe65ac41aefedb84899ead3472cff3d7dd93c21e9f49177bf87afed3c0b',
  'dice_seed': null,
  'players': [player(a, 0, position: aPos, on: aOn, timeouts: aTimeouts), player(b, 1, position: bPos, skip: bSkip)],
  'rules': rules,
};

/// A full last_action (every field present, as in game.state_update).
Map<String, dynamic> last({
  String user = a,
  int dice = 5,
  String moveType = 'moved',
  required int from,
  required int to,
  Map<String, dynamic>? landing,
  bool extra = false,
  bool venom = false,
  bool auto = false,
  List<String> captured = const [],
  int? overshot,
  Map<String, dynamic>? charm,
  bool over = false,
  String? winner,
  String? next = b,
}) => {
  'action_type': 'roll_dice', 'user_id': user, 'auto_roll': auto, 'dice_value': dice, 'move_type': moveType,
  'from_position': from, 'to_position': to, 'extra_turn': extra, 'landing': landing, 'venom': venom, 'multiplier': null,
  'rerolled_from': null, 'captured': captured, 'carried': <String>[], 'overshot': overshot, 'snake_charm': charm,
  'game_over': over, 'winner': winner, 'next_turn_user_id': next,
};

// The real room.created reply from the doc (a staked 1v1 Duel).
const roomCreated = {
  'room_id': '333a8320-dd44-476d-89cc-0281b7bf7d4f', 'room_code': '333a8320', 'seat': 0,
  'board_layout': 'classic_100', 'variant': 'classic_100', 'mode_code': 'duel_casual', 'mode_name': '1v1 Duel casual',
  'max_players': 2, 'currency': 'gold', 'bet_amount': 100, 'turn_timer_sec': 20, 'listed': false,
  'rules': rules,
  'board': {
    'size': 100,
    'snakes': {'17': 7, '54': 34, '62': 19, '64': 60, '87': 36, '93': 73, '95': 75, '99': 78},
    'ladders': {'4': 14, '9': 31, '20': 38, '28': 84, '40': 59, '51': 67, '63': 81, '71': 91},
  },
};

// The real match.found reply (no board, the player alone).
const matchFound = {
  'room_id': 'b941f91c-c3b9-41b3-8d41-05ec7630dd8a', 'room_code': 'b941f91c', 'seat': 0,
  'board_layout': 'quick_50', 'mode_code': 'quick_50', 'max_players': 2, 'currency': 'token', 'bet_amount': 0,
  'players': [{'seat': 0, 'user_id': a, 'username': 'wsnldoca1795514218'}],
  'rules': rules,
};

/// The controller against a scripted server.
class Harness {
  Harness({void Function()? onWalletChanged, void Function(String, String)? onModeError, void Function(List<String>)? onUnknown, void Function()? onBoosts}) {
    c = SnlController(
      request: _request,
      events: events.stream,
      myUserId: a,
      onWalletChanged: onWalletChanged,
      onModeError: onModeError,
      onUnknownPlayers: onUnknown,
      onBoostsChanged: onBoosts,
      serverNow: () => DateTime.fromMillisecondsSinceEpoch(1795514389333),
      resyncWait: const Duration(milliseconds: 20),
    );
  }

  final events = StreamController<SocketMessage>.broadcast();
  late final SnlController c;
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

  /// Seated in a 2-player Quick 50 room with names, then the game starts.
  Future<void> started({Map<String, dynamic>? state}) async {
    replies['match.find'] = (_) => matchFound;
    await c.quickMatch(modeCode: 'quick_50', playerCount: 2);
    await push('room.user_joined', {'countdown_seconds': 5, 'room_full': true, 'seat': 1, 'user_id': b, 'username': 'ShadowChamp'});
    await push('game.started', {'match_id': 'm', 'turn_order': [a, b], 'current_turn': 0, 'tournament': null, 'state': state ?? stateJson()});
  }
}

void expectSent((String, Map<String, dynamic>) sent, String event, Map<String, dynamic> data) {
  expect(sent.$1, event);
  expect(sent.$2, data);
}

void main() {
  group('frames', () {
    test('room.created (real): board with string keys, turn_timer_sec, no players', () {
      final r = RoomInfo.fromJson(roomCreated);
      expect((r.roomCode, r.seat, r.modeCode, r.staked, r.currency, r.variant), ('333a8320', 0, 'duel_casual', true, 'gold', 'classic_100'));
      expect(r.players, isEmpty);
      final board = SnlBoards.fromRoomBoard(r.raw['board'])!;
      expect(board.size, 100);
      expect(board.snakes[99], 78);
      expect(board.ladders[28], 84);
      expect(board, SnlBoards.classic100);
    });

    test('room.joined (real) and match.found: board from board_layout; rejoined', () {
      final j = RoomInfo.fromJson({
        'room_id': 'r', 'room_code': '333a8320', 'seat': 1, 'board_layout': 'classic_100', 'mode_code': 'duel_casual', 'max_players': 2,
        'currency': 'gold', 'bet_amount': 100, 'rules': null, 'tournament': {'tournament_id': 't', 'round': 2, 'table_number': 3},
        'players': [
          {'ready': false, 'seat': 0, 'user_id': a, 'username': 'wsnldoca1795514218'},
          {'ready': false, 'seat': 1, 'user_id': b, 'username': 'wsnldocb1795514218'},
        ],
      });
      expect((j.seat, j.variant, j.players.length, j.rules.isEmpty, j.tournament!.table), (1, 'classic_100', 2, true, 3));
      expect(SnlBoards.of(j.variant), SnlBoards.classic100);
      final m = RoomInfo.fromJson(matchFound, quickMatch: true);
      expect((m.variant, m.staked, m.players.single.username), ('quick_50', false, 'wsnldoca1795514218'));
      expect(SnlBoards.of('venom_100')!.venom, {23, 44, 66, 88});
      final re = RoomInfo.fromJson({'room_id': 'r', 'room_code': 'c', 'seat': 0, 'match_id': 'm', 'rejoined': true});
      expect((re.rejoined, re.matchId), (true, 'm'));
    });

    test('game state (real game.started): board, deadline ms, players', () {
      final st = SnlState.fromJson(stateJson(venom: true, bSkip: 1, skipped: [b]));
      expect((st.board!.size, st.board!.snakes[26], st.board!.venom.length), (100, 10, 4));
      expect(st.turnDeadline!.millisecondsSinceEpoch, 1795514399333);
      expect((st.turnTimeMs, st.maxTimeouts, st.player(b)!.skipTurns), (20000, 5, 1));
      expect(st.skippedTurns, [b]);
      final quick = SnlState.fromJson(stateJson());
      expect(quick.board, SnlBoards.quick50);
    });

    test('roll ack (real) and last_action samples parse', () {
      final ack = SnlRoll.fromJson({
        'dice_value': 5, 'move_type': 'climbed_ladder', 'from_position': 13, 'to_position': 37, 'extra_turn': false,
        'landing': {'kind': 'ladder', 'square': 18}, 'next_turn_user_id': b, 'game_over': false, 'winner': null,
      })!;
      expect((ack.diceValue, ack.moveType, ack.from, ack.to, ack.landingKind, ack.landingSquare, ack.nextTurnUserId), (5, 'climbed_ladder', 13, 37, 'ladder', 18, b));
      final cap = SnlRoll.fromJson(last(user: b, dice: 1, from: 6, to: 7, captured: [a]))!;
      expect(cap.captured, [a]);
      expect(cap.landingSquare, isNull);
      final over = SnlRoll.fromJson(last(dice: 4, moveType: 'overshot', from: 47, to: 47, overshot: 51))!;
      expect(over.overshot, 51);
      final charm = SnlRoll.fromJson(last(dice: 2, from: 40, to: 42, charm: {'code': 'sl_anti_snake', 'head': 42, 'tail': 23}))!;
      expect(charm.snakeCharm!['code'], 'sl_anti_snake');
    });

    test('wallet update (real): place and royal_stakes; bet options (real)', () {
      final w = RoomWalletUpdate.fromJson({
        'match_id': '333a8320-dd44-476d-89cc-0281b7bf7d4f', 'pot_amount': 200, 'rake_amount': 10, 'royal_stakes': false,
        'payouts': [
          {'user_id': a, 'amount': 190, 'result': 'win', 'place': 1},
          {'user_id': b, 'amount': 0, 'result': 'loss', 'place': 2},
        ],
      });
      expect((w.pot, w.rake, w.payoutFor(a)!.amount, w.payoutFor(b)!.place, w.royalStakes), (200, 10, 190, 2, false));
      final o = SnlBetOffer.fromJson({
        'currency': 'gold', 'balance': 500, 'band_from': 100, 'band_to': 1000,
        'bets': [{'amount': 100, 'locked': false}, {'amount': 200, 'locked': false}, {'amount': 300, 'locked': true}],
        'default': 200, 'custom_step': null, 'max_bet': 250,
      })!;
      expect(o.unlocked, [100, 200]);
      expect((o.defaultBet, o.maxBet), (200, 250));
      expect(SnlBetOffer.fromJson(null), isNull);
      final list = RoomSummary.fromJson({
        'room_id': 'r', 'room_code': '06c537b3', 'game_type': 'snake_and_ladder', 'board_layout': 'quick_50', 'variant': 'quick_50',
        'mode_code': 'quick_friends', 'matchmaking': 'private_room', 'players': 1, 'max_players': 2, 'status': 'waiting',
      });
      expect((list.players, list.variant, list.matchmaking), (1, 'quick_50', 'private_room'));
    });
  });

  group('the board (server numbering)', () {
    test('rows of 10 from the bottom-left, alternating', () {
      expect(SnlBoards.quick50.rows, 5);
      expect(SnlBoards.quick50.cellOf(1), (0, 4));
      expect(SnlBoards.quick50.cellOf(10), (9, 4));
      expect(SnlBoards.quick50.cellOf(11), (9, 3));
      expect(SnlBoards.quick50.cellOf(50), (9, 0));
      expect(SnlBoards.classic100.cellOf(100), (0, 0));
      // The offline board keeps its numbering.
      expect(SnakesLayout.classic.cellOf(37), SnakesRules.cellOf(37));
    });

    test('moves from last_action: hop, ladder, snake, overshoot, snake charmer', () {
      const l = SnlBoards.quick50;
      final ladder = SnlBoardGame.moveOf(SnlRoll.fromJson(last(from: 13, to: 37, landing: {'kind': 'ladder', 'square': 18}))!, 0, 0, l)!;
      expect(ladder.steps, [14, 15, 16, 17, 18]);
      expect((ladder.jump, ladder.to), (SnakesJump.ladder, 37));
      final snake = SnlBoardGame.moveOf(SnlRoll.fromJson(last(from: 37, to: 23, landing: {'kind': 'snake', 'square': 42}))!, 1, 0, l)!;
      expect((snake.steps.last, snake.jump, snake.to, snake.player), (42, SnakesJump.snake, 23, 1));
      final plain = SnlBoardGame.moveOf(SnlRoll.fromJson(last(dice: 1, from: 6, to: 7))!, 0, 0, l)!;
      expect(plain.steps, [7]);
      expect(plain.jump, SnakesJump.none);
      final over = SnlBoardGame.moveOf(SnlRoll.fromJson(last(dice: 4, moveType: 'overshot', from: 47, to: 47, overshot: 51))!, 0, 0, l)!;
      expect(over.blocked, isTrue);
      // A six onto a ladder keeps move_type extra_turn: animate by landing.
      final six = SnlBoardGame.moveOf(SnlRoll.fromJson(last(dice: 6, moveType: 'extra_turn', from: 23, to: 44, extra: true, landing: {'kind': 'ladder', 'square': 29}))!, 0, 0, l)!;
      expect((six.steps.last, six.jump, six.to), (29, SnakesJump.ladder, 44));
      final charmer = SnlBoardGame.moveOf(SnlRoll.fromJson(last(dice: 2, from: 23, to: 44, landing: {'kind': 'snake', 'square': 25}))!, 0, 0, l)!;
      expect(charmer.jump, SnakesJump.ladder);
    });

    testWidgets('the board view draws a 50-square server board with venom', (tester) async {
      final g = SnlBoardGame(players: 2, layout: const SnakesLayout(size: 50, snakes: {25: 5}, ladders: {3: 16}, venom: {23}));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SizedBox(width: 360, height: 300, child: SnakesBoardView(game: g, colors: const [Colors.red, Colors.green], onMoveAnimated: g.clearPending))),
      ));
      g.applyServer(positions: [16, 0], turn: 1, move: const SnakesMove(player: 0, roll: 3, from: 0, steps: [1, 2, 3], jump: SnakesJump.ladder, jumpTo: 16), dice: 3);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(g.pending, isNull, reason: 'the animation ends and commits the server square');
      expect(g.positions, [16, 0]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      g.dispose();
    });
  });

  group('controller', () {
    test('a chat line (no reply) does not lock rolling while it waits', () async {
      final h = Harness();
      final never = Completer<SocketMessage>();
      final c = SnlController(request: (e, d) => never.future, events: h.events.stream, myUserId: a);
      unawaited(c.sendChat(roomQuickChat.first));
      await Future<void>.delayed(Duration.zero);
      expect(c.busy, isFalse);
      c.dispose();
    });

    test('quick match: match.find with player_count, then ready; a bot joins; game.started → game', () async {
      final h = Harness()..replies['match.find'] = (_) => matchFound;
      await h.c.quickMatch(modeCode: 'quick_50', playerCount: 2);
      expect(h.sent.map((s) => s.$1), ['match.find', 'player.ready']);
      expect(h.sent.first.$2, {'mode_code': 'quick_50', 'player_count': 2});
      expect((h.c.phase, h.c.room!.quickMatch), (RoomPhase.room, true));
      expect(h.c.previewBoard, SnlBoards.quick50, reason: 'match.found has no board: the known layout');
      // A bot fills the seat and readies at once (real).
      await h.push('room.user_joined', {'countdown_seconds': 5, 'room_full': true, 'seat': 1, 'user_id': b, 'username': 'ShadowChamp'});
      await h.push('player.ready_update', {'ready': true, 'user_id': b});
      expect(h.c.room!.players.map((p) => (p.username, p.ready)), [('wsnldoca1795514218', false), ('ShadowChamp', true)]);
      await h.push('game.started', {'match_id': 'm', 'turn_order': [a, b], 'current_turn': 0, 'state': stateJson()});
      expect(h.c.phase, RoomPhase.game);
      expect(h.c.board!.layout, SnlBoards.quick50);
      expect((h.c.myTurn, h.c.canRoll, h.c.nameOf(b)), (true, true, 'ShadowChamp'));
      expect(h.c.turnLeft, const Duration(seconds: 10), reason: 'from turn_deadline_ms on the server clock');
      expect(h.c.turnRingMs, 20000);
    });

    test('roll sends roll_dice only; the state update animates the ladder, then sets the board', () async {
      final h = Harness();
      await h.started();
      h.replies['game.action'] = (_) => {'action_type': 'roll_dice', 'result': {'dice_value': 3, 'move_type': 'climbed_ladder', 'from_position': 0, 'to_position': 16}};
      await h.c.roll();
      expectSent(h.sent.last, 'game.action', {'action_type': 'roll_dice'});
      await h.push('game.state_update', {
        'last_action': last(dice: 3, moveType: 'climbed_ladder', from: 0, to: 16, landing: {'kind': 'ladder', 'square': 3}),
        'state': stateJson(turn: b, aPos: 16),
      });
      final m = h.c.board!.pending!;
      expect(m.steps, [1, 2, 3]);
      expect((m.jump, m.to), (SnakesJump.ladder, 16));
      expect(h.c.board!.positions[0], 0, reason: 'the token stays put until the animation ends');
      expect(h.c.board!.lastRoll, 3);
      expect(h.c.board!.lastText, 'You climbed a ladder to 16');
      h.c.board!.clearPending();
      expect(h.c.board!.positions, [16, 0]);
      expect(h.c.myTurn, isFalse);
    });

    test('a capture, an overshoot, venom and a skipped turn are told', () async {
      final h = Harness();
      await h.started(state: stateJson(venom: true, aPos: 6, bPos: 7));
      await h.push('game.state_update', {
        'last_action': last(user: b, dice: 1, from: 6, to: 7, captured: [a], next: a),
        'state': stateJson(venom: true, aPos: 0, bPos: 7),
      });
      expect(h.c.notice!.text, 'ShadowChamp sent you back to the start.');
      expect(h.c.board!.positions[0], 6, reason: 'the captured token flies home after the move');
      h.c.board!.clearPending();
      expect(h.c.board!.positions[0], 0);
      await h.push('game.state_update', {
        'last_action': last(user: b, dice: 6, moveType: 'extra_turn', from: 60, to: 66, extra: true, venom: true, next: b),
        'state': stateJson(venom: true, turn: b, bPos: 66, bSkip: 1),
      });
      expect(h.c.notice!.text, contains('Venom! ShadowChamp sits out'));
      expect(h.c.board!.lastText, 'ShadowChamp rolled 6 → 66 · rolls again');
      await h.push('game.state_update', {
        'last_action': last(dice: 4, from: 12, to: 16, next: a),
        'state': stateJson(venom: true, aPos: 16, bPos: 66, skipped: [b]),
      });
      expect(h.c.skipped, {b});
      expect(h.c.notice!.text, 'ShadowChamp skipped (venom).');
      await h.push('game.state_update', {
        'last_action': last(dice: 4, moveType: 'overshot', from: 97, to: 97, overshot: 101),
        'state': stateJson(venom: true, turn: b, aPos: 97),
      });
      expect(h.c.board!.lastText, 'You rolled 4 · needs exactly 3');
      expect(h.c.board!.pending!.blocked, isTrue);
    });

    test("time's up: the server rolls, counted per player, a warning before the last allowed", () async {
      final h = Harness();
      await h.started();
      for (var i = 1; i <= 4; i++) {
        await h.push('game.state_update', {'last_action': last(auto: true, dice: 1, from: i - 1, to: i), 'state': stateJson(turn: b, aPos: i, aTimeouts: i)});
      }
      expect(h.c.timeouts[a], 4);
      expect(h.c.notice!.text, contains("you'll be removed"));
      expect(h.c.board!.lastText, startsWith("Time's up"));
      // Rolling by hand resets it.
      await h.push('game.state_update', {'last_action': last(dice: 2, from: 4, to: 6), 'state': stateJson(turn: b, aPos: 6)});
      expect(h.c.timeouts[a], 0);
    });

    test('a real finish: last_action.game_over → result with places; the payout re-reads the wallet', () async {
      var wallet = 0;
      final h = Harness(onWalletChanged: () => wallet++);
      await h.started(state: stateJson(aPos: 47));
      await h.push('game.state_update', {
        'last_action': last(dice: 3, moveType: 'won', from: 47, to: 50, over: true, winner: a, next: null),
        'state': stateJson(status: 'completed', winner: a, places: [a, b], aPos: 50, deadline: null),
      });
      expect(h.c.phase, RoomPhase.result);
      expect(h.c.iWon, isTrue);
      expect(h.c.standings.map((p) => p.userId), [a, b]);
      await h.push('game.wallet_update', {'match_id': 'm', 'pot_amount': 200, 'rake_amount': 10, 'royal_stakes': false,
        'payouts': [{'user_id': a, 'amount': 190, 'result': 'win', 'place': 1}]});
      expect((h.c.walletUpdate!.payoutFor(a)!.amount, wallet), (190, 1));
    });

    test('a 2-player game ended by game.player_forfeited alone shows the result', () async {
      final h = Harness();
      await h.started(state: stateJson(aPos: 10, bPos: 30));
      await h.push('game.player_forfeited', {'user_id': b, 'reason': 'manual', 'game_over': true, 'winner_id': a, 'current_turn_user_id': a, 'turn_deadline_ms': null});
      expect(h.c.phase, RoomPhase.result);
      expect(h.c.iWon, isTrue);
      expect(h.c.standings.first.userId, a, reason: 'the winner first, then by position');
      expect(h.c.state!.player(b)!.forfeited, isTrue);
      expect(h.c.notice!.text, 'ShadowChamp gave up.');
    });

    test('with more players a forfeit marks the seat out and play goes on', () async {
      final h = Harness();
      await h.started();
      await h.push('game.player_forfeited', {'user_id': b, 'reason': 'timeout', 'game_over': false, 'winner_id': null, 'current_turn_user_id': a, 'turn_deadline_ms': 1795514420000});
      expect(h.c.phase, RoomPhase.game);
      expect(h.c.state!.player(b)!.forfeited, isTrue);
      expect(h.c.state!.turnDeadline!.millisecondsSinceEpoch, 1795514420000);
      expect(h.c.notice!.text, 'ShadowChamp ran out of time too often.');
    });

    test('create: turn_timer_sec, the room board preview; bet_not_offered reloads the bets', () async {
      final h = Harness()..replies['room.create'] = (_) => roomCreated;
      expect(await h.c.createRoom(modeCode: 'duel_casual', maxPlayers: 2, turnTimerSec: 20, currency: 'gold', betAmount: 100, rules: {'rematch_allowed': true}), isTrue);
      expectSent(h.sent.single, 'room.create', {'mode_code': 'duel_casual', 'max_players': 2, 'turn_timer_sec': 20, 'currency': 'gold', 'bet_amount': 100, 'rematch_allowed': true});
      expect(h.c.previewBoard, SnlBoards.classic100);
      expect(h.c.rematchAllowed, isTrue);

      final h2 = Harness();
      h2.replies['room.create'] = (_) => const SocketError('bet_not_offered', 'the bet ladder does not offer 7 gold at a balance of 500');
      h2.replies['wallet.bet_options'] = (_) => {'offer': {'currency': 'gold', 'bets': [{'amount': 100, 'locked': false}]}};
      expect(await h2.c.createRoom(currency: 'gold', betAmount: 7), isFalse);
      expect(h2.c.notice!.text, contains('isn’t offered'));
      expectSent(h2.sent.last, 'wallet.bet_options', {'currency': 'gold'});
      expect(h2.c.betOffer!.unlocked, [100]);
      h2.replies['room.create'] = (_) => const SocketError('insufficient_funds', 'insufficient balance for a stake of 1000 gold');
      await h2.c.createRoom(currency: 'gold', betAmount: 1000);
      expect(h2.c.notice!.text, contains('Not enough'));
    });

    test('reconnect ending in game.state_sync: back in the game; names looked up', () async {
      final asked = <String>[];
      final h = Harness(onUnknown: asked.addAll);
      h.replies['chat.history'] = (_) => {'messages': [{'from_user_id': b, 'username': 'wsnldocb', 'message': 'Good luck!', 'timestamp': 1}]};
      await h.push('game.state_sync', {'match_id': 'm', 'state': stateJson(turn: b, aPos: 4)});
      expect(h.c.phase, RoomPhase.game);
      expect(h.c.readOnly, isFalse);
      expect(asked, [b]);
      expect(h.c.nameOf(b), 'Player 2', reason: 'no player_names in the state');
      h.c.setName(b, 'Maya');
      expect(h.c.nameOf(b), 'Maya');
      await Future<void>.delayed(Duration.zero);
      expect(h.c.chat.single.message, 'Good luck!');
      expect(h.c.busy, isFalse);
      expect(h.c.board!.positions[0], 4);
    });

    test('reconnect ending in game.final_state: the result, read-only (also with an expired state)', () async {
      final h = Harness();
      await h.push('game.final_state', {'match_id': 'm', 'room_id': 'm', 'read_only': true,
        'state': stateJson(status: 'completed', winner: b, places: [b, a])});
      expect((h.c.phase, h.c.readOnly, h.c.iWon), (RoomPhase.result, true, false));
      final h2 = Harness();
      await h2.push('game.final_state', {'match_id': 'm', 'room_id': 'm', 'read_only': true, 'state': null});
      expect((h2.c.phase, h2.c.state), (RoomPhase.result, null));
    });

    test('signed in again with no game to go back to → the lobby; a state_sync keeps the game', () async {
      final h = Harness();
      await h.push('game.state_sync', {'match_id': 'm', 'state': stateJson()});
      await h.push('auth.login_success', {'user_id': a});
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(h.c.phase, RoomPhase.lobby);
      final h2 = Harness();
      await h2.push('game.state_sync', {'match_id': 'm', 'state': stateJson()});
      await h2.push('auth.login_success', {'user_id': a});
      await h2.push('game.state_sync', {'match_id': 'm', 'state': stateJson(turn: b)});
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(h2.c.phase, RoomPhase.game);
    });

    test('leaving a resumed game tells the server; its late frames are ignored', () async {
      final h = Harness();
      await h.push('game.state_sync', {'match_id': 'm', 'state': stateJson()});
      await h.c.leave();
      expect(h.sent.map((x) => x.$1), contains('room.leave'));
      expect(h.c.phase, RoomPhase.lobby);
      await h.push('game.state_update', {'last_action': last(from: 0, to: 5), 'state': stateJson(status: 'completed', winner: b)});
      expect(h.c.phase, RoomPhase.lobby);
    });

    test('a dropped player shows as away; back with only {user_id, reconnected} keeps the name', () async {
      final h = Harness();
      await h.started();
      await h.push('room.user_left', {'reason': 'disconnected', 'user_id': b});
      expect(h.c.away.containsKey(b), isTrue);
      await h.push('room.user_joined', {'user_id': b, 'reconnected': true});
      expect(h.c.away.containsKey(b), isFalse);
      expect(h.c.nameOf(b), 'ShadowChamp');
      expect(h.c.notice!.text, 'ShadowChamp is back.');
    });

    test('boosts: use_powerup before rolling; powerup_used shows on the seat; a shield save is told', () async {
      var boosts = 0;
      final h = Harness(onBoosts: () => boosts++);
      await h.started();
      expect(h.c.canBoost, isTrue);
      expect(h.c.boostAllowed('sl_snake_charmer'), isTrue);
      h.replies['game.action'] = (_) => {'action_type': 'use_powerup', 'powerup_code': 'shield', 'remaining_quantity': 0};
      await h.c.usePowerup('shield');
      expectSent(h.sent.last, 'game.action', {'action_type': 'use_powerup', 'powerup_code': 'shield'});
      await h.push('game.powerup_used', {'active_powerups': ['shield'], 'powerup_code': 'shield', 'user_id': a});
      expect(h.c.myBoosts, ['shield']);
      expect(boosts, 1);
      expect(h.c.notice!.text, 'You switched on Shield.');
      // Moved onto the snake head at 25 with the shield on: no flag, so compare.
      await h.push('game.state_update', {'last_action': last(dice: 3, from: 22, to: 25), 'state': stateJson(turn: b, aPos: 25)});
      expect(h.c.notice!.text, 'Shield! You stay on the snake’s head.');
      // A refused boost explains itself.
      h.replies['game.action'] = (_) => const SocketError('invalid_state', "bad request: no 'shield' power-ups remaining");
      await h.push('game.state_update', {'last_action': last(user: b, from: 0, to: 2, next: a), 'state': stateJson(aPos: 25, bPos: 2)});
      h.c.board!.clearPending();
      await h.c.usePowerup('shield');
      expect(h.c.notice!.text, 'You have none of that boost left.');
    });

    test('action errors: not_your_turn is quiet, game_over shows the result, busy is retried once', () async {
      final h = Harness();
      await h.started();
      h.replies['game.action'] = (_) => const SocketError('not_your_turn', 'not your turn');
      final before = h.c.noticeId;
      await h.c.roll();
      expect(h.c.noticeId, before);
      var calls = 0;
      h.replies['game.action'] = (_) => ++calls == 1 ? const SocketError('busy', 'lock timeout') : {'action_type': 'roll_dice', 'result': {'dice_value': 2}};
      await h.c.roll();
      expect(calls, 2);
      h.replies['game.action'] = (_) => const SocketError('game_over', 'game is over');
      await h.c.roll();
      expect(h.c.phase, RoomPhase.result);
    });

    test('rematch: my own offer is ignored; joining an offer leaves, then joins', () async {
      final h = Harness();
      await h.started();
      await h.push('game.player_forfeited', {'user_id': b, 'reason': 'manual', 'game_over': true, 'winner_id': a});
      await h.push('game.rematch_offered', {'from_user_id': a, 'room_code': '091f250f', 'room_id': 'r2'});
      expect(h.c.rematchOffer, isNull);
      await h.push('game.rematch_offered', {'from_user_id': b, 'room_code': '091f250f', 'room_id': 'r2'});
      expect(h.c.rematchOffer!.roomCode, '091f250f');
      h.replies['room.join'] = (d) => {...roomCreated, 'room_code': d['room_code'], 'seat': 1};
      await h.c.acceptRematch();
      expect(h.sent.map((s) => s.$1).toList().sublist(h.sent.length - 2), ['room.leave', 'room.join']);
      expect(h.c.phase, RoomPhase.room);
    });

    test('invalid_mode and a kill switch reach the catalogue; errors show the doc’s messages', () async {
      final codes = <String>[];
      final h = Harness(onModeError: (c, _) => codes.add(c));
      h.replies['match.find'] = (_) => const SocketError('invalid_mode', "validation error: mode 'classic_2' supports 2-2 players, not 4");
      await h.c.quickMatch(modeCode: 'classic_2', playerCount: 4);
      expect(h.c.phase, RoomPhase.lobby);
      h.replies['room.create'] = (_) => const SocketError('kill_switch_engaged', 'Snake & Ladder is paused');
      await h.c.createRoom();
      expect(codes, ['invalid_mode', 'kill_switch_engaged']);
      expect(h.c.killSwitchMessage, 'Snake & Ladder is paused');
      h.replies['room.join'] = (_) => const SocketError('not_found', "no room found for code 'zzzzzzzz'");
      expect(await h.c.joinRoom('zzzzzzzz'), isFalse);
      expect(h.c.notice!.text, 'No room with that code.');
      for (final code in ['room_full', 'game_in_progress', 'not_your_table', 'insufficient_funds', 'bet_not_offered', 'invalid_settings', 'busy', 'internal_error', 'duplicate']) {
        expect(snlErrorText(SocketError(code, 'x')), isNot(contains('x')), reason: code);
      }
      expect(snlActionErrorText(const SocketError('invalid_state', 'maximum 2 power-ups per turn')), contains('At most 2'));
    });

    test('game.start_error clears ready flags and explains', () async {
      final h = Harness()..replies['room.join'] = (_) => {
            ...roomCreated, 'seat': 1,
            'players': [
              {'user_id': a, 'username': 'x', 'seat': 1, 'ready': true},
              {'user_id': b, 'username': 'y', 'seat': 0, 'ready': true},
            ],
          };
      await h.c.joinRoom('333a8320');
      await h.push('game.start_error', {'error': 'insufficient_funds', 'message': 'One or more players have insufficient funds to cover the bet'});
      expect(h.c.room!.players.every((p) => !p.ready), isTrue);
      expect(h.c.notice!.text, contains('enough'));
    });
  });

  test('catalogue: friends modes list host options without the timer; stake tiers per mode', () {
    final casual = RoomMode.fromJson({
      'id': 143, 'code': 'casual', 'name': 'Casual with Friends', 'player_count': 4, 'min_players': 2, 'variant_code': 'classic_100',
      'mode_config': {
        'host_can_choose': ['turn_timer_sec', 'exact_finish', 'extra_turn_on_six', 'capture_sends_home', 'powerups_enabled'],
        'host_options': {'exact_finish': {'label': 'Exact roll to finish'}, 'turn_timer_sec': {'label': 'Turn timer', 'values': [20, 30, 45]}},
        'exact_finish': true,
        'timer': {'allowed_turn_seconds': [20, 30, 45], 'max_timeouts': 5, 'turn_ms': 30000},
      },
    });
    expect(casual.friends, isTrue);
    expect(casual.hostOptions.map((o) => o.key), ['exact_finish', 'extra_turn_on_six', 'capture_sends_home', 'powerups_enabled']);
    expect(casual.allowedTurnSeconds, [20, 30, 45]);
    expect((casual.turnSeconds, casual.maxTimeouts), (30, 5));
    final quick = RoomMode.fromJson({'id': 1, 'code': 'quick_50', 'player_count': 4, 'mode_config': {'timer': {'max_timeouts': 3, 'turn_ms': 30000}}});
    final cat = RoomCatalogue(gameId: 25, modes: [quick, casual], stakes: const [
      RoomStake(modeId: 1, currency: 'gold', amount: 25),
      RoomStake(modeId: 1, currency: 'gold', amount: 10),
      RoomStake(modeId: 143, currency: 'token', amount: 50),
    ]);
    expect(cat.stakesFor(quick, 'gold'), [10, 25]);
    expect(cat.stakesFor(quick, 'token'), isEmpty);
    expect(cat.mode(snlQuickMode)!.maxTimeouts, 3);
    expect(cat.friendsModes.single.code, snlFriendsMode);
  });
}
