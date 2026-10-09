import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../game/chess/chess_controller.dart';
import '../../game/chess/chess_engine.dart';
import '../dev_proxy.dart';
import 'socket_client.dart';
import 'socket_events.dart';

/// WebSocket URL for the chess service. Resolution mirrors [ApiClient]:
/// 1. explicit `--dart-define=CHESS_WS_URL=…` (wins — gateway/relay/staging);
/// 2. the local proxy (`tools/cors_proxy.dart`, which also proxies the WS) when
///    the proxy switch is ON (see `dev_proxy.dart`);
/// 3. the dev gateway default.
///
/// The gateway (169.58.184.121:30080) serves the WS at `/api/v1/ws`; the auth
/// token is sent in the `auth.login` first frame, not at the upgrade.
const _wsOverride = String.fromEnvironment('CHESS_WS_URL');
const _remoteWsUrl = 'ws://169.58.184.121:30080/api/v1/ws';
final chessWsUrl = _wsOverride.isNotEmpty
    ? _wsOverride
    : (kUseProxy ? '$kProxyWsBase/api/v1/ws' : _remoteWsUrl);

/// Whether the socket goes through the local dev proxy (proxy switch ON).
bool get _viaProxy => _wsOverride.isEmpty && kUseProxy;

/// The WS URL to actually dial.
///
/// The gateway requires auth at the upgrade. Through the proxy the token rides
/// as `?token=` (a browser can't set WS headers) and the proxy lifts it into a
/// Bearer header upstream. Direct, native sends it as a real header instead
/// (see [chessWsHeaders]). The token is ALSO
/// sent in the `auth.login` first frame either way.
String chessWsUrlWithToken(String token) {
  if (token.isEmpty || !_viaProxy) return chessWsUrl;
  final sep = chessWsUrl.contains('?') ? '&' : '?';
  return '$chessWsUrl${sep}token=${Uri.encodeQueryComponent(token)}';
}

/// Upgrade headers for native: `Authorization: Bearer <token>` (ignored on web).
Map<String, dynamic> chessWsHeaders(String token) =>
    token.isEmpty ? const {} : {'Authorization': 'Bearer $token'};

enum ChessPhase { idle, connecting, authenticated, searching, inRoom, inGame, completed, error }

/// Bridges the realtime socket protocol (Chess API) to a [ChessController].
///
/// Flow: connect → login → create/join/find → ready → game.started → moves
/// over `game.action` ↔ `game.state_update` → game.completed. Local moves are
/// applied optimistically and sent; opponent/bot moves arrive via
/// `last_action` and are mirrored into the engine.
class ChessSession extends ChangeNotifier {
  ChessSession({required this.socket, required this.userId}) {
    game.onLocalMove = _sendMove;
  }

  final SocketClient socket;

  /// This client's user id (from auth) — used to tell our own echoed moves
  /// apart from the opponent's.
  final String userId;

  final ChessController game = ChessController();

  ChessPhase phase = ChessPhase.idle;
  String? roomCode;
  PieceColor? myColor;
  String? matchId;

  /// Result/winner once the game ends ("white_wins" / "black_wins" / "draw").
  String? result;
  String? winnerId;

  /// Opponent's username from game.started (null until known).
  String? opponentName;

  /// Colour ("white"/"black") that ran out of move time, from game.turn_timeout.
  String? timedOutColor;

  /// What this player was paid on a wagered win (game.wallet_update).
  int? payout;

  /// Set when the opponent has an outstanding draw offer.
  String? drawOfferedBy;

  /// Countdown (seconds) once the room is full, before ready-up.
  int? countdown;

  // ── Server-driven per-move clock (from `game.turn_start`) ──
  /// Colour ("white"/"black") whose per-move clock is currently running, or
  /// null before the first turn opens.
  String? clockColor;

  /// Per-move time budget the server granted for the current turn (ms).
  int turnLimitMs = 30000;

  /// Local arrival time of the latest `game.turn_start` — remaining time is
  /// measured from here, so we don't depend on server/client epoch alignment.
  DateTime? _turnStartedAt;

  /// Milliseconds left on the active side's move, derived from the server's
  /// `time_limit_ms` and when its `game.turn_start` arrived.
  int clockRemainingMs() {
    final start = _turnStartedAt;
    if (start == null) return turnLimitMs;
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    return (turnLimitMs - elapsed).clamp(0, turnLimitMs);
  }

  /// True once the server has opened at least one turn (so the UI knows the
  /// clock is server-driven rather than a local stand-in).
  bool get hasServerClock => clockColor != null;

  /// In-room chat log (quick-chat phrases).
  final List<ChatLine> chat = [];

  String? lastError;

  StreamSubscription<SocketMessage>? _sub;

  bool get myTurn => myColor != null && game.state.turn == myColor && !game.isOver;

  void _setPhase(ChessPhase p) {
    phase = p;
    notifyListeners();
  }

  // ── Lifecycle ──

  /// Connect and authenticate (owns the socket), then listen for pushes.
  Future<void> start({required String token, String? username}) async {
    _setPhase(ChessPhase.connecting);
    try {
      await socket.connect();
      await socket.login(token: token, username: username);
      _sub = socket.broadcasts.listen(_onBroadcast);
      _setPhase(ChessPhase.authenticated);
    } on Object catch (e) {
      lastError = '$e';
      _setPhase(ChessPhase.error);
    }
  }

  /// Attach to an ALREADY-connected + authenticated socket (the shared app
  /// socket opened at login): just subscribe to broadcasts and mark
  /// authenticated. The caller then matchmakes. (Unlike [start], this does not
  /// own the socket and must not dispose it.)
  void attachAuthenticated() {
    _sub = socket.broadcasts.listen(_onBroadcast);
    _setPhase(ChessPhase.authenticated);
  }

  // ── Lobby ──

  Future<void> createRoom({required String currency, required int betAmount}) async {
    final res = await socket.request(SocketEvent.roomCreate, {'currency': currency, 'bet_amount': betAmount});
    _applyRoom(res.data);
    _setPhase(ChessPhase.inRoom);
  }

  Future<void> joinRoom(String code) async {
    final res = await socket.request(SocketEvent.roomJoin, {'room_code': code});
    _applyRoom(res.data);
    _setPhase(ChessPhase.inRoom);
  }

  Future<void> findMatch({required String currency, required int betAmount, String gameType = 'chess'}) async {
    _setPhase(ChessPhase.searching);
    final res = await socket.request(SocketEvent.matchFind, {
      'game_type': gameType,
      'currency': currency,
      'bet_amount': betAmount,
    });
    if (res.event == SocketEvent.matchFound) {
      _applyRoom(res.data);
      _setPhase(ChessPhase.inRoom);
    }
    // Otherwise match.searching → wait for the match.found broadcast.
  }

  Future<void> ready() => socket.request(SocketEvent.playerReady);
  Future<void> leave() => socket.request(SocketEvent.roomLeave);

  /// Seat/colour from a room.created / room.joined / match.found payload.
  void _applyRoom(Map<String, dynamic> data) {
    roomCode = data['room_code'] as String? ?? roomCode;
    final seat = data['seat'] as int?;
    final colorStr = data['color'] as String?;
    myColor = _parseColor(colorStr) ?? (seat == 0 ? PieceColor.white : seat == 1 ? PieceColor.black : myColor);
  }

  // ── Game actions ──

  void _sendMove(Move m) {
    final data = <String, dynamic>{'action_type': 'move', 'from': squareName(m.from), 'to': squareName(m.to)};
    if (m.promotion != null) data['promotion'] = _promoChar(m.promotion!);
    socket.request(SocketEvent.gameAction, data).catchError((Object e) {
      lastError = '$e';
      notifyListeners();
      // A rejected move (rare — same FIDE engine both sides) could be resynced
      // from a full state snapshot here in a later revision.
      return SocketMessage(event: SocketEvent.gameActionError, data: const {});
    });
  }

  /// Send a quick-chat phrase to the room (the server only accepts predefined
  /// phrases — see [quickChatPhrases]).
  void sendChat(String message) => socket.send(SocketEvent.chatSend, {'message': message});

  Future<void> resign() => socket.request(SocketEvent.gameAction, {'action_type': 'resign'});
  Future<void> offerDraw() => socket.request(SocketEvent.gameAction, {'action_type': 'offer_draw'});
  Future<void> acceptDraw() => socket.request(SocketEvent.gameAction, {'action_type': 'accept_draw'});
  Future<void> declineDraw() => socket.request(SocketEvent.gameAction, {'action_type': 'decline_draw'});

  // ── Inbound pushes ──

  void _onBroadcast(SocketMessage m) {
    switch (m.event) {
      case SocketEvent.roomUserJoined:
        if (m.data['room_full'] == true) countdown = m.data['countdown_seconds'] as int?;
        notifyListeners();
      case SocketEvent.matchFound:
        _applyRoom(m.data);
        _setPhase(ChessPhase.inRoom);
      case SocketEvent.gameStarted:
        _onStarted(m.data);
      case SocketEvent.gameStateUpdate:
        _onStateUpdate(m.data);
      case SocketEvent.gameTurnStart:
        _onTurnStart(m.data);
      case SocketEvent.gameTurnTimeout:
        // The server also sends game.completed right after; just stop ticking
        // the active clock here (the result handler ends the game).
        _turnStartedAt = null;
        timedOutColor = m.data['color'] as String?;
        notifyListeners();
      case 'game.wallet_update':
        // Two shapes (Chess API): WS path {winner_id, payout, rake}; bot path
        // {payouts: [{user_id, amount}]}.
        if (m.data['winner_id'] == userId) payout = (m.data['payout'] as num?)?.toInt();
        for (final p in (m.data['payouts'] as List? ?? const [])) {
          if (p is Map && p['user_id'] == userId) payout = (p['amount'] as num?)?.toInt();
        }
        notifyListeners();
      case 'game.completed':
        _onCompleted(m.data);
      case 'game.draw_offered':
        drawOfferedBy = m.data['offered_by'] as String?;
        notifyListeners();
      case 'game.draw_declined':
        drawOfferedBy = null;
        notifyListeners();
      case SocketEvent.chatMessage:
        chat.add(ChatLine(
          fromUserId: m.data['from_user_id'] as String? ?? '',
          username: m.data['username'] as String? ?? '',
          message: m.data['message'] as String? ?? '',
          mine: m.data['from_user_id'] == userId,
        ));
        notifyListeners();
      case SocketEvent.sessionExpired:
      case SocketEvent.kicked:
        lastError = m.data['reason'] as String? ?? 'Disconnected';
        _setPhase(ChessPhase.error);
    }
  }

  void _onStarted(Map<String, dynamic> data) {
    final state = (data['state'] as Map?)?.cast<String, dynamic>() ?? data;
    final players = (state['players'] as List?) ?? (data['players'] as List?);
    if (players != null) {
      for (final p in players.cast<Map>()) {
        if (p['user_id'] == userId) {
          myColor = _parseColor(p['color'] as String?) ?? (p['seat'] == 0 ? PieceColor.white : PieceColor.black);
        } else {
          opponentName = p['username'] as String? ?? opponentName;
        }
      }
    }
    matchId = state['match_id'] as String? ?? data['match_id'] as String?;
    game.reset();
    game.localColor = myColor;
    drawOfferedBy = null;
    _setPhase(ChessPhase.inGame);
  }

  void _onStateUpdate(Map<String, dynamic> data) {
    final last = (data['last_action'] as Map?)?.cast<String, dynamic>();
    if (last == null) return;
    // Our own move is already applied optimistically → ignore the echo.
    if (last['user_id'] == userId) return;
    final from = squareFromName(last['from'] as String? ?? '');
    final to = squareFromName(last['to'] as String? ?? '');
    if (from == null || to == null) return;
    final promo = _parsePromotion(last['algebraic'] as String?);
    game.applyExternalCoords(from, to, promotion: promo);
  }

  /// `game.turn_start`: the server opened a new per-move clock. Payload shape
  /// (relay / Chess API): `{ color, user_id, turn, time_limit_ms, deadline_ms,
  /// server_time_ms }`. We key remaining time off local arrival + time_limit_ms.
  void _onTurnStart(Map<String, dynamic> data) {
    clockColor = data['color'] as String?;
    final limit = (data['time_limit_ms'] as num?)?.toInt();
    if (limit != null && limit > 0) turnLimitMs = limit;
    _turnStartedAt = DateTime.now();
    notifyListeners();
  }

  void _onCompleted(Map<String, dynamic> data) {
    result = data['result'] as String?;
    winnerId = data['winner_id'] as String?;
    clockColor = null;
    _turnStartedAt = null;
    _setPhase(ChessPhase.completed);
  }

  @override
  void dispose() {
    _sub?.cancel();
    game.dispose();
    super.dispose();
  }
}

/// A received (or sent) quick-chat line.
class ChatLine {
  const ChatLine({required this.fromUserId, required this.username, required this.message, required this.mine});
  final String fromUserId;
  final String username;
  final String message;
  final bool mine;
}

/// Predefined quick-chat phrases (the server rejects anything else).
const quickChatPhrases = ['Good luck!', 'Nice move', 'Good game', 'Oops', 'Rematch?', 'Thanks!'];

PieceColor? _parseColor(String? s) => switch (s) {
      'white' => PieceColor.white,
      'black' => PieceColor.black,
      _ => null,
    };

String _promoChar(PieceType t) => switch (t) {
      PieceType.queen => 'q',
      PieceType.rook => 'r',
      PieceType.bishop => 'b',
      PieceType.knight => 'n',
      _ => 'q',
    };

/// Parse a promotion target out of SAN like "e8=Q+" → queen.
PieceType? _parsePromotion(String? algebraic) {
  if (algebraic == null || !algebraic.contains('=')) return null;
  final ch = algebraic.split('=').last.replaceAll(RegExp(r'[^QRBNqrbn]'), '');
  return switch (ch.toLowerCase()) {
    'q' => PieceType.queen,
    'r' => PieceType.rook,
    'b' => PieceType.bishop,
    'n' => PieceType.knight,
    _ => null,
  };
}
