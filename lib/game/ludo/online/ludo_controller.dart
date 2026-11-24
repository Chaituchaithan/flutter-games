/// Online Ludo: the state machine over the Ludo socket (docs/services/ludo.md).
///
/// `lobby` (signed in) → `searching` (quick match) → `room` (seated,
/// waiting) → `game` → `result`. The room, lobby, chat, gifts and reconnect
/// handling are shared with the other rooms-family games
/// ([RoomController]); this adds Ludo's board. The board is redrawn only
/// from the server's `state`; local code never moves a pawn.
library;

import 'package:flutter/foundation.dart';

import '../../../services/socket/socket_client.dart';
import '../../common/online_room/room_controller.dart';
import '../ludo_engine.dart';
import 'ludo_models.dart';

export '../../common/online_room/room_controller.dart' show RoomPhase, RoomRequest;
export 'ludo_models.dart' show LudoRoomColor, LudoSeatColor;

typedef LudoPhase = RoomPhase;

/// Sends a request and awaits its reply (the shared socket's [SocketClient.request]).
typedef LudoRequest = RoomRequest;

/// A short message for the screen to show once (a toast).
typedef LudoNotice = RoomNotice;

class LudoController extends RoomController {
  LudoController({
    required super.request,
    required super.events,
    required super.myUserId,
    super.serverNow,
    super.maxTimeouts,
    super.onWalletChanged,
    super.onModeError,
    super.resyncWait,
  });

  LudoState? state;
  LudoLastAction? lastAction;

  /// The board, built from [state] (null before a game).
  LudoGame? board;

  /// My moveable pawns after my roll.
  List<int> _moveable = const [];

  /// The turn deadline last seen, and how long that turn was when it began
  /// (the ring's full length when no rule says it).
  DateTime? _deadlineSeen;
  Duration? _turnTotal;

  @override
  String? get currentMatchId => state?.matchId;

  @override
  bool get hasGameState => state != null;

  // ── Derived ──

  bool get myTurn => phase == LudoPhase.game && state?.currentTurnUserId == myUserId;
  bool get canRoll => myTurn && !(state?.pendingPawnSelection ?? true) && !busy && board?.pending == null;
  bool get canMove => myTurn && (state?.pendingPawnSelection ?? false) && !busy;
  List<int> get moveable => canMove ? _moveable : const [];

  LudoPlayerState? get me => state?.player(myUserId);
  int get mySeat => me?.seat ?? room?.seat ?? 0;
  LudoColor get myColor => seatColor(mySeat);

  @override
  String nameOf(String? userId) {
    if (userId == null) return 'Player';
    if (userId == myUserId) return 'You';
    return names[userId] ?? state?.playerNames[userId] ?? 'Player';
  }

  /// The full length of a turn, for the countdown ring.
  int get turnRingMs {
    final fromRules = (state?.rules['turn_ms'] as num?)?.toInt() ?? ((room?.rules['turn_seconds'] as num?)?.toInt() ?? 0) * 1000;
    if (fromRules > 0) return fromRules;
    if (turnMs != null && turnMs! > 0) return turnMs!;
    final measured = _turnTotal?.inMilliseconds ?? 0;
    return measured > 0 ? measured : 15000;
  }

  /// Time left on the current turn (null: no timer runs).
  Duration? get turnLeft => _left(state?.turnDeadline);

  /// Rush: time left on the match clock.
  Duration? get matchLeft => _left(state?.matchDeadline);

  Duration? _left(DateTime? deadline) {
    if (deadline == null || phase != LudoPhase.game) return null;
    final d = deadline.difference(serverNow());
    return d.isNegative ? Duration.zero : d;
  }

  /// Places when the game is over: (user, place), 1st first.
  List<LudoPlayerState> get standings {
    final ps = [...?state?.players];
    ps.sort((a, b) => (a.place ?? 99).compareTo(b.place ?? 99));
    return ps;
  }

  bool get iWon => state?.winner == myUserId || me?.place == 1;

  // ── Rooms ──

  /// A private room (`room.create`). Only the rule picks the mode lists.
  Future<bool> createRoom({
    String? modeCode,
    int? maxPlayers,
    int? color,
    int? turnSeconds,
    String? currency,
    int? betAmount,
    bool listed = false,
    Map<String, bool> rules = const {},
  }) => createRoomWith({
    'mode_code': ?modeCode,
    'max_players': ?maxPlayers,
    'color': ?color,
    'turn_seconds': ?turnSeconds,
    if (betAmount != null && betAmount > 0) ...{'currency': currency ?? 'token', 'bet_amount': betAmount},
    if (listed) 'listed': true,
    ...rules,
  });

  // ── Game ──

  Future<void> roll({bool double = false}) {
    if (!canRoll) return Future.value();
    return action({'action_type': 'roll_dice', if (double) 'double': true}, onResult: (r) {
      final roll = LudoRollResult.fromJson(r);
      if (roll != null && roll.mustSelectPawn) _moveable = roll.moveablePawns;
    });
  }

  Future<void> move(int pawnId) {
    if (!canMove || !_moveable.contains(pawnId)) return Future.value();
    return action({'action_type': 'move_pawn', 'pawn_id': pawnId});
  }

  Future<void> pickDie(int index) => action({'action_type': 'pick_die', 'index': index});
  Future<void> undo() => action({'action_type': 'undo'});
  Future<void> usePowerup(String code) => action({'action_type': 'use_powerup', 'powerup_code': code});

  /// Give up (asked first). With two players the other wins.
  Future<void> forfeit() => action({'action_type': 'forfeit'});

  // ── Frames from the server ──

  @override
  bool handleGame(SocketMessage m) {
    final d = m.data;
    switch (m.event) {
      case LudoEvent.gameStarted:
        _onStarted(d);
      case LudoEvent.stateUpdate:
        _onStateUpdate(d);
      case LudoEvent.stateSync:
        // Back in a running game after a reconnect (or a cold start).
        readOnly = false;
        _applyState(LudoState.fromJson(RoomController.mapOf(d['state'])));
        phase = LudoPhase.game;
        // Missed chat while away (ludo.md §7 step 3).
        loadMissedChat();
      case LudoEvent.finalState:
        // The game ended while away: the result, read-only.
        readOnly = true;
        _applyState(LudoState.fromJson(RoomController.mapOf(d['state'])));
        phase = LudoPhase.result;
      case LudoEvent.playerForfeited:
        forfeitNotice(d);
      case LudoEvent.powerupUsed:
        notify(LudoNotice('${nameOf('${d['user_id']}')} used ${'${d['powerup_code'] ?? 'a boost'}'.replaceAll('_', ' ')}.'));
      default:
        return false;
    }
    return true;
  }

  void _onStarted(Map<String, dynamic> d) {
    final st = LudoState.fromJson(RoomController.mapOf(d['state']));
    board?.dispose();
    board = null;
    startedFresh();
    _applyState(st);
    phase = LudoPhase.game;
  }

  void _onStateUpdate(Map<String, dynamic> d) {
    final before = state;
    final action = LudoLastAction.fromJson(d['last_action']);
    final st = LudoState.fromJson(RoomController.mapOf(d['state']));
    final previous = lastAction;
    lastAction = action;
    if (action != null) _countTimeouts(action, previous);
    if (action?.userId == myUserId && action?.rollResult != null && action!.rollResult!.mustSelectPawn) {
      _moveable = action.rollResult!.moveablePawns;
    }
    _applyState(st, action: action, before: before);
    if (d['game_over'] == true || st.completed) phase = LudoPhase.result;
  }

  /// "Time's up" when the server played a turn; warn before the last strike.
  void _countTimeouts(LudoLastAction a, LudoLastAction? previous) {
    final id = a.userId;
    if (id == null) return;
    if (!a.autoPlay) {
      if (a.actionType == 'roll_dice' || a.actionType == 'move_pawn') timeouts[id] = 0;
      return;
    }
    if (a.actionType == 'clock_expired') return;
    // An automatic roll and its automatic move are one timed-out turn.
    if (a.actionType == 'move_pawn' && previous != null && previous.autoPlay && previous.userId == id && previous.actionType == 'roll_dice') {
      return;
    }
    final n = (timeouts[id] ?? 0) + 1;
    timeouts[id] = n;
    if (id == myUserId && n >= maxTimeouts - 1) {
      notify(LudoNotice("Time's up. Play your turn or you'll be removed.", error: true, seatUserId: id));
    } else {
      notify(LudoNotice("Time's up", seatUserId: id));
    }
  }

  /// Redraw everything from [st]; animate [action] (dice, then the pawn).
  void _applyState(LudoState st, {LudoLastAction? action, LudoState? before}) {
    state = st;
    names.addAll(st.playerNames);
    if (st.players.isEmpty) return;
    var b = board;
    final colors = [for (final p in st.players) p.color];
    if (b == null || !listEquals(b.colors, colors)) {
      b?.dispose();
      b = board = LudoGame(colors: colors, layout: LudoLayout.server);
    }
    final current = st.player(st.currentTurnUserId ?? '')?.color;
    final mine = st.currentTurnUserId == myUserId && st.pendingPawnSelection;
    if (!mine) _moveable = const [];
    // Back mid-pick (state_sync carries no moveable list): work it out from
    // the board; the server still checks the move.
    if (mine && _moveable.isEmpty) _moveable = _moveableFrom(st);
    final deadline = st.turnDeadline;
    if (deadline != _deadlineSeen) {
      _deadlineSeen = deadline;
      if (deadline != null) _turnTotal = deadline.difference(serverNow());
    }
    final dice = action?.diceValue;
    if (dice != null && (action!.actionType == 'roll_dice' || action.actionType == 'roll_and_move' || action.actionType == 'pick_die')) {
      b.showRoll(dice);
    }
    final winner = st.player(st.winner ?? '')?.color;
    b.applyServer(
      positions: {for (final p in st.players) p.color: p.progress},
      current: current,
      rolled: mine ? st.lastDiceValue : null,
      movable: mine ? _moveable : const [],
      pending: _moveOf(action?.moveResult, action?.userId, st, before),
      winner: winner,
      text: action == null ? null : _describe(action),
    );
  }

  /// My pawns that can move with the last roll (6 to leave the base, no
  /// overshooting home).
  List<int> _moveableFrom(LudoState st) {
    final me = st.player(myUserId);
    final dice = st.lastDiceValue;
    if (me == null || dice == null) return const [];
    final home = LudoLayout.server.home;
    return [
      for (final p in me.pawns)
        if (p.progress(me.seat) == LudoRules.base ? dice == 6 : p.progress(me.seat) != home && p.progress(me.seat) + dice <= home) p.id,
    ];
  }

  /// The pawn move to animate (from → to, a capture flying home).
  LudoMove? _moveOf(LudoMoveResult? r, String? userId, LudoState st, LudoState? before) {
    if (r == null || userId == null) return null;
    final mover = st.player(userId) ?? before?.player(userId);
    if (mover == null) return null;
    // Where the pawn really was and is: the two board states are the truth.
    // The move's `from_position` / `to_position` text can leave out the
    // square (`home_stretch`, `on_board:start`), which made a 2 animate as
    // several hops; it is only the fallback now.
    LudoPawn? pawnIn(LudoState? s) => s?.player(userId)?.pawns.where((p) => p.id == r.pawnId).firstOrNull;
    final was = pawnIn(before), now = pawnIn(st);
    var from = was?.progress(mover.seat) ?? ludoProgressOf(mover.seat, r.fromPosition);
    final to = now?.progress(mover.seat) ?? ludoProgressOf(mover.seat, r.toPosition);
    if (from == to && r.fromPosition != null) return null;
    // Never more or fewer hops than the dice (a stale "before" after a missed
    // frame): walk the last [dice] squares into the real square.
    final dice = r.diceValue;
    if (dice != null && from != LudoRules.base && to != LudoRules.base && to - from != dice && to - dice >= 0) {
      debugPrint('[LUDO] move of ${to - from} squares for a $dice (${r.fromPosition} → ${r.toPosition}): animating $dice');
      from = to - dice;
    }
    final captured = <(LudoColor, int)>[];
    final capturedFrom = <(LudoColor, int), int>{};
    if (r.captured) {
      final victim = (seatColor(r.capturedSeat!), r.capturedPawnId!);
      captured.add(victim);
      final prev = before?.players.where((p) => p.seat == r.capturedSeat).firstOrNull;
      final at = prev != null && r.capturedPawnId! < prev.pawns.length ? prev.pawns[r.capturedPawnId!].progress(prev.seat) : null;
      // Fall back to the square the mover landed on.
      final landed = LudoRules.trackIndex(mover.color, to.clamp(0, 51));
      capturedFrom[victim] = at ?? (landed == null ? LudoRules.base : (landed - LudoRules.startIndex(victim.$1)) % 52);
    }
    return LudoMove(
      color: mover.color,
      token: r.pawnId,
      from: from,
      to: to,
      captured: captured,
      capturedFrom: capturedFrom,
    );
  }

  String _describe(LudoLastAction a) {
    final who = nameOf(a.userId);
    final m = a.moveResult;
    final prefix = a.autoPlay ? "Time's up · " : '';
    if (a.actionType == 'forfeit') return '$who gave up';
    if (a.actionType == 'undo') return '$who took back a move';
    if (a.actionType == 'clock_expired') return 'Time! The match clock ran out';
    if (m != null) {
      return prefix +
          switch (m.moveType) {
            'captured' || 'extra_turn:captured' => '$who captured a pawn',
            'entered' => '$who entered a pawn',
            'reached_home' => '$who brought a pawn home',
            'won' => '$who won!',
            'finished' => '$who finished',
            'shielded' => '$who’s pawn was shielded',
            'extra_turn:rolled_six' => '$who moved ${m.diceValue ?? ''} · rolls again',
            _ => '$who moved ${m.diceValue ?? ''}',
          };
    }
    if (a.rollResult?.turnForfeited == true || a.moveType == 'lost_turn_consecutive_sixes') return '$prefix$who rolled three 6s · turn lost';
    if (a.moveType == 'no_move' || a.moveType == 'no_pawn_moveable') return '$prefix$who rolled ${a.diceValue} · no move';
    if (a.diceValue != null) return '$prefix$who rolled ${a.diceValue}';
    return prefix + who;
  }

  @override
  void onActionError(SocketError e) {
    switch (e.code) {
      case 'invalid_state':
        // Usually a double tap: the latest state is already drawn.
        break;
      case 'game_over':
        setState(() => phase = LudoPhase.result);
      case 'not_found':
        notify(const LudoNotice('This game is over.', error: true));
        toLobby();
      default:
        notify(LudoNotice(ludoErrorText(e), error: true));
    }
  }

  @override
  String errorText(SocketError e, {String? event}) => ludoErrorText(e, event: event);

  @override
  void resetGame() {
    super.resetGame();
    state = null;
    lastAction = null;
    board?.dispose();
    board = null;
    _moveable = const [];
    _deadlineSeen = null;
    _turnTotal = null;
  }

  @override
  void dispose() {
    board?.dispose();
    super.dispose();
  }
}

/// Player-facing text for a refused Ludo request (ludo.md error tables).
/// Server messages are developer text, except a kill switch's.
String ludoErrorText(SocketError e, {String? event}) => roomErrorText(e, event: event);
