// End-to-end chess check against the live services, with two real accounts.
//
// Logs both accounts in through the API gateway, then plays a FREE game on
// chess-service (stake 0 — no wallet change):
//   connect → auth.login (token) → A room.create → B room.join → both ready
//   → game.started → White e2-e4 → Black e7-e5 → Black resigns
//   → game.completed → both room.leave
//
// Run (passwords are asked at a hidden prompt — never pass them as args):
//   dart run tools/chess_flow_test.dart <emailA> <emailB>
//
// Host and ports come from lib/configs (gateway 31294, chess 31283).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:snakeladder/configs/environment.dart';
import 'package:snakeladder/configs/games/chess/chess_config.dart';

final _server = currentEnvironment.server;
final _chessWs = _server.socketUrl(chessConfig.port, chessConfig.socketPath);

String _mask(String s) =>
    s.replaceAllMapped(RegExp(r'"(token|refresh_token|access_token)"\s*:\s*"([^"]{6})[^"]*"'), (m) => '"${m[1]}":"${m[2]}…"');

String _prompt(String label) {
  stdout.write(label);
  stdin.echoMode = false;
  final v = stdin.readLineSync() ?? '';
  stdin.echoMode = true;
  stdout.writeln();
  return v;
}

Future<String> _login(String email, String password) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('${_server.apiBaseUrl}/auth/login'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'email': email, 'password': password}));
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    if (res.statusCode != 200) throw 'login $email → ${res.statusCode} ${_mask(body)}';
    return (jsonDecode(body) as Map)['access_token'] as String;
  } finally {
    client.close();
  }
}

class _Player {
  _Player(this.name);
  final String name;
  late WebSocket ws;
  int _id = 0;
  final _pending = <String, Completer<Map>>{};
  final _pushes = StreamController<Map>.broadcast();

  Future<void> open() async {
    ws = await WebSocket.connect(_chessWs);
    final established = Completer<void>();
    ws.listen((raw) {
      final m = jsonDecode(raw as String) as Map;
      final text = _mask(raw);
      stdout.writeln('  [$name] << ${text.length > 240 ? '${text.substring(0, 240)}…' : text}');
      if (m['event'] == 'connection.established' && !established.isCompleted) established.complete();
      final id = m['id'];
      if (id != null && _pending.containsKey(id)) {
        _pending.remove(id)!.complete(m);
      } else {
        _pushes.add(m);
      }
    }, onDone: () => stdout.writeln('  [$name] closed (${ws.closeCode})'));
    await established.future.timeout(const Duration(seconds: 6));
  }

  Future<Map> req(String event, [Map data = const {}]) {
    final id = '$name-${_id++}';
    final c = Completer<Map>();
    _pending[id] = c;
    final frame = jsonEncode({'id': id, 'event': event, 'data': data});
    stdout.writeln('  [$name] >> ${_mask(frame)}');
    ws.add(frame);
    return c.future.timeout(const Duration(seconds: 8), onTimeout: () => {'event': 'TIMEOUT', 'for': event});
  }

  Future<Map> next(String event) => _pushes.stream
      .firstWhere((m) => m['event'] == event)
      .timeout(const Duration(seconds: 10), onTimeout: () => {'event': 'TIMEOUT', 'waiting': event});
}

void _check(bool ok, String step) {
  stdout.writeln(ok ? '✅ $step' : '❌ $step');
  if (!ok) exit(1);
}

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: dart run tools/chess_flow_test.dart <emailA> <emailB>');
    exit(64);
  }
  stdout.writeln('Gateway ${_server.apiBaseUrl} · chess $_chessWs\n');
  final tokenA = await _login(args[0], _prompt('Password for ${args[0]}: '));
  final tokenB = await _login(args[1], _prompt('Password for ${args[1]}: '));
  _check(true, 'Gateway login (both accounts)');

  final a = _Player('A'), b = _Player('B');
  await a.open();
  await b.open();
  _check(true, 'Socket connected (connection.established)');

  _check((await a.req('auth.login', {'token': tokenA}))['event'] == 'auth.login_success' &&
      (await b.req('auth.login', {'token': tokenB}))['event'] == 'auth.login_success', 'auth.login with gateway tokens');

  final created = await a.req('room.create', {'currency': 'token', 'bet_amount': 0});
  final code = (created['data'] as Map?)?['room_code'];
  _check(created['event'] == 'room.created' && code != null, 'A created a free room ($code)');

  _check((await b.req('room.join', {'room_code': code}))['event'] == 'room.joined', 'B joined the room');

  final started = a.next('game.started');
  await a.req('player.ready');
  await b.req('player.ready');
  _check((await started)['event'] == 'game.started', 'Both ready → game.started');

  // A created the room → seat 0 → White.
  final reply1 = b.next('game.state_update');
  final ack1 = await a.req('game.action', {'action_type': 'move', 'from': 'e2', 'to': 'e4'});
  _check(ack1['event'] == 'game.action_ack' && (await reply1)['event'] == 'game.state_update', 'White e2-e4 (ack + opponent update)');

  final reply2 = a.next('game.state_update');
  final ack2 = await b.req('game.action', {'action_type': 'move', 'from': 'e7', 'to': 'e5'});
  _check(ack2['event'] == 'game.action_ack' && (await reply2)['event'] == 'game.state_update', 'Black e7-e5 (ack + opponent update)');

  final done = a.next('game.completed');
  await b.req('game.action', {'action_type': 'resign'});
  final completed = await done;
  _check(completed['event'] == 'game.completed', 'Black resigned → game.completed (${(completed['data'] as Map?)?['result']})');

  await a.req('room.leave');
  await b.req('room.leave');
  await a.ws.close();
  await b.ws.close();
  stdout.writeln('\nAll chess API + socket checks passed.');
  exit(0);
}
