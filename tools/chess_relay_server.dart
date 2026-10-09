// A tiny local WebSocket relay implementing the subset of the Chess API
// realtime protocol the app needs, so two clients (e.g. two Android emulators)
// can play a live game with no real backend.
//
// Run:  dart run tools/chess_relay_server.dart   (listens on 0.0.0.0:3112)
// Point the app at it:  --dart-define=CHESS_WS_URL=ws://10.0.2.2:3112/ws
//   (10.0.2.2 is the host loopback as seen from an Android emulator.)
//
// It does NOT validate chess moves — both clients run the same FIDE engine, so
// the server just relays each move's coordinates. Matchmaking pairs the two
// clients waiting on the same currency/bet; room create+join by code also work.
// Finish a game by resigning or agreeing a draw (no server-side mate detection).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

final _rng = Random();

/// Per-move time budget the relay enforces (mirrors the real server's per-move
/// clock: each turn starts fresh and times out if no move arrives in time).
const int kTurnLimitMs = 30000;

class Client {
  Client(this.ws);
  final WebSocket ws;
  String userId = '';
  String? matchKey; // currency:bet while searching

  void sendEvent(String event, Map<String, dynamic> data, {String? id}) {
    final env = <String, dynamic>{'event': event, 'data': data};
    if (id != null) env['id'] = id;
    ws.add(jsonEncode(env));
  }

  void sendError(String id, String code, String message) {
    ws.add(jsonEncode({
      'id': id,
      'event': 'error',
      'data': const {},
      'error': {'code': code, 'message': message},
    }));
  }
}

class Game {
  Game(this.code);
  final String code;
  Client? white;
  Client? black;
  final Set<String> ready = {};
  bool started = false;

  // Per-move clock state.
  String activeColor = 'white';
  int turnSeq = 0;
  Timer? turnTimer;

  Iterable<Client> get members => [white, black].whereType<Client>();
  Client? other(Client c) => c == white ? black : white;
  Client? clientFor(String color) => color == 'white' ? white : black;
}

final Map<WebSocket, Client> _clients = {};
final Map<WebSocket, Game> _gameOf = {};
final Map<String, Game> _roomsByCode = {};
final Map<String, Client> _waiting = {}; // matchKey -> waiting client

String _code() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return List.generate(6, (_) => alphabet[_rng.nextInt(alphabet.length)]).join();
}

void main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 3112);
  _log('Chess relay listening on ws://0.0.0.0:3112/ws  (emulator: ws://10.0.2.2:3112/ws)');
  await for (final req in server) {
    if (WebSocketTransformer.isUpgradeRequest(req)) {
      try {
        final ws = await WebSocketTransformer.upgrade(req);
        _onConnect(ws);
      } catch (e) {
        _log('upgrade failed: $e');
      }
    } else {
      req.response
        ..statusCode = HttpStatus.ok
        ..write('chess relay ok')
        ..close();
    }
  }
}

void _onConnect(WebSocket ws) {
  final client = Client(ws);
  _clients[ws] = client;
  _log('client connected (${_clients.length} online)');
  // The app's SocketClient resolves connect() on this frame.
  client.sendEvent('connection.established', const {});
  ws.listen(
    (raw) => _onMessage(client, raw),
    onDone: () => _onDisconnect(client),
    onError: (_) => _onDisconnect(client),
    cancelOnError: false,
  );
}

void _onMessage(Client c, dynamic raw) {
  Map<String, dynamic> env;
  try {
    env = (jsonDecode(raw as String) as Map).cast<String, dynamic>();
  } catch (_) {
    return;
  }
  final id = env['id'] as String?;
  final event = env['event'] as String? ?? '';
  final data = (env['data'] as Map?)?.cast<String, dynamic>() ?? const {};

  switch (event) {
    case 'connection.ping':
      c.sendEvent('connection.pong', const {});
      return;
    case 'connection.pong':
      return;

    case 'auth.login':
      // Identity: prefer the (debug) username, else the token, else random —
      // matching the Chess API "JWT or bare username" rule.
      final uname = (data['username'] as String?)?.trim();
      final tok = (data['token'] as String?)?.trim();
      c.userId = (uname != null && uname.isNotEmpty)
          ? uname
          : (tok != null && tok.isNotEmpty ? tok : 'user_${_rng.nextInt(99999)}');
      _log('login: ${c.userId}');
      if (id != null) {
        c.sendEvent('auth.login_success', {'token': tok ?? c.userId, 'user_id': c.userId, 'username': c.userId}, id: id);
      }
      return;

    case 'match.find':
      _onMatchFind(c, id, data);
      return;

    case 'room.create':
      _onRoomCreate(c, id);
      return;

    case 'room.join':
      _onRoomJoin(c, id, data);
      return;

    case 'player.ready':
      _onReady(c, id);
      return;

    case 'game.action':
      _onAction(c, id, data);
      return;

    case 'chat.send':
      _onChat(c, data);
      return;

    case 'room.leave':
      if (id != null) c.sendEvent('room.left', const {}, id: id);
      _leaveGame(c);
      return;

    default:
      if (id != null) c.sendError(id, 'invalid_request', 'Unhandled event: $event');
  }
}

void _onMatchFind(Client c, String? id, Map<String, dynamic> data) {
  final key = '${data['currency'] ?? 'tokens'}:${data['bet_amount'] ?? 0}';
  final partner = _waiting[key];
  if (partner != null && partner != c && partner.ws.readyState == WebSocket.open) {
    _waiting.remove(key);
    final game = Game(_code())
      ..white = partner
      ..black = c;
    _roomsByCode[game.code] = game;
    _gameOf[partner.ws] = game;
    _gameOf[c.ws] = game;
    // Requester (second to arrive) is black; waiting player is white.
    if (id != null) {
      c.sendEvent('match.found', {'room_code': game.code, 'seat': 1, 'color': 'black'}, id: id);
    }
    partner.sendEvent('match.found', {'room_code': game.code, 'seat': 0, 'color': 'white'});
    _log('matched ${partner.userId}(white) vs ${c.userId}(black) [$key]');
  } else {
    c.matchKey = key;
    _waiting[key] = c;
    if (id != null) c.sendEvent('match.searching', const {}, id: id);
    _log('searching: ${c.userId} [$key]');
  }
}

void _onRoomCreate(Client c, String? id) {
  final game = Game(_code())..white = c;
  _roomsByCode[game.code] = game;
  _gameOf[c.ws] = game;
  if (id != null) {
    c.sendEvent('room.created', {'room_code': game.code, 'seat': 0, 'color': 'white'}, id: id);
  }
  _log('room ${game.code} created by ${c.userId}');
}

void _onRoomJoin(Client c, String? id, Map<String, dynamic> data) {
  final code = (data['room_code'] as String? ?? '').toUpperCase();
  final game = _roomsByCode[code];
  if (game == null || game.black != null) {
    if (id != null) c.sendError(id, 'not_found', 'Room not found or full');
    return;
  }
  game.black = c;
  _gameOf[c.ws] = game;
  if (id != null) {
    c.sendEvent('room.joined', {'room_code': code, 'seat': 1, 'color': 'black'}, id: id);
  }
  for (final m in game.members) {
    m.sendEvent('room.user_joined', {'room_full': true, 'countdown_seconds': 3});
  }
  _log('${c.userId} joined room $code');
}

void _onReady(Client c, String? id) {
  final game = _gameOf[c.ws];
  if (game == null) {
    if (id != null) c.sendError(id, 'invalid_state', 'Not in a room');
    return;
  }
  game.ready.add(c.userId);
  if (id != null) c.sendEvent('player.ready_update', {'ready': game.ready.toList()}, id: id);
  if (game.ready.length >= 2 && game.white != null && game.black != null && !game.started) {
    game.started = true;
    final players = [
      {'user_id': game.white!.userId, 'color': 'white', 'seat': 0},
      {'user_id': game.black!.userId, 'color': 'black', 'seat': 1},
    ];
    final state = {'match_id': game.code, 'players': players};
    for (final m in game.members) {
      m.sendEvent('game.started', {'state': state});
    }
    _log('game.started ${game.code}');
    // White moves first — open the per-move clock for white.
    _startTurn(game, 'white');
  }
}

/// Opens a turn for [color]: broadcasts `game.turn_start` with the per-move
/// budget + deadline, and arms a server timer that fires `game.turn_timeout`
/// (and ends the game) if no move lands in time.
void _startTurn(Game game, String color) {
  game.turnTimer?.cancel();
  game.activeColor = color;
  game.turnSeq++;
  final seq = game.turnSeq;
  final now = DateTime.now().millisecondsSinceEpoch;
  final uid = game.clientFor(color)?.userId;
  for (final m in game.members) {
    if (m.ws.readyState != WebSocket.open) continue;
    m.sendEvent('game.turn_start', {
      'color': color,
      'user_id': uid,
      'turn': seq,
      'time_limit_ms': kTurnLimitMs,
      'deadline_ms': now + kTurnLimitMs,
      'server_time_ms': now,
    });
  }
  _log('turn $seq → $color (${kTurnLimitMs}ms)');
  game.turnTimer = Timer(const Duration(milliseconds: kTurnLimitMs), () {
    // Ignore if the turn already advanced (a move arrived).
    if (game.turnSeq != seq) return;
    _onTurnTimeout(game, color);
  });
}

void _onTurnTimeout(Game game, String color) {
  final loserUid = game.clientFor(color)?.userId;
  for (final m in game.members) {
    if (m.ws.readyState != WebSocket.open) continue;
    m.sendEvent('game.turn_timeout', {'color': color, 'user_id': loserUid});
  }
  final result = color == 'white' ? 'black_wins' : 'white_wins';
  final winner = game.clientFor(color == 'white' ? 'black' : 'white');
  _log('$color timed out → $result');
  _complete(game, result, winner?.userId);
}

void _onAction(Client c, String? id, Map<String, dynamic> data) {
  final game = _gameOf[c.ws];
  if (game == null) {
    if (id != null) c.sendError(id, 'invalid_state', 'Not in a game');
    return;
  }
  if (id != null) c.sendEvent('game.action_ack', const {}, id: id);
  final type = data['action_type'] as String? ?? 'move';
  switch (type) {
    case 'move':
      final from = data['from'] as String? ?? '';
      final to = data['to'] as String? ?? '';
      final promo = data['promotion'] as String?;
      final algebraic = promo != null ? '$from$to=${promo.toUpperCase()}' : '$from$to';
      final last = {'from': from, 'to': to, 'algebraic': algebraic, 'user_id': c.userId};
      for (final m in game.members) {
        m.sendEvent('game.state_update', {'last_action': last});
      }
      _log('move ${c.userId}: $from$to${promo != null ? '=$promo' : ''}');
      // The mover's move ended their turn — open a fresh clock for the other side.
      _startTurn(game, c == game.white ? 'black' : 'white');
    case 'resign':
      final winner = game.other(c);
      final result = c == game.white ? 'black_wins' : 'white_wins';
      _complete(game, result, winner?.userId);
      _log('${c.userId} resigned');
    case 'offer_draw':
      for (final m in game.members) {
        m.sendEvent('game.draw_offered', {'offered_by': c.userId});
      }
    case 'accept_draw':
      _complete(game, 'draw', null);
    case 'decline_draw':
      for (final m in game.members) {
        m.sendEvent('game.draw_declined', const {});
      }
  }
}

void _complete(Game game, String result, String? winnerId) {
  game.turnTimer?.cancel();
  for (final m in game.members) {
    if (m.ws.readyState != WebSocket.open) continue;
    m.sendEvent('game.completed', {'result': result, 'winner_id': winnerId});
  }
  _roomsByCode.remove(game.code);
}

void _onChat(Client c, Map<String, dynamic> data) {
  final game = _gameOf[c.ws];
  if (game == null) return;
  for (final m in game.members) {
    m.sendEvent('chat.message', {
      'from_user_id': c.userId,
      'username': c.userId,
      'message': data['message'] as String? ?? '',
    });
  }
}

void _leaveGame(Client c) {
  final game = _gameOf.remove(c.ws);
  if (game == null) return;
  game.turnTimer?.cancel();
  if (game.white == c) game.white = null;
  if (game.black == c) game.black = null;
  for (final m in game.members) {
    if (m.ws.readyState != WebSocket.open) continue;
    m.sendEvent('room.user_left', {'user_id': c.userId});
  }
}

void _onDisconnect(Client c) {
  _clients.remove(c.ws);
  if (c.matchKey != null && _waiting[c.matchKey] == c) _waiting.remove(c.matchKey);
  _leaveGame(c);
  _log('client disconnected (${_clients.length} online)');
}

void _log(String m) => stdout.writeln('[relay ${DateTime.now().toIso8601String().substring(11, 19)}] $m');
