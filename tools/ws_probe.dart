// Dev-only: find which gateway path actually serves the chess WebSocket.
//
// The gateway checks auth BEFORE routing, so without a valid token every
// /api/v1/* path answers 401 — even ones that don't exist. With a real access
// token, a missing route turns into 404 and the real one into 101.
//
// Run (token = access_token from /auth/login; the cors_proxy log prints it):
//   dart run tools/ws_probe.dart <access_token> [username]
// Optional: WS_HOST=host:port (default 169.58.184.121:30080).
//
// For every candidate path it tries the token as a Bearer header and as a
// ?token= query param. On a 101 it runs the Chess API handshake:
// connection.established → auth.login {token, username} → prints the reply.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _paths = [
  '/ws',
  '/api/v1/ws',
  '/api/v1/chess/ws',
  '/api/v1/games/chess/ws',
  '/api/v1/games/ws',
  '/api/v1/realtime',
  '/api/v1/socket',
  '/chess/ws',
];

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tools/ws_probe.dart <access_token> [username]');
    exit(64);
  }
  final token = args[0];
  final username = args.length > 1 ? args[1] : null;
  final host = Platform.environment['WS_HOST'] ?? '169.58.184.121:30080';

  // The gateway has /api/v1/games/{i64}/… routes, so the socket may be per
  // game. Look the games up and add per-id candidates (chess first).
  final paths = [..._paths, ...await _gamePaths(host, token)];
  for (final path in paths) {
    for (final mode in ['header', 'query']) {
      final uri = Uri.parse('ws://$host$path${mode == 'query' ? '?token=${Uri.encodeQueryComponent(token)}' : ''}');
      final headers = mode == 'header' ? {'Authorization': 'Bearer $token'} : <String, dynamic>{};
      final (status, body) = await _status(uri, headers);
      stdout.writeln('${path.padRight(30)} $mode  -> $status ${body.length > 120 ? body.substring(0, 120) : body}');
      if (status == 101) await _handshake(uri, headers, token, username);
    }
  }
}

Future<List<String>> _gamePaths(String host, String token) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final r = await client.getUrl(Uri.parse('http://$host/api/v1/games'));
    r.headers.set('Authorization', 'Bearer $token');
    final res = await r.close();
    final body = await utf8.decodeStream(res);
    stdout.writeln('GET /api/v1/games -> ${res.statusCode} ${body.length > 400 ? '${body.substring(0, 400)}…' : body}');
    final j = jsonDecode(body);
    final list = (j is Map ? j['data'] : j) as List? ?? const [];
    final games = list.whereType<Map>().toList()
      ..sort((a, b) => '${b['name']}${b['slug']}'.toLowerCase().contains('chess') ? 1 : -1);
    final out = <String>[];
    for (final g in games.take(3)) {
      final id = g['id'];
      stdout.writeln('  game id=$id name=${g['name'] ?? g['slug']}');
      for (final suffix in ['ws', 'socket', 'connect', 'play']) {
        out.add('/api/v1/games/$id/$suffix');
      }
    }
    return out;
  } catch (e) {
    stdout.writeln('GET /api/v1/games failed: $e');
    return const [];
  } finally {
    client.close(force: true);
  }
}

Future<(int, String)> _status(Uri wsUri, Map<String, dynamic> headers) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final r = await client.getUrl(wsUri.replace(scheme: 'http'));
    headers.forEach((k, v) => r.headers.set(k, v));
    r.headers
      ..set('Connection', 'Upgrade')
      ..set('Upgrade', 'websocket')
      ..set('Sec-WebSocket-Version', '13')
      ..set('Sec-WebSocket-Key', 'dGhlIHNhbXBsZSBub25jZQ==');
    final res = await r.close();
    if (res.statusCode == 101) return (101, '');
    final body = await utf8.decodeStream(res).timeout(const Duration(seconds: 5), onTimeout: () => '');
    return (res.statusCode, body.trim());
  } catch (e) {
    return (0, '$e');
  } finally {
    client.close(force: true);
  }
}

Future<void> _handshake(Uri uri, Map<String, dynamic> headers, String token, String? username) async {
  final WebSocket ws;
  try {
    ws = await WebSocket.connect(uri.toString(), headers: headers);
  } catch (e) {
    stdout.writeln('    connect failed: $e');
    return;
  }
  final done = Completer<void>();
  ws.listen((f) {
    stdout.writeln('    << $f');
    final m = jsonDecode(f as String) as Map;
    if (m['event'] == 'connection.established') {
      ws.add(jsonEncode({
        'id': 'probe_1',
        'event': 'auth.login',
        'data': {'token': token, 'username': ?username},
      }));
      stdout.writeln('    >> auth.login');
    } else if ((m['event'] as String).startsWith('auth.') && !done.isCompleted) {
      done.complete();
    }
  }, onDone: () {
    stdout.writeln('    closed (${ws.closeCode} ${ws.closeReason})');
    if (!done.isCompleted) done.complete();
  });
  await done.future.timeout(const Duration(seconds: 8), onTimeout: () => stdout.writeln('    (no auth reply in 8s)'));
  await ws.close();
}
