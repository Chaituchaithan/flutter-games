import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../configs/network_config.dart';
import 'socket_events.dart';
import 'ws_connect.dart';

/// Temporary capture switch: when true, raw turn/clock frames are printed to
/// the console (browser DevTools on web) with a `[CLOCK-CAPTURE]` prefix so the
/// server's per-move clock payload can be inspected. Set false to silence.
const bool kLogClockFrames = true;

/// Temporary: logs the socket handshake (WS open, connection.established, the
/// auth.login we send with the token masked, and auth/connection results) to
/// the console with a `[SOCKET]` prefix, so a failing connection can be
/// pinpointed. Set false to silence.
const bool kLogSocket = true;
void _slog(String msg) {
  if (kLogSocket) {
    // ignore: avoid_print
    print('[SOCKET] $msg');
  }
}

/// Masks a token for logging: keeps the first/last few chars only.
String _mask(String t) => t.length <= 10 ? '***' : '${t.substring(0, 6)}…${t.substring(t.length - 4)}';

/// A parsed envelope: `{ id?, event, data, error? }` (SOCKET_HOOKS.md §Message
/// Envelope). Broadcasts have no `id`; direct responses echo the request `id`.
class SocketMessage {
  const SocketMessage({this.id, required this.event, required this.data, this.error});
  final String? id;
  final String event;
  final Map<String, dynamic> data;
  final SocketError? error;

  bool get isError => error != null;

  factory SocketMessage.fromJson(Map<String, dynamic> json) => SocketMessage(
        id: json['id'] as String?,
        event: json['event'] as String? ?? '',
        data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        error: json['error'] is Map ? SocketError.fromJson((json['error'] as Map).cast<String, dynamic>()) : null,
      );
}

class SocketError implements Exception {
  const SocketError(this.code, this.message);
  final String code;
  final String message;
  factory SocketError.fromJson(Map<String, dynamic> j) =>
      SocketError(j['code'] as String? ?? 'unknown', j['message'] as String? ?? '');
  @override
  String toString() => 'SocketError($code): $message';
}

enum SocketStatus { disconnected, connecting, connected, authenticated, reconnecting }

/// Factory so tests can inject a fake channel.
typedef ChannelFactory = WebSocketChannel Function(Uri url);

/// Single-connection WebSocket client implementing the envelope protocol:
/// correlation-id request/response, broadcast stream, keepalive ping/pong,
/// and exponential-backoff reconnection with session resume.
class SocketClient {
  SocketClient({
    required this.url,
    ChannelFactory? channelFactory,
    this.pingInterval = NetworkConfig.socketPingInterval,
    this.requestTimeout = const Duration(seconds: 15),
    this.maxBackoff = NetworkConfig.socketMaxBackoff,
    Map<String, dynamic>? headers,
  }) : _channelFactory = channelFactory ?? ((u) => connectWs(u, headers: headers));

  final Uri url;
  final ChannelFactory _channelFactory;
  final Duration pingInterval;
  final Duration requestTimeout;
  final Duration maxBackoff;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _manuallyClosed = false;

  /// The token used to resume the session on reconnect (set after login).
  String? _sessionToken;

  /// Optional display/debug identity sent alongside the token on auth.login
  /// (the Chess API accepts a bare `username` as a throwaway identity).
  String? _username;

  int _idCounter = 0;
  final Map<String, Completer<SocketMessage>> _pending = {};

  final _broadcasts = StreamController<SocketMessage>.broadcast();
  final _status = StreamController<SocketStatus>.broadcast();
  SocketStatus _currentStatus = SocketStatus.disconnected;

  /// Server-initiated messages (no correlation id): room/game/chat pushes, etc.
  Stream<SocketMessage> get broadcasts => _broadcasts.stream;

  /// Connection status changes.
  Stream<SocketStatus> get statusStream => _status.stream;
  SocketStatus get status => _currentStatus;

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
    _slog('opening WS → $url');
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
          _slog('WS stream error (upgrade/transport): $e');
          _lastError = e;
          _onDone();
        },
        cancelOnError: false,
      );
    } catch (e) {
      _slog('WS open threw: $e');
      _lastError = e;
      if (_sessionToken != null) _scheduleReconnect();
      if (!established.isCompleted) established.completeError(SocketError('connect_failed', '$e'));
    }
    // `connection.established` resolves this. A failed upgrade (401/404) or a
    // server that never sends the handshake must surface as an error here —
    // otherwise the caller goes on to send auth.login on a dead channel and
    // only sees a misleading "Not connected"/timeout.
    try {
      await established.future.timeout(requestTimeout);
    } on TimeoutException {
      throw SocketError(
        'connect_timeout',
        _lastError != null
            ? 'WebSocket to $url failed: $_lastError'
            : 'No connection.established from $url within ${requestTimeout.inSeconds}s',
      );
    } finally {
      _pendingEstablished = null;
    }
  }

  /// The handshake being awaited by [_open], so a transport failure can fail
  /// it immediately instead of waiting for the timeout.
  Completer<void>? _pendingEstablished;

  /// Last transport/upgrade error, kept for a useful connect() failure message.
  Object? _lastError;

  void _onMessage(dynamic raw, [Completer<void>? established]) {
    Map<String, dynamic> json;
    try {
      json = (jsonDecode(raw as String) as Map).cast<String, dynamic>();
    } catch (_) {
      return; // ignore malformed frames
    }
    final msg = SocketMessage.fromJson(json);

    // ── Clock-protocol capture ──
    // Dumps the RAW server payload for turn/clock frames so we can see the
    // backend's authoritative per-move clock shape (game.turn_start /
    // game.turn_timeout) and wire the UI timer to it. Temporary: remove once
    // the server clock is wired in. Online only — Quick Play is local and never
    // opens a socket.
    if (kLogClockFrames &&
        (msg.event.contains('turn') ||
            msg.event.contains('timeout') ||
            msg.event == SocketEvent.gameStarted ||
            msg.event == SocketEvent.gameStateUpdate)) {
      // ignore: avoid_print
      print('[CLOCK-CAPTURE] ${msg.event} :: $raw');
    }

    // Handshake / auth visibility.
    if (msg.event == SocketEvent.established ||
        msg.event.startsWith('auth.') ||
        msg.event == SocketEvent.connectionError ||
        msg.event == SocketEvent.kicked) {
      _slog('recv ${msg.event}${msg.isError ? ' ERROR ${msg.error}' : ' ${msg.data}'}');
    }

    // Keepalive.
    if (msg.event == SocketEvent.established) {
      _setStatus(SocketStatus.connected);
      _reconnectAttempt = 0;
      _startPing();
      // Resume session if we have a token (reconnect path).
      if (_sessionToken != null) {
        send(SocketEvent.login, _loginData(_sessionToken!));
      }
      if (established != null && !established.isCompleted) established.complete();
      return;
    }
    if (msg.event == SocketEvent.pong) return;
    if (msg.event == SocketEvent.ping) {
      send(SocketEvent.pong, const {});
      return;
    }

    // Correlated response → complete the pending request.
    final id = msg.id;
    if (id != null && _pending.containsKey(id)) {
      final c = _pending.remove(id)!;
      if (msg.isError) {
        c.completeError(msg.error!);
      } else if (msg.event.endsWith('_error') || msg.event.endsWith('.error')) {
        // Some handlers put {code, message} in `data` instead of `error`
        // (SOCKET_HOOKS.md tables) — still a failure, not a success.
        c.completeError(SocketError(
          msg.data['code'] as String? ?? msg.event,
          msg.data['message'] as String? ?? '',
        ));
      } else {
        c.complete(msg);
      }
      return;
    }

    // Track auth state from broadcasts/responses.
    if (msg.event == SocketEvent.loginSuccess || msg.event == SocketEvent.registerSuccess) {
      _sessionToken = msg.data['token'] as String? ?? _sessionToken;
      _setStatus(SocketStatus.authenticated);
    } else if (msg.event == SocketEvent.tokenRefreshed) {
      _sessionToken = msg.data['token'] as String? ?? _sessionToken;
    }

    // Everything else is a server push.
    if (!_broadcasts.isClosed) _broadcasts.add(msg);
  }

  /// Fire-and-forget send (no response awaited). Adds no `id`.
  void send(String event, Map<String, dynamic> data) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode({'event': event, 'data': data}));
  }

  /// Send a request and await the correlated response. Throws [SocketError]
  /// on an error envelope, or [TimeoutException] if no reply arrives.
  Future<SocketMessage> request(String event, [Map<String, dynamic> data = const {}]) {
    final channel = _channel;
    if (channel == null) {
      return Future.error(const SocketError('disconnected', 'Not connected'));
    }
    final id = 'req_${_idCounter++}';
    final completer = Completer<SocketMessage>();
    _pending[id] = completer;
    channel.sink.add(jsonEncode({'id': id, 'event': event, 'data': data}));
    return completer.future.timeout(requestTimeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('No response for $event', requestTimeout);
    });
  }

  /// Authenticate with a token (first message after connect; also used on
  /// reconnect to resume). Stores the token + username for session resume.
  /// [username] is an optional identity the Chess API accepts alongside (or
  /// instead of) the JWT; see `auth.login` in Chess API.pdf.
  Future<SocketMessage> login({required String token, String? username}) async {
    if (username != null && username.isNotEmpty) _username = username;
    _slog('send auth.login { token: ${_mask(token)}, username: ${_username ?? "(none)"} }');
    final res = await request(SocketEvent.login, _loginData(token));
    _sessionToken = res.data['token'] as String? ?? token;
    _setStatus(SocketStatus.authenticated);
    return res;
  }

  /// Builds the `auth.login` payload: always the token, plus the username when
  /// one has been set.
  Map<String, dynamic> _loginData(String token) => {
        'token': token,
        if (_username != null && _username!.isNotEmpty) 'username': _username,
      };

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) => send(SocketEvent.ping, const {}));
  }

  void _onDone() {
    _slog('WS closed (code ${_channel?.closeCode}, reason ${_channel?.closeReason})');
    final hs = _pendingEstablished;
    if (hs != null && !hs.isCompleted) {
      hs.completeError(SocketError(
        'connect_failed',
        'WebSocket to $url closed before connection.established'
            '${_lastError != null ? ': $_lastError' : ' (upgrade rejected or wrong path?)'}',
      ));
    }
    _pingTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    _channel = null;
    // Fail any in-flight requests.
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(const SocketError('disconnected', 'Connection closed'));
    }
    _pending.clear();
    if (_manuallyClosed || hs != null && _sessionToken == null) {
      // Manual close, or the very first handshake failed: report it to the
      // caller instead of silently retrying forever in the background.
      _setStatus(SocketStatus.disconnected);
    } else {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _setStatus(SocketStatus.reconnecting);
    _reconnectAttempt++;
    // Exponential backoff with a cap (1s, 2s, 4s … maxBackoff).
    final ms = (1000 * (1 << (_reconnectAttempt - 1))).clamp(1000, maxBackoff.inMilliseconds);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: ms), () {
      if (!_manuallyClosed) _open().catchError((Object e) => _slog('reconnect failed: $e'));
    });
  }

  Future<void> close() async {
    _manuallyClosed = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
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
