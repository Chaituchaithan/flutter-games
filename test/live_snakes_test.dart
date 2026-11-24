// Live online Snake & Ladder against the running server
// (docs/services/snake-and-ladder.md), with fresh guest accounts. Skipped
// unless both addresses are given:
//
//   flutter test test/live_snakes_test.dart \
//     --dart-define=LIVE_API=http://192.168.0.235:1280/api/v1 \
//     --dart-define=LIVE_SNAKES_WS=ws://192.168.0.235:1292/ws
//
// Covers: a friends room created and joined by code, both ready, a Quick 50
// game played to the real finish; a reconnect mid-game (state_sync); a Duel
// ended by a forfeit (result from game.player_forfeited alone) and a
// rematch; the bet ladder. Prints only game events, never tokens.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/snakes/online/snakes_online_controller.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/auth_service.dart';
import 'package:snakeladder/services/socket/socket_client.dart';

const _api = String.fromEnvironment('LIVE_API');
const _ws = String.fromEnvironment('LIVE_SNAKES_WS');

/// Demo: a room code for a second player to join and play.
const _join = String.fromEnvironment('LIVE_SNAKES_JOIN');

const _skip = _api == '' || _ws == '' ? 'set LIVE_API and LIVE_SNAKES_WS' : false;

final _tokens = <String, String>{};

// ignore: avoid_print
void _log(String s) => print('[SNL] $s');

Future<(SnlController, SocketClient, String)> _player() async {
  final auth = RemoteAuthService(ApiClient(dio: Dio(BaseOptions(baseUrl: '$_api/', contentType: 'application/json'))));
  final g = await auth.loginGuest();
  _tokens[g.user.id] = g.accessToken;
  final (c, socket) = await _signIn(g.accessToken, g.user.id);
  return (c, socket, g.user.username);
}

/// A fresh socket + controller for a signed-in player (what a cold start
/// does). Frames that arrive during sign-in are replayed into the controller.
Future<(SnlController, SocketClient)> _signIn(String token, String userId) async {
  final socket = SocketClient(url: Uri.parse(_ws), requestTimeout: const Duration(seconds: 8));
  final early = <SocketMessage>[];
  final sub = socket.broadcasts.listen(early.add);
  await socket.connect();
  await socket.login(token: token);
  await Future<void>.delayed(const Duration(milliseconds: 800));
  await sub.cancel();
  final c = SnlController(request: socket.request, events: socket.broadcasts, myUserId: userId, serverNow: socket.serverNow);
  early.forEach(c.handle);
  return (c, socket);
}

Future<void> _until(SnlController c, bool Function() ok, {Duration timeout = const Duration(seconds: 15)}) async {
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

/// Both players roll on their turns until [stop] or the game ends.
Future<int> _play(SnlController a, SnlController b, {int maxRolls = 400, bool Function()? stop}) async {
  var rolls = 0;
  final end = DateTime.now().add(const Duration(minutes: 4));
  while (a.phase == RoomPhase.game && b.phase == RoomPhase.game && rolls < maxRolls && DateTime.now().isBefore(end)) {
    if (stop?.call() ?? false) break;
    a.board?.clearPending();
    b.board?.clearPending();
    final turn = a.canRoll ? a : (b.canRoll ? b : null);
    if (turn == null) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      continue;
    }
    final n = turn.state!.turnNumber;
    await turn.roll();
    rolls++;
    try {
      await _until(turn, () => turn.state!.turnNumber != n || turn.phase != RoomPhase.game, timeout: const Duration(seconds: 5));
    } on TimeoutException {
      _log('no state update after a roll (turn ${turn.state?.turnNumber})');
    }
    if (rolls <= 12 || turn.phase != RoomPhase.game) _log('${identical(turn, a) ? 'A' : 'B'}: ${turn.board?.lastText}');
  }
  return rolls;
}

void main() {
  test('friends room by code, both ready, a Quick 50 game to the real finish', () async {
    final (a, sa, nameA) = await _player();
    final (b, sb, nameB) = await _player();
    _log('A = $nameA, B = $nameB');

    final offer = await a.loadBetOptions('gold');
    _log('bet ladder (gold): ${offer == null ? 'none' : '${offer.bets.map((x) => '${x.amount}${x.locked ? '(locked)' : ''}').join(', ')}, default ${offer.defaultBet}'}');

    expect(await a.createRoom(modeCode: 'quick_friends', maxPlayers: 2, turnTimerSec: 20), isTrue, reason: a.notice?.text);
    final code = a.room!.roomCode;
    _log('A created room $code; board from room.created: ${a.previewBoard?.size} squares, ${a.previewBoard?.snakes.length} snakes');
    expect(code, hasLength(8));
    expect(a.room!.raw['board'], isNotNull, reason: 'room.created carries the board');

    expect(await b.joinRoom(code.toUpperCase()), isTrue, reason: b.notice?.text);
    _log('B joined seat ${b.room!.seat}');
    await _until(a, () => a.room!.players.length == 2);

    await a.ready();
    await b.ready();
    await _until(a, () => a.phase == RoomPhase.game);
    await _until(b, () => b.phase == RoomPhase.game);
    final st = a.state!;
    _log('game.started: board ${st.board?.size}, turn ${a.nameOf(st.currentTurnUserId)}, deadline in ${a.turnLeft?.inSeconds}s, ring ${a.turnRingMs} ms');
    expect(st.board, isNotNull);
    expect(a.turnLeft, isNotNull);

    await a.sendChat('Good luck!');
    await _until(b, () => b.chat.any((l) => l.message == 'Good luck!'));
    _log('chat reached B');

    final rolls = await _play(a, b);
    await _until(a, () => a.phase == RoomPhase.result, timeout: const Duration(seconds: 10));
    await _until(b, () => b.phase == RoomPhase.result, timeout: const Duration(seconds: 10));
    _log('finished after $rolls rolls: winner ${a.nameOf(a.state!.winner)}, places ${a.standings.map((p) => a.nameOf(p.userId)).join(', ')}, seed ${a.state!.diceSeed != null ? 'shown' : 'missing'}');
    expect(a.iWon != b.iWon, isTrue);

    await a.leave();
    await b.leave();
    a.dispose();
    b.dispose();
    await sa.close();
    await sb.close();
  }, timeout: const Timeout(Duration(minutes: 6)), skip: _skip);

  test('a reconnect mid-game: a fresh socket signs in and is back in the same game', () async {
    final (a, sa, _) = await _player();
    final (b, sb, _) = await _player();
    expect(await a.createRoom(modeCode: 'quick_friends', maxPlayers: 2, turnTimerSec: 45), isTrue, reason: a.notice?.text);
    expect(await b.joinRoom(a.room!.roomCode), isTrue);
    await a.ready();
    await b.ready();
    await _until(a, () => a.phase == RoomPhase.game);
    await _play(a, b, maxRolls: 4);
    final match = a.state!.matchId;
    final aId = a.myUserId;
    a.dispose();
    await sa.close();
    _log('A dropped');
    await _until(b, () => b.away.containsKey(aId), timeout: const Duration(seconds: 10));
    _log('B sees A away');

    final (a2, sa2) = await _signIn(_tokens[aId]!, aId);
    await _until(a2, () => a2.phase == RoomPhase.game, timeout: const Duration(seconds: 10));
    expect(a2.state!.matchId, match);
    expect(a2.readOnly, isFalse);
    _log('A back in $match (state_sync); B is "${a2.nameOf(b.myUserId)}" (no names in the state)');
    await _until(b, () => !b.away.containsKey(aId), timeout: const Duration(seconds: 10));
    _log('B sees A back');

    await b.forfeit();
    await _until(a2, () => a2.phase == RoomPhase.result);
    expect(a2.iWon, isTrue);
    a2.dispose();
    b.dispose();
    await sa2.close();
    await sb.close();
  }, timeout: const Timeout(Duration(minutes: 3)), skip: _skip);

  test('Duel: a forfeit ends it (result from game.player_forfeited), then a rematch', () async {
    final (a, sa, _) = await _player();
    final (b, sb, _) = await _player();
    expect(await a.createRoom(modeCode: 'duel_casual', maxPlayers: 2, turnTimerSec: 20, rules: {'rematch_allowed': true}), isTrue, reason: a.notice?.text);
    expect(a.rematchAllowed, isTrue);
    expect(await b.joinRoom(a.room!.roomCode), isTrue);
    await a.ready();
    await b.ready();
    await _until(a, () => a.phase == RoomPhase.game);
    await _play(a, b, maxRolls: 6);

    final frames = <String>[];
    final sub = sa.broadcasts.listen((m) => frames.add(m.event));
    await b.forfeit();
    await _until(a, () => a.phase == RoomPhase.result);
    await _until(b, () => b.phase == RoomPhase.result);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await sub.cancel();
    _log('after the forfeit A got: ${frames.join(', ')}');
    expect(a.iWon, isTrue);
    expect(b.iWon, isFalse);

    await a.rematch();
    expect(a.phase, RoomPhase.room, reason: a.notice?.text);
    await _until(b, () => b.rematchOffer != null);
    expect(a.rematchOffer, isNull, reason: 'the asker sees no offer');
    _log('B sees: ${b.nameOf(b.rematchOffer!.fromUserId)} wants a rematch (${b.rematchOffer!.roomCode})');
    await b.acceptRematch();
    await _until(a, () => a.room!.players.length == 2);
    _log('rematch room ${a.room!.roomCode}: ${a.room!.players.map((p) => p.username).join(' + ')}');

    await a.leave();
    await b.leave();
    a.dispose();
    b.dispose();
    await sa.close();
    await sb.close();
  }, timeout: const Timeout(Duration(minutes: 3)), skip: _skip);

  test('quick match: a bot fills the lobby (when the bot service runs)', () async {
    final (a, sa, _) = await _player();
    await a.quickMatch(modeCode: 'quick_50', playerCount: 2);
    expect(a.phase, RoomPhase.room, reason: a.notice?.text);
    try {
      await _until(a, () => a.phase == RoomPhase.game, timeout: const Duration(seconds: 15));
      _log('quick match started against ${a.nameOf(a.state!.players.firstWhere((p) => p.userId != a.myUserId).userId)}');
      await a.forfeit();
      await _until(a, () => a.phase == RoomPhase.result);
    } on TimeoutException {
      _log('no bot joined in 15 s (bot service off?)');
      await a.cancelSearch();
    }
    a.dispose();
    await sa.close();
  }, timeout: const Timeout(Duration(minutes: 2)), skip: _skip);

  // A second player for a demo in the app: joins LIVE_SNAKES_JOIN, readies,
  // and rolls its own turns until the game ends (or 5 minutes pass).
  test('second player joins a room code and plays', () async {
    final (b, sb, name) = await _player();
    expect(await b.joinRoom(_join), isTrue, reason: b.notice?.text);
    _log('$name joined room $_join');
    await b.ready();
    await _until(b, () => b.phase == RoomPhase.game, timeout: const Duration(minutes: 3));
    final end = DateTime.now().add(const Duration(minutes: 5));
    while (b.phase == RoomPhase.game && DateTime.now().isBefore(end)) {
      b.board?.clearPending();
      if (b.canRoll) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        await b.roll();
        _log(b.board?.lastText ?? '');
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    b.dispose();
    await sb.close();
  }, timeout: const Timeout(Duration(minutes: 9)), skip: _api == '' || _ws == '' || _join == '' ? 'set LIVE_SNAKES_JOIN' : false);
}
