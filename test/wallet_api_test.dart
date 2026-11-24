// The wallet contract (docs/services/03-wallet.md): model parsing of the real
// replies (string and number money, null fields), the ledger "load more"
// loop, transfer error mapping and Idempotency-Key reuse on a retry. Dio runs
// against a stand-in adapter that answers like the gateway.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/wallet.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/wallet_api.dart';
import 'package:snakeladder/services/wallet_store.dart';
import 'package:snakeladder/widgets/aura.dart' show Currency;

class _Req {
  _Req(this.method, this.path, this.query, this.headers, this.body);
  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Map<String, dynamic> headers;
  final dynamic body;
}

typedef _Handler = FutureOr<(int, Object?)> Function(_Req);

class _Gateway implements HttpClientAdapter {
  _Gateway(this.routes);
  final Map<String, _Handler> routes;
  final List<_Req> log = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final req = _Req(o.method, o.uri.path.replaceFirst('/api/v1', ''), o.uri.queryParameters, Map.of(o.headers), o.data);
    log.add(req);
    final handler = routes['${req.method} ${req.path}'];
    final (status, json) = handler == null ? (404, {'error': 'NOT_FOUND', 'message': 'no route'}) : await handler(req);
    if (status == 0) {
      throw DioException.connectionError(requestOptions: o, reason: 'offline');
    }
    return ResponseBody.fromString(json == null ? '' : jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

RemoteWalletApi _wallet(_Gateway g) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1/', contentType: 'application/json'))..httpClientAdapter = g;
  return RemoteWalletApi(ApiClient(dio: dio)..authToken = 'acc', retryDelay: Duration.zero);
}

(int, Object?) _err(int status, String code, [Map<String, Object?> extra = const {}]) =>
    (status, {'error': code, 'message': 'developer text: $code', ...extra});

// Real replies from the doc (24 Nov 2026).
const _balance = {
  'user_id': '97d5bce4-0b63-4d30-8492-bbfba48cf83a',
  'balance_tokens': '100',
  'balance_gold': '500',
  'updated_at': '2026-11-24T09:18:24.050121Z',
};

Map<String, Object?> _row(String id, {String currency = 'gold', String direction = 'credit', Object amount = 5, String kind = 'transfer', String? match, String? game}) => {
      'entry_id': id,
      'created_at': '2026-11-24T09:19:48.358890Z',
      'currency': currency,
      'direction': direction,
      'amount': amount,
      'kind': kind,
      'counterparty': match == null ? 'user' : 'house_revenue',
      'counterparty_user_id': match == null ? '97d5bce4-0b63-4d30-8492-bbfba48cf83a' : null,
      'tournament_id': null,
      'match_id': match,
      'item_kind': null,
      'item_name': null,
      'game_code': game,
      'variant_code': game == null ? null : 'classic',
    };

void main() {
  group('models', () {
    test('balance: money as strings, updated_at, user_id', () {
      final w = Wallet.fromJson(_balance);
      expect(w.tokens, 100);
      expect(w.goldCoins, 500);
      expect(w.userId, '97d5bce4-0b63-4d30-8492-bbfba48cf83a');
      expect(w.updatedAt, DateTime.utc(2026, 11, 24, 9, 18, 24, 50, 121));
      expect(w.gold, '500');
      // Numbers too (game sockets), and thousands separators.
      final n = Wallet.fromJson({'balance_tokens': 12000, 'balance_gold': 1234567});
      expect(n.gems, '12,000');
      expect(n.gold, '1,234,567');
    });

    test('ledger page: number amounts, null fields, cursor', () {
      final p = LedgerPage.fromJson({
        'items': [
          _row('ledger:42029', currency: 'token', amount: 3),
          _row('ledger:42021', direction: 'debit', amount: 10, kind: 'entry_fee', match: '4452d182-de43-4d79-9905-31a0be00c564', game: 'ludo'),
        ],
        'page': 1,
        'pages': 3,
        'total': 5,
        'next_cursor': '7b22',
      });
      expect(p.items, hasLength(2));
      expect(p.total, 5);
      expect(p.nextCursor, '7b22');
      final t = p.items.first;
      expect(t.currency, WalletCurrency.token);
      expect(t.credit, isTrue);
      expect(t.amount, 3);
      expect(t.label, 'Received');
      expect(t.signedAmount, '+3');
      expect(t.matchId, isNull);
      expect(t.detail, 'From a player');
      final fee = p.items.last;
      expect(fee.signedAmount, '-10');
      expect(fee.label, 'Entry fee');
      expect(fee.detail, 'Ludo'); // never the counterparty for match rows
      expect(fee.isMatch, isTrue);

      final end = LedgerPage.fromJson({'items': [], 'page': 99, 'pages': 1, 'total': 5, 'next_cursor': null});
      expect(end.items, isEmpty);
      expect(end.hasMore, isFalse);
    });

    test('kind labels: match_* = Ludo kinds; unknown → Wallet update', () {
      LedgerEntry e(String kind, {bool credit = true}) =>
          LedgerEntry.fromJson(_row('x', kind: kind, direction: credit ? 'credit' : 'debit'));
      expect(e('signup_grant').label, 'Welcome credit');
      expect(e('match_stake').label, e('entry_fee').label);
      expect(e('match_payout').label, e('payout').label);
      expect(e('match_refund').label, e('refund').label);
      expect(e('payout').label, 'Winnings');
      expect(e('transfer', credit: false).label, 'Sent');
      expect(e('gift').label, 'Gift received');
      expect(e('iap_gold_pack').label, 'Bought gold');
      expect(e('daily_bonus').label, 'Bonus');
      expect(e('minigame_prize').label, 'Bonus game');
      expect(e('something_new').label, 'Wallet update');
      expect(LedgerEntry.gameName('snake-and-ladder'), 'Snake And Ladder');
    });

    test('transfer reply: strings, any field order (replay)', () {
      final r = TransferResult.fromJson({'currency': 'gold', 'sender_balance': '504', 'transferred': '5'});
      expect(r.senderBalance, 504);
      expect(r.transferred, 5);
      expect(r.currency, WalletCurrency.gold);
    });

    test('game.wallet_update: own payout by user id', () {
      final u = WalletUpdate.fromJson({
        'match_id': '4452d182-de43-4d79-9905-31a0be00c564',
        'payouts': [
          {'amount': 19, 'result': 'win', 'user_id': 'a'},
          {'amount': 0, 'result': 'forfeit', 'user_id': 'b'},
        ],
        'pot_amount': 20,
        'rake_amount': 1,
      });
      expect(u.payoutFor('a')?.amount, 19);
      expect(u.payoutFor('b')?.result, 'forfeit');
      expect(u.payoutFor('c'), isNull);
      expect(u.potAmount, 20);
      expect(u.rakeAmount, 1);
    });
  });

  group('RemoteWalletApi', () {
    test('balance: GET /wallet/balance with the bearer token', () async {
      final g = _Gateway({'GET /wallet/balance': (_) => (200, _balance)});
      final w = await _wallet(g).balance();
      expect(w.goldCoins, 500);
      expect(g.log.single.headers['Authorization'], 'Bearer acc');
    });

    test('balance 404 → "Wallet unavailable."', () async {
      final g = _Gateway({'GET /wallet/balance': (_) => _err(404, 'NOT_FOUND')});
      await expectLater(
          _wallet(g).balance(), throwsA(isA<AppException>().having((e) => e.message, 'message', 'Wallet unavailable.')));
    });

    test('ledger: currency / per / after query (never cursor=)', () async {
      final g = _Gateway({
        'GET /wallet/ledger': (_) => (200, {'items': [], 'page': 1, 'pages': 1, 'total': 0, 'next_cursor': null}),
      });
      await _wallet(g).ledger(currency: WalletCurrency.token, per: 2, after: 'abc');
      expect(g.log.single.query, {'currency': 'token', 'per': '2', 'after': 'abc'});
      await _wallet(g).ledger();
      expect(g.log.last.query, isEmpty);
    });

    test('load more: after=<next_cursor> with the same filter until null', () async {
      final pages = {
        null: {'items': [_row('ledger:5'), _row('ledger:4')], 'page': 1, 'pages': 3, 'total': 5, 'next_cursor': 'c1'},
        'c1': {'items': [_row('ledger:3'), _row('ledger:2')], 'page': 2, 'pages': 3, 'total': 5, 'next_cursor': 'c2'},
        'c2': {'items': [_row('ledger:1')], 'page': 3, 'pages': 3, 'total': 5, 'next_cursor': null},
      };
      final g = _Gateway({'GET /wallet/ledger': (r) => (200, pages[r.query['after']])});
      final pager = LedgerPager(_wallet(g), currency: WalletCurrency.gold, per: 2);
      await pager.reload();
      expect(pager.hasMore, isTrue);
      while (pager.hasMore) {
        await pager.loadMore();
      }
      expect(pager.items.map((e) => e.entryId), ['ledger:5', 'ledger:4', 'ledger:3', 'ledger:2', 'ledger:1']);
      expect(g.log.map((r) => r.query['after']), [null, 'c1', 'c2']);
      expect(g.log.every((r) => r.query['currency'] == 'gold' && r.query['per'] == '2'), isTrue);
      expect(g.log.any((r) => r.query.containsKey('cursor') || r.query.containsKey('page')), isFalse);
      // Another call does nothing at the end.
      await pager.loadMore();
      expect(g.log, hasLength(3));
      // Pull to refresh: from the top, no after.
      await pager.reload();
      expect(g.log.last.query.containsKey('after'), isFalse);
      expect(pager.items, hasLength(2));
    });

    test('load more with a refused cursor reloads from the top', () async {
      final g = _Gateway({
        'GET /wallet/ledger': (r) => r.query['after'] == null
            ? (200, {'items': [_row('ledger:2')], 'page': 1, 'pages': 2, 'total': 2, 'next_cursor': 'bad'})
            : _err(400, 'BAD_REQUEST'),
      });
      final pager = LedgerPager(_wallet(g));
      await pager.reload();
      await pager.loadMore();
      expect(g.log.map((r) => r.query['after']), [null, 'bad', null]);
      expect(pager.items.single.entryId, 'ledger:2');
    });

    test('empty history', () async {
      final g = _Gateway({
        'GET /wallet/ledger': (_) => (200, {'items': [], 'page': 1, 'pages': 1, 'total': 0, 'next_cursor': null}),
      });
      final pager = LedgerPager(_wallet(g));
      await pager.reload();
      expect(pager.isEmpty, isTrue);
    });

    test('transfer: body, Idempotency-Key header, string reply', () async {
      final g = _Gateway({
        'POST /wallet/transfer': (_) => (200, {'sender_balance': '504', 'transferred': '5', 'currency': 'gold'}),
      });
      final r = await _wallet(g).transfer(recipientId: 'u2', amount: 5, currency: WalletCurrency.gold, idempotencyKey: 'k1');
      expect(r.senderBalance, 504);
      final req = g.log.single;
      expect(jsonDecode(jsonEncode(req.body)), {'recipient_id': 'u2', 'amount': 5, 'currency': 'gold'});
      expect(req.headers['Idempotency-Key'], 'k1');
    });

    test('transfer: no network → one retry with the SAME key', () async {
      var n = 0;
      final g = _Gateway({
        'POST /wallet/transfer': (_) =>
            n++ == 0 ? (0, null) : (200, {'currency': 'gold', 'sender_balance': '504', 'transferred': '5'}),
      });
      final r = await _wallet(g).transfer(recipientId: 'u2', amount: 5, currency: WalletCurrency.gold, idempotencyKey: 'k-retry');
      expect(r.transferred, 5);
      expect(g.log, hasLength(2));
      expect(g.log.map((r) => r.headers['Idempotency-Key']), ['k-retry', 'k-retry']);
    });

    test('transfer: RATE_LIMITED retries once, then shows the error', () async {
      final g = _Gateway({'POST /wallet/transfer': (_) => _err(429, 'RATE_LIMITED')});
      await expectLater(
        _wallet(g).transfer(recipientId: 'u2', amount: 5, currency: WalletCurrency.gold, idempotencyKey: 'k'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'RATE_LIMITED')),
      );
      expect(g.log, hasLength(2));
    });

    final cases = <(int, String, Map<String, Object?>, WalletCurrency, String)>[
      (400, 'VALIDATION_ERROR', {'field': 'amount'}, WalletCurrency.gold, 'Enter a whole amount above 0.'),
      (404, 'NOT_FOUND', {}, WalletCurrency.gold, "That player can't receive money."),
      (409, 'INSUFFICIENT_FUNDS', {}, WalletCurrency.gold, 'Not enough gold.'),
      (409, 'INSUFFICIENT_FUNDS', {}, WalletCurrency.token, 'Not enough tokens.'),
      (429, 'GIFT_QUOTA_EXCEEDED', {}, WalletCurrency.gold, "You've reached today's sending limit."),
      (409, 'CONFLICT', {}, WalletCurrency.gold, 'Something went wrong. Try again.'),
      (400, 'BAD_REQUEST', {}, WalletCurrency.gold, 'Something went wrong. Try again.'),
      (401, 'FINGERPRINT_MISMATCH', {}, WalletCurrency.gold, 'Your session has ended. Please log in again.'),
    ];
    for (final (status, code, extra, currency, text) in cases) {
      test('transfer error $status $code ($currency) → "$text"', () async {
        final g = _Gateway({'POST /wallet/transfer': (_) => _err(status, code, extra)});
        await expectLater(
          _wallet(g).transfer(recipientId: 'u2', amount: 5, currency: currency, idempotencyKey: 'k'),
          throwsA(isA<AppException>()
              .having((e) => e.message, 'message', text)
              .having((e) => e.code, 'code', code)
              .having((e) => e.statusCode, 'status', status)),
        );
        expect(g.log, hasLength(1)); // no retry for a definite answer
      });
    }

    test('transfer KILL_SWITCH_ENGAGED shows the operator message', () async {
      final g = _Gateway({
        'POST /wallet/transfer': (_) => (503, {'error': 'KILL_SWITCH_ENGAGED', 'message': 'Transfers are paused for maintenance.'}),
      });
      await expectLater(
        _wallet(g).transfer(recipientId: 'u2', amount: 5, currency: WalletCurrency.gold, idempotencyKey: 'k'),
        throwsA(isA<AppException>()
            .having((e) => e.message, 'message', 'Transfers are paused for maintenance.')
            .having((e) => e.isKillSwitch, 'isKillSwitch', isTrue)),
      );
    });
  });

  group('WalletStore', () {
    test('reads on start, throttles refresh to 10 s, forced events re-read, transfer applies sender_balance', () async {
      final api = _CountingApi();
      final c = ProviderContainer(overrides: [walletApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      final sub = c.listen(walletProvider, (_, _) {});
      addTearDown(sub.close);

      expect((await c.read(walletProvider.future)).goldCoins, 500);
      expect(api.reads, 1);

      await c.read(walletProvider.notifier).refresh(); // under 10 s: skipped
      expect(api.reads, 1);
      await c.read(walletProvider.notifier).gameEnded();
      expect(api.reads, 2);
      await c.read(walletProvider.notifier).moneyMoved();
      expect(api.reads, 3);

      api.gold = 495;
      final r = await c.read(walletProvider.notifier).transfer(
          recipientId: 'u2', amount: 5, currency: WalletCurrency.gold, idempotencyKey: 'k');
      expect(r.senderBalance, 495);
      expect(c.read(walletProvider).value?.of(Currency.gold), 495);
      await Future<void>.delayed(Duration.zero);
      expect(api.reads, 4); // re-read after a transfer
    });

    test('a failed re-read keeps the last balance', () async {
      final api = _CountingApi();
      final c = ProviderContainer(overrides: [walletApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      final sub = c.listen(walletProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(walletProvider.future);
      api.fail = true;
      await c.read(walletProvider.notifier).refresh(force: true);
      expect(c.read(walletProvider).value?.goldCoins, 500);
      expect(c.read(walletProvider).hasError, isFalse);
    });
  });
}

class _CountingApi implements WalletApi {
  int reads = 0;
  int gold = 500;
  bool fail = false;

  @override
  Future<Wallet> balance() async {
    reads++;
    if (fail) throw const AppException("Can't reach the server.", kind: AppErrorKind.offline);
    return Wallet(tokens: 100, goldCoins: gold);
  }

  @override
  Future<LedgerPage> ledger({WalletCurrency? currency, int? per, String? after}) async => const LedgerPage(items: []);

  @override
  Future<TransferResult> transfer({
    required String recipientId,
    required int amount,
    required WalletCurrency currency,
    required String idempotencyKey,
  }) async =>
      TransferResult(senderBalance: gold, transferred: amount, currency: currency);
}
