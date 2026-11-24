// Tournaments (docs/services/06-tournaments.md): parsing every real sample,
// the API's paths and paging, each join / leave error → player text, the
// controller's moves through the end-to-end flow, a cancelled tournament
// showing the refund, unknown enum values, and the lobby / detail screens.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/tournament.dart';
import 'package:snakeladder/data/models/wallet.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/server_clock.dart';
import 'package:snakeladder/services/tournament_api.dart';
import 'package:snakeladder/services/tournament_controller.dart';
import 'package:snakeladder/services/wallet_api.dart';
import 'package:snakeladder/screens/tournaments/tournament_detail_screen.dart';
import 'package:snakeladder/screens/tournaments/tournaments_screen.dart';

// ── Real samples (24 Nov 2026) ──

const _sngId = 'f1a95eea-8468-64da-5d23-667828f2a704';

Map<String, Object?> _row({
  String id = _sngId,
  String name = 'Weekday Ladder Final',
  String type = 'single_table_sng',
  String status = 'registering',
  Object? max = 4,
  int current = 0,
  Object entry = 250,
  Object fee = 25,
  Object pool = 0,
  String startsAt = '2026-11-19T22:00:00Z',
}) =>
    {
      'id': id, 'game_id': 1, 'mode_id': 58, 'name': name, 'tournament_type': type, 'status': status,
      'max_players': max, 'current_players': current, 'entry_fee': entry, 'fee_amount': fee, 'currency': 'token',
      'prize_pool': pool, 'starts_at': startsAt,
    };

const _listReal = {
  'data': [
    {'id': '93ae50a9-0ac4-376b-0387-996360e1bd8c', 'game_id': 1, 'mode_id': 58, 'name': 'Sunday Dice Royale',
     'tournament_type': 'single_table_sng', 'status': 'registering', 'max_players': 4, 'current_players': 0,
     'entry_fee': 2500, 'fee_amount': 250, 'currency': 'token', 'prize_pool': 0, 'starts_at': '2026-11-15T01:00:00Z'},
    {'id': _sngId, 'game_id': 1, 'mode_id': 58, 'name': 'Weekday Ladder Final',
     'tournament_type': 'single_table_sng', 'status': 'registering', 'max_players': 4, 'current_players': 0,
     'entry_fee': 250, 'fee_amount': 25, 'currency': 'token', 'prize_pool': 0, 'starts_at': '2026-11-19T22:00:00Z'},
  ],
  'total': 2, 'page': 1, 'per_page': 20, 'total_pages': 1,
};

const _freeroll = {'id': '2df67ec2-04d0-4aee-cc1d-feb52dd52fd6', 'game_id': 1, 'mode_id': 58, 'name': 'Breakfast Freeroll',
  'tournament_type': 'multi_table_mtt', 'status': 'announced', 'max_players': 500, 'current_players': 0,
  'entry_fee': 0, 'fee_amount': 0, 'currency': 'token', 'prize_pool': 5000, 'starts_at': '2026-11-24T18:00:00Z'};

const _players = [
  {'player_id': '8fe11c59-fe42-4100-9c34-891b97681130', 'username': 'w06docb1795513349', 'seat': 0, 'place': null, 'leave_reason': null},
  {'player_id': '3d3ad895-d55d-4e58-b75f-e04e291f358f', 'username': 'w06doca1795513349', 'seat': 1, 'place': null, 'leave_reason': null},
  {'player_id': '8b4a149e-f880-441e-8660-8e5799616181', 'username': 'w06docd1795513349', 'seat': 2, 'place': null, 'leave_reason': null},
  {'player_id': '047466bd-3ba0-4f71-862a-fe5222bea86d', 'username': 'w06docc1795513349', 'seat': 3, 'place': null, 'leave_reason': null},
];

Map<String, Object?> _tablePlaying({String deadline = '2026-11-24T09:46:14.665Z'}) => {
      'tournament_status': 'running',
      'entry_status': 'active',
      'table': {
        'round': 1, 'table_number': 1, 'status': 'playing', 'seat': 1,
        'room_code': '1fbbb0ed', 'match_id': '1fbbb0ed-5949-4601-add7-d147033c8e4b',
        'seat_deadline_at': deadline, 'place': null, 'players': _players,
      },
    };

const _tableDone = {
  'tournament_status': 'completed',
  'entry_status': 'winner',
  'table': {
    'round': 1, 'table_number': 1, 'status': 'closed', 'seat': 2,
    'room_code': '1fbbb0ed', 'match_id': '1fbbb0ed-5949-4601-add7-d147033c8e4b',
    'seat_deadline_at': '2026-11-24T09:46:14.665Z', 'place': 1,
    'players': [
      {'player_id': '8fe11c59-fe42-4100-9c34-891b97681130', 'username': 'w06docb1795513349', 'seat': 0, 'place': 3, 'leave_reason': 'busted'},
      {'player_id': '3d3ad895-d55d-4e58-b75f-e04e291f358f', 'username': 'w06doca1795513349', 'seat': 1, 'place': 4, 'leave_reason': 'busted'},
      {'player_id': '8b4a149e-f880-441e-8660-8e5799616181', 'username': 'w06docd1795513349', 'seat': 2, 'place': 1, 'leave_reason': 'finished'},
      {'player_id': '047466bd-3ba0-4f71-862a-fe5222bea86d', 'username': 'w06docc1795513349', 'seat': 3, 'place': 2, 'leave_reason': 'busted'},
    ],
  },
};

const _standingsReal = [
  {'place': 1, 'player_id': '8b4a149e-f880-441e-8660-8e5799616181', 'username': 'w06docd1795513349', 'entry_status': 'winner',
   'matches_won': 1, 'matches_lost': 0, 'prize_amount': 650, 'prize_currency': 'token'},
  {'place': 2, 'player_id': '047466bd-3ba0-4f71-862a-fe5222bea86d', 'username': 'w06docc1795513349', 'entry_status': 'busted',
   'matches_won': 0, 'matches_lost': 1, 'prize_amount': 350, 'prize_currency': 'token'},
  {'place': 3, 'player_id': '8fe11c59-fe42-4100-9c34-891b97681130', 'username': 'w06docb1795513349', 'entry_status': 'busted',
   'matches_won': 0, 'matches_lost': 1, 'prize_amount': 0, 'prize_currency': null},
  {'place': 4, 'player_id': '3d3ad895-d55d-4e58-b75f-e04e291f358f', 'username': 'w06doca1795513349', 'entry_status': 'busted',
   'matches_won': 0, 'matches_lost': 1, 'prize_amount': 0, 'prize_currency': null},
];

const _roundsReal = [
  {'number': 1, 'status': 'completed', 'seed': 777241965933346041,
   'starts_at': '2026-11-24T09:44:14.653061Z', 'ends_at': '2026-11-24T09:44:54.666999Z',
   'tables': [{'id': 'c0c24d19-a7d8-457a-be16-f421ccf54d0b', 'table_number': 1, 'status': 'closed',
     'match_id': '1fbbb0ed-5949-4601-add7-d147033c8e4b', 'opened_at': '2026-11-24T09:44:14.667917Z',
     'seat_deadline_at': '2026-11-24T09:46:14.665Z', 'closed_at': '2026-11-24T09:44:54.649138Z', 'last_error': null,
     'seats': [
       {'player_id': '8b4a149e-f880-441e-8660-8e5799616181', 'username': 'w06docd1795513349', 'seat': 2, 'place': 1, 'leave_reason': 'finished'},
       {'player_id': '047466bd-3ba0-4f71-862a-fe5222bea86d', 'username': 'w06docc1795513349', 'seat': 3, 'place': 2, 'leave_reason': 'busted'}]}]},
];

const _refundedTournament = {'id': 'a439b6c4-a868-42e6-ac2d-2cb2a21b9910', 'game_id': 1, 'mode_id': 58, 'name': 'Weekday Ladder Final',
  'tournament_type': 'single_table_sng', 'status': 'refunded', 'max_players': 4, 'current_players': 4,
  'entry_fee': 250, 'fee_amount': 25, 'currency': 'token', 'prize_pool': 1000, 'starts_at': '2026-11-24T09:44:14.642114Z'};

const _refundedMyTable = {'tournament_status': 'refunded', 'entry_status': 'withdrawn',
  'table': {'round': 1, 'table_number': 1, 'status': 'closed', 'seat': 0, 'room_code': '70d189c4',
    'match_id': '70d189c4-d001-4965-85a5-73b3540665da', 'seat_deadline_at': '2026-11-24T09:47:54.696Z', 'place': null,
    'players': [{'player_id': '3d3ad895-d55d-4e58-b75f-e04e291f358f', 'username': 'w06doca1795513349', 'seat': 0, 'place': null, 'leave_reason': 'withdrawn'}]}};

// ── Fake gateway (Dio adapter) ──

class _Req {
  _Req(this.method, this.path, this.query);
  final String method;
  final String path;
  final Map<String, String> query;
}

class _Gateway implements HttpClientAdapter {
  _Gateway(this.routes);
  final Map<String, FutureOr<(int, Object?)> Function(_Req)> routes;
  final List<_Req> log = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final req = _Req(o.method, o.uri.path.replaceFirst('/api/v1', ''), o.uri.queryParameters);
    log.add(req);
    final h = routes['${req.method} ${req.path}'];
    final (status, json) = h == null ? (404, {'error': 'NOT_FOUND', 'message': 'not found: no route'}) : await h(req);
    if (status == 0) throw DioException.connectionError(requestOptions: o, reason: 'offline');
    return ResponseBody.fromString(json == null ? '' : jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

RemoteTournamentApi _remote(_Gateway g) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1/', contentType: 'application/json'))..httpClientAdapter = g;
  return RemoteTournamentApi(ApiClient(dio: dio)..authToken = 'acc');
}

(int, Object?) _err(int status, String code, String message) => (status, {'error': code, 'message': message});

/// The real error body, thrown through the real ApiClient mapping.
Future<AppException> _errorOf(int status, String code, String message) async {
  final api = _remote(_Gateway({'POST /tournaments/x/register': (_) => _err(status, code, message)}));
  try {
    await api.register('x');
  } on AppException catch (e) {
    return e;
  }
  throw StateError('no error');
}

// ── Scriptable fake API for the controller and screens ──

class _FakeApi implements TournamentApi {
  _FakeApi(this.t, this.m);
  Tournament t;
  MyTable m;
  List<Standing> standingRows = const [];
  List<Tournament> listed = const [];
  AppException? registerError;
  AppException? unregisterError;
  AppException? getError;
  int gets = 0;
  int registers = 0;

  @override
  Future<Tournament> get(String id) async {
    gets++;
    if (getError != null) throw getError!;
    return t;
  }

  @override
  Future<MyTable> myTable(String id) async => m;

  @override
  Future<TournamentEntry> register(String id) async {
    registers++;
    if (registerError != null) throw registerError!;
    m = MyTable(tournamentStatus: t.status, entryStatus: EntryStatus.registered);
    t = t.copyWith(currentPlayers: t.currentPlayers + 1);
    return TournamentEntry(tournamentId: id, userId: 'me', status: EntryStatus.registered);
  }

  @override
  Future<void> unregister(String id) async {
    if (unregisterError != null) throw unregisterError!;
    m = MyTable(tournamentStatus: t.status, entryStatus: EntryStatus.withdrawn);
    t = t.copyWith(currentPlayers: t.currentPlayers - 1);
  }

  @override
  Future<List<Standing>> standings(String id) async => standingRows;

  @override
  Future<TournamentPage> list({int? gameId, TournamentStatus? status, int page = 1, int perPage = 20}) async {
    final rows = listed.where((x) => status == null || x.status == status).toList();
    return TournamentPage(items: rows, total: rows.length, totalPages: rows.isEmpty ? 0 : 1);
  }

  @override
  Future<List<Round>> rounds(String id) async => const [];

  @override
  Future<List<BracketNode>> bracket(String id) async => const [];
}

class _Wallet implements WalletApi {
  _Wallet(this.tokens);
  final int tokens;
  @override
  Future<Wallet> balance() async => Wallet(tokens: tokens, goldCoins: 0);
  @override
  Future<LedgerPage> ledger({WalletCurrency? currency, int? per, String? after}) async => const LedgerPage(items: []);
  @override
  Future<TransferResult> transfer({required String recipientId, required int amount, required WalletCurrency currency, required String idempotencyKey}) =>
      throw UnimplementedError();
}

Tournament _t(Map<String, Object?> j) => Tournament.fromJson(j);
MyTable _m(Map<String, Object?> j) => MyTable.fromJson(j);

void main() {
  group('parsing the real samples', () {
    test('list page (shape 2) and its rows', () {
      final p = TournamentPage.fromJson(_listReal);
      expect((p.total, p.page, p.perPage, p.totalPages), (2, 1, 20, 1));
      expect(p.items, hasLength(2));
      final t = p.items[1];
      expect(t.id, _sngId);
      expect((t.gameId, t.modeId, t.maxPlayers, t.currentPlayers), (1, 58, 4, 0));
      expect(t.type, TournamentType.singleTableSng);
      expect(t.status, TournamentStatus.registering);
      expect((t.entryFee, t.feeAmount, t.totalCost, t.currency), (250, 25, 275, WalletCurrency.token));
      expect(t.priceText, '250 + 25 tokens');
      expect(t.seatsText, '0 / 4');
      expect(t.poolText, 'Pool: 1,000 tokens when full');
      expect(t.startsAt, DateTime.utc(2026, 11, 19, 22));
      expect(t.comingSoon, isFalse);
    });

    test('free tournament with a guaranteed pool; not run by the server', () {
      final t = _t(_freeroll);
      expect(t.isFree, isTrue);
      expect(t.priceText, 'Free');
      expect(t.poolText, 'Prize pool 5,000 tokens');
      expect(t.type, TournamentType.multiTableMtt);
      expect(t.comingSoon, isTrue);
      expect(t.status.tab, TournamentTab.upcoming);
    });

    test('detail before and after the start; money as strings too', () {
      final full = _t(_row(current: 4));
      expect(full.isFull, isTrue);
      final started = _t(_row(status: 'running', current: 4, pool: 1000));
      expect(started.prizePool, 1000);
      expect(started.poolText, 'Prize pool 1,000 tokens');
      expect(started.status.tab, TournamentTab.running);
      final strings = _t(_row(entry: '250', fee: '25', pool: '1000'));
      expect((strings.entryFee, strings.feeAmount, strings.prizePool), (250, 25, 1000));
      expect(_t(_row(max: null)).seatsText, '0 entered');
    });

    test('my-table: not entered, registered, playing, after the game', () {
      final none = _m({'tournament_status': 'registering', 'entry_status': null, 'table': null});
      expect((none.entryStatus, none.table, none.entered), (null, null, false));
      final reg = _m({'tournament_status': 'registering', 'entry_status': 'registered', 'table': null});
      expect(reg.entryStatus, EntryStatus.registered);
      expect(reg.inPlay, isTrue);

      final play = _m(_tablePlaying());
      final table = play.table!;
      expect(play.tournamentStatus, TournamentStatus.running);
      expect(play.entryStatus, EntryStatus.active);
      expect((table.round, table.tableNumber, table.status, table.seat), (1, 1, TableStatus.playing, 1));
      expect(table.roomCode, '1fbbb0ed');
      expect(table.matchId, '1fbbb0ed-5949-4601-add7-d147033c8e4b');
      expect(table.seatDeadlineAt, DateTime.utc(2026, 11, 24, 9, 46, 14, 665));
      expect(table.label, 'Round 1, Table 1');
      expect(table.isReady, isTrue);
      expect(table.players.map((p) => p.seat), [0, 1, 2, 3]);
      expect(table.players[1].username, 'w06doca1795513349');

      final done = _m(_tableDone);
      expect(done.entryStatus, EntryStatus.winner);
      expect(done.table!.status, TableStatus.closed);
      expect(done.table!.place, 1);
      expect(done.table!.isReady, isFalse);
      expect(done.table!.players.map((p) => p.leaveReason), [LeaveReason.busted, LeaveReason.busted, LeaveReason.finished, LeaveReason.busted]);
    });

    test('register entry and refunded tournament', () {
      final e = TournamentEntry.fromJson({'tournament_id': _sngId, 'user_id': '3d3ad895-d55d-4e58-b75f-e04e291f358f',
        'status': 'registered', 'rebuys': 0, 'registered_at': '2026-11-24T09:44:02.261239Z'});
      expect((e.tournamentId, e.status, e.rebuys), (_sngId, EntryStatus.registered, 0));
      expect(e.registeredAt, isNotNull);

      final t = _t(_refundedTournament);
      expect(t.status, TournamentStatus.refunded);
      expect(t.status.isCancelled, isTrue);
      expect(t.status.tab, TournamentTab.finished);
      // Stale numbers on a cancelled tournament are ignored.
      expect(t.poolText, isNull);
      final m = _m(_refundedMyTable);
      expect(m.entryStatus, EntryStatus.withdrawn);
      expect(m.entered, isTrue);
      expect(m.table!.players.single.leaveReason, LeaveReason.withdrawn);
    });

    test('standings, rounds, bracket', () {
      final s = Standing.listFromJson(_standingsReal);
      expect(s.map((x) => x.place), [1, 2, 3, 4]);
      expect((s[0].prizeAmount, s[0].prizeCurrency, s[0].prizeText, s[0].entryStatus), (650, WalletCurrency.token, '650 tokens', EntryStatus.winner));
      expect((s[2].hasPrize, s[2].prizeCurrencyWire, s[2].matchesLost), (false, null, 1));
      expect(Standing.listFromJson(const []), isEmpty);

      final r = Round.listFromJson(_roundsReal).single;
      expect((r.number, r.isCompleted, r.tables.single.tableNumber, r.tables.single.status), (1, true, 1, TableStatus.closed));
      expect(r.tables.single.seats.first.leaveReason, LeaveReason.finished);
      expect(r.tables.single.closedAt, isNotNull);

      final b = BracketNode.listFromJson([
        {'id': 'b1', 'tournament_id': 't', 'bracket_type': 'winners', 'round': 1, 'position': 1, 'player_a_id': 'a',
         'player_b_id': 'b', 'winner_id': null, 'match_id': null, 'parent_bracket_id': 'p', 'status': 'pending'},
      ]).single;
      expect((b.bracketType, b.round, b.position, b.status, b.winnerId), ('winners', 1, 1, 'pending', null));
    });

    test('unknown status, type, entry status, leave reason and table status do not crash', () {
      final t = _t(_row(status: 'exploded', type: 'galaxy_brain'));
      expect(t.status, TournamentStatus.unknown);
      expect(t.status.tab, isNull);
      expect(t.status.label, 'Unavailable');
      expect(t.type, TournamentType.unknown);
      expect(t.type.label, 'Tournament');
      expect(t.comingSoon, isTrue);
      expect(t.typeWire, 'galaxy_brain');
      final m = _m({'tournament_status': 'weird', 'entry_status': 'zombie', 'table': {'status': 'melting', 'players': [{'leave_reason': 'abducted'}]}});
      expect(m.tournamentStatus, TournamentStatus.unknown);
      expect(m.entryStatus, EntryStatus.unknown);
      expect(m.table!.status, TableStatus.waiting); // unknown = waiting
      expect(m.table!.players.single.leaveReason, LeaveReason.unknown);
      expect(LeaveReason.parse('no_show'), LeaveReason.noShow);
      // Garbage shapes.
      expect(TournamentPage.fromJson('nope').items, isEmpty);
      expect(_m(const {}).table, isNull);
    });
  });

  group('RemoteTournamentApi', () {
    test('paths, query and paging limits', () async {
      final g = _Gateway({
        'GET /tournaments': (_) => (200, _listReal),
        'GET /tournaments/$_sngId': (_) => (200, _row()),
        'POST /tournaments/$_sngId/register': (_) => (201, {'tournament_id': _sngId, 'user_id': 'u', 'status': 'registered', 'rebuys': 0}),
        'POST /tournaments/$_sngId/unregister': (_) => (200, {'status': 'withdrawn'}),
        'GET /tournaments/$_sngId/my-table': (_) => (200, _tablePlaying()),
        'GET /tournaments/$_sngId/standings': (_) => (200, _standingsReal),
        'GET /tournaments/$_sngId/rounds': (_) => (200, _roundsReal),
        'GET /tournaments/$_sngId/bracket': (_) => (200, const []),
      });
      final api = _remote(g);
      await api.list(gameId: 1, status: TournamentStatus.registering);
      expect(g.log.last.query, {'game_id': '1', 'status': 'registering', 'page': '1', 'per_page': '20'});
      await api.list(page: 0, perPage: 0);
      expect(g.log.last.query, {'page': '1', 'per_page': '1'});
      await api.list(perPage: 500, status: TournamentStatus.unknown);
      expect(g.log.last.query, {'page': '1', 'per_page': '100'});

      expect((await api.get(_sngId)).name, 'Weekday Ladder Final');
      expect((await api.register(_sngId)).status, EntryStatus.registered);
      await api.unregister(_sngId);
      expect((await api.myTable(_sngId)).table!.roomCode, '1fbbb0ed');
      expect(await api.standings(_sngId), hasLength(4));
      expect(await api.rounds(_sngId), hasLength(1));
      expect(await api.bracket(_sngId), isEmpty);
      expect(g.log.map((r) => '${r.method} ${r.path}').skip(3), [
        'GET /tournaments/$_sngId',
        'POST /tournaments/$_sngId/register',
        'POST /tournaments/$_sngId/unregister',
        'GET /tournaments/$_sngId/my-table',
        'GET /tournaments/$_sngId/standings',
        'GET /tournaments/$_sngId/rounds',
        'GET /tournaments/$_sngId/bracket',
      ]);
    });

    test('404 and 400 on a tournament route throw with the code', () async {
      final api = _remote(_Gateway({
        'GET /tournaments/00000000-0000-4000-8000-000000000000': (_) =>
            _err(404, 'NOT_FOUND', 'not found: tournament 00000000-0000-4000-8000-000000000000'),
        'GET /tournaments/nope': (_) => _err(400, 'BAD_REQUEST', 'bad request: Path deserialize error: UUID parsing failed'),
      }));
      await expectLater(api.get('00000000-0000-4000-8000-000000000000'),
          throwsA(isA<AppException>().having((e) => e.statusCode, 'status', 404)));
      await expectLater(api.get('nope'), throwsA(isA<AppException>().having((e) => e.code, 'code', 'BAD_REQUEST')));
    });

    test('lobby tabs: one status per call; Finished reads the last page, newest first', () async {
      final calls = <String>[];
      final g = _Gateway({
        'GET /tournaments': (r) {
          calls.add('${r.query['status']}:${r.query['page']}');
          final status = r.query['status'];
          final page = int.parse(r.query['page']!);
          if (status == 'completed') {
            // 3 pages of 2, oldest first.
            final rows = [for (var i = 1; i <= 5; i++) _row(id: 'c$i', status: 'completed', startsAt: '2026-11-0${i}T00:00:00Z')];
            return (200, {'data': rows.skip((page - 1) * 2).take(2).toList(), 'total': 5, 'page': page, 'per_page': 2, 'total_pages': 3});
          }
          if (status == 'refunded') {
            return (200, {'data': [_row(id: 'r1', status: 'refunded', startsAt: '2026-11-06T00:00:00Z')], 'total': 1, 'page': 1, 'per_page': 2, 'total_pages': 1});
          }
          return (200, {'data': [], 'total': 0, 'page': 1, 'per_page': 2, 'total_pages': 0});
        },
      });
      final api = _remote(g);
      final finished = await loadTournamentTab(api, TournamentTab.finished, gameId: 1, perPage: 2);
      expect(calls, ['completed:1', 'completed:3', 'completed:2', 'refunded:1', 'cancelled:1']);
      expect(finished.map((t) => t.id), ['r1', 'c5']);
      expect(g.log.every((r) => r.query['game_id'] == '1'), isTrue);

      calls.clear();
      await loadTournamentTab(api, TournamentTab.upcoming, gameId: 1);
      expect(calls, ['registering:1', 'announced:1']);
      calls.clear();
      await loadTournamentTab(api, TournamentTab.running);
      expect(calls, ['running:1', 'paused:1']);
    });

    test('next copy after TOURNAMENT_FULL', () async {
      final full = _t(_row(current: 4));
      final api = _FakeApi(full, const MyTable(tournamentStatus: TournamentStatus.registering))
        ..listed = [full, _t(_row(id: 'other', name: 'Sunday Dice Royale')), _t(_row(id: 'copy', current: 1))];
      expect((await findNextCopy(api, full))?.id, 'copy');
    });
  });

  group('join / leave errors → player text', () {
    Future<TournamentIssue> join(int s, String code, String msg) async => tournamentIssue(await _errorOf(s, code, msg), join: true, gameName: 'Ludo');
    Future<TournamentIssue> leave(int s, String code, String msg) async => tournamentIssue(await _errorOf(s, code, msg), join: false, gameName: 'Ludo');

    test('every row of 06 §4', () async {
      var i = await join(400, 'BAD_REQUEST', 'bad request: tournament is not accepting registrations');
      expect((i.text, i.fix), ("Registration isn't open.", TournamentFix.refresh));
      i = await join(400, 'BAD_REQUEST', 'bad request: registration closed at 2026-11-24 11:48:00 UTC');
      expect(i.text, 'Registration has closed.');
      i = await join(400, 'BAD_REQUEST', 'bad request: registration opens at 2026-11-25 11:48:00 UTC');
      expect(i.text, 'Registration opens soon.');
      i = await leave(400, 'BAD_REQUEST', 'bad request: cannot unregister once the tournament has started or ended');
      expect((i.text, i.fix), ("You can't leave once it has started.", TournamentFix.refresh));
      i = await join(403, 'FORBIDDEN', 'forbidden: requires level 5 in this game (you are level 1)');
      expect(i.text, 'Reach level 5 in Ludo to join.');
      i = await join(403, 'FORBIDDEN', 'forbidden: requires a gold subscription');
      expect((i.text, i.fix), ('Gold members only.', TournamentFix.membership));
      i = await join(403, 'FORBIDDEN', 'forbidden: buy-in would exceed your daily loss limit (90 lost of 100)');
      expect(i.text, 'This would pass your spending limit.');
      i = await join(403, 'FORBIDDEN', 'forbidden: you are banned from tournaments');
      expect(i.text, "You can't join right now.");
      i = await join(404, 'NOT_FOUND', 'not found: tournament x');
      expect(i.fix, TournamentFix.reloadLobby);
      i = await leave(404, 'NOT_FOUND', 'not found: not registered for this tournament');
      expect((i.text, i.fix), (null, TournamentFix.refresh));
      i = await join(409, 'CONFLICT', 'conflict: already registered');
      expect((i.text, i.fix), (null, TournamentFix.refresh));
      i = await join(409, 'TOURNAMENT_FULL', 'tournament full');
      expect((i.text, i.fix), ('This tournament is full.', TournamentFix.nextCopy));
      i = await join(409, 'INSUFFICIENT_FUNDS', 'insufficient funds');
      expect((i.text, i.fix), ('Not enough tokens.', TournamentFix.shop));
      i = await join(503, 'KILL_SWITCH_ENGAGED', 'Tournaments are paused for maintenance.');
      expect((i.text, i.fix), ('Tournaments are paused for maintenance.', TournamentFix.disableJoin));
      i = await join(500, 'INTERNAL_ERROR', 'boom');
      expect(i.text, 'Something went wrong. Try again.');
      i = tournamentIssue(const AppException('x', kind: AppErrorKind.offline), join: true);
      expect(i.text, "Can't reach the server. Check your connection.");
    });
  });

  group('TournamentController', () {
    final sng = _t(_row(current: 3));

    test('end-to-end: join → waiting → table ready → at table → results coming → finished', () async {
      final api = _FakeApi(sng, const MyTable(tournamentStatus: TournamentStatus.registering));
      var money = 0;
      final entered = <String>[];
      final c = TournamentController(
        api: api, id: _sngId, initial: sng, settleDelay: Duration.zero,
        onMoneyMoved: () => money++, onEntered: entered.add,
      );
      await c.refresh();
      expect(c.phase, TournamentPhase.notEntered);

      expect(await c.join(), isNull);
      expect(entered, [_sngId]);
      expect(money, 1);
      expect(c.phase, TournamentPhase.entered);
      expect(c.tournament!.seatsText, '4 / 4');

      api
        ..t = _t(_row(status: 'running', current: 4, pool: 1000))
        ..m = _m(_tablePlaying(deadline: DateTime.now().toUtc().add(const Duration(minutes: 2)).toIso8601String()));
      await c.refresh();
      expect(c.phase, TournamentPhase.tableReady);
      expect(c.seatTimeLeft!.inSeconds, greaterThan(100));

      c.wentToTable();
      expect(c.phase, TournamentPhase.atTable);

      // The game ended; settlement not done yet.
      api.m = _m({..._tableDone, 'tournament_status': 'running'});
      await c.backFromTable();
      expect(c.phase, TournamentPhase.waitingResult);
      expect(c.shouldPoll, isTrue);

      api
        ..t = _t(_row(status: 'completed', current: 4, pool: 1000))
        ..m = _m(_tableDone)
        ..standingRows = Standing.listFromJson(_standingsReal);
      await c.refresh();
      expect(c.phase, TournamentPhase.finished);
      expect(c.shouldPoll, isFalse);
      expect(c.standingOf('8b4a149e-f880-441e-8660-8e5799616181')!.prizeAmount, 650);
      expect(money, greaterThanOrEqualTo(3)); // join, back from table, prize
      c.dispose();
    });

    testWidgets('polls every 10 s while registering; stops when over or at the table', (tester) async {
      // testWidgets runs on a fake clock: pump() moves time.
      final api = _FakeApi(sng, const MyTable(tournamentStatus: TournamentStatus.registering));
      final c = TournamentController(api: api, id: _sngId, initial: sng);
      unawaited(c.start());
      await tester.pump();
      expect(api.gets, 1);
      await tester.pump(const Duration(seconds: 9));
      expect(api.gets, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(api.gets, 2);
      c.wentToTable();
      await tester.pump(const Duration(seconds: 30));
      expect(api.gets, 2);
      unawaited(c.backFromTable());
      await tester.pump(const Duration(seconds: 3));
      final after = api.gets;
      api.t = _t(_row(status: 'completed', current: 4));
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 60));
      expect(api.gets, after + 1);
      c.dispose();
    });

    test('countdowns use the server clock (ServerClock)', () async {
      addTearDown(ServerClock.reset);
      final deadline = DateTime.now().toUtc().add(const Duration(minutes: 2));
      final api = _FakeApi(sng, _m(_tablePlaying(deadline: deadline.toIso8601String())));
      final c = TournamentController(api: api, id: _sngId, initial: sng);
      await c.refresh();
      expect(c.seatTimeLeft!.inSeconds, inInclusiveRange(110, 120));
      // The server is a minute ahead of the phone: one minute is left.
      ServerClock.fromSocket(DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch);
      expect(c.seatTimeLeft!.inSeconds, inInclusiveRange(50, 60));
      c.dispose();
    });

    test('a cancelled tournament shows the refund and re-reads the wallet', () async {
      final api = _FakeApi(sng, const MyTable(tournamentStatus: TournamentStatus.registering, entryStatus: EntryStatus.registered));
      var money = 0;
      final c = TournamentController(api: api, id: _sngId, initial: sng, onMoneyMoved: () => money++);
      await c.refresh();
      expect(c.phase, TournamentPhase.entered);
      api
        ..t = _t(_refundedTournament)
        ..m = _m(_refundedMyTable);
      await c.refresh();
      expect(c.phase, TournamentPhase.cancelled);
      expect(c.myTable!.entered, isTrue);
      expect(money, 1);
      c.dispose();
    });

    test('join errors: full, conflict; offline join that went through', () async {
      final api = _FakeApi(sng, const MyTable(tournamentStatus: TournamentStatus.registering))
        ..registerError = const AppException('', statusCode: 409, code: 'TOURNAMENT_FULL');
      final c = TournamentController(api: api, id: _sngId, initial: sng);
      await c.refresh();
      expect((await c.join())!.fix, TournamentFix.nextCopy);

      api.registerError = const AppException('', statusCode: 409, code: 'CONFLICT');
      final conflict = await c.join();
      expect((conflict!.text, conflict.fix), (null, TournamentFix.refresh));

      // Timeout, but my-table says registered: it went through.
      api
        ..registerError = const AppException('', kind: AppErrorKind.timeout)
        ..m = const MyTable(tournamentStatus: TournamentStatus.registering, entryStatus: EntryStatus.registered);
      expect(await c.join(), isNull);
      expect(c.phase, TournamentPhase.entered);
      c.dispose();
    });

    test('kill switch disables Join; 404 = gone', () async {
      final api = _FakeApi(sng, const MyTable(tournamentStatus: TournamentStatus.registering))
        ..registerError = const AppException('Paused by ops.', statusCode: 503, code: 'KILL_SWITCH_ENGAGED');
      final c = TournamentController(api: api, id: _sngId, initial: sng);
      await c.refresh();
      await c.join();
      expect(c.joinPausedText, 'Paused by ops.');
      api.getError = const AppException('', statusCode: 404, code: 'NOT_FOUND');
      await c.refresh();
      expect(c.phase, TournamentPhase.gone);
      c.dispose();
    });

    test('leave refunds and returns to notEntered', () async {
      final api = _FakeApi(sng, const MyTable(tournamentStatus: TournamentStatus.registering, entryStatus: EntryStatus.registered));
      final left = <String>[];
      final c = TournamentController(api: api, id: _sngId, initial: sng, onLeft: left.add);
      await c.refresh();
      expect(await c.leave(), isNull);
      expect(left, [_sngId]);
      expect(c.phase, TournamentPhase.notEntered);
      c.dispose();
    });
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, Widget home, {required TournamentApi api, int tokens = 600}) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          tournamentApiProvider.overrideWithValue(api),
          walletApiProvider.overrideWithValue(_Wallet(tokens)),
        ],
        child: MaterialApp(home: home),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('lobby: Sit & Go row shows seats, "Starts when full", price, no start time', (tester) async {
      final row = _t(_row(current: 3));
      final api = _FakeApi(row, const MyTable(tournamentStatus: TournamentStatus.registering))
        ..listed = [row, _t(_freeroll)];
      await pump(tester, const TournamentsScreen(), api: api);
      expect(find.text('Weekday Ladder Final'), findsOneWidget);
      expect(find.text('Sit & Go, 4 players · Starts when full'), findsOneWidget);
      expect(find.text('250 + 25 tokens'), findsOneWidget);
      expect(find.text('3 / 4 seated'), findsOneWidget);
      expect(find.text('Pool: 1,000 tokens when full'), findsOneWidget);
      expect(find.textContaining('2026'), findsNothing);
      // An unrun format: "Coming soon", no Join.
      expect(find.text('Breakfast Freeroll'), findsOneWidget);
      expect(find.text('Soon'), findsOneWidget);
      await tester.tap(find.text('Finished'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('No finished tournaments yet.'), findsOneWidget);
    });

    testWidgets('detail: Join greyed out when the wallet cannot cover it', (tester) async {
      final t = _t(_row(current: 3));
      final api = _FakeApi(t, const MyTable(tournamentStatus: TournamentStatus.registering));
      await pump(tester, TournamentDetailScreen(tournament: t, autoOpenTable: false), api: api, tokens: 250);
      expect(find.text('Join · 250 + 25 tokens'), findsOneWidget);
      expect(find.text('You need 275 tokens. You have 250.'), findsOneWidget);
      await tester.tap(find.text('Join · 250 + 25 tokens'));
      await tester.pump();
      expect(api.registers, 0);
    });

    testWidgets('detail: confirm, join, "You\'re in", Leave', (tester) async {
      final t = _t(_row(current: 2));
      final api = _FakeApi(t, const MyTable(tournamentStatus: TournamentStatus.registering));
      await pump(tester, TournamentDetailScreen(tournament: t, autoOpenTable: false), api: api);
      await tester.tap(find.text('Join · 250 + 25 tokens'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Join Weekday Ladder Final for 250 + 25 tokens?'), findsOneWidget);
      expect(find.text('600 tokens'), findsOneWidget);
      await tester.tap(find.text('Join').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.registers, 1);
      expect(find.text("You're in"), findsWidgets);
      expect(find.text("You're in. Waiting for players (3 / 4)"), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4)); // toast away
    });

    testWidgets('detail: table ready hand-off with the seat deadline', (tester) async {
      final t = _t(_row(status: 'running', current: 4, pool: 1000));
      final deadline = DateTime.now().toUtc().add(const Duration(minutes: 1, seconds: 58)).toIso8601String();
      final api = _FakeApi(t, _m(_tablePlaying(deadline: deadline)));
      await pump(tester, TournamentDetailScreen(tournament: t, autoOpenTable: false), api: api);
      expect(find.text('Your table is ready'), findsOneWidget);
      expect(find.text('Round 1, Table 1'), findsWidgets);
      expect(find.textContaining('Join within 1:5'), findsOneWidget);
      expect(find.text('Go to table'), findsOneWidget);
    });

    testWidgets('detail: cancelled tournament shows the refund', (tester) async {
      final t = _t(_refundedTournament);
      final api = _FakeApi(t, _m(_refundedMyTable));
      await pump(tester, TournamentDetailScreen(tournament: t, autoOpenTable: false), api: api);
      expect(find.text('This tournament was cancelled.'), findsOneWidget);
      expect(find.text('Your 275 tokens have been refunded.'), findsOneWidget);
      expect(find.text('Cancelled, entry refunded'), findsOneWidget);
      expect(find.text('You left this tournament'), findsNothing);
    });

    testWidgets('detail: unknown status renders a neutral label', (tester) async {
      final t = _t(_row(status: 'exploded', type: 'galaxy_brain'));
      final api = _FakeApi(t, _m({'tournament_status': 'exploded', 'entry_status': 'zombie', 'table': null}));
      await pump(tester, TournamentDetailScreen(tournament: t, autoOpenTable: false), api: api);
      expect(tester.takeException(), isNull);
      expect(find.text('Unavailable'), findsOneWidget);
    });
  });
}
