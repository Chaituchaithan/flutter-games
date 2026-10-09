import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:snakeladder/game/chess/chess_engine.dart';
import 'package:snakeladder/services/socket/chess_session.dart';
import 'package:snakeladder/services/socket/socket_client.dart';
import 'package:snakeladder/services/socket/socket_events.dart';

class _FakeChannel implements WebSocketChannel {
  final _incoming = StreamController<String>();
  final List<Map<String, dynamic>> sent = [];
  late final _FakeSink _sink = _FakeSink(this);
  void serverSend(Map<String, dynamic> json) => _incoming.add(jsonEncode(json));
  @override
  Stream get stream => _incoming.stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this.channel);
  final _FakeChannel channel;
  @override
  void add(dynamic data) => channel.sent.add((jsonDecode(data as String) as Map).cast<String, dynamic>());
  @override
  Future close([int? c, String? r]) async => channel._incoming.close();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _FakeChannel fake;
  late SocketClient client;
  late ChessSession session;

  Future<void> boot() async {
    fake = _FakeChannel();
    client = SocketClient(url: Uri.parse('ws://t/ws'), channelFactory: (_) => fake);
    session = ChessSession(socket: client, userId: 'me');
    final f = session.start(token: 'tok');
    fake.serverSend({'event': SocketEvent.established, 'data': {}});
    // login request → reply
    await Future<void>.delayed(Duration.zero);
    final loginId = fake.sent.firstWhere((m) => m['event'] == SocketEvent.login)['id'];
    fake.serverSend({'id': loginId, 'event': SocketEvent.loginSuccess, 'data': {'user_id': 'me', 'token': 't2'}});
    await f;
  }

  test('game.started sets my colour and resets the board', () async {
    await boot();
    fake.serverSend({
      'event': SocketEvent.gameStarted,
      'data': {
        'state': {
          'match_id': 'm1',
          'players': [
            {'user_id': 'me', 'seat': 0, 'color': 'white'},
            {'user_id': 'bob', 'seat': 1, 'color': 'black'},
          ],
        }
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(session.phase, ChessPhase.inGame);
    expect(session.myColor, PieceColor.white);
    expect(session.matchId, 'm1');
    expect(session.game.state.turn, PieceColor.white);
  });

  test('a local move is sent as game.action with lowercase squares', () async {
    await boot();
    fake.serverSend({
      'event': SocketEvent.gameStarted,
      'data': {'state': {'match_id': 'm1', 'players': [
        {'user_id': 'me', 'seat': 0, 'color': 'white'},
        {'user_id': 'bob', 'seat': 1, 'color': 'black'},
      ]}},
    });
    await Future<void>.delayed(Duration.zero);
    fake.sent.clear();

    // Tap e2 then e4 (white's opening).
    session.game.onTapSquare(squareFromName('e2')!);
    session.game.onTapSquare(squareFromName('e4')!);
    await Future<void>.delayed(Duration.zero);

    final action = fake.sent.firstWhere((m) => m['event'] == SocketEvent.gameAction);
    expect(action['data']['action_type'], 'move');
    expect(action['data']['from'], 'e2');
    expect(action['data']['to'], 'e4');
    // Applied optimistically.
    expect(session.game.state.pieceAt(squareFromName('e4')!)?.type, PieceType.pawn);
  });

  test('opponent move from state_update is mirrored into the engine', () async {
    await boot();
    fake.serverSend({
      'event': SocketEvent.gameStarted,
      'data': {'state': {'match_id': 'm1', 'players': [
        {'user_id': 'me', 'seat': 0, 'color': 'white'},
        {'user_id': 'bob', 'seat': 1, 'color': 'black'},
      ]}},
    });
    await Future<void>.delayed(Duration.zero);

    // We play e4, then bob replies e5 via a broadcast.
    session.game.onTapSquare(squareFromName('e2')!);
    session.game.onTapSquare(squareFromName('e4')!);
    fake.serverSend({
      'event': SocketEvent.gameStateUpdate,
      'data': {'last_action': {'action_type': 'move', 'from': 'e7', 'to': 'e5', 'algebraic': 'e5', 'user_id': 'bob'}},
    });
    await Future<void>.delayed(Duration.zero);

    expect(session.game.state.pieceAt(squareFromName('e5')!)?.type, PieceType.pawn);
    expect(session.game.state.turn, PieceColor.white); // back to us
  });

  test('our own echoed state_update is ignored (no double-apply)', () async {
    await boot();
    fake.serverSend({
      'event': SocketEvent.gameStarted,
      'data': {'state': {'match_id': 'm1', 'players': [
        {'user_id': 'me', 'seat': 0, 'color': 'white'},
        {'user_id': 'bob', 'seat': 1, 'color': 'black'},
      ]}},
    });
    await Future<void>.delayed(Duration.zero);
    session.game.onTapSquare(squareFromName('e2')!);
    session.game.onTapSquare(squareFromName('e4')!);
    final fenAfterLocal = session.game.state.toFen();

    // Server echoes our own move — must be a no-op.
    fake.serverSend({
      'event': SocketEvent.gameStateUpdate,
      'data': {'last_action': {'action_type': 'move', 'from': 'e2', 'to': 'e4', 'algebraic': 'e4', 'user_id': 'me'}},
    });
    await Future<void>.delayed(Duration.zero);
    expect(session.game.state.toFen(), fenAfterLocal);
  });

  test('game.completed sets the result', () async {
    await boot();
    fake.serverSend({'event': 'game.completed', 'data': {'match_id': 'm1', 'result': 'white_wins', 'winner_id': 'me'}});
    await Future<void>.delayed(Duration.zero);
    expect(session.phase, ChessPhase.completed);
    expect(session.result, 'white_wins');
    expect(session.winnerId, 'me');
  });

  test('createRoom sends room.create and stores code + colour (White)', () async {
    await boot();
    final fut = session.createRoom(currency: 'tokens', betAmount: 200);
    final req = fake.sent.firstWhere((m) => m['event'] == SocketEvent.roomCreate);
    expect(req['data']['bet_amount'], 200);
    fake.serverSend({'id': req['id'], 'event': SocketEvent.roomCreated, 'data': {'room_code': 'AX7K2Q', 'seat': 0, 'color': 'white'}});
    await fut;
    expect(session.roomCode, 'AX7K2Q');
    expect(session.myColor, PieceColor.white);
    expect(session.phase, ChessPhase.inRoom);
  });

  test('joinRoom by code stores colour (Black for seat 1)', () async {
    await boot();
    final fut = session.joinRoom('AX7K2Q');
    final req = fake.sent.firstWhere((m) => m['event'] == SocketEvent.roomJoin);
    expect(req['data']['room_code'], 'AX7K2Q');
    fake.serverSend({'id': req['id'], 'event': SocketEvent.roomJoined, 'data': {'room_code': 'AX7K2Q', 'seat': 1, 'color': 'black'}});
    await fut;
    expect(session.myColor, PieceColor.black);
  });

  test('quick chat sends chat.send and appends incoming chat.message', () async {
    await boot();
    session.sendChat('Good luck!');
    expect(fake.sent.last['event'], SocketEvent.chatSend);
    expect(fake.sent.last['data']['message'], 'Good luck!');

    fake.serverSend({'event': SocketEvent.chatMessage, 'data': {'from_user_id': 'bob', 'username': 'bob', 'message': 'Nice move'}});
    await Future<void>.delayed(Duration.zero);
    expect(session.chat.length, 1);
    expect(session.chat.first.message, 'Nice move');
    expect(session.chat.first.mine, isFalse);
  });
}
