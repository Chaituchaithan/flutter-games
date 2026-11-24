import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/configs.dart';
import '../data/models/tournament.dart';
import 'api_client.dart';
import 'app_exception.dart';
import 'server_clock.dart';
import 'session.dart';

/// The tournament routes (docs/services/06-tournaments.md). All need the
/// bearer token; none has the device check. Every method returns a typed
/// result or throws [AppException]; map a failure to player text with
/// [tournamentIssue].
abstract class TournamentApi {
  /// `GET /tournaments`: one [status] per call (null = all), [gameId] the
  /// numeric catalogue id. [page] is sent >= 1 and [perPage] 1-100 (the
  /// server doesn't check them: Known issues, 4).
  Future<TournamentPage> list({int? gameId, TournamentStatus? status, int page = 1, int perPage = 20});

  /// `GET /tournaments/{id}`.
  Future<Tournament> get(String id);

  /// `POST /tournaments/{id}/register` → 201, the entry. Takes buy-in + fee.
  Future<TournamentEntry> register(String id);

  /// `POST /tournaments/{id}/unregister` → `{"status": "withdrawn"}`. Refunds
  /// buy-in and fee in full.
  Future<void> unregister(String id);

  /// `GET /tournaments/{id}/my-table`: the entry and the latest table.
  Future<MyTable> myTable(String id);

  /// `GET /tournaments/{id}/standings`: best place first; `[]` once cancelled.
  Future<List<Standing>> standings(String id);

  /// `GET /tournaments/{id}/rounds`: `[]` before the first round.
  Future<List<Round>> rounds(String id);

  /// `GET /tournaments/{id}/bracket`: knockout pairings (always `[]` today).
  Future<List<BracketNode>> bracket(String id);
}

/// Sends `page` >= 1 and `per_page` 1-100 only (`per_page=0` drops the
/// connection on the server).
({int page, int perPage}) tournamentPaging(int page, int perPage) =>
    (page: page < 1 ? 1 : page, perPage: perPage.clamp(1, 100));

class RemoteTournamentApi implements TournamentApi {
  RemoteTournamentApi(this._api);
  final ApiClient _api;

  static Map<String, dynamic> _map(Object? body) =>
      body is Map ? body.cast<String, dynamic>() : throw const AppException('Something went wrong. Try again.');

  @override
  Future<TournamentPage> list({int? gameId, TournamentStatus? status, int page = 1, int perPage = 20}) async {
    final p = tournamentPaging(page, perPage);
    final query = <String, dynamic>{
      'game_id': ?gameId,
      // Unknown is never sent (the server answers 400).
      if (status != null && status != TournamentStatus.unknown) 'status': status.name,
      'page': p.page,
      'per_page': p.perPage,
    };
    return TournamentPage.fromJson(await _api.get(ApiEndpoints.tournaments, query: query));
  }

  @override
  Future<Tournament> get(String id) async => Tournament.fromJson(_map(await _api.get(ApiEndpoints.tournament(id))));

  @override
  Future<TournamentEntry> register(String id) async =>
      TournamentEntry.fromJson(_map(await _api.post(ApiEndpoints.tournamentRegister(id))));

  @override
  Future<void> unregister(String id) async {
    await _api.post(ApiEndpoints.tournamentUnregister(id));
  }

  @override
  Future<MyTable> myTable(String id) async => MyTable.fromJson(_map(await _api.get(ApiEndpoints.tournamentMyTable(id))));

  @override
  Future<List<Standing>> standings(String id) async => Standing.listFromJson(await _api.get(ApiEndpoints.tournamentStandings(id)));

  @override
  Future<List<Round>> rounds(String id) async => Round.listFromJson(await _api.get(ApiEndpoints.tournamentRounds(id)));

  @override
  Future<List<BracketNode>> bracket(String id) async =>
      BracketNode.listFromJson(await _api.get(ApiEndpoints.tournamentBracket(id)));
}

/// Offline demo: a few tournaments in every tab, kept in memory so Join and
/// Leave work. No table ever opens (there is no game server).
class DemoTournamentApi implements TournamentApi {
  DemoTournamentApi({DateTime? now}) : _now = now ?? ServerClock.now() {
    for (final t in _seed()) {
      _all[t.id] = t;
    }
  }

  final DateTime _now;
  final Map<String, Tournament> _all = {};
  final Set<String> _entered = {};

  static const _userId = 'demo-user';

  List<Tournament> _seed() => [
        Tournament(
            id: 'demo-sng', gameId: 1, modeId: 58, name: 'Weekday Ladder Final', type: TournamentType.singleTableSng,
            status: TournamentStatus.registering, maxPlayers: 4, currentPlayers: 2, entryFee: 250, feeAmount: 25,
            startsAt: _now.subtract(const Duration(days: 4))),
        Tournament(
            id: 'demo-window', gameId: 1, modeId: 58, name: 'Evening Royale', type: TournamentType.leaderboardWindow,
            status: TournamentStatus.registering, maxPlayers: 50, currentPlayers: 12, entryFee: 100, feeAmount: 10,
            prizePool: 2000, startsAt: _now.add(const Duration(hours: 2, minutes: 14))),
        Tournament(
            id: 'demo-freeroll', gameId: 1, modeId: 58, name: 'Breakfast Freeroll', type: TournamentType.multiTableMtt,
            status: TournamentStatus.announced, maxPlayers: 500, prizePool: 5000,
            startsAt: _now.add(const Duration(days: 1, hours: 3))),
        Tournament(
            id: 'demo-live', gameId: 1, modeId: 58, name: 'Sunday Dice Royale', type: TournamentType.singleTableSng,
            status: TournamentStatus.running, maxPlayers: 4, currentPlayers: 4, entryFee: 50, feeAmount: 5, prizePool: 200,
            startsAt: _now.subtract(const Duration(minutes: 6))),
        Tournament(
            id: 'demo-done', gameId: 1, modeId: 58, name: 'Weekday Ladder Final', type: TournamentType.singleTableSng,
            status: TournamentStatus.completed, maxPlayers: 4, currentPlayers: 4, entryFee: 250, feeAmount: 25,
            prizePool: 1000, startsAt: _now.subtract(const Duration(days: 1))),
        Tournament(
            id: 'demo-refunded', gameId: 1, modeId: 58, name: 'Weekday Ladder Final', type: TournamentType.singleTableSng,
            status: TournamentStatus.refunded, maxPlayers: 4, currentPlayers: 4, entryFee: 250, feeAmount: 25,
            prizePool: 1000, startsAt: _now.subtract(const Duration(hours: 5))),
      ];

  Tournament _require(String id) =>
      _all[id] ?? (throw const AppException('Not found.', kind: AppErrorKind.notFound, statusCode: 404, code: ApiErrorCode.notFound));

  static AppException _err(int status, String code) => AppException('', statusCode: status, code: code);

  @override
  Future<TournamentPage> list({int? gameId, TournamentStatus? status, int page = 1, int perPage = 20}) async {
    final p = tournamentPaging(page, perPage);
    final rows = _all.values
        .where((t) => status == null || t.status == status)
        .toList()
      ..sort((a, b) => (a.startsAt ?? _now).compareTo(b.startsAt ?? _now));
    final pages = rows.isEmpty ? 0 : (rows.length / p.perPage).ceil();
    final slice = rows.skip((p.page - 1) * p.perPage).take(p.perPage).toList();
    return TournamentPage(items: slice, total: rows.length, page: p.page, perPage: p.perPage, totalPages: pages);
  }

  @override
  Future<Tournament> get(String id) async => _require(id);

  @override
  Future<TournamentEntry> register(String id) async {
    final t = _require(id);
    if (t.status != TournamentStatus.registering) throw _err(400, ApiErrorCode.badRequest);
    if (_entered.contains(id)) throw _err(409, ApiErrorCode.conflict);
    if (t.isFull) throw _err(409, ApiErrorCode.tournamentFull);
    _entered.add(id);
    _all[id] = t.copyWith(currentPlayers: t.currentPlayers + 1);
    return TournamentEntry(tournamentId: id, userId: _userId, status: EntryStatus.registered, registeredAt: DateTime.now());
  }

  @override
  Future<void> unregister(String id) async {
    final t = _require(id);
    if (t.status != TournamentStatus.registering && t.status != TournamentStatus.announced) {
      throw _err(400, ApiErrorCode.badRequest);
    }
    if (!_entered.remove(id)) throw _err(404, ApiErrorCode.notFound);
    _all[id] = t.copyWith(currentPlayers: t.currentPlayers - 1);
  }

  @override
  Future<MyTable> myTable(String id) async {
    final t = _require(id);
    return switch (id) {
      'demo-done' => MyTable(
          tournamentStatus: t.status,
          entryStatus: EntryStatus.busted,
          table: TournamentTable(
            round: 1, tableNumber: 1, status: TableStatus.closed, seat: 1, roomCode: 'demo0001', place: 2,
            players: [for (final s in _demoStandings) TableSeat(playerId: s.playerId, username: s.username, seat: s.place! - 1, place: s.place)],
          ),
        ),
      'demo-refunded' => MyTable(tournamentStatus: t.status, entryStatus: EntryStatus.withdrawn),
      _ => MyTable(tournamentStatus: t.status, entryStatus: _entered.contains(id) ? EntryStatus.registered : null),
    };
  }

  static const _demoStandings = [
    Standing(playerId: 'p1', username: 'ZeroCool', place: 1, entryStatus: EntryStatus.winner, matchesWon: 1, prizeAmount: 650, prizeCurrencyWire: 'token'),
    Standing(playerId: _userId, username: 'You', place: 2, entryStatus: EntryStatus.busted, matchesLost: 1, prizeAmount: 350, prizeCurrencyWire: 'token'),
    Standing(playerId: 'p3', username: 'NovaKid', place: 3, entryStatus: EntryStatus.busted, matchesLost: 1),
    Standing(playerId: 'p4', username: 'IronByte', place: 4, entryStatus: EntryStatus.busted, matchesLost: 1),
  ];

  @override
  Future<List<Standing>> standings(String id) async {
    final t = _require(id);
    if (id == 'demo-done') return _demoStandings;
    if (t.status.isCancelled) return const [];
    return [
      if (_entered.contains(id)) const Standing(playerId: _userId, username: 'You', entryStatus: EntryStatus.registered),
    ];
  }

  @override
  Future<List<Round>> rounds(String id) async => const [];

  @override
  Future<List<BracketNode>> bracket(String id) async => const [];
}

/// The live API when signed in against the real gateway; the demo otherwise.
final tournamentApiProvider = Provider<TournamentApi>((ref) {
  final live = ref.watch(useRemoteAuthProvider) && ref.watch(sessionProvider.select((u) => u != null));
  return live ? RemoteTournamentApi(ref.watch(apiClientProvider)) : DemoTournamentApi();
});

// ── Lobby ──

/// One lobby tab: one call per status (06 §1 "Tabs"), the rows of each in
/// order. Upcoming = registering then announced; Running = running and
/// paused; Finished = completed, refunded, cancelled, **newest first** (the
/// list is oldest first with no sort parameter, so the last page is read).
Future<List<Tournament>> loadTournamentTab(TournamentApi api, TournamentTab tab, {int? gameId, int perPage = 50}) async {
  final out = <Tournament>[];
  for (final status in tab.statuses) {
    if (tab != TournamentTab.finished) {
      out.addAll((await api.list(gameId: gameId, status: status, perPage: perPage)).items);
      continue;
    }
    final first = await api.list(gameId: gameId, status: status, perPage: perPage);
    var rows = first.items;
    if (first.totalPages > 1) {
      final lastPage = first.totalPages;
      final last = (await api.list(gameId: gameId, status: status, page: lastPage, perPage: perPage)).items;
      // A short last page: top it up with the page before.
      var before = const <Tournament>[];
      if (last.length < perPage) {
        before = lastPage - 1 == 1
            ? first.items
            : (await api.list(gameId: gameId, status: status, page: lastPage - 1, perPage: perPage)).items;
      }
      rows = [...before, ...last];
    }
    out.addAll(rows);
  }
  if (tab == TournamentTab.finished) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    out.sort((a, b) => (b.startsAt ?? epoch).compareTo(a.startsAt ?? epoch));
    return out.take(perPage).toList();
  }
  return out;
}

/// After `TOURNAMENT_FULL`: the open copy of a full Sit & Go (same name,
/// format, price and seats, with a free seat). Null = none listed.
Future<Tournament?> findNextCopy(TournamentApi api, Tournament full) async {
  final page = await api.list(gameId: full.gameId, status: TournamentStatus.registering, perPage: 100);
  return page.items
      .where((t) =>
          t.id != full.id &&
          t.name == full.name &&
          t.type == full.type &&
          t.entryFee == full.entryFee &&
          t.feeAmount == full.feeAmount &&
          t.currencyWire == full.currencyWire &&
          !t.isFull)
      .firstOrNull;
}

// ── Errors → player text (06 §4 "Errors") ──

/// What the screen does next after a refused call.
enum TournamentFix {
  /// Just show the text (or nothing).
  none,

  /// Re-read the tournament and `my-table` (no message for CONFLICT and a
  /// leave that finds no entry).
  refresh,

  /// The tournament is gone: back to the lobby and reload.
  reloadLobby,

  /// "Not enough tokens": offer the shop.
  shop,

  /// "Gold members only": offer the membership screen.
  membership,

  /// "This tournament is full": offer the next copy.
  nextCopy,

  /// An operator paused it: disable Join.
  disableJoin,
}

class TournamentIssue {
  const TournamentIssue(this.text, this.fix);

  /// Player text; null = refresh quietly.
  final String? text;
  final TournamentFix fix;
}

/// Maps a refused join ([join] true) or leave to the player's text. Decides
/// on the status and `error`; reads the developer `message` ([AppException
/// .detail]) only where 06 §4 says to (the three 403 kinds and the
/// registration window, Known issues 5). [gameName]: "Reach level 5 in Ludo".
TournamentIssue tournamentIssue(AppException e, {required bool join, String gameName = 'this game', String noun = 'tokens'}) {
  if (e.isOffline || e.kind == AppErrorKind.timeout) {
    return const TournamentIssue("Can't reach the server. Check your connection.", TournamentFix.none);
  }
  final detail = (e.detail ?? '').toLowerCase();
  switch (e.code) {
    case ApiErrorCode.badRequest:
      if (!join) return const TournamentIssue("You can't leave once it has started.", TournamentFix.refresh);
      if (detail.contains('registration closed')) return const TournamentIssue('Registration has closed.', TournamentFix.refresh);
      if (detail.contains('registration opens')) return const TournamentIssue('Registration opens soon.', TournamentFix.refresh);
      return const TournamentIssue("Registration isn't open.", TournamentFix.refresh);
    case ApiErrorCode.forbidden:
      final level = RegExp(r'requires level (\d+)').firstMatch(detail);
      if (level != null) return TournamentIssue('Reach level ${level.group(1)} in $gameName to join.', TournamentFix.none);
      if (detail.contains('subscription')) {
        final tier = RegExp(r'requires an? (\w+) subscription').firstMatch(detail)?.group(1);
        final name = tier == null || tier.isEmpty ? 'Gold' : '${tier[0].toUpperCase()}${tier.substring(1)}';
        return TournamentIssue('$name members only.', TournamentFix.membership);
      }
      if (detail.contains('limit')) return const TournamentIssue('This would pass your spending limit.', TournamentFix.none);
      return const TournamentIssue("You can't join right now.", TournamentFix.none);
    case ApiErrorCode.notFound:
      // Leave with no entry (or already left): refresh, no message.
      if (!join && detail.contains('not registered')) return const TournamentIssue(null, TournamentFix.refresh);
      return const TournamentIssue('This tournament is no longer available.', TournamentFix.reloadLobby);
    case ApiErrorCode.conflict:
      return const TournamentIssue(null, TournamentFix.refresh);
    case ApiErrorCode.tournamentFull:
      return const TournamentIssue('This tournament is full.', TournamentFix.nextCopy);
    case ApiErrorCode.insufficientFunds:
      return TournamentIssue('Not enough $noun.', TournamentFix.shop);
    case ApiErrorCode.killSwitch:
      // ApiClient already put the operator's message in [message].
      return TournamentIssue(e.message.isEmpty ? 'Tournaments are paused right now.' : e.message, TournamentFix.disableJoin);
    case ApiErrorCode.rateLimited:
      return const TournamentIssue('Too many requests. Try again in a minute.', TournamentFix.none);
  }
  if ((e.statusCode ?? 0) >= 500 || e.kind == AppErrorKind.server) {
    return const TournamentIssue('Something went wrong. Try again.', TournamentFix.none);
  }
  return TournamentIssue(e.message.isEmpty ? 'Something went wrong. Try again.' : e.message, TournamentFix.none);
}
