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

  test('login sends both token and username in the auth.login payload', () async {
    final fut = client.connect();
    fake.serverSend({'event': SocketEvent.established, 'data': {}});
    await fut;

    final loginFut = client.login(token: 'jwt-abc', username: 'test_12345');
    final sent = fake.sent.last;
    expect(sent['event'], SocketEvent.login);
    expect(sent['data']['token'], 'jwt-abc');
    expect(sent['data']['username'], 'test_12345');
    fake.serverSend({'id': sent['id'], 'event': SocketEvent.loginSuccess, 'data': {'user_id': 'u1'}});
    await loginFut;
  });
}
