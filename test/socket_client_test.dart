import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:snakeladder/services/socket/socket_client.dart';
import 'package:snakeladder/services/socket/socket_events.dart';

/// Minimal in-memory fake so we can drive the client without a real server.
class _FakeChannel implements WebSocketChannel {
  final _incoming = StreamController<String>();
  final List<Map<String, dynamic>> sent = [];
  late final _FakeSink _sink = _FakeSink(this);

  /// Simulate a frame from the server.
  void serverSend(Map<String, dynamic> json) => _incoming.add(jsonEncode(json));

  @override
  Stream get stream => _incoming.stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this.channel);
  final _FakeChannel channel;
  @override
  void add(dynamic data) => channel.sent.add((jsonDecode(data as String) as Map).cast<String, dynamic>());
  @override
  Future close([int? code, String? reason]) async => channel._incoming.close();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _FakeChannel fake;
  late SocketClient client;

  setUp(() {
    fake = _FakeChannel();
    client = SocketClient(url: Uri.parse('ws://test/ws'), channelFactory: (_) => fake);
  });

  test('connect resolves on connection.established and starts connected', () async {
    final fut = client.connect();
    fake.serverSend({'event': SocketEvent.established, 'data': {'server_version': '1'}});
    await fut;
    expect(client.status, SocketStatus.connected);
  });

  test('connect fails fast when the upgrade is refused (socket closes before established)', () async {
    final fut = client.connect();
    await fake.sink.close(); // e.g. gateway answered 401/404 instead of 101
    await expectLater(fut, throwsA(isA<SocketError>()));
    expect(client.status, SocketStatus.disconnected);
  });

  test('login fails on an auth.login_error reply that carries the error in data', () async {
    final fut = client.connect();
    fake.serverSend({'event': SocketEvent.established, 'data': {}});
    await fut;
    final login = client.login(token: 'bad');
    final id = fake.sent.last['id'];
    fake.serverSend({'id': id, 'event': SocketEvent.loginError, 'data': {'code': 'unauthorized', 'message': 'bad token'}});
    await expectLater(login, throwsA(isA<SocketError>().having((e) => e.code, 'code', 'unauthorized')));
  });

  test('request correlates the response by id', () async {
    final fut = client.connect();
    fake.serverSend({'event': SocketEvent.established, 'data': {}});
    await fut;

    final reqFuture = client.request(SocketEvent.roomList, {'game_type': 'chess'});
    // The client should have sent a framed request with an id.
    final sent = fake.sent.last;
    expect(sent['event'], SocketEvent.roomList);
    expect(sent['id'], isNotNull);

    // Server replies with the same id.
    fake.serverSend({'id': sent['id'], 'event': SocketEvent.roomListResult, 'data': {'total': 3}});
    final res = await reqFuture;
    expect(res.data['total'], 3);
  });

  test('error envelope rejects the request', () async {
    final fut = client.connect();
    fake.serverSend({'event': SocketEvent.established, 'data': {}});
    await fut;

    final reqFuture = client.request(SocketEvent.roomJoin, {'room_code': 'XXX'});
    final id = fake.sent.last['id'];
    fake.serverSend({'id': id, 'event': SocketEvent.roomJoinError, 'error': {'code': 'not_found', 'message': 'nope'}});
    await expectLater(reqFuture, throwsA(isA<SocketError>().having((e) => e.code, 'code', 'not_found')));
  });

  test('broadcasts (no id) surface on the broadcast stream', () async {
    final fut = client.connect();
    fake.serverSend({'event': SocketEvent.established, 'data': {}});
    await fut;

    final next = client.broadcasts.first;
    fake.serverSend({'event': SocketEvent.gameStateUpdate, 'data': {'status': 'in_progress'}});
    final msg = await next;
    expect(msg.event, SocketEvent.gameStateUpdate);
    expect(msg.id, isNull);
    expect(msg.data['status'], 'in_progress');
  });

  test('a requested connection.ping completes with the pong that carries its id', () async {
    final fut = client.connect();
    fake.serverSend({'event': SocketEvent.established, 'data': {}});
    await fut;
    final ping = client.request(SocketEvent.ping);
    fake.serverSend({'id': fake.sent.last['id'], 'event': SocketEvent.pong, 'data': {}});
    expect((await ping).event, SocketEvent.pong);
  });

  test('server ping is answered with a pong', () async {
    final fut = client.connect();
    fake.serverSend({'event': SocketEvent.established, 'data': {}});
    await fut;
    fake.sent.clear();
    fake.serverSend({'event': SocketEvent.ping, 'data': {}});
    await Future<void>.delayed(Duration.zero);
    expect(fake.sent.any((m) => m['event'] == SocketEvent.pong), isTrue);
  });

  test('login stores the token and marks authenticated', () async {
    final fut = client.connect();
    fake.serverSend({'event': SocketEvent.established, 'data': {}});
    await fut;

    final loginFut = client.login(token: 'abc');
    final id = fake.sent.last['id'];
    expect(fake.sent.last['event'], SocketEvent.login);
    fake.serverSend({'id': id, 'event': SocketEvent.loginSuccess, 'data': {'user_id': 'u1', 'token': 'fresh'}});
    await loginFut;
    expect(client.status, SocketStatus.authenticated);
  });

  test('auth.login sends only the token', () async {
    final fut = client.connect();
    fake.serverSend({'event': SocketEvent.established, 'data': {}});
    await fut;

    final loginFut = client.login(token: 'jwt-abc');
    final sent = fake.sent.last;
    expect(sent['event'], SocketEvent.login);
    expect(sent['data'], {'token': 'jwt-abc'});
    fake.serverSend({'id': sent['id'], 'event': SocketEvent.loginSuccess, 'data': {'user_id': 'u1'}});
    await loginFut;
  });

  test('connection.established timestamp sets the server clock offset', () async {
    final fut = client.connect();
    final serverMs = DateTime.now().millisecondsSinceEpoch + 60000; // server 1 min ahead
    fake.serverSend({'event': SocketEvent.established, 'data': {'timestamp': serverMs}});
    await fut;
    expect(client.serverClockOffset.inSeconds, inInclusiveRange(59, 60));
    expect(client.serverNow().difference(DateTime.now()).inSeconds, inInclusiveRange(59, 60));
  });

  test('an error reply with the request id rejects it; connection.error carries the code', () async {
    final fut = client.connect();
    fake.serverSend({'event': SocketEvent.established, 'data': {}});
    await fut;
    final req = client.request('room.dance');
    final id = fake.sent.last['id'];
    fake.serverSend({'id': id, 'event': SocketEvent.connectionError, 'error': {'code': 'unknown_event', 'message': "unknown event 'room.dance'"}});
    await expectLater(req, throwsA(isA<SocketError>().having((e) => e.code, 'code', 'unknown_event')));
  });

  test('kill switch: the operator message is player text; other messages are not', () {
    expect(socketErrorText(const SocketError('kill_switch_engaged', 'Back at 6 pm'), fallback: 'x'), 'Back at 6 pm');
    expect(socketErrorText(const SocketError('invalid_state', 'dev text'), fallback: 'x'), 'x');
  });

  test('auth.refresh: a fresh token is sent on the open socket before expires_at', () async {
    final ch = _FakeChannel();
    final c = SocketClient(url: Uri.parse('ws://test/ws'), channelFactory: (_) => ch, reauth: () async => 'NEW');
    final opened = c.connect();
    ch.serverSend({'event': SocketEvent.established, 'data': {}});
    await opened;
    final login = c.login(token: 'OLD');
    await Future<void>.delayed(Duration.zero);
    // The refresh timer is set from expires_at; call it directly here.
    ch.serverSend({
      'id': ch.sent.last['id'],
      'event': SocketEvent.loginSuccess,
      'data': {'user_id': 'u1', 'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 900},
    });
    await login;
    final refreshed = c.refreshToken();
    await Future<void>.delayed(Duration.zero);
    final frame = ch.sent.last;
    expect(frame['event'], SocketEvent.refresh);
    expect(frame['data'], {'token': 'NEW'});
    ch.serverSend({'id': frame['id'], 'event': SocketEvent.tokenRefreshed, 'data': {'expires_at': 0}});
    await refreshed;
    await c.close();
  });

  test('reconnect after a drop: 0.5 s backoff, a 30 s deadline, then auth.login with a fresh token', () async {
    final channels = <_FakeChannel>[];
    final urls = <Uri>[];
    final c = SocketClient(
      url: Uri.parse('ws://test/ws'),
      channelFactory: (u) {
        urls.add(u);
        final ch = _FakeChannel();
        channels.add(ch);
        return ch;
      },
      reauth: () async => 'NEW',
    );
    final opened = c.connect();
    channels.last.serverSend({'event': SocketEvent.established, 'data': {}});
    await opened;
    final login = c.login(token: 'OLD');
    await Future<void>.delayed(Duration.zero);
    final id = channels.last.sent.last['id'];
    channels.last.serverSend({'id': id, 'event': SocketEvent.loginSuccess, 'data': {'user_id': 'u1'}});
    await login;

    await channels.last.sink.close();
    await Future<void>.delayed(Duration.zero);
    expect(c.status, SocketStatus.reconnecting);
    final left = c.reconnectDeadline!.difference(DateTime.now());
    expect(left.inSeconds, inInclusiveRange(29, 30));

    // First retry after 0.5 s (not the old 1 s+): wait for it, with slack for a busy CI.
    final dropped = DateTime.now();
    while (channels.length < 2 && DateTime.now().difference(dropped) < const Duration(seconds: 5)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(channels, hasLength(2));
    expect(DateTime.now().difference(dropped), greaterThanOrEqualTo(const Duration(milliseconds: 450)));
    expect(urls.every((u) => !u.hasQuery), isTrue, reason: 'never a token in the URL');
    channels.last.serverSend({'event': SocketEvent.established, 'data': {}});
    await Future<void>.delayed(Duration.zero);
    final resumed = channels.last.sent.lastWhere((m) => m['event'] == SocketEvent.login);
    expect(resumed['data'], {'token': 'NEW'});
    channels.last.serverSend({'event': SocketEvent.loginSuccess, 'data': {'user_id': 'u1'}});
    await Future<void>.delayed(Duration.zero);
    expect(c.status, SocketStatus.authenticated);
    expect(c.reconnectDeadline, isNull);
    await c.close();
  });

  test('a refused sign-in after a reconnect: retries once with a fresh token, then stops', () async {
    final channels = <_FakeChannel>[];
    var reauths = 0;
    final c = SocketClient(
      url: Uri.parse('ws://test/ws'),
      channelFactory: (_) => (channels..add(_FakeChannel())).last,
      reauth: () async => 'T${++reauths}',
    );
    final opened = c.connect();
    channels.last.serverSend({'event': SocketEvent.established, 'data': {}});
    await opened;
    final login = c.login(token: 'OLD');
    await Future<void>.delayed(Duration.zero);
    channels.last.serverSend({'id': channels.last.sent.last['id'], 'event': SocketEvent.loginSuccess, 'data': {}});
    await login;

    await channels.last.sink.close();
    while (channels.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    channels.last.serverSend({'event': SocketEvent.established, 'data': {}});
    await Future<void>.delayed(Duration.zero);
    channels.last.serverSend({'event': SocketEvent.loginError, 'data': {'code': 'invalid_credentials'}});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final logins = channels.last.sent.where((m) => m['event'] == SocketEvent.login).toList();
    expect(logins, hasLength(2), reason: 'one retry with a fresh token');
    expect(logins.last['data'], {'token': 'T2'});

    channels.last.serverSend({'event': SocketEvent.loginError, 'data': {'code': 'token_revoked'}});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.status, SocketStatus.disconnected, reason: 'stops instead of looking connected');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(channels, hasLength(2), reason: 'no reconnect loop after a refusal');
  });
}
