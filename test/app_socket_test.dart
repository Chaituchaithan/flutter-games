// Socket sign-in at app login: connection.established → auth.login {token}
// → auth.login_success, plus failure and log-out handling.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:snakeladder/app/game_socket_login.dart';
import 'package:snakeladder/configs/configs.dart';
import 'package:snakeladder/services/socket/app_socket.dart';
import 'package:snakeladder/services/socket/socket_client.dart';

class _FakeChannel implements WebSocketChannel {
  final incoming = StreamController<String>();
  final sent = <Map<String, dynamic>>[];
  late final _sink = _FakeSink(this);
  Uri? dialed;

  /// Plays the server: greets on open, answers auth.login per [loginReply].
  void Function(Map<String, dynamic> frame)? onSend;

  @override
  Stream get stream => incoming.stream;
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
  _FakeSink(this.ch);
  final _FakeChannel ch;
  @override
  void add(dynamic data) {
    final f = (jsonDecode(data as String) as Map).cast<String, dynamic>();
    ch.sent.add(f);
    ch.onSend?.call(f);
  }

  @override
  Future close([int? code, String? reason]) async => ch.incoming.close();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

_FakeChannel _server({required bool accept}) {
  final ch = _FakeChannel();
  scheduleMicrotask(() => ch.incoming.add(jsonEncode({'event': 'connection.established', 'data': {}})));
  ch.onSend = (f) {
    if (f['event'] != 'auth.login') return;
    ch.incoming.add(jsonEncode(accept
        ? {'id': f['id'], 'event': 'auth.login_success', 'data': {'user_id': 'u1', 'username': 'chaitu01'}}
        : {'id': f['id'], 'event': 'auth.login_error', 'error': {'code': 'invalid_credentials', 'message': 'invalid token'}}));
  };
  return ch;
}

void main() {
  test('login: auth.login carries only the token (never a username) → authenticated', () async {
    final ch = _server(accept: true);
    final sock = AppSocket(channelFactory: (u) => ch..dialed = u);
    await sock.connect(token: 'jwt-123', username: 'chaitu01', game: chessConfig);

    final login = ch.sent.firstWhere((f) => f['event'] == 'auth.login');
    expect(login['id'], isNotNull);
    expect(login['data'], {'token': 'jwt-123'});
    expect(sock.isConnected, isTrue);
    expect(sock.username, 'chaitu01');
    // Dials the chess service directly, with no token in the URL.
    expect(ch.dialed.toString(), 'ws://192.168.0.235:${AppConfig.server.servicePort(chessConfig.port)}/ws');
    sock.disconnect();
  });

  test('rejected login throws and leaves no half-open socket', () async {
    final ch = _server(accept: false);
    final sock = AppSocket(channelFactory: (_) => ch);
    await expectLater(
      sock.connect(token: 'bad', username: 'x', game: chessConfig),
      throwsA(isA<SocketError>().having((e) => e.code, 'code', 'invalid_credentials')),
    );
    expect(sock.client, isNull);
    expect(sock.isConnected, isFalse);
  });

  test('logout sends auth.logout and closes the socket', () async {
    final ch = _server(accept: true);
    final sock = AppSocket(channelFactory: (_) => ch);
    await sock.connect(token: 'jwt-123', username: 'chaitu01', game: chessConfig);
    sock.logout();
    expect(ch.sent.last['event'], 'auth.logout');
    expect(sock.client, isNull);
  });

  test('after login the app signs in on the live Ludo server (ws://<host>:1285/ws)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final game = container.read(gameSocketLoginProvider).game;
    expect(game.id, GameId.ludo);
    expect(GameEndpoints(game).socketUrl, 'ws://192.168.0.235:1285/ws');
  });

  test('the shared socket remembers its game server', () async {
    final sock = AppSocket(channelFactory: (_) => _server(accept: true));
    await sock.connect(token: 'jwt-123', game: ludoConfig);
    expect(sock.game?.id, GameId.ludo);
    sock.disconnect();
    expect(sock.game, isNull);
  });
}
