// Live matchmaking and rooms against the running Ludo server
// (docs/services/05-matchmaking-and-rooms.md), with fresh guest accounts.
// Skipped unless both addresses are given:
//
//   flutter test test/live_lobby_test.dart \
//     --dart-define=LIVE_API=http://192.168.0.235:1280/api/v1 \
//     --dart-define=LIVE_LUDO_WS=ws://192.168.0.235:1285/ws

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/game_catalogue.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/auth_service.dart';
import 'package:snakeladder/services/lobby/game_lobby.dart';
import 'package:snakeladder/services/lobby/live_rooms.dart';
import 'package:snakeladder/services/lobby/lobby_controller.dart';
import 'package:snakeladder/services/lobby/lobby_models.dart';
import 'package:snakeladder/services/socket/socket_client.dart';

const _api = String.fromEnvironment('LIVE_API');
const _ws = String.fromEnvironment('LIVE_LUDO_WS');

class _P {
  _P(this.c, this.socket, this.api);
  final LobbyController c;
  final SocketClient socket;
  final ApiClient api;
}

Future<_P> _player() async {
  final api = ApiClient(dio: Dio(BaseOptions(baseUrl: '$_api/', contentType: 'application/json')));
  final g = await RemoteAuthService(api).loginGuest();
  api.authToken = g.accessToken;
  final socket = SocketClient(url: Uri.parse(_ws), requestTimeout: const Duration(seconds: 8));
  await socket.connect();
  await socket.login(token: g.accessToken);
  final c = LobbyController(lobby: SocketGameLobby.onSocket('ludo', socket), myUserId: g.user.id);
  return _P(c, socket, api);
}

Future<void> _until(LobbyController c, bool Function() ok, {Duration timeout = const Duration(seconds: 15)}) async {
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

const _casual2p = GameMode(id: 0, code: 'casual_2p', name: 'Casual 2', playerCount: 2, minPlayers: 2);
const _casual4p = GameMode(id: 0, code: 'casual_4p', name: 'Casual 4', playerCount: 4, minPlayers: 2);
const _friends = GameMode(id: 0, code: 'friends_room', name: 'Friends', playerCount: 4, minPlayers: 2, hostCanChoose: ['safe_squares']);
const _nope = GameMode(id: 0, code: 'nope_mode', name: '', playerCount: 2, minPlayers: 2);

PlaySelection _sel(GameMode m, {int stake = 0}) =>
    PlaySelection(gameCode: 'ludo', modeCode: m.code, currency: stake > 0 ? 'token' : null, betAmount: stake);

void main() {
  final skip = _api.isEmpty || _ws.isEmpty ? 'set LIVE_API and LIVE_LUDO_WS' : null;

  test('flows A, B, C and the errors', () async {
    final a = await _player();
    final b = await _player();
    try {
      // Modes and the 4-seat lobby (player_count is always sent).
      expect(await a.c.quickMatch(_casual4p, _sel(_casual4p)), isTrue);
      expect(a.c.seat!.maxPlayers, 4);
      // ignore: avoid_print
      print('A searching in ${a.c.seat!.roomCode} (4 seats)');

      // Flow C: B sees A's lobby in the open tables list.
      await b.c.refreshOpenRooms(force: true);
      // ignore: avoid_print
      print('B open tables: ${[for (final r in b.c.openRooms) '${r.modeCode} ${r.players}/${r.maxPlayers} ${r.matchmaking}']}');
      expect(b.c.openRooms.any((r) => r.roomCode == a.c.seat!.roomCode), isTrue);
      await a.c.cancelSearch();
      expect(a.c.phase, LobbyPhase.idle);

      // Flow B: create (listed), wrong code, join in upper case, both ready.
      expect(await a.c.createRoom(_friends, _sel(_friends), const RoomOptions(maxPlayers: 2, listed: true)), isTrue);
      final code = a.c.seat!.displayCode;
      expect(await b.c.joinByCode('ZZZZZZZZ'), isFalse);
      expect(b.c.failure!.text, 'No room with that code.');
      expect(await b.c.joinByCode(code), isTrue);
      await _until(a.c, () => a.c.seat?.isFull ?? false);
      // match.cancel in a private room is refused → the controller leaves instead.
      try {
        await a.c.lobby.cancelSearch();
        fail('match.cancel should be refused in a private room');
      } on LobbyFailure catch (f) {
        expect(f.error, LobbyError.invalidState);
      }
      await a.c.setReady(true);
      await b.c.setReady(true);
      await _until(a.c, () => a.c.phase == LobbyPhase.inGame);
      await _until(b.c, () => b.c.phase == LobbyPhase.inGame);
      // One room at a time.
      try {
        await a.c.lobby.quickMatch(_casual2p, _sel(_casual2p));
        fail('match.find in a game should be refused');
      } on LobbyFailure catch (f) {
        expect(f.error, LobbyError.invalidState);
      }
      await a.c.leave(); // a forfeit
      await b.c.leave();

      // Stakes and modes.
      expect(await a.c.quickMatch(_casual2p, _sel(_casual2p, stake: 99999999)), isFalse);
      expect(a.c.failure!.error, LobbyError.insufficientFunds);
      expect(await a.c.quickMatch(_nope, _sel(_nope)), isFalse);
      expect(a.c.failure!.error, LobbyError.invalidMode);

      // Flow A: two humans meet at one table.
      expect(await a.c.quickMatch(_casual2p, _sel(_casual2p)), isTrue);
      expect(await b.c.quickMatch(_casual2p, _sel(_casual2p)), isTrue);
      // ignore: avoid_print
      print('A ${a.c.phase} ${a.c.seat?.roomCode} · B ${b.c.phase} ${b.c.seat?.roomCode}');
      await _until(a.c, () => a.c.phase == LobbyPhase.inGame, timeout: const Duration(seconds: 20));
      await _until(b.c, () => b.c.phase == LobbyPhase.inGame);
      await a.c.leave();
      await b.c.leave();

      // Bingo live rooms over the gateway.
      final rooms = await LiveRoomsApi(a.api).list();
      // ignore: avoid_print
      print('live rooms: ${rooms.length} (${rooms.map((r) => r.name).take(3).join(', ')})');
      expect(rooms.every((r) => r.isActive), isTrue);
    } finally {
      a.socket.dispose();
      b.socket.dispose();
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('quick match alone: a bot or the no-players prompt', () async {
    final a = await _player();
    try {
      expect(await a.c.quickMatch(_casual2p, _sel(_casual2p)), isTrue);
      await Future<void>.delayed(const Duration(seconds: 8));
      // ignore: avoid_print
      print('after 8 s: ${a.c.phase}, players ${[for (final p in a.c.seat?.players ?? <SeatPlayer>[]) '${p.username}${p.isBot ? ' (bot)' : ''}']}');
      if (a.c.phase != LobbyPhase.searching) await a.c.leave();
      if (a.c.phase == LobbyPhase.searching) await a.c.cancelSearch();
      expect(a.c.phase, LobbyPhase.idle);
    } finally {
      a.socket.dispose();
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 1)));
}
