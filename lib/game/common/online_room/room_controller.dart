/// The room and lobby half of a rooms-family game's state machine, shared by
/// online Ludo and online Snake & Ladder (same room protocol: ludo.md,
/// snake-and-ladder.md "Differences from Ludo").
///
/// `lobby` (signed in) → `searching` (quick match) → `room` (seated,
/// waiting) → `game` → `result`. This class owns the room, the lobby list,
/// chat, gifts, rematch, reconnect waits, notices and the request plumbing;
/// each game adds its own state and moves in [handleGame].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../services/socket/socket_client.dart';
import '../../../services/socket/socket_events.dart';
import 'room_models.dart';

enum RoomPhase { lobby, searching, room, game, result }

/// Sends a request and awaits its reply (the shared socket's [SocketClient.request]).
typedef RoomRequest = Future<SocketMessage> Function(String event, Map<String, dynamic> data);

abstract class RoomController extends ChangeNotifier {
  RoomController({
    required this.request,
    required Stream<SocketMessage> events,
    required this.myUserId,
    DateTime Function()? serverNow,
    this.maxTimeouts = 3,
    this.onWalletChanged,
    this.onModeError,
    this.resyncWait = const Duration(seconds: 3),
  }) : serverNow = serverNow ?? DateTime.now {
    _sub = events.listen(handle);
  }

  final RoomRequest request;
  final String myUserId;

  /// The server's clock (deadlines are on it).
  final DateTime Function() serverNow;

  /// Timed-out turns in a row before a player is out (the mode's
  /// `mode_config.timer.max_timeouts`).
  int maxTimeouts;

  /// A staked game paid out (`game.wallet_update`): re-read the balance.
  final VoidCallback? onWalletChanged;

  /// `invalid_mode` or `kill_switch_engaged`: (code, message) for the
  /// catalogue (refetch modes / pause the game).
  final void Function(String code, String message)? onModeError;

  /// How long to wait for a game after signing in again.
  final Duration resyncWait;

  /// The mode's turn length (`mode_config.timer.turn_ms`), when known.
  int? turnMs;

  late final StreamSubscription<SocketMessage> _sub;
  bool _disposed = false;
  bool get disposed => _disposed;

  RoomPhase phase = RoomPhase.lobby;
  RoomInfo? room;

  /// Open rooms (`room.list`).
  List<RoomSummary> openRooms = const [];
  final List<RoomChatLine> chat = [];
  final List<RoomGift> gifts = [];

  /// The pot and payouts of a staked game (a moment after it ends).
  RoomWalletUpdate? walletUpdate;

  /// The game ended while away (`game.final_state`): the result is read-only.
  bool readOnly = false;

  /// A tournament table cancelled by the engine (`game.cancelled`).
  String? cancelledReason;

  /// `game.rematch_offered`: who asks, and the new room's code.
  ({String fromUserId, String roomCode})? rematchOffer;

  /// An operator paused new games: their message; play buttons are disabled.
  String? killSwitchMessage;

  /// A request is in flight (disable its button).
  bool busy = false;

  /// The latest message to show; [noticeId] changes with each one.
  RoomNotice? notice;
  int noticeId = 0;

  /// Players whose socket dropped mid-game, and when (30 s to come back).
  final Map<String, DateTime> away = {};

  /// Timed-out turns in a row, per player.
  final Map<String, int> timeouts = {};

  /// `user_id` → name, from the room, the state and chat.
  final Map<String, String> names = {};

  /// After a reconnect: waits for `game.state_sync` / `game.final_state`.
  Timer? _resyncWait;

  /// The game this player left: its late frames are ignored.
  String? _leftMatchId;

  /// The last refused request's code.
  String? lastErrorCode;

  // ── For the game ──

  /// The running game's match id (null before a game).
  String? get currentMatchId;

  /// A game state is held (a resumed game has no room, only a state).
  bool get hasGameState;

  /// The game's own frames (game.started, state updates, forfeits, …).
  /// Returns true when the frame changed something to redraw.
  @protected
  bool handleGame(SocketMessage m);

  /// A refused `game.action`.
  @protected
  void onActionError(SocketError e);

  /// Player-facing text for a refused request.
  @protected
  String errorText(SocketError e, {String? event});

  /// Why a player was put out (`game.player_forfeited` `reason`).
  @protected
  String forfeitWhy(String? reason) => switch (reason) {
    'timeouts' || 'timeout' => 'ran out of time too often',
    'disconnected' => 'didn’t come back in time',
    'left' => 'left the game',
    'no_show' => 'didn’t show up',
    _ => 'gave up',
  };

  // ── Derived ──

  String nameOf(String? userId) {
    if (userId == null) return 'Player';
    if (userId == myUserId) return 'You';
    return names[userId] ?? 'Player';
  }

  // ── Lobby ──

  /// `room.list`: open rooms (quick-match lobbies and listed private rooms).
  Future<void> listRooms({String? variant, bool includeInPlay = false}) => run(RoomEvent.roomList, {
    'variant': ?variant,
    if (includeInPlay) 'include_in_play': true,
  }, onReply: (m) {
    openRooms = [
      for (final r in (m.data['rooms'] as List? ?? const []))
        if (r is Map) RoomSummary.fromJson(r.cast<String, dynamic>()),
    ];
  });

  /// Quick match (`match.find`). A bot fills an empty lobby after ~5 s.
  Future<void> quickMatch({String? modeCode, int? playerCount, String? currency, int? betAmount}) async {
    setState(() {
      phase = RoomPhase.searching;
      resetGame();
    });
    final ok = await run(RoomEvent.matchFind, {
      'mode_code': ?modeCode,
      'player_count': ?playerCount,
      'currency': ?currency,
      if (betAmount != null && betAmount > 0) 'bet_amount': betAmount,
    }, onReply: (m) => seat(RoomInfo.fromJson(m.data, quickMatch: true)));
    if (!ok) {
      if (phase == RoomPhase.searching) setState(() => phase = RoomPhase.lobby);
      return;
    }
    // Seated in a lobby: ready at once (a quick match has no waiting step).
    await ready();
  }

  /// Stop searching and leave the lobby (`match.cancel`).
  Future<void> cancelSearch() async {
    await run(RoomEvent.matchCancel, const {});
    toLobby();
  }

  /// `room.create` with the game's fields.
  @protected
  Future<bool> createRoomWith(Map<String, dynamic> data) {
    setState(resetGame);
    return run(RoomEvent.roomCreate, data, onReply: (m) => seat(RoomInfo.fromJson(m.data)));
  }

  /// Join with a friend's code (`room.join`; case doesn't matter).
  Future<bool> joinRoom(String code, {int? color, bool retried = false}) async {
    setState(resetGame);
    final ok = await run(RoomEvent.roomJoin, {'room_code': code.trim(), 'color': ?color}, quiet: const {'already_in_room'}, onReply: (m) {
      // A finished game answers with its result instead.
      if (m.event == RoomEvent.finalState) {
        handle(m);
        return;
      }
      final r = RoomInfo.fromJson(m.data);
      seat(r);
      // Back into a running game: `game.state_sync` follows.
      if (r.rejoined) phase = RoomPhase.game;
    });
    if (!ok && lastErrorCode == 'already_in_room' && !retried) {
      // Already seated in that waiting room, but this screen has no copy of
      // it: take the seat again to get the room (go to the waiting room).
      await run(RoomEvent.roomLeave, const {}, quiet: const {'not_in_room', 'not_found'});
      return joinRoom(code, color: color, retried: true);
    }
    return ok;
  }

  /// `room.leave`: back to the lobby. Mid-game it is a forfeit — the screen
  /// asks first.
  Future<void> leave() async {
    // Also after a resume (no room, only a state): the server must hear it.
    if (room != null || hasGameState) {
      _leftMatchId = currentMatchId;
      await run(RoomEvent.roomLeave, const {}, quiet: const {'not_in_room', 'not_found'});
    }
    toLobby();
  }

  Future<void> ready() => run(RoomEvent.ready, const {}, onReply: _onReadyUpdate);
  Future<void> unready() => run(RoomEvent.unready, const {}, onReply: _onReadyUpdate);

  /// Ask for a rematch: a new private room with the same settings.
  Future<void> rematch() async {
    final ok = await run(RoomEvent.rematch, const {}, onReply: (m) {
      resetGame();
      seat(RoomInfo.fromJson(m.data));
    });
    if (ok) notify(const RoomNotice('Rematch room created. Waiting for the others.'));
  }

  /// Join the offered rematch: leave this room, then join the new one.
  Future<void> acceptRematch() async {
    final offer = rematchOffer;
    if (offer == null) return;
    await run(RoomEvent.roomLeave, const {});
    rematchOffer = null;
    await joinRoom(offer.roomCode);
  }

  // ── Chat and gifts ──

  /// One of [roomQuickChat] (sent in English; the screen translates).
  Future<void> sendChat(String line, {bool team = false}) async {
    if (!roomQuickChat.contains(line)) return;
    // No reply of its own: the line comes back as the room's chat.message.
    await run(RoomEvent.chatSend, {'message': line, if (team) 'team': true}, expectReply: false);
  }

  Future<void> loadChatHistory({int limit = 50}) => run(RoomEvent.chatHistory, {'limit': limit}, lock: false, onReply: (m) {
    chat
      ..clear()
      ..addAll([
        for (final l in (m.data['messages'] as List? ?? const []))
          if (l is Map) RoomChatLine.fromJson(l.cast<String, dynamic>()),
      ]);
  });

  /// Pays another player in the room at once (confirmed by the screen first).
  Future<bool> sendGift({
    required String receiverId,
    required int amount,
    String currency = 'token',
    String? itemType,
    String? message,
  }) async {
    final ok = await run(RoomEvent.giftSend, {
      'receiver_id': receiverId,
      'amount': amount,
      'currency': currency,
      'item_type': ?itemType,
      'message': ?message,
    });
    if (ok) notify(RoomNotice('Gift sent to ${nameOf(receiverId)}.'));
    return ok;
  }

  // ── Frames from the server ──

  static bool _isGameFrame(String e) => e == RoomEvent.stateUpdate || e == RoomEvent.stateSync || e == RoomEvent.finalState;

  /// Every pushed frame (no matching request id).
  void handle(SocketMessage m) {
    if (_disposed) return;
    final d = m.data;
    if (_isGameFrame(m.event)) {
      final matchId = '${d['match_id'] ?? mapOf(d['state'])['match_id'] ?? ''}';
      // Late frames of a game this player left.
      if (_leftMatchId != null && matchId == _leftMatchId) return;
      // A stray update while not in a game (resumes come as state_sync).
      if (m.event == RoomEvent.stateUpdate && (phase == RoomPhase.lobby || phase == RoomPhase.searching)) return;
      if (m.event != RoomEvent.stateUpdate) _resyncWait?.cancel();
    }
    switch (m.event) {
      case RoomEvent.matchFound:
        if (phase == RoomPhase.searching) seat(RoomInfo.fromJson(d, quickMatch: true));
      case RoomEvent.userJoined:
        final id = '${d['user_id'] ?? ''}';
        away.remove(id);
        if (d['reconnected'] == true) {
          // Back after a drop: only {user_id, reconnected}. Keep the name and seat.
          final name = roomStr(d['username']);
          if (name != null) names[id] = name;
          notify(RoomNotice('${nameOf(id)} is back.'));
          return;
        }
        final seat = RoomSeat.fromJson(d);
        names[seat.userId] = seat.username;
        final r = room;
        if (r != null && phase == RoomPhase.room) {
          room = r.withPlayers([...r.players.where((p) => p.userId != seat.userId && p.seat != seat.seat), seat]);
        }
      case RoomEvent.userLeft:
        final id = '${d['user_id'] ?? ''}';
        if (phase == RoomPhase.game) {
          // Mid-game: "Reconnecting…" on that seat for 30 s.
          away[id] = DateTime.now();
        } else if (room != null) {
          room = room!.withPlayers(room!.players.where((p) => p.userId != id).toList());
        }
      case RoomEvent.readyUpdate:
        _onReadyUpdate(m);
      case RoomEvent.startError:
        // Stakes couldn't be taken: refunded, ready flags cleared, waiting again.
        final r = room;
        if (r != null) room = r.withPlayers([for (final p in r.players) p.copyWith(ready: false)]);
        final code = errorFromData(m).code;
        notify(RoomNotice(
          code == 'insufficient_funds'
              ? 'A player doesn’t have enough for this stake. The game didn’t start.'
              : 'The game couldn’t start. Ready up to try again.',
          error: true,
        ));
      case RoomEvent.walletUpdate:
        walletUpdate = RoomWalletUpdate.fromJson(d);
        onWalletChanged?.call();
      case RoomEvent.rematchOffered:
        final from = '${d['from_user_id'] ?? ''}';
        if (from != myUserId) rematchOffer = (fromUserId: from, roomCode: '${d['room_code'] ?? ''}');
      case RoomEvent.cancelled:
        cancelledReason = '${d['reason'] ?? 'cancelled'}';
        phase = RoomPhase.result;
        notify(const RoomNotice('This table was cancelled.', error: true));
      case RoomEvent.chatMessage:
        final line = RoomChatLine.fromJson(d);
        names.putIfAbsent(line.fromUserId, () => line.username);
        chat.add(line);
        if (chat.length > 100) chat.removeAt(0);
      case RoomEvent.giftReceived:
        final g = RoomGift.fromJson(d);
        gifts.add(g);
        notify(RoomNotice(
          g.receiverId == myUserId
              ? '${g.senderName} sent you ${g.amount} ${g.currency == 'gold' ? 'gold' : 'tokens'}.'
              : '${g.senderName} sent ${nameOf(g.receiverId)} a ${g.itemType}.',
          seatUserId: g.receiverId,
        ));
      case SocketEvent.loginSuccess:
        // Signed in again after a reconnect: a game to go back to arrives at
        // once; nothing more means there is none → the lobby.
        if ((phase == RoomPhase.game || phase == RoomPhase.room) && !readOnly) {
          _resyncWait?.cancel();
          _resyncWait = Timer(resyncWait, () {
            if (_disposed || !(phase == RoomPhase.game || phase == RoomPhase.room)) return;
            notify(const RoomNotice('That game is over. You’re back in the lobby.'));
            toLobby();
          });
        }
        return;
      case SocketEvent.loginError:
        if (phase == RoomPhase.game || phase == RoomPhase.room) {
          notify(const RoomNotice('Couldn’t get back into the game. Sign in again.', error: true));
        }
      case 'auth.session_expired':
        notify(const RoomNotice('Reconnecting…'));
      default:
        if (!handleGame(m)) return;
    }
    changed();
  }

  /// "Name gave up." for a `game.player_forfeited`.
  @protected
  void forfeitNotice(Map<String, dynamic> d) {
    final id = '${d['user_id'] ?? ''}';
    away.remove(id);
    final why = forfeitWhy(roomStr(d['reason']));
    notify(RoomNotice(id == myUserId ? 'You’re out of the game: you $why.' : '${nameOf(id)} $why.', seatUserId: id));
  }

  /// A resumed game (state_sync): missed chat while away.
  @protected
  void loadMissedChat() => unawaited(loadChatHistory());

  void _onReadyUpdate(SocketMessage m) {
    final id = '${m.data['user_id'] ?? ''}';
    final r = room;
    if (r == null) return;
    room = r.withPlayers([for (final p in r.players) p.userId == id ? p.copyWith(ready: m.data['ready'] == true) : p]);
  }

  /// A new game began: clear the last game's leftovers.
  @protected
  void startedFresh() {
    timeouts.clear();
    away.clear();
    walletUpdate = null;
    rematchOffer = null;
    readOnly = false;
    _leftMatchId = null;
  }

  // ── Requests ──

  /// A `game.action`; a `busy` reply is retried once.
  @protected
  Future<void> action(Map<String, dynamic> data, {void Function(Map<String, dynamic> result)? onResult}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        setState(() => busy = true);
        final res = await request(RoomEvent.action, data);
        final result = res.data['result'];
        if (result is Map) onResult?.call(result.cast<String, dynamic>());
        return;
      } on SocketError catch (e) {
        // `busy`: the match lock wasn't free — retry once.
        if (e.code == 'busy' && attempt == 0) continue;
        onActionError(e);
        return;
      } on TimeoutException {
        // The state_update still tells everyone what happened.
        return;
      } finally {
        setState(() => busy = false);
      }
    }
  }

  /// One request; true when it was answered without an error.
  @protected
  Future<bool> run(
    String event,
    Map<String, dynamic> data, {
    void Function(SocketMessage reply)? onReply,
    bool expectReply = true,
    bool lock = true,
    Set<String> quiet = const {},
  }) async {
    if (_disposed) return false;
    lastErrorCode = null;
    // A fire-and-forget request (chat) or a background read must not lock
    // the board while it waits.
    final locks = expectReply && lock;
    if (locks) setState(() => busy = true);
    try {
      final res = await request(event, data);
      onReply?.call(res);
      if (killSwitchMessage != null && _startsSomething(event)) killSwitchMessage = null;
      return true;
    } on SocketError catch (e) {
      lastErrorCode = e.code;
      if (e.isKillSwitch) killSwitchMessage = socketErrorText(e, fallback: '');
      if (e.isKillSwitch || e.code == 'invalid_mode') onModeError?.call(e.code, e.message);
      if (quiet.contains(e.code)) return false;
      notify(RoomNotice(errorText(e, event: event), error: true));
      return false;
    } on TimeoutException {
      if (!expectReply || !lock) return !expectReply;
      notify(const RoomNotice('The game server didn’t answer. Try again.', error: true));
      return false;
    } finally {
      if (locks) setState(() => busy = false);
    }
  }

  static bool _startsSomething(String event) =>
      {RoomEvent.matchFind, RoomEvent.roomCreate, RoomEvent.roomJoin, RoomEvent.ready, RoomEvent.rematch}.contains(event);

  @protected
  void seat(RoomInfo r) {
    // Snake & Ladder's room.created has no players list: the host is alone
    // on its seat.
    if (!r.players.any((p) => p.userId == myUserId)) {
      r = r.withPlayers([...r.players, RoomSeat(userId: myUserId, username: names[myUserId] ?? 'You', seat: r.seat)]);
    }
    room = r;
    for (final p in r.players) {
      names[p.userId] = p.username;
    }
    phase = RoomPhase.room;
  }

  /// Forget the room and the game (the game adds its own state).
  @protected
  @mustCallSuper
  void resetGame() {
    room = null;
    walletUpdate = null;
    readOnly = false;
    cancelledReason = null;
    rematchOffer = null;
    away.clear();
    timeouts.clear();
    _resyncWait?.cancel();
  }

  @protected
  void toLobby() => setState(() {
    resetGame();
    chat.clear();
    phase = RoomPhase.lobby;
  });

  @protected
  void notify(RoomNotice n) {
    notice = n;
    noticeId++;
    changed();
  }

  @protected
  void setState(void Function() f) {
    f();
    changed();
  }

  @protected
  void changed() {
    if (!_disposed) notifyListeners();
  }

  static Map<String, dynamic> mapOf(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};

  @override
  void dispose() {
    _disposed = true;
    _resyncWait?.cancel();
    _sub.cancel();
    super.dispose();
  }
}

/// Player-facing text for the room protocol's common error codes. Server
/// messages are developer text, except a kill switch's.
String roomErrorText(SocketError e, {String? event}) => switch (e.code) {
  'kill_switch_engaged' => socketErrorText(e, fallback: 'New games are paused for a moment.'),
  'not_found' when event == RoomEvent.roomJoin => 'No room with that code.',
  'not_found' => 'That room or game no longer exists.',
  'room_full' => 'That room is full.',
  'game_in_progress' => 'That game has already started.',
  'not_your_table' => 'This tournament table has no seat for you.',
  'insufficient_funds' => 'Not enough tokens or gold for this table. Try a lower stake or visit the shop.',
  'invalid_mode' => 'That mode isn’t available right now.',
  'invalid_settings' => 'Those room settings aren’t allowed for this mode.',
  'invalid_state' when event == RoomEvent.matchCancel => 'The game has already started.',
  'invalid_state' => 'That isn’t possible right now.',
  'not_in_room' => 'You’re not in a room.',
  'duplicate' => 'You are already signed in on another device.',
  'busy' || 'internal_error' => 'The game server is busy. Try again.',
  'rate_limited' => 'Too many actions. Slow down a little.',
  'invalid_request' => 'Something went wrong. Try again.',
  _ => 'Something went wrong. Try again.',
};
