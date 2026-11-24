import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/configs.dart';
import 'socket_client.dart';
import 'socket_events.dart';

// The socket on/off switch (kSocketEnabled) lives in configs/feature_flags.dart.

/// App-wide realtime socket, opened right after a successful API login:
/// open the game server's WebSocket → `auth.login {token}` → on
/// `auth.login_success` the socket is Authenticated → Home. One socket per
/// player per game server: the old one is closed before a new one opens.
class AppSocket {
  /// [channelFactory] lets tests supply a fake connection.
  AppSocket({this.channelFactory});

  final ChannelFactory? channelFactory;

  /// A currently valid access token for automatic reconnects (refreshing an
  /// expired one) — wired by the app to the session. Null = reuse the login
  /// token.
  Future<String?> Function()? freshToken;

  SocketClient? _client;
  String? _username;
  StreamSubscription<SocketMessage>? _forward;

  final _events = StreamController<SocketMessage>.broadcast();

  /// Every pushed frame of the current socket (follows reconnects and a new
  /// sign-in, unlike one client's [SocketClient.broadcasts]).
  Stream<SocketMessage> get events => _events.stream;

  /// A `game.state_sync` / `game.final_state` that arrived after signing in
  /// (a reconnect or a cold start with a game running) and no game screen
  /// has taken yet. See [takeResume].
  SocketMessage? get pendingResume => _resume;
  SocketMessage? _resume;
  final _resumes = StreamController<SocketMessage>.broadcast();

  /// Fires when a game to go back to arrives (ludo.md §7).
  Stream<SocketMessage> get resumes => _resumes.stream;

  /// A game screen is open and takes resume frames itself (otherwise the app
  /// opens the game's screen for them).
  bool gameScreenOpen = false;

  /// A game screen took the pending resume frame.
  SocketMessage? takeResume() {
    final r = _resume;
    _resume = null;
    return r;
  }

  static const _resumeEvents = {'game.state_sync', 'game.final_state'};

  SocketClient? get client => _client;

  /// The game server [client] is signed in to (e.g. Ludo). A game screen
  /// reuses the shared socket only when it is on its own server.
  GameConfig? get game => _client == null ? null : _game;
  GameConfig? _game;

  /// The signed-in account's username (from /users/me), for display and
  /// game state. Not sent on `auth.login`: the server reads it from the token.
  String get username => _username ?? '';

  bool get isConnected => _client?.status == SocketStatus.authenticated;

  /// Open + authenticate the socket on [game]'s server. Completes on
  /// `auth.login_success`; throws [SocketError]/[TimeoutException] otherwise.
  Future<void> connect({required String token, String? username, required GameConfig game}) async {
    if (username != null && username.trim().isNotEmpty) _username = username.trim();
    // A second signed-in socket for the same player is refused (`duplicate`).
    _client?.dispose();
    _client = null;
    final c = SocketClient(
      url: Uri.parse(GameEndpoints(game).socketUrl),
      requestTimeout: NetworkConfig.socketRequestTimeout,
      channelFactory: channelFactory,
      reauth: freshToken,
    );
    // Listen before signing in: a running game's `game.state_sync` follows
    // `auth.login_success` at once.
    _forward?.cancel();
    _forward = c.broadcasts.listen((m) {
      if (_resumeEvents.contains(m.event)) {
        _resume = m;
        if (!_resumes.isClosed) _resumes.add(m);
      }
      if (!_events.isClosed) _events.add(m);
    });
    try {
      await c.connect();
      await c.login(token: token);
    } on Object {
      // Don't leave a half-open, unauthenticated socket behind.
      _forward?.cancel();
      _forward = null;
      c.dispose();
      rethrow;
    }
    _client = c;
    _game = game;
  }

  /// Sign the socket out (`auth.logout`, best effort) and close it — on app
  /// log-out, so the next account never inherits this socket session.
  void logout() {
    final c = _client;
    if (c != null && c.status == SocketStatus.authenticated) {
      c.send(SocketEvent.logout);
    }
    disconnect();
  }

  void disconnect() {
    _forward?.cancel();
    _forward = null;
    _resume = null;
    _client?.dispose();
    _client = null;
    _username = null;
  }
}

final appSocketProvider = Provider<AppSocket>((ref) {
  final socket = AppSocket();
  ref.onDispose(socket.disconnect);
  return socket;
});
