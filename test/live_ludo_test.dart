// Live online Ludo against the running server (docs/services/ludo.md), with
// two fresh guest accounts. Skipped unless both addresses are given:
//
//   flutter test test/live_ludo_test.dart \
//     --dart-define=LIVE_API=http://192.168.0.235:1280/api/v1 \
//     --dart-define=LIVE_LUDO_WS=ws://192.168.0.235:1285/ws
//
// A creates a friends room, B joins with the code, both ready, real turns
// are played (rolls and moves), chat goes both ways, B gives up → A wins,
// then A asks for a rematch and B joins it. Prints only game events.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/ludo/online/ludo_controller.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/auth_service.dart';
import 'package:snakeladder/services/socket/socket_client.dart';

const _api = String.fromEnvironment('LIVE_API');
const _ws = String.fromEnvironment('LIVE_LUDO_WS');

/// Demo: the room code for the second player to join.
const _join = String.fromEnvironment('LIVE_LUDO_JOIN');

Future<(LudoController, SocketClient, String)> _player() async {
  final auth = RemoteAuthService(ApiClient(dio: Dio(BaseOptions(baseUrl: '$_api/', contentType: 'application/json'))));
  final g = await auth.loginGuest();
  final (c, socket) = await _signIn(g.accessToken, g.user.id);
  _tokens[g.user.id] = g.accessToken;
  return (c, socket, g.user.username);
}

final _tokens = <String, String>{};

/// A fresh socket + controller for a signed-in player (what a page reload
/// or a cold start does). Frames that arrive during sign-in are buffered and
/// replayed into the controller, as the app's socket does for resumes.
Future<(LudoController, SocketClient)> _signIn(String token, String userId) async {
  final socket = SocketClient(url: Uri.parse(_ws), requestTimeout: const Duration(seconds: 8));
  final early = <SocketMessage>[];
  final sub = socket.broadcasts.listen(early.add);
  await socket.connect();
  await socket.login(token: token);
  await Future<void>.delayed(const Duration(milliseconds: 800));
  await sub.cancel();
  final c = LudoController(
    request: socket.request,
    events: socket.broadcasts,
    myUserId: userId,
    serverNow: socket.serverNow,
  );
  early.forEach(c.handle);
  return (c, socket);
}

/// Waits until [ok] holds (re-checked on every change).
Future<void> _until(LudoController c, bool Function() ok, {Duration timeout = const Duration(seconds: 15)}) async {
  if (ok()) return;
  final done = Completer<void>();
  void check() {
    if (ok() && !done.isCompleted) done.complete();
  }

  c.addListener(check);
  try {
    await done.future.timeout(timeout);
  } finally {
    c.removeListener(check);
  }
}

void main() {
  test('a page reload mid-game: a fresh socket signs in and is back in the same game', () async {
    final (a, sa, _) = await _player();
    final (b, sb, _) = await _player();
    // ignore: avoid_print
    void log(String s) => print('[LUDO] $s');
    expect(await a.createRoom(modeCode: 'friends_room', maxPlayers: 2, turnSeconds: 15), isTrue);
    expect(await b.joinRoom(a.room!.roomCode), isTrue);
    await a.ready();
    await b.ready();
    await _until(a, () => a.phase == LudoPhase.game);
    final match = a.state!.matchId;
    log('game $match started');

    // "Reload": A's tab drops its socket without leaving the room.
    final aId = a.myUserId;
    a.dispose();
    await sa.close();
    log('A dropped (reload)');
    await _until(b, () => b.away.containsKey(aId), timeout: const Duration(seconds: 10));
    log('B sees A as away (reconnecting)');

    // The reloaded page signs in on a new socket within the 30 s window.
    final (a2, sa2) = await _signIn(_tokens[aId]!, aId);
    await _until(a2, () => a2.phase == LudoPhase.game, timeout: const Duration(seconds: 10));
    expect(a2.state!.matchId, match, reason: 'the same game, not a new one');
    expect(a2.readOnly, isFalse);
    log('A is back in game ${a2.state!.matchId} (state_sync), turn: ${a2.nameOf(a2.state!.currentTurnUserId)}');
    await _until(b, () => !b.away.containsKey(aId), timeout: const Duration(seconds: 10));
    log('B sees A back');

    await b.forfeit();
    await _until(a2, () => a2.phase == LudoPhase.result);
    a2.dispose();
    b.dispose();
    await sa2.close();
    await sb.close();
  }, timeout: const Timeout(Duration(minutes: 2)), skip: _api.isEmpty || _ws.isEmpty ? 'set LIVE_API and LIVE_LUDO_WS' : false);

  test('two players: room, ready, turns, chat, forfeit, result, rematch', () async {
    final (a, sa, nameA) = await _player();
    final (b, sb, nameB) = await _player();
    // ignore: avoid_print
    void log(String s) => print('[LUDO] $s');
    log('A = $nameA, B = $nameB');

    // A creates a free 2-seat friends room.
    expect(await a.createRoom(modeCode: 'friends_room', maxPlayers: 2, turnSeconds: 15), isTrue);
    final code = a.room!.roomCode;
    log('A created room $code (seat ${a.room!.seat}, ${a.room!.color.name})');
    expect(code, hasLength(8));

    // B joins with the code (upper case works too).
    expect(await b.joinRoom(code.toUpperCase()), isTrue);
    log('B joined, seat ${b.room!.seat} (${b.room!.color.name})');
    await _until(a, () => a.room!.players.length == 2);
    log('A sees ${a.room!.players.map((p) => p.username).join(' + ')}');

    // Both ready → game.started for both.
    await a.ready();
    await b.ready();
    await _until(a, () => a.phase == LudoPhase.game);
    await _until(b, () => b.phase == LudoPhase.game);
    log('game.started: ${a.state!.players.length} players, first turn ${a.nameOf(a.state!.currentTurnUserId)}');
    expect(a.board!.colors, hasLength(2));
    expect(a.turnLeft, isNotNull, reason: 'a turn timer runs');

    // Quick chat both ways.
    await a.sendChat('Good luck!');
    await _until(b, () => b.chat.any((l) => l.message == 'Good luck!'));
    await b.sendChat('Thanks!');
    await _until(a, () => a.chat.any((l) => l.message == 'Thanks!'));
    log('chat: "${b.chat.last.message}" reached B, "${a.chat.last.message}" reached A');

    // Play real turns: whoever's turn rolls, and moves when asked.
    var actions = 0;
    var moves = 0;
    while (actions < 12) {
      final turn = a.myTurn ? a : (b.myTurn ? b : null);
      if (turn == null) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      final who = identical(turn, a) ? 'A' : 'B';
      final updates = turn.state!.turnNumber;
      if (turn.canMove && turn.moveable.isNotEmpty) {
        await turn.move(turn.moveable.first);
        moves++;
      } else if (turn.canRoll) {
        await turn.roll();
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      actions++;
      // The state update reaches both players.
      await _until(a, () => a.lastAction != null);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      turn.board?.clearPending();
      (identical(turn, a) ? b : a).board?.clearPending();
      log('$who: ${turn.board!.lastText}${updates != turn.state!.turnNumber ? '' : ''}');
    }
    log('$actions actions played ($moves pawn moves)');
    expect(a.state!.players.map((p) => p.pawns.length), everyElement(4));

    // B gives up → A wins; both see the result.
    await b.forfeit();
    await _until(a, () => a.phase == LudoPhase.result);
    await _until(b, () => b.phase == LudoPhase.result);
    log('result: winner ${a.nameOf(a.state!.winner)}, places ${a.standings.map((p) => '${a.nameOf(p.userId)} #${p.place}').join(', ')}');
    expect(a.iWon, isTrue);
    expect(b.iWon, isFalse);

    // Rematch: A asks, B sees the offer and joins.
    await a.rematch();
    expect(a.phase, LudoPhase.room);
    await _until(b, () => b.rematchOffer != null);
    log('B sees: ${b.nameOf(b.rematchOffer!.fromUserId)} wants a rematch (room ${b.rematchOffer!.roomCode})');
    await b.acceptRematch();
    await _until(a, () => a.room!.players.length == 2);
    log('rematch room ${a.room!.roomCode}: ${a.room!.players.map((p) => p.username).join(' + ')}');

    await a.leave();
    await b.leave();
    a.dispose();
    b.dispose();
    await sa.close();
    await sb.close();
  }, timeout: const Timeout(Duration(minutes: 3)), skip: _api.isEmpty || _ws.isEmpty ? 'set LIVE_API and LIVE_LUDO_WS' : false);

  // A second player for a demo in the app: joins LIVE_LUDO_JOIN, readies, and
  // plays its own turns until the game ends (or 5 minutes pass).
  test('second player joins a room code and plays', () async {
    final (b, sb, name) = await _player();
    // ignore: avoid_print
    void log(String s) => print('[LUDO-B] $s');
    expect(await b.joinRoom(_join), isTrue, reason: b.notice?.text);
    log('$name joined room $_join as ${b.room!.color.name}');
    await b.ready();
    await b.sendChat('Good luck!');
    await _until(b, () => b.phase == LudoPhase.game, timeout: const Duration(minutes: 3));
    log('game started');
    final end = DateTime.now().add(const Duration(minutes: 5));
    while (b.phase == LudoPhase.game && DateTime.now().isBefore(end)) {
      b.board?.clearPending();
      if (b.canMove && b.moveable.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await b.move(b.moveable.first);
        log(b.board!.lastText);
      } else if (b.canRoll) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        await b.roll();
        log(b.board!.lastText);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    log('done: ${b.phase.name}${b.state?.winner == null ? '' : ', winner ${b.nameOf(b.state!.winner)}'}');
    b.dispose();
    await sb.close();
  }, timeout: const Timeout(Duration(minutes: 9)), skip: _api.isEmpty || _ws.isEmpty || _join.isEmpty ? 'set LIVE_LUDO_JOIN' : false);
}
