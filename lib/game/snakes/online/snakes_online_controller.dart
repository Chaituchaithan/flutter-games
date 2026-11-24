/// Online Snake & Ladder: the state machine over its socket
/// (docs/services/snake-and-ladder.md).
///
/// `lobby` (signed in) → `searching` (quick match) → `room` (seated,
/// waiting) → `game` → `result`. The room, lobby, chat, gifts, rematch and
/// reconnect handling are shared with Ludo ([RoomController]); this adds the
/// board, rolls, boosts and the two ways a game ends. Tokens move only from
/// server frames, never from a local guess.
library;

import 'package:flutter/foundation.dart';

import '../../../services/socket/socket_client.dart';
import '../../common/online_room/room_controller.dart';
import '../snakes_engine.dart';
import 'snakes_online_board.dart';
import 'snakes_online_models.dart';

export '../../common/online_room/room_controller.dart' show RoomPhase, RoomRequest;

class SnlController extends RoomController {
  SnlController({
    required super.request,
    required super.events,
    required super.myUserId,
    super.serverNow,
    super.maxTimeouts = 5,
    super.onWalletChanged,
    super.onModeError,
    super.resyncWait,
    this.onBoostsChanged,
    this.onUnknownPlayers,
  });

  /// This player switched a boost on (re-read the inventory).
  final VoidCallback? onBoostsChanged;

  /// Players with no name yet (a cold start: the state carries none). The
  /// screen looks them up and calls [setName].
  final void Function(List<String> userIds)? onUnknownPlayers;

  SnlState? state;
  SnlRoll? lastAction;

  /// The board, built from [state] (null before a game).
  SnlBoardGame? board;

  /// The bet ladder for a private room's stake picker (`wallet.bet_options`).
  SnlBetOffer? betOffer;

  /// Players the last roll passed over (venom), for a mark on their seat.
  Set<String> skipped = const {};

  /// My last roll's ack (the second die and the boosts that acted).
  SnlRoll? _myAck;

  DateTime? _deadlineSeen;
  Duration? _turnTotal;
  final Set<String> _askedNames = {};

  @override
  String? get currentMatchId => state?.matchId;

  @override
  bool get hasGameState => state != null;

  // ── Derived ──

  bool get myTurn => phase == RoomPhase.game && state?.currentTurnUserId == myUserId && !(me?.forfeited ?? false);
  bool get canRoll => myTurn && !busy && board?.pending == null;

  SnlPlayer? get me => state?.player(myUserId);

  /// The board to draw in the waiting room: `room.created`'s `board`, else
  /// the known board of `board_layout`.
  SnakesLayout? get previewBoard {
    final r = room;
    if (r == null) return null;
    return SnlBoards.fromRoomBoard(r.raw['board']) ?? SnlBoards.of(r.variant);
  }

  /// The room's rules (the game state's once a game runs).
  Map<String, dynamic> get rules => (state?.rules.isNotEmpty ?? false) ? state!.rules : (room?.rules ?? const {});

  /// Boosts can be switched on in this room.
  bool get boostsOn => rules['powerups_enabled'] != false;

  /// Whether the room allows [code] (`pu_*` rules; ranked rooms refuse the
  /// Snake Charmer).
  bool boostAllowed(String code) {
    if (!boostsOn) return false;
    final r = rules;
    return switch (code) {
      'sl_antivenom' => r['pu_anti_venom'] != false,
      'ladder_boost' || 'sl_grease' => r['pu_ladder_boost'] != false,
      'sl_reroll' => r['pu_reroll'] != false,
      'sl_snake_charmer' => r['ranked'] != true,
      _ => true,
    };
  }

  /// Boosts on for me now.
  List<String> get myBoosts => me?.activePowerups ?? const [];

  /// Boosts can be switched on now (my turn, before rolling).
  bool get canBoost => canRoll && boostsOn;

  bool get rematchAllowed => rules['rematch_allowed'] == true;

  @override
  String nameOf(String? userId) {
    if (userId == null) return 'Player';
    if (userId == myUserId) return 'You';
    final n = names[userId];
    if (n != null) return n;
    final seat = state?.player(userId)?.seat ?? room?.players.where((p) => p.userId == userId).firstOrNull?.seat;
    return seat == null ? 'Player' : 'Player ${seat + 1}';
  }

  /// A name looked up at the gateway after a cold start.
  void setName(String userId, String name) {
    if (name.isEmpty || names[userId] == name) return;
    names[userId] = name;
    changed();
  }

  /// The full length of a turn, for the countdown ring.
  int get turnRingMs {
    final fromState = state?.turnTimeMs ?? 0;
    if (fromState > 0) return fromState;
    final fromRoom = ((room?.raw['turn_timer_sec'] as num?)?.toInt() ?? 0) * 1000;
    if (fromRoom > 0) return fromRoom;
    if (turnMs != null && turnMs! > 0) return turnMs!;
    final measured = _turnTotal?.inMilliseconds ?? 0;
    return measured > 0 ? measured : 20000;
  }

  /// Time left on the current turn (server clock; null: no timer runs).
  Duration? get turnLeft {
    final deadline = state?.turnDeadline;
    if (deadline == null || phase != RoomPhase.game) return null;
    final d = deadline.difference(serverNow());
    return d.isNegative ? Duration.zero : d;
  }

  /// Timed-out turns allowed in a row.
  int get timeoutsAllowed => state?.maxTimeouts ?? maxTimeouts;

  /// Places once over: the server's `places`, else the winner first, then
  /// by how far each got.
  List<SnlPlayer> get standings {
    final st = state;
    if (st == null) return const [];
    final ps = [...st.players];
    if (st.places.isNotEmpty) {
      int at(SnlPlayer p) {
        final i = st.places.indexOf(p.userId);
        return i < 0 ? 99 : i;
      }

      ps.sort((a, b) => at(a).compareTo(at(b)));
      return ps;
    }
    final winners = {...st.winners, ?st.winner};
    ps.sort((a, b) {
      final wa = winners.contains(a.userId) ? 0 : 1;
      final wb = winners.contains(b.userId) ? 0 : 1;
      if (wa != wb) return wa.compareTo(wb);
      if (a.forfeited != b.forfeited) return a.forfeited ? 1 : -1;
      return b.position.compareTo(a.position);
    });
    return ps;
  }

  bool get iWon => state != null && (state!.winner == myUserId || state!.winners.contains(myUserId));

  // ── Rooms ──

  /// A private room (`room.create`). Only the rule picks the mode's
  /// `host_can_choose` lists. The timer is `turn_timer_sec` (not Ludo's
  /// `turn_seconds`); a bet must be one [loadBetOptions] offers unlocked.
  Future<bool> createRoom({
    String? modeCode,
    int? maxPlayers,
    int? turnTimerSec,
    String? currency,
    int? betAmount,
    bool listed = false,
    Map<String, bool> rules = const {},
  }) async {
    final ok = await createRoomWith({
      'mode_code': ?modeCode,
      'max_players': ?maxPlayers,
      'turn_timer_sec': ?turnTimerSec,
      if (betAmount != null && betAmount > 0) ...{'currency': currency ?? 'token', 'bet_amount': betAmount},
      if (listed) 'listed': true,
      ...rules,
    });
    // The ladder changed under the picker: offer the current bets again.
    if (!ok && lastErrorCode == 'bet_not_offered') await loadBetOptions(currency ?? 'token');
    return ok;
  }

  /// `wallet.bet_options` for [currency] (any signed-in state).
  Future<SnlBetOffer?> loadBetOptions(String currency) async {
    await run(RoomEvent.betOptions, {'currency': currency}, lock: false, onReply: (m) {
      betOffer = SnlBetOffer.fromJson(m.data['offer']);
    });
    return betOffer;
  }

  // ── Game ──

  /// Roll: the server moves the one token at once.
  Future<void> roll() {
    if (!canRoll) return Future.value();
    return action({'action_type': 'roll_dice'}, onResult: (r) => _myAck = SnlRoll.fromJson(r));
  }

  /// Switch a boost on before rolling (acts on the next roll).
  Future<void> usePowerup(String code) async {
    if (!canBoost) return;
    await action({'action_type': 'use_powerup', 'powerup_code': code});
  }

  /// Give up (asked first). With two players the other wins.
  Future<void> forfeit() => action({'action_type': 'forfeit'});

  // ── Frames from the server ──

  @override
  bool handleGame(SocketMessage m) {
    final d = m.data;
    switch (m.event) {
      case RoomEvent.gameStarted:
        board?.dispose();
        board = null;
        lastAction = null;
        skipped = const {};
        startedFresh();
        final t = RoomTournament.fromJson(d['tournament']);
        if (t != null && room != null && room!.tournament == null) {
          room = RoomInfo.fromJson({...room!.raw, 'tournament': d['tournament']}, quickMatch: room!.quickMatch).withPlayers(room!.players);
        }
        _apply(SnlState.fromJson(RoomController.mapOf(d['state'])));
        phase = RoomPhase.game;
      case RoomEvent.stateUpdate:
        _onStateUpdate(d);
      case RoomEvent.stateSync:
        // Back in a running game after a reconnect (or a cold start).
        readOnly = false;
        board?.dispose();
        board = null;
        _apply(SnlState.fromJson(RoomController.mapOf(d['state'])));
        phase = RoomPhase.game;
        loadMissedChat();
      case RoomEvent.finalState:
        // The game ended while away: the result, read-only (`state` is null
        // once the finished game expired).
        readOnly = true;
        final raw = d['state'];
        if (raw is Map) _apply(SnlState.fromJson(raw.cast<String, dynamic>()));
        phase = RoomPhase.result;
      case RoomEvent.playerForfeited:
        _onForfeited(d);
      case RoomEvent.powerupUsed:
        final id = '${d['user_id'] ?? ''}';
        final code = '${d['powerup_code'] ?? ''}';
        final on = d['active_powerups'] is List ? [for (final p in d['active_powerups'] as List) '$p'] : null;
        final st = state;
        if (st != null && on != null) {
          state = st.withPlayers([for (final p in st.players) p.userId == id ? p.copyWith(activePowerups: on) : p]);
        }
        if (id == myUserId) onBoostsChanged?.call();
        notify(RoomNotice('${nameOf(id)} switched on ${snlBoostName(code)}.', seatUserId: id));
      default:
        return false;
    }
    return true;
  }

  void _onStateUpdate(Map<String, dynamic> d) {
    final before = state;
    final a = SnlRoll.fromJson(d['last_action']);
    final st = SnlState.fromJson(RoomController.mapOf(d['state']));
    lastAction = a;
    if (a != null) {
      _countTimeouts(a, st);
      _tellAbout(a, before, st);
    }
    _apply(st, action: a, before: before);
    _myAck = null;
    // No top-level game_over (not like Ludo): the end flag is on last_action.
    if ((a?.gameOver ?? false) || st.completed) phase = RoomPhase.result;
  }

  /// A game ended by a forfeit sends only `game.player_forfeited` (no final
  /// state update, not like Ludo): the result comes from it alone.
  void _onForfeited(Map<String, dynamic> d) {
    forfeitNotice(d);
    final id = '${d['user_id'] ?? ''}';
    final st = state;
    if (st == null) return;
    final turn = roomStr(d['current_turn_user_id']);
    final deadline = roomMs(d['turn_deadline_ms']);
    var next = st.withPlayers(
      [for (final p in st.players) p.userId == id ? p.copyWith(forfeited: true) : p],
      currentTurnUserId: turn,
      turnDeadline: deadline,
      clearDeadline: deadline == null,
    );
    if (d['game_over'] == true) {
      final winner = roomStr(d['winner_id']);
      next = SnlState(
        matchId: next.matchId,
        status: 'completed',
        players: next.players,
        board: next.board,
        currentTurnUserId: next.currentTurnUserId,
        turnNumber: next.turnNumber,
        turnTimeMs: next.turnTimeMs,
        maxTimeouts: next.maxTimeouts,
        winner: winner,
        winners: winner == null ? const [] : [winner],
        royalStakes: next.royalStakes,
        diceSeedHash: next.diceSeedHash,
        rules: next.rules,
      );
      board?.clearPending();
      _apply(next);
      phase = RoomPhase.result;
    } else {
      state = next;
    }
  }

  /// "Time's up" when the server rolled; warn before the last strike.
  void _countTimeouts(SnlRoll a, SnlState st) {
    final id = a.userId;
    if (id == null || !a.isRoll) return;
    if (!a.autoRoll) {
      timeouts[id] = 0;
      return;
    }
    final fromServer = st.player(id)?.timeouts ?? 0;
    final n = fromServer > 0 ? fromServer : (timeouts[id] ?? 0) + 1;
    timeouts[id] = n;
    final allowed = st.maxTimeouts ?? maxTimeouts;
    if (id == myUserId && n >= allowed - 1) {
      notify(RoomNotice("Time's up. Play your turn or you'll be removed.", error: true, seatUserId: id));
    } else {
      notify(RoomNotice("Time's up", seatUserId: id));
    }
  }

  /// Toasts for what a roll did beyond the move itself.
  void _tellAbout(SnlRoll a, SnlState? before, SnlState st) {
    final id = a.userId;
    skipped = {...st.skippedTurns};
    if (id == null) return;
    final who = nameOf(id);
    final layout = st.board ?? before?.board;
    final shieldOn = before?.player(id)?.activePowerups.any((p) => p == 'shield' || p == 'sl_antivenom') ?? false;
    if (a.snakeCharm != null) {
      final code = '${a.snakeCharm!['code'] ?? ''}';
      notify(RoomNotice(code == 'sl_snake_charmer' ? '$who charmed the snake and climbed it!' : 'Anti-Snake! $who wasn’t bitten.', seatUserId: id));
    } else if (shieldOn && a.moveType == 'moved' && layout != null && layout.snakes.containsKey(a.to)) {
      notify(RoomNotice('Shield! ${id == myUserId ? 'You stay' : '$who stays'} on the snake’s head.', seatUserId: id));
    }
    if (a.captured.isNotEmpty) {
      final victims = a.captured.map((u) => u == myUserId ? 'you' : nameOf(u)).join(', ');
      notify(RoomNotice('$who sent $victims back to the start.', seatUserId: a.captured.first));
    }
    if (a.venom) notify(RoomNotice('Venom! $who ${id == myUserId ? 'sit' : 'sits'} out the next turn.', seatUserId: id));
    for (final s in st.skippedTurns) {
      notify(RoomNotice('${nameOf(s)} skipped (venom).', seatUserId: s));
    }
  }

  /// Redraw everything from [st]; animate [action] (die, hop, then any
  /// ladder or snake).
  void _apply(SnlState st, {SnlRoll? action, SnlState? before}) {
    // A shortened state may leave the board out: keep the one we have.
    final layout = st.board ?? state?.board ?? before?.board ?? previewBoard;
    state = st.board == null && layout != null ? _withBoard(st, layout) : st;
    if (st.maxTimeouts != null) maxTimeouts = st.maxTimeouts!;
    for (final p in st.players) {
      if (p.timeouts > 0 && action?.userId != p.userId) timeouts[p.userId] = p.timeouts;
    }
    _askNames(st);
    final deadline = st.turnDeadline;
    if (deadline != _deadlineSeen) {
      _deadlineSeen = deadline;
      if (deadline != null) _turnTotal = deadline.difference(serverNow());
    }
    if (st.players.length < 2 || layout == null) return;
    var b = board;
    if (b == null || b.players != st.players.length || b.layout != layout) {
      b?.dispose();
      b = board = SnlBoardGame(players: st.players.length, layout: layout);
    }
    final order = [for (final p in st.players) p.userId];
    final turn = order.indexOf(st.currentTurnUserId ?? '');
    final winnerIdx = st.winner == null ? -1 : order.indexOf(st.winner!);
    SnakesMove? move;
    var captured = <int>{};
    if (action != null && action.userId != null && action.isRoll) {
      final idx = order.indexOf(action.userId!);
      if (idx >= 0) {
        move = SnlBoardGame.moveOf(action, idx, before?.player(action.userId!)?.position ?? 0, layout);
        captured = {for (final u in action.captured) if (order.contains(u)) order.indexOf(u)};
      }
    }
    b.applyServer(
      positions: [for (final p in st.players) p.position],
      turn: turn < 0 ? b.turn : turn,
      winner: winnerIdx < 0 ? null : winnerIdx,
      move: move,
      captured: captured,
      dice: action?.isRoll == true ? _shownDie(action!) : null,
      text: action == null ? null : describe(action, layout),
    );
  }

  /// The face to show (Double Dice sums up to 12: show the first die).
  int? _shownDie(SnlRoll a) {
    final v = a.diceValue;
    if (v == null) return null;
    final ack = _myAck;
    if (a.userId == myUserId && ack?.secondDiceValue != null && ack?.diceValue == v) return v - ack!.secondDiceValue!;
    return v > 6 ? 6 : v;
  }

  static SnlState _withBoard(SnlState st, SnakesLayout layout) => SnlState(
    matchId: st.matchId,
    status: st.status,
    players: st.players,
    board: layout,
    currentTurnUserId: st.currentTurnUserId,
    turnNumber: st.turnNumber,
    turnDeadline: st.turnDeadline,
    turnTimeMs: st.turnTimeMs,
    maxTimeouts: st.maxTimeouts,
    skippedTurns: st.skippedTurns,
    winner: st.winner,
    winners: st.winners,
    places: st.places,
    royalStakes: st.royalStakes,
    diceSeedHash: st.diceSeedHash,
    diceSeed: st.diceSeed,
    rules: st.rules,
  );

  void _askNames(SnlState st) {
    final unknown = [
      for (final p in st.players)
        if (p.userId != myUserId && !names.containsKey(p.userId) && !_askedNames.contains(p.userId)) p.userId,
    ];
    if (unknown.isEmpty || onUnknownPlayers == null) return;
    _askedNames.addAll(unknown);
    onUnknownPlayers!(unknown);
  }

  /// One line for the board ("Ana climbed a ladder to 37").
  String describe(SnlRoll a, SnakesLayout? layout) {
    final who = nameOf(a.userId);
    final prefix = a.autoRoll ? "Time's up · " : '';
    if (a.actionType == 'forfeit') return '$who gave up';
    final n = a.diceValue ?? 0;
    final rolled = a.rerolledFrom != null ? 'rolled $n (rerolled a ${a.rerolledFrom})' : 'rolled $n';
    final to = a.to ?? 0;
    final x = (a.multiplier ?? 0) > 1 ? ' ×${a.multiplier}' : '';
    final landed = switch (a.landingKind) {
      'ladder' => '$who climbed a ladder to $to$x',
      'snake' when to > (a.landingSquare ?? 0) => '$who rode the snake up to $to',
      'snake' => '$who ${a.userId == myUserId ? 'were' : 'was'} bitten by a snake: down to $to',
      _ => '$who $rolled → $to',
    };
    final text = switch (a.moveType) {
      'overshot' => '$who $rolled · needs exactly ${(layout?.size ?? 100) - (a.from ?? 0)}',
      'lost_turn_consecutive_max' => '$who rolled three 6s · turn lost',
      'waiting_to_start' => '$who $rolled · a six to start',
      'won' => '$who won!',
      'extra_turn' => '$landed · rolls again',
      _ => landed,
    };
    return prefix + text;
  }

  // ── Errors ──

  @override
  void onActionError(SocketError e) {
    switch (e.code) {
      case 'not_your_turn':
        // Usually a double tap: the latest state is already drawn.
        changed();
      case 'turn_expired':
        notify(const RoomNotice('Your turn ran out. The server rolled for you.'));
      case 'game_over':
        setState(() => phase = RoomPhase.result);
      case 'game_not_started':
        notify(const RoomNotice('The game hasn’t started yet.'));
      case 'not_in_match' || 'already_forfeited':
        if (state != null) {
          setState(() => phase = RoomPhase.result);
        } else {
          toLobby();
        }
      case 'not_found':
        notify(const RoomNotice('This game is over.', error: true));
        toLobby();
      default:
        notify(RoomNotice(snlActionErrorText(e), error: true));
    }
  }

  @override
  String errorText(SocketError e, {String? event}) => snlErrorText(e, event: event);

  @override
  void resetGame() {
    super.resetGame();
    state = null;
    lastAction = null;
    board?.dispose();
    board = null;
    skipped = const {};
    _myAck = null;
    _deadlineSeen = null;
    _turnTotal = null;
  }

  @override
  void dispose() {
    board?.dispose();
    super.dispose();
  }
}

/// Player-facing text for a refused Snake & Ladder request
/// (snake-and-ladder.md error tables).
String snlErrorText(SocketError e, {String? event}) => switch (e.code) {
  'bet_not_offered' => 'That stake isn’t offered at your balance. Pick another.',
  'insufficient_funds' => 'Not enough tokens or gold for this table. Try a lower stake or visit the shop.',
  'invalid_state' when event == RoomEvent.roomCreate || event == RoomEvent.roomJoin => 'Leave this room first.',
  'invalid_state' when event == RoomEvent.rematch => 'A rematch isn’t possible for this game.',
  'invalid_state' when event == RoomEvent.chatSend => 'Team chat isn’t on in this room.',
  'not_in_room' when event == RoomEvent.giftSend => 'That player isn’t in your room.',
  'gift_quota_exceeded' => 'You’ve sent all the gifts you can for now.',
  _ => roomErrorText(e, event: event),
};

/// A refused move (`game.action_error`). A refused boost answers
/// `invalid_state` with developer text: shown as one of these lines.
String snlActionErrorText(SocketError e) {
  if (e.code != 'invalid_state') {
    return switch (e.code) {
      'invalid_request' => 'Something went wrong. Try again.',
      'busy' || 'internal_error' => 'The game server is busy. Try again.',
      _ => roomErrorText(e),
    };
  }
  final m = e.message.toLowerCase();
  if (m.contains('remaining')) return 'You have none of that boost left.';
  if (m.contains('already active')) return 'That boost is already on.';
  if (m.contains('maximum') || m.contains('per turn')) return 'At most 2 boosts can be on at once.';
  if (m.contains('switched off')) return 'That boost is off in this room.';
  if (m.contains('limit') || m.contains('per match')) return 'You’ve used that boost as often as this match allows.';
  if (m.contains('ranked')) return 'That boost isn’t allowed in ranked games.';
  if (m.contains('not your turn')) return 'It isn’t your turn.';
  return 'That boost can’t be used right now.';
}
