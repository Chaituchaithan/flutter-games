import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chess_session.dart' show chessWsHeaders, chessWsUrlWithToken;
import 'socket_client.dart';

/// MASTER SWITCH for the realtime socket ("turn on/off socket").
///
/// `false` = BYPASS: login goes straight to Home without opening the socket,
/// and Online Play opens the offline practice board instead of matchmaking.
/// Temporary while the server's chess socket URL is unknown (it 404s — see
/// docs/RUN_AND_TEST.md §9). Override per run with
/// `--dart-define=SOCKET_ENABLED=true|false`.
const bool _socketEnabled = false;
const String _socketDefine = String.fromEnvironment('SOCKET_ENABLED');
const bool kSocketEnabled = _socketDefine == '' ? _socketEnabled : _socketDefine == 'true';

/// App-wide realtime socket, opened right after a successful API login.
///
/// Flow (see Chess API.pdf §Game flow): API login → gateway token → open the
/// WebSocket → send `auth.login {token, username}` → on `auth.login_success`
/// the socket is Authenticated → the app navigates Home.
///
/// The `auth.login` event requires a `username`. The login flow passes the
/// account's real username (from /users/me) to [connect]; the build-time
/// `SOCKET_USERNAME` default is only a fallback for dev/relay testing when no
/// real identity is supplied.
class AppSocket {
  SocketClient? _client;
  String? _username;

  SocketClient? get client => _client;

  /// Build-time default identity, overridable per build:
  /// `--dart-define=SOCKET_USERNAME=test2`. Defaults to `test1`.
  static const _envUsername = String.fromEnvironment('SOCKET_USERNAME', defaultValue: 'test1');

  /// The identity sent on `auth.login`. An explicit [connect] username overrides
  /// it if provided.
  String get username => _username ??= _envUsername;

  bool get isConnected => _client?.status == SocketStatus.authenticated;

  /// Open + authenticate the socket. Completes when `auth.login_success`
  /// arrives; throws [SocketError]/[TimeoutException] on failure so the caller
  /// can decide whether to gate navigation on it. Pass [username] to send the
  /// real login identity (e.g. `auratester01`); omit it to use the fallback.
  Future<void> connect({required String token, String? username}) async {
    if (username != null && username.trim().isNotEmpty) _username = username.trim();
    // The gateway requires auth at the WS upgrade. Native can carry it in the
    // auth.login first frame, but browsers can't set WS headers — so when going
    // through the proxy the token rides as a query param (the proxy turns it
    // into a Bearer header upstream). [chessWsUrlWithToken] handles both.
    final uri = Uri.parse(chessWsUrlWithToken(token));
    final c = SocketClient(url: uri, headers: chessWsHeaders(token), requestTimeout: const Duration(seconds: 8));
    await c.connect();
    // Use the getter (not the param) so the fallback identity applies when no
    // username was supplied.
    await c.login(token: token, username: this.username);
    _client?.dispose();
    _client = c;
  }

  void disconnect() {
    _client?.dispose();
    _client = null;
  }
}

final appSocketProvider = Provider<AppSocket>((ref) {
  final socket = AppSocket();
  ref.onDispose(socket.disconnect);
  return socket;
});
