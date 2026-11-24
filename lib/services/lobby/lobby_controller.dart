/// The lobby state machine every game's screens share
/// (docs/services/05-matchmaking-and-rooms.md "For the Claude agent" 2):
///
/// `idle` (signed in on the socket) → `searching` (quick match, alone in a
/// lobby) or `waitingRoom` (seated, others arriving) → `inGame` → `result` →
/// back to `idle`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/game_catalogue.dart';
import 'game_lobby.dart';
import 'lobby_models.dart';

enum LobbyPhase { idle, searching, waitingRoom, inGame, result }

/// Whether the wallet covers a stake (`GET /wallet/balance`); null = unknown.
typedef CanAfford = bool Function(String currency, int amount);

class LobbyController extends ChangeNotifier {
  LobbyController({
    required this.lobby,
    this.myUserId,
    this.searchTimeout = const Duration(seconds: 60),
    this.listInterval = const Duration(seconds: 10),
    this.retryDelay = const Duration(seconds: 1),
    this.autoReady = true,
    this.onFailure,
    this.onStakedGameEnded,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now {
    _sub = lobby.events.listen(_onEvent);
  }

  final GameLobby lobby;
  final String? myUserId;

  /// The server has no search timeout and no "no bot" signal (Known gaps 3):
  /// after this long searching, ask "Keep waiting" or "Cancel".
  final Duration searchTimeout;

  /// The open tables list has no push: never ask more often than this.
  final Duration listInterval;

  /// Wait before the one retry of a `busy` / `internal_error` refusal.
  final Duration retryDelay;

  /// Send `player.ready` once a quick-match table is full (the design may
  /// show a Ready button instead: set false and call [setReady]).
  final bool autoReady;

  /// Every refusal, for app-wide reactions: `invalid_mode` → refetch the
  /// catalogue, `kill_switch_engaged` → the game's banner
  /// (`catalogueEventsProvider`).
  final void Function(LobbyFailure failure)? onFailure;

  /// A staked game ended: re-read the wallet (`WalletStore.gameEnded`).
  /// Never compute the payout on the device.
  final VoidCallback? onStakedGameEnded;

  final DateTime Function() _now;
  late final StreamSubscription<LobbyEvent> _sub;
  bool _disposed = false;

  LobbyPhase phase = LobbyPhase.idle;

  /// The current table (null in [LobbyPhase.idle]).
  RoomSeat? seat;

  /// The mode being searched / played.
  GameMode? mode;

  /// The stake of the current table (re-read the wallet after it ends).
  PlaySelection? selection;

  /// When the current search started (for the "0:03" timer).
  DateTime? searchStartedAt;

  /// Searching for [searchTimeout] with nobody coming: show "No players found
  /// right now." with Keep waiting / Cancel.
  bool noPlayersFound = false;
  Timer? _searchTimer;

  /// `game.started` / `game.state_sync` payload for the board.
  Map<String, dynamic>? gameData;

  /// `game.final_state`: the game ended while away (show the result read-only).
  bool resumedFinished = false;

  /// The latest refusal; [failureId] changes with each one (show once).
  LobbyFailure? failure;
  int failureId = 0;

  /// An operator paused new games: their message. Play buttons are disabled.
  String? killSwitchMessage;
  bool get playEnabled => killSwitchMessage == null;

  /// A request is in flight.
  bool busy = false;

  /// Open tables (`room.list`).
  List<OpenRoom> openRooms = const [];
  DateTime? _listedAt;
  bool loadingRooms = false;

  /// Cancel shows only while searching; hidden once the game starts.
  bool get canCancel => phase == LobbyPhase.searching;

  /// Leaving now is a forfeit: ask first.
  bool get leavingForfeits => phase == LobbyPhase.inGame;

  /// Quick match, Play with friends, Join and Open tables only from idle
  /// (one room at a time: seated → `invalid_state`).
  bool get canStart => phase == LobbyPhase.idle && !busy && playEnabled;

  bool get iAmReady => seat?.players.where((p) => p.userId == myUserId).firstOrNull?.ready ?? false;

  /// Elapsed search time.
  Duration get searchElapsed => searchStartedAt == null ? Duration.zero : _now().difference(searchStartedAt!);

  // ── Quick match (Flow A) ──

  Future<bool> quickMatch(GameMode mode, PlaySelection selection) async {
    if (phase != LobbyPhase.idle) return false;
    this.mode = mode;
    this.selection = selection;
    _set(() {
      phase = LobbyPhase.searching;
      _startSearchClock();
    });
    final s = await _run(() => lobby.quickMatch(mode, selection));
    if (s == null) {
      _toIdle();
      return false;
    }
    _set(() => _seatAt(s));
    return true;
  }

  /// "Keep waiting" on the no-players prompt: another [searchTimeout].
  void keepWaiting() {
    if (phase != LobbyPhase.searching) return;
    _set(_startSearchClock);
  }

  /// Cancel a search (`match.cancel`). A private room refuses it
  /// (`invalid_state`): leave the room instead.
  Future<void> cancelSearch() async {
    if (phase != LobbyPhase.searching) return;
    _set(() => busy = true);
    try {
      await lobby.cancelSearch();
    } on LobbyFailure catch (f) {
      if (phase == LobbyPhase.inGame) {
        // The game started meanwhile: Cancel no longer applies (leaving is
        // now a forfeit).
        busy = false;
        _changed();
        return;
      }
      if (f.error == LobbyError.invalidState) {
        // "not searching: this is a private room, use room.leave".
        try {
          await lobby.leaveRoom();
        } on LobbyFailure catch (_) {}
      }
    } finally {
      busy = false;
    }
    _toIdle();
  }

  // ── Private room (Flow B) ──

  Future<bool> createRoom(GameMode mode, PlaySelection selection, RoomOptions options) async {
    if (phase != LobbyPhase.idle) return false;
    this.mode = mode;
    this.selection = selection;
    final s = await _run(() => lobby.createRoom(mode, selection, options));
    if (s == null) return false;
    _set(() => _seatAt(s));
    return true;
  }

  Future<bool> joinByCode(String code) async {
    if (phase != LobbyPhase.idle) return false;
    final s = await _run(() => lobby.joinByCode(code));
    if (s == null) {
      // The room filled or started between the list and the tap.
      final e = failure?.error;
      if (e == LobbyError.roomFull || e == LobbyError.gameInProgress) {
        unawaited(refreshOpenRooms(force: true));
      }
      return false;
    }
    _set(() => _seatAt(s));
    return true;
  }

  Future<void> setReady(bool ready) async {
    if (phase != LobbyPhase.waitingRoom && phase != LobbyPhase.searching) return;
    await _run(() => lobby.setReady(ready));
  }

  /// `room.leave`: before the start it frees the seat; in a game it is a
  /// forfeit (the screen asks first, see [leavingForfeits]); after the game
  /// it returns to the lobby state (needed before searching again).
  Future<void> leave() async {
    if (seat == null && phase == LobbyPhase.idle) return;
    if (phase == LobbyPhase.searching) return cancelSearch();
    _set(() => busy = true);
    try {
      await lobby.leaveRoom();
    } on LobbyFailure catch (_) {
      // Already out (room closed): fine.
    } finally {
      busy = false;
    }
    _toIdle();
  }

  /// From the result back to the lobby.
  Future<void> backToLobby() => leave();

  // ── Open tables (Flow C) ──

  /// `room.list`, at most once every [listInterval] unless [force] (after a
  /// `room_full` / `game_in_progress` join). Only from the lobby state.
  Future<void> refreshOpenRooms({String? variant, bool force = false}) async {
    if (phase != LobbyPhase.idle || loadingRooms) return;
    final last = _listedAt;
    if (!force && last != null && _now().difference(last) < listInterval) return;
    _set(() => loadingRooms = true);
    final rooms = await _run(() => lobby.listOpenRooms(variant: variant), markBusy: false);
    loadingRooms = false;
    if (rooms != null) {
      openRooms = rooms;
      _listedAt = _now();
    }
    _changed();
  }

  /// Rows to show: waiting tables the wallet can cover.
  List<OpenRoom> visibleRooms([CanAfford? canAfford]) => [
    for (final r in openRooms)
      if (r.isWaiting && (r.isFree || canAfford == null || canAfford(r.currency ?? 'token', r.stake ?? 0))) r,
  ];

  // ── Pushed frames ──

  void _onEvent(LobbyEvent e) {
    if (_disposed) return;
    switch (e) {
      case SeatFound(:final seat):
        if (phase == LobbyPhase.searching) _seatAt(seat);
      case PlayerJoined(:final player):
        final s = seat;
        if (s == null || phase == LobbyPhase.inGame || phase == LobbyPhase.result) break;
        seat = s.withPlayers([...s.players.where((p) => p.userId != player.userId && p.seat != player.seat), player]);
        _checkFull();
      case PlayerLeft(:final userId):
        final s = seat;
        if (s == null || phase == LobbyPhase.inGame) break;
        if (userId == myUserId) {
          _toIdle(notify: false);
          break;
        }
        seat = s.withPlayers(s.players.where((p) => p.userId != userId).toList());
        // A quick-match lobby that lost a player searches again.
        if (phase == LobbyPhase.waitingRoom && s.quickMatch && !seat!.isFull) {
          phase = LobbyPhase.searching;
          _startSearchClock();
        }
      case ReadyChanged(:final userId, :final ready):
        final s = seat;
        if (s != null) seat = s.withPlayers([for (final p in s.players) p.userId == userId ? p.copyWith(ready: ready) : p]);
      case GameStarted(:final data):
        _stopSearchClock();
        gameData = data;
        resumedFinished = false;
        phase = LobbyPhase.inGame;
      case GameResumed(:final data, :final finished):
        // Back in a running game after a reconnect: straight to the board.
        _stopSearchClock();
        gameData = data;
        resumedFinished = finished;
        phase = finished ? LobbyPhase.result : LobbyPhase.inGame;
        if (finished) _ended();
      case GameEnded(:final data):
        if (phase != LobbyPhase.inGame) break;
        gameData = {...?gameData, 'result': data};
        phase = LobbyPhase.result;
        _ended();
      case StartFailed(:final failure):
        final s = seat;
        if (s != null) seat = s.withPlayers([for (final p in s.players) p.copyWith(ready: false)]);
        _fail(failure);
      case RoomClosed():
        if (phase == LobbyPhase.inGame) {
          phase = LobbyPhase.result;
          _ended();
        } else {
          _toIdle(notify: false);
        }
    }
    _changed();
  }

  void _seatAt(RoomSeat s) {
    seat = s;
    if (s.quickMatch && !s.isFull) {
      phase = LobbyPhase.searching;
      if (searchStartedAt == null) _startSearchClock();
    } else {
      phase = LobbyPhase.waitingRoom;
      _stopSearchClock();
    }
    _checkFull();
  }

  void _checkFull() {
    final s = seat;
    if (s == null || !s.isFull) return;
    if (phase == LobbyPhase.searching) {
      phase = LobbyPhase.waitingRoom;
      _stopSearchClock();
    }
    if (autoReady && s.quickMatch && !iAmReady && phase == LobbyPhase.waitingRoom) {
      unawaited(setReady(true));
    }
  }

  void _startSearchClock() {
    _searchTimer?.cancel();
    noPlayersFound = false;
    searchStartedAt ??= _now();
    _searchTimer = Timer(searchTimeout, () {
      if (_disposed || phase != LobbyPhase.searching) return;
      noPlayersFound = true;
      _changed();
    });
  }

  void _stopSearchClock() {
    _searchTimer?.cancel();
    _searchTimer = null;
    noPlayersFound = false;
    searchStartedAt = null;
  }

  void _toIdle({bool notify = true}) {
    _stopSearchClock();
    phase = LobbyPhase.idle;
    seat = null;
    selection = null;
    gameData = null;
    resumedFinished = false;
    if (notify) _changed();
  }

  /// Runs [op]; on a refusal records it, and retries `busy` /
  /// `internal_error` once after [retryDelay].
  Future<T?> _run<T>(Future<T> Function() op, {bool markBusy = true}) async {
    if (markBusy) _set(() => busy = true);
    try {
      try {
        return await op();
      } on LobbyFailure catch (f) {
        if (!f.error.retryable || _disposed) rethrow;
        await Future<void>.delayed(retryDelay);
        if (_disposed) return null;
        return await op();
      }
    } on LobbyFailure catch (f) {
      _fail(f);
      return null;
    } finally {
      if (markBusy) busy = false;
      _changed();
    }
  }

  void _fail(LobbyFailure f) {
    failure = f;
    failureId++;
    if (f.error == LobbyError.killSwitch) killSwitchMessage = f.text;
    onFailure?.call(f);
  }

  /// Staked by the server's word (a joiner learns the stake from the seat),
  /// or by the player's own pick.
  void _ended() {
    final staked = !(seat?.isFree ?? true) || !(selection?.isFree ?? true);
    if (staked) onStakedGameEnded?.call();
  }

  /// Clear the kill switch (e.g. after a retry later).
  void clearKillSwitch() => _set(() => killSwitchMessage = null);

  void _set(VoidCallback f) {
    f();
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    _sub.cancel();
    super.dispose();
  }
}
