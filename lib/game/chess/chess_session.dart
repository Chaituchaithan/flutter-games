import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:snakeladder/game/chess/chess_controller.dart';
import 'package:snakeladder/game/chess/chess_engine.dart';
import 'package:snakeladder/configs/configs.dart';
import 'package:snakeladder/services/game_session.dart';
import 'package:snakeladder/services/socket/socket_client.dart';
import 'package:snakeladder/services/socket/socket_events.dart';

/// Chess socket endpoints — resolved from [chessConfig] by [GameEndpoints]
/// (`CHESS_WS_URL` override → dev proxy → host:port/path). See lib/configs.
const chessEndpoints = GameEndpoints(chessConfig);

enum ChessPhase { idle, connecting, authenticated, searching, inRoom, inGame, completed, error }

/// Bridges the realtime socket protocol (Chess API) to a [ChessController].
///
/// Flow: connect → login → create/join/find → ready → game.started → moves
/// over `game.action` ↔ `game.state_update` → game.completed. Local moves are
/// applied optimistically and sent; opponent/bot moves arrive via
/// `last_action` and are mirrored into the engine.
class ChessSession extends ChangeNotifier implements GameSession {
  @override
  GameConfig get config => chessConfig;

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

  /// The match couldn't start (`game.start_error`, e.g. stake not covered).
  bool startFailed = false;

  /// room.create / room.join was refused (bad code, room full, …).
  bool roomFailed = false;

  /// Room stake + currency as the server reports them (a joiner only learns
  /// the host's stake this way). Null until sent.
  int? betAmount;
  String? currency;

  /// Colour ("white"/"black") that ran out of move time, from game.turn_timeout.
  String? timedOutColor;

  /// What this player was paid on a wagered win (game.wallet_update).
  int? payout;

  /// Set when the opponent has an outstanding draw offer.
  String? drawOfferedBy;

  /// Countdown (seconds) once the room is full, before ready-up.
  int? countdown;

  /// An opponent has taken the other seat (room full / game started) — the
  /// matchmaking screen stops its search countdown and reveals them.
  bool opponentJoined = false;

  /// The server gave up the search (`match.timeout`).
  bool searchTimedOut = false;

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
  @override
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

  @override
  Future<void> createRoom({required String currency, required int betAmount}) async {
    try {
      final res = await socket.request(SocketEvent.roomCreate, {'currency': currency, 'bet_amount': betAmount});
      _applyRoom(res.data);
      _setPhase(ChessPhase.inRoom);
    } on SocketError catch (e) {
      _onRoomFailed(e.code, e.message);
    }
  }

  @override
  Future<void> joinRoom(String code) async {
    try {
      final res = await socket.request(SocketEvent.roomJoin, {'room_code': code});
      _applyRoom(res.data);
      _setPhase(ChessPhase.inRoom);
    } on SocketError catch (e) {
      _onRoomFailed(e.code, e.message);
    }
  }

  /// room.create_error / room.join_error → a plain reason on the error view.
  void _onRoomFailed(String code, String message) {
    roomFailed = true;
    lastError = switch (code) {
      'not_found' => 'No room with that code. Check it with your friend.',
      'full' => 'That room is already full.',
      'already_in_room' => 'You’re still in another room. Go back and try again.',
      'insufficient_balance' => 'Not enough balance for this stake. Top up in the Store and try again.',
      _ => message.isNotEmpty ? message : 'Couldn’t open the room. Please try again.',
    };
    _setPhase(ChessPhase.error);
  }

  @override
  Future<void> findMatch({required String currency, required int betAmount, int? seat}) async {
    _setPhase(ChessPhase.searching);
    // {game_type, player_count, currency, bet_amount, seat} — seat = preferred
    // colour (ChessSeats: 0 White, 1 Black); omitted = no preference.
    final res = await socket.request(SocketEvent.matchFind, {
      'game_type': 'chess',
      'player_count': config.maxPlayers,
      'currency': currency,
      'bet_amount': betAmount,
      'seat': ?seat,
    });
    if (res.event == SocketEvent.matchFound) {
      _applyRoom(res.data);
      _setPhase(ChessPhase.inRoom);
    }
    // Otherwise match.searching → wait for the match.found broadcast.
  }

  /// Leave the matchmaking queue (`match.cancel`) — on Cancel or timeout.
  @override
  Future<void> cancelMatch() async {
    try {
      await socket.request(SocketEvent.matchCancel);
    } on Object {
      // Best effort: the screen is leaving anyway.
    }
  }

  /// Ready up. If the start fails (stake not covered, server error) the reply
  /// is an error — e.g. `game.start_error` — and the session shows why.
  @override
  Future<void> ready() async {
    try {
      await socket.request(SocketEvent.playerReady);
    } on SocketError catch (e) {
      _onStartFailed(e.code, e.message);
    } on TimeoutException {
      // No direct reply is fine: game.started arrives as a broadcast.
    }
  }

  /// The server couldn't start the match (e.g. the stake couldn't be taken).
  void _onStartFailed(String code, String message) {
    startFailed = true;
    lastError = code == 'insufficient_balance' || message.toLowerCase().contains('balance')
        ? 'Not enough balance for this stake. Top up in the Store and try again.'
        : (message.isNotEmpty ? message : 'The match couldn’t start. Please try again.');
    _setPhase(ChessPhase.error);
  }
  @override
  Future<void> leave() => socket.request(SocketEvent.roomLeave);

  /// Seat/colour from a room.created / room.joined / match.found payload.
  void _applyRoom(Map<String, dynamic> data) {
    roomCode = data['room_code'] as String? ?? roomCode;
    _applyStake(data);
    final seat = data['seat'] as int?;
    final colorStr = data['color'] as String?;
    myColor = _parseColor(colorStr) ??
        (seat == ChessSeats.white ? PieceColor.white : seat == ChessSeats.black ? PieceColor.black : myColor);
  }

  void _applyStake(Map<String, dynamic> data) {
    betAmount = (data['bet_amount'] as num?)?.toInt() ?? betAmount;
    currency = data['currency'] as String? ?? currency;
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
  @override
  void sendChat(String message) => socket.send(SocketEvent.chatSend, {'message': message});

  @override
  Future<void> resign() => socket.request(SocketEvent.gameAction, {'action_type': 'resign'});
  Future<void> offerDraw() => socket.request(SocketEvent.gameAction, {'action_type': 'offer_draw'});
  Future<void> acceptDraw() => socket.request(SocketEvent.gameAction, {'action_type': 'accept_draw'});
  Future<void> declineDraw() => socket.request(SocketEvent.gameAction, {'action_type': 'decline_draw'});

  // ── Inbound pushes ──

  void _onBroadcast(SocketMessage m) {
    switch (m.event) {
      case SocketEvent.roomUserJoined:
        final joined = m.data['username'] as String?;
        if (joined != null && m.data['user_id'] != userId) opponentName = joined;
        if (m.data['room_full'] == true) {
          countdown = m.data['countdown_seconds'] as int?;
          opponentJoined = true;
        }
        notifyListeners();
      case SocketEvent.matchTimeout:
        searchTimedOut = true;
        notifyListeners();
      case SocketEvent.matchFound:
        _applyRoom(m.data);
        _setPhase(ChessPhase.inRoom);
      case 'game.start_error':
        _onStartFailed(m.error?.code ?? m.data['code'] as String? ?? '',
            m.error?.message ?? m.data['message'] as String? ?? '');
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
          myColor = _parseColor(p['color'] as String?) ??
              (p['seat'] == ChessSeats.white ? PieceColor.white : PieceColor.black);
        } else {
          opponentName = p['username'] as String? ?? opponentName;
        }
      }
    }
    matchId = state['match_id'] as String? ?? data['match_id'] as String?;
    _applyStake(state);
    _applyStake(data);
    opponentJoined = true;
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
  /// (Chess API): `{ color, user_id, turn, time_limit_ms, deadline_ms,
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
