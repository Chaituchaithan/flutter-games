import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../configs/network_config.dart';
import '../server_clock.dart';
import 'socket_events.dart';
import 'ws_connect.dart';

/// Logs the socket lifecycle with a `[SOCKET]` prefix: event names, error
/// codes and close codes only — never tokens, URLs with secrets, or frame
/// bodies (00-conventions.md "Security").
const bool kLogSocket = true;
void _slog(String msg) {
  if (kLogSocket) {
    // ignore: avoid_print
    print('[SOCKET] $msg');
  }
}

/// A parsed envelope: `{ id?, event, data, error? }` (00-conventions.md "The
/// envelope"). Broadcasts have no `id`; replies echo the request's `id`.
class SocketMessage {
  const SocketMessage({this.id, required this.event, required this.data, this.error});
  final String? id;
  final String event;
  final Map<String, dynamic> data;
  final SocketError? error;

  bool get isError => error != null;

  factory SocketMessage.fromJson(Map<String, dynamic> json) => SocketMessage(
    id: json['id']?.toString(),
    event: json['event'] as String? ?? '',
    data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
    error: json['error'] is Map ? SocketError.fromJson((json['error'] as Map).cast<String, dynamic>()) : null,
  );
}

/// A refused socket request. [code] is snake_case (`invalid_state`,
/// `duplicate`, `kill_switch_engaged`, …); [message] is developer text, except
/// for `kill_switch_engaged`, where it is the operator's text for players.
class SocketError implements Exception {
  const SocketError(this.code, this.message);
  final String code;
  final String message;
  factory SocketError.fromJson(Map<String, dynamic> j) =>
      SocketError(j['code'] as String? ?? 'unknown', j['message'] as String? ?? '');

  bool get isKillSwitch => code == 'kill_switch_engaged';

  @override
  String toString() => 'SocketError($code)';
}

/// Player-facing text for a socket failure: the operator's message on a kill
/// switch, otherwise [fallback] (error messages are developer text).
String socketErrorText(Object e, {required String fallback}) {
  if (e is SocketError) {
    if (e.isKillSwitch) return e.message.isNotEmpty ? e.message : 'New games are paused for a moment. Try again soon.';
    if (e.code == 'duplicate') return 'You are already signed in on another device.';
    if (e.code == 'rate_limited') return 'Too many actions. Slow down a little.';
  }
  return fallback;
}

/// The error a `*_error` / `*.error` frame carries: `error {code, message}`,
/// or `data {code | error, message}` (e.g. `game.start_error`).
SocketError errorFromData(SocketMessage msg) {
  if (msg.error != null) return msg.error!;
  final code = msg.data['code'] ?? msg.data['error'];
  return SocketError(code is String ? code : msg.event, msg.data['message'] as String? ?? '');
}

enum SocketStatus { disconnected, connecting, connected, authenticated, reconnecting }

/// Factory so tests can inject a fake connection.
typedef ChannelFactory = WebSocketChannel Function(Uri url);

/// One game-server WebSocket (00-conventions.md "Game sockets"):
///
/// 1. open `ws://<host>:<port>/ws` (no token in the URL) and wait for
///    `connection.established` (its `timestamp` sets [serverClockOffset]);
/// 2. `auth.login {token}`; until `auth.login_success` only `auth.login` and
///    `connection.ping` are accepted;
/// 3. requests carry an `id`, matched to the reply with the same `id`;
///    everything else goes to [broadcasts];
/// 4. before the token's `expires_at`, a fresh token is sent with
///    `auth.refresh` (the socket keeps its room and game);
/// 5. on a drop: reconnect after 0.5 s, 1 s, 2 s, then every 3 s, and sign in
///    again — the server restores the game within [reconnectWindow].
class SocketClient {
  SocketClient({
    required Uri url,
    ChannelFactory? channelFactory,
    this.pingInterval = NetworkConfig.socketPingInterval,
    this.requestTimeout = const Duration(seconds: 15),
    this.reauth,
  }) // Named params can't be private initializing formals.
    // ignore: prefer_initializing_formals
    : _url = url,
       _customFactory = channelFactory;

  Uri get url => _url;
  final Uri _url;
  final ChannelFactory? _customFactory;
  WebSocketChannel _channelFactory(Uri u) =>
      (_customFactory ?? (x) => connectWs(x, pingInterval: pingInterval))(u);

  /// A currently valid access token (refreshed at the gateway when it is
  /// about to expire). Used for `auth.refresh` and for signing in again after
  /// a reconnect. Null result = keep the current token.
  final Future<String?> Function()? reauth;
  final Duration pingInterval;
  final Duration requestTimeout;

  /// How long the server keeps a dropped player's seat (then: a forfeit).
  static const reconnectWindow = Duration(seconds: 30);

  /// Reconnect delays: 0.5 s, 1 s, 2 s, then every 3 s.
  static const backoff = [Duration(milliseconds: 500), Duration(seconds: 1), Duration(seconds: 2)];
  static const backoffSteady = Duration(seconds: 3);

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _refreshTimer;
  int _reconnectAttempt = 0;
  bool _manuallyClosed = false;

  /// The token used to sign in again after a reconnect (set by [login]).
  String? _sessionToken;

  int _idCounter = 0;
  final Map<String, Completer<SocketMessage>> _pending = {};

  final _broadcasts = StreamController<SocketMessage>.broadcast();
  final _status = StreamController<SocketStatus>.broadcast();
  SocketStatus _currentStatus = SocketStatus.disconnected;

  /// Server-initiated messages (no matching `id`): room/game/chat pushes, etc.
  Stream<SocketMessage> get broadcasts => _broadcasts.stream;

  /// Connection status changes.
  Stream<SocketStatus> get statusStream => _status.stream;
  SocketStatus get status => _currentStatus;

  /// `serverTimestamp - deviceNow` from `connection.established`. Draw
  /// countdowns from `deadline - serverNow()`: the phone's clock can be wrong.
  Duration serverClockOffset = Duration.zero;

  /// Now on the server's clock.
  DateTime serverNow() => DateTime.now().add(serverClockOffset);

  /// While reconnecting: when the server gives up the player's seat (drop +
  /// 30 s). Show "Reconnecting…" with a countdown to it. Null when connected.
  DateTime? get reconnectDeadline => _droppedAt?.add(reconnectWindow);
  DateTime? _droppedAt;

  void _setStatus(SocketStatus s) {
    _currentStatus = s;
    if (!_status.isClosed) _status.add(s);
  }

  /// Open the connection. Completes when `connection.established` arrives.
  Future<void> connect() async {
    _manuallyClosed = false;
    await _open();
  }

  Future<void> _open() async {
    _setStatus(_reconnectAttempt == 0 ? SocketStatus.connecting : SocketStatus.reconnecting);
    _slog('opening ${url.scheme}://${url.host}:${url.port}${url.path}');
    final established = Completer<void>();
    _pendingEstablished = established;
    _lastError = null;
    try {
      final channel = _channelFactory(url);
      _channel = channel;
      _sub = channel.stream.listen(
        (raw) => _onMessage(raw, established),
        onDone: _onDone,
        onError: (e) {
          _slog('stream error: ${e.runtimeType}');
          _lastError = e;
          _onDone();
        },
        cancelOnError: false,
      );
    } catch (e) {
      _slog('open failed: ${e.runtimeType}');
      _lastError = e;
      if (_sessionToken != null) _scheduleReconnect();
      if (!established.isCompleted) established.completeError(SocketError('connect_failed', '$e'));
    }
    // A refused upgrade or a server that never sends the handshake surfaces
    // here, not later as a misleading "Not connected".
    try {
      await established.future.timeout(requestTimeout);
    } on TimeoutException {
      throw SocketError(
        'connect_timeout',
        _lastError != null
            ? 'WebSocket to ${url.host}:${url.port} failed: $_lastError'
            : 'No connection.established within ${requestTimeout.inSeconds}s',
      );
    } finally {
      _pendingEstablished = null;
    }
  }

  Completer<void>? _pendingEstablished;
  Object? _lastError;

  void _onMessage(dynamic raw, [Completer<void>? established]) {
    Map<String, dynamic> json;
    try {
      json = (jsonDecode(raw as String) as Map).cast<String, dynamic>();
    } catch (_) {
      return; // ignore malformed frames
    }
    final msg = SocketMessage.fromJson(json);

    if (msg.event == SocketEvent.established ||
        msg.event.startsWith('auth.') ||
        msg.event == SocketEvent.connectionError ||
        msg.event == SocketEvent.kicked) {
      _slog('recv ${msg.event}${msg.isError ? ' error ${msg.error!.code}' : ''}');
    }

    if (msg.event == SocketEvent.established) {
      final ts = msg.data['timestamp'];
      if (ts is num) {
        serverClockOffset = Duration(milliseconds: ts.toInt() - DateTime.now().millisecondsSinceEpoch);
        ServerClock.fromSocket(ts.toInt());
      }
      _setStatus(SocketStatus.connected);
      _startPing();
      // Reconnect: sign in again; the server puts the player back in the game.
      if (_sessionToken != null) send(SocketEvent.login, {'token': _sessionToken});
      if (established != null && !established.isCompleted) established.complete();
      return;
    }
    // A reply to one of our requests → complete it (success or error). Checked
    // first: a requested ping's pong carries its id.
    final id = msg.id;
    if (id != null && _pending.containsKey(id)) {
      final c = _pending.remove(id)!;
      if (msg.isError) {
        c.completeError(msg.error!);
      } else if (msg.event.endsWith('_error') || msg.event.endsWith('.error')) {
        // Some handlers put {code, message} (or {error, message}) in `data`.
        c.completeError(errorFromData(msg));
      } else {
        c.complete(msg);
      }
      return;
    }
    if (msg.event == SocketEvent.pong) return; // our keep-alive pings
    if (msg.event == SocketEvent.ping) {
      send(SocketEvent.pong, const {});
      return;
    }

    switch (msg.event) {
      case SocketEvent.loginSuccess:
        // A sign-in after a reconnect (sent without an id).
        _onSignedIn(msg.data);
      case SocketEvent.loginError:
        // A sign-in after a reconnect was refused.
        _onReloginError(msg);
      case SocketEvent.tokenRefreshed:
        _scheduleTokenRefresh(msg.data['expires_at']);
      case SocketEvent.kicked:
        // `slow_consumer`: the app read too slowly → reconnect.
        final reason = msg.data['reason'] ?? msg.data['code'] ?? msg.error?.code;
        if (reason == 'slow_consumer') _channel?.sink.close();
    }

    if (!_broadcasts.isClosed) _broadcasts.add(msg);
  }

  bool _reloginRetried = false;

  /// `auth.login_error` after a reconnect: an expired token → get a fresh one
  /// and try once more; anything else (revoked, duplicate, banned) → stop.
  /// The frame is still broadcast so the app can sign out or tell the player.
  Future<void> _onReloginError(SocketMessage msg) async {
    final code = (msg.error ?? errorFromData(msg)).code;
    _slog('re-login refused: $code');
    if (code == 'invalid_credentials' && !_reloginRetried && reauth != null) {
      _reloginRetried = true;
      await _refreshCredentials();
      if (_channel != null && _sessionToken != null) send(SocketEvent.login, {'token': _sessionToken});
      return;
    }
    _sessionToken = null;
    await close();
  }

  void _onSignedIn(Map<String, dynamic> data) {
    _reloginRetried = false;
    _setStatus(SocketStatus.authenticated);
    _reconnectAttempt = 0;
    _droppedAt = null;
    _scheduleTokenRefresh(data['expires_at']);
  }

  /// Fire-and-forget send (no reply awaited, no `id`).
  void send(String event, [Map<String, dynamic>? data]) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode({'event': event, 'data': ?data}));
  }

  /// Send a request and await the reply with the same `id`. Throws
  /// [SocketError] on an error reply, or [TimeoutException] without a reply.
  Future<SocketMessage> request(String event, [Map<String, dynamic> data = const {}]) {
    final channel = _channel;
    if (channel == null) {
      return Future.error(const SocketError('disconnected', 'Not connected'));
    }
    final id = 'req_${_idCounter++}';
    final completer = Completer<SocketMessage>();
    _pending[id] = completer;
    channel.sink.add(jsonEncode({'id': id, 'event': event, 'data': data}));
    return completer.future.timeout(
      requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('No response for $event', requestTimeout);
      },
    );
  }

  /// `auth.login {token}` — the first request after [connect]. The token is
  /// kept to sign in again after a reconnect.
  Future<SocketMessage> login({required String token}) async {
    final res = await request(SocketEvent.login, {'token': token});
    _sessionToken = token;
    _onSignedIn(res.data);
    return res;
  }

  /// Before the token expires (`expires_at`, epoch seconds): refresh it at the
  /// gateway ([reauth]) and send `auth.refresh {token}`.
  void _scheduleTokenRefresh(Object? expiresAt) {
    _refreshTimer?.cancel();
    if (expiresAt is! num || reauth == null) return;
    final at = DateTime.fromMillisecondsSinceEpoch(expiresAt.toInt() * 1000);
    // Server-clock time → device time, then a minute early.
    var wait = at.difference(serverNow()) - NetworkConfig.refreshAhead;
    if (wait < const Duration(seconds: 5)) wait = const Duration(seconds: 5);
    _refreshTimer = Timer(wait, refreshToken);
  }

  /// Send a fresh token on the open socket (`auth.refresh`). Failures are
  /// left to the server: an expired socket gets `auth.session_expired`, closes,
  /// and the reconnect signs in with a fresh token.
  Future<void> refreshToken() async {
    final get = reauth;
    if (get == null || _currentStatus != SocketStatus.authenticated) return;
    try {
      final token = await get();
      if (token == null || token.isEmpty) return;
      final res = await request(SocketEvent.refresh, {'token': token});
      _sessionToken = token;
      _scheduleTokenRefresh(res.data['expires_at']);
    } on Object catch (e) {
      _slog('auth.refresh failed: ${e is SocketError ? e.code : e.runtimeType}');
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) => send(SocketEvent.ping));
  }

  void _onDone() {
    _slog('closed (code ${_channel?.closeCode})');
    final hs = _pendingEstablished;
    if (hs != null && !hs.isCompleted) {
      hs.completeError(
        SocketError(
          'connect_failed',
          'WebSocket to ${url.host}:${url.port} closed before connection.established'
              '${_lastError != null ? ': $_lastError' : ' (upgrade rejected or wrong path?)'}',
        ),
      );
    }
    _pingTimer?.cancel();
    _refreshTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    _channel = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(const SocketError('disconnected', 'Connection closed'));
    }
    _pending.clear();
    if (_manuallyClosed || hs != null && _sessionToken == null) {
      // Manual close, or the very first handshake failed: report it to the
      // caller instead of silently retrying in the background.
      _setStatus(SocketStatus.disconnected);
    } else {
      _droppedAt ??= DateTime.now();
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _setStatus(SocketStatus.reconnecting);
    final delay = _reconnectAttempt < backoff.length ? backoff[_reconnectAttempt] : backoffSteady;
    _reconnectAttempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (_manuallyClosed) return;
      await _refreshCredentials();
      if (!_manuallyClosed) _open().catchError((Object e) => _slog('reconnect failed'));
    });
  }

  /// Before a reconnect: a valid token for the new `auth.login`.
  Future<void> _refreshCredentials() async {
    final get = reauth;
    if (get == null) return;
    try {
      final token = await get();
      if (token != null && token.isNotEmpty) _sessionToken = token;
    } on Object catch (_) {
      _slog('reauth failed');
    }
  }

  Future<void> close() async {
    _manuallyClosed = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _refreshTimer?.cancel();
    _droppedAt = null;
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setStatus(SocketStatus.disconnected);
  }

  void dispose() {
    close();
    _broadcasts.close();
    _status.close();
  }
}
