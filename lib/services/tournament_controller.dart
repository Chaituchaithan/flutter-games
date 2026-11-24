import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/tournament.dart';
import 'app_exception.dart';
import 'app_prefs.dart';
import 'server_clock.dart';
import 'session.dart';
import 'tournament_api.dart';

/// Where the player stands in one tournament (06 "Controller states").
enum TournamentPhase {
  /// First read in flight.
  loading,

  /// Not entered (or left): Join while registering.
  notEntered,

  /// Entered, waiting for the Sit & Go to fill or the table to open.
  entered,

  /// The table is open: hand-off with the seat deadline and Go.
  tableReady,

  /// On the game screen.
  atTable,

  /// The game ended, the tournament still runs: "Results coming".
  waitingResult,

  /// `completed`: Results.
  finished,

  /// `cancelled` or `refunded`.
  cancelled,

  /// `404`: the tournament was removed. Back to the lobby.
  gone,

  /// The first read failed (offline…): Retry.
  failed,
}

/// One open tournament screen's state (06 "For the Claude agent", 3): the
/// tournament and the player's `my-table`, re-read every [pollEvery] while
/// the screen is open and the tournament is registering, running or paused
/// (never faster: 00-conventions "Limits"). There is no push when a Sit & Go
/// starts (Known issues, 7): polling is how the table is found.
class TournamentController extends ChangeNotifier {
  TournamentController({
    required this.api,
    required this.id,
    Tournament? initial,
    this.gameName = 'this game',
    this.onMoneyMoved,
    this.onEntered,
    this.onLeft,
    this.pollEvery = const Duration(seconds: 10),
    this.settleDelay = const Duration(seconds: 2),
    DateTime Function()? now,
  })  : tournament = initial,
        _now = now ?? ServerClock.now;

  final TournamentApi api;
  final String id;

  /// For "Reach level 5 in Ludo to join."
  final String gameName;

  /// Money moved (join, leave, prize, refund): re-read the wallet.
  final VoidCallback? onMoneyMoved;

  /// Joined / left: keep the ids on the device (Known issues, 7).
  final void Function(String id)? onEntered;
  final void Function(String id)? onLeft;

  final Duration pollEvery;

  /// Wait after a game ends before the first re-read (settlement takes about
  /// a second, 06 §6).
  final Duration settleDelay;
  final DateTime Function() _now;

  Tournament? tournament;
  MyTable? myTable;

  /// Read once the tournament is over (and by the results screen).
  List<Standing> standings = const [];

  /// The last failed read (the shown data is kept).
  AppException? loadError;

  /// A join or leave in flight.
  bool busy = false;

  /// An operator paused joining (`KILL_SWITCH_ENGAGED`): their text.
  String? joinPausedText;

  bool _gone = false;
  bool _atTable = false;
  bool _settling = false;
  bool _paused = false;
  bool _disposed = false;
  bool _startRefreshed = false;
  Timer? _poll;
  Future<void>? _refreshing;

  /// Now on the server's clock ([ServerClock]): every countdown here is to
  /// a server time (seat deadline, start).
  DateTime now() => _now();

  TournamentStatus? get status => tournament?.status;

  TournamentPhase get phase {
    if (_gone) return TournamentPhase.gone;
    final t = tournament;
    final m = myTable;
    if (t == null || m == null) return loadError == null ? TournamentPhase.loading : TournamentPhase.failed;
    if (t.status.isCancelled) return TournamentPhase.cancelled;
    if (t.status == TournamentStatus.completed) return TournamentPhase.finished;
    if (_atTable) return TournamentPhase.atTable;
    if (_settling) return TournamentPhase.waitingResult;
    final e = m.entryStatus;
    final table = m.table;
    final live = e == EntryStatus.active || e == EntryStatus.registered;
    if (live && table != null && table.isReady) return TournamentPhase.tableReady;
    final running = t.status == TournamentStatus.running || t.status == TournamentStatus.paused;
    if (running &&
        (e == EntryStatus.busted || e == EntryStatus.winner || e == EntryStatus.disqualified ||
            (live && table?.status == TableStatus.closed))) {
      return TournamentPhase.waitingResult;
    }
    if (live) return TournamentPhase.entered;
    return TournamentPhase.notEntered;
  }

  /// Re-read while registering, running or paused (and never while playing).
  bool get shouldPoll {
    final s = status;
    return s == TournamentStatus.registering || s == TournamentStatus.running || s == TournamentStatus.paused;
  }

  /// Time left to take the seat (zero once past); null without a table.
  Duration? get seatTimeLeft {
    final d = myTable?.table?.seatDeadlineAt;
    if (d == null) return null;
    final left = d.difference(now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Scheduled formats: time to `starts_at` (never for a Sit & Go).
  Duration? get startsIn {
    final t = tournament;
    if (t == null || t.isSitAndGo || t.startsAt == null) return null;
    final left = t.startsAt!.difference(now());
    return left.isNegative ? Duration.zero : left;
  }

  /// The player's own standing (null when not listed).
  Standing? standingOf(String userId) => standings.where((s) => s.playerId == userId).firstOrNull;

  /// First read, then a re-read every [pollEvery].
  Future<void> start() {
    _poll ??= Timer.periodic(pollEvery, (_) => _tick());
    return refresh();
  }

  void _tick() {
    if (_disposed || _paused || _atTable || busy) return;
    if (shouldPoll) {
      unawaited(refresh());
      return;
    }
    // A scheduled start reached its time: re-read once (it may have started,
    // been cancelled, or moved a week later).
    final left = startsIn;
    if (!_startRefreshed && left != null && left == Duration.zero && status == TournamentStatus.announced) {
      _startRefreshed = true;
      unawaited(refresh());
    }
  }

  /// App to the background: stop polling. [resume] re-reads at once.
  void pause() => _paused = true;

  Future<void> resume() {
    _paused = false;
    return refresh();
  }

  /// Reads the tournament and `my-table` together (06 §2); the standings
  /// too once it is over. A failed read keeps what is shown.
  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    final before = tournament?.status;
    try {
      final r = await Future.wait<Object>([api.get(id), api.myTable(id)]);
      if (_disposed) return;
      final t = r[0] as Tournament;
      final m = r[1] as MyTable;
      tournament = t;
      myTable = m;
      loadError = null;
      if (t.status.isOver) {
        try {
          standings = await api.standings(id);
        } on AppException {
          // Keep the last standings; the next read tries again.
        }
      }
      // A prize or a refund just landed: re-read the wallet.
      final moneyNow = (t.status == TournamentStatus.completed || t.status == TournamentStatus.refunded) && m.entered;
      if (before != null && before != t.status && moneyNow) onMoneyMoved?.call();
    } on AppException catch (e) {
      if (_disposed) return;
      if (e.statusCode == 404 || e.code == ApiErrorCode.notFound) {
        _gone = true;
        _poll?.cancel();
      } else {
        loadError = e;
      }
    }
    _notify();
  }

  /// Join (`POST register`). Returns null on success, else what to show.
  /// No network or a timeout: re-reads `my-table` first; `registered` means
  /// it went through (never joins twice blindly).
  Future<TournamentIssue?> join() async {
    if (busy) return null;
    busy = true;
    _notify();
    try {
      await api.register(id);
      return await _joined();
    } on AppException catch (e) {
      if (e.isOffline || e.kind == AppErrorKind.timeout) {
        try {
          final m = await api.myTable(id);
          if (m.entryStatus == EntryStatus.registered || m.entryStatus == EntryStatus.active) return await _joined();
        } on AppException {
          // Still unknown: report the network problem.
        }
      }
      final issue = tournamentIssue(e, join: true, gameName: gameName, noun: tournament?.currency.noun ?? 'tokens');
      if (issue.fix == TournamentFix.disableJoin) joinPausedText = issue.text;
      if (issue.fix == TournamentFix.reloadLobby) {
        _gone = true;
      } else if (issue.fix != TournamentFix.none || e.code == ApiErrorCode.tournamentFull) {
        await refresh();
      }
      return issue;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<TournamentIssue?> _joined() async {
    onEntered?.call(id);
    onMoneyMoved?.call();
    await refresh();
    return null;
  }

  /// Leave (`POST unregister`): only while announced or registering; buy-in
  /// and fee come back in full.
  Future<TournamentIssue?> leave() async {
    if (busy) return null;
    busy = true;
    _notify();
    try {
      await api.unregister(id);
      onLeft?.call(id);
      onMoneyMoved?.call();
      await refresh();
      return null;
    } on AppException catch (e) {
      final issue = tournamentIssue(e, join: false, gameName: gameName);
      if (issue.fix == TournamentFix.reloadLobby) {
        _gone = true;
      } else if (issue.fix == TournamentFix.refresh) {
        await refresh();
      }
      return issue;
    } finally {
      busy = false;
      _notify();
    }
  }

  /// The game screen opened (the socket's `room.joined` follows): no polling
  /// meanwhile.
  void wentToTable() {
    _atTable = true;
    _notify();
  }

  /// Back from the game screen: "Results coming" for [settleDelay], then
  /// re-read the tournament, `my-table` and standings (and the wallet).
  Future<void> backFromTable() async {
    _atTable = false;
    _settling = true;
    _notify();
    await Future<void>.delayed(settleDelay);
    if (_disposed) return;
    _settling = false;
    await refresh();
    onMoneyMoved?.call();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}

/// The ids of tournaments the player joined on this device (no "my
/// tournaments" route: Known issues, 7). Best effort; shows "Entered" in the
/// lobby. Cleared per player.
class JoinedTournaments extends Notifier<Set<String>> {
  static const _key = 'tournaments.joined';

  @override
  Set<String> build() {
    final user = ref.watch(sessionProvider.select((u) => u?.id));
    unawaited(_load(user));
    return const {};
  }

  String get _prefKey => '$_key.${ref.read(sessionProvider)?.id ?? 'demo'}';

  Future<void> _load(String? user) async {
    final raw = await ref.read(appPrefsProvider).get('$_key.${user ?? 'demo'}');
    if (!ref.mounted || raw == null || raw.isEmpty) return;
    state = {...state, ...raw.split(',').where((s) => s.isNotEmpty)};
  }

  void add(String id) => _save({...state, id});
  void remove(String id) => _save({...state}..remove(id));

  void _save(Set<String> ids) {
    state = ids;
    // Keep the newest few dozen.
    final keep = ids.length > 50 ? ids.skip(ids.length - 50) : ids;
    unawaited(ref.read(appPrefsProvider).set(_prefKey, keep.join(',')));
  }
}

final joinedTournamentsProvider = NotifierProvider<JoinedTournaments, Set<String>>(JoinedTournaments.new);
