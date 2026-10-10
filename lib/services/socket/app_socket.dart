import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/configs.dart';
import 'socket_client.dart';
import 'socket_events.dart';

// The socket on/off switch (kSocketEnabled) lives in configs/feature_flags.dart.

/// App-wide realtime socket, opened right after a successful API login.
///
/// Flow (see Chess API.pdf §Game flow): API login → gateway token → open the
/// WebSocket → send `auth.login {token, username}` → on `auth.login_success`
/// the socket is Authenticated → the app navigates Home.
///
/// The `auth.login` event requires a `username`. The login flow passes the
/// account's real username (from /users/me) to [connect]; the build-time
/// `SOCKET_USERNAME` default is only a fallback for dev testing when no
/// real identity is supplied.
class AppSocket {
  /// [channelFactory] lets tests supply a fake connection.
  AppSocket({this.channelFactory});

  final ChannelFactory? channelFactory;
  SocketClient? _client;
  String? _username;

  SocketClient? get client => _client;

  /// Build-time default identity, overridable per build:
  /// `--dart-define=SOCKET_USERNAME=test2`. Defaults to `test1`.
  static const _envUsername = BuildOverrides.socketUsername;

  /// The identity sent on `auth.login`. An explicit [connect] username overrides
  /// it if provided.
  String get username => _username ??= _envUsername;

  bool get isConnected => _client?.status == SocketStatus.authenticated;

  /// Open + authenticate the socket. Completes when `auth.login_success`
  /// arrives; throws [SocketError]/[TimeoutException] on failure so the caller
  /// can decide whether to gate navigation on it. Pass [username] to send the
  /// real login identity (e.g. `auratester01`); omit it to use the fallback.
  ///
  /// [game] picks the game service to connect to (its port/path come from the
  /// game's config); Chess by default.
  Future<void> connect({required String token, String? username, required GameConfig game}) async {
    if (username != null && username.trim().isNotEmpty) _username = username.trim();
    // The gateway requires auth at the WS upgrade. Native can carry it in the
    // auth.login first frame, but browsers can't set WS headers — so when going
    // through the proxy the token rides as a query param (the proxy turns it
    // into a Bearer header upstream). [GameEndpoints] handles both.
    final endpoints = GameEndpoints(game);
    final uri = Uri.parse(endpoints.socketUrlWithToken(token));
    final c = SocketClient(
      url: uri,
      headers: endpoints.socketHeaders(token),
      requestTimeout: NetworkConfig.socketRequestTimeout,
      channelFactory: channelFactory,
    );
    try {
      await c.connect();
      // Use the getter (not the param) so the fallback identity applies when no
      // username was supplied.
      await c.login(token: token, username: this.username);
    } on Object {
      // Don't leave a half-open, unauthenticated socket behind.
      c.dispose();
      rethrow;
    }
    _client?.dispose();
    _client = c;
  }

  /// Sign the socket out (`auth.logout`, best effort) and close it — on app
  /// log-out, so the next account never inherits this socket session.
  void logout() {
    final c = _client;
    if (c != null && c.status == SocketStatus.authenticated) {
      c.send(SocketEvent.logout, const {});
    }
    disconnect();
  }

  void disconnect() {
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
