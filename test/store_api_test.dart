// The store contract (docs/services/11-store.md): model parsing of the real
// replies (string and number money, both subscription shapes), the payment
// rule and discount badges, error mapping per route, Idempotency-Key reuse on
// a retry and a new key per purchase, `Idempotent-Replayed: true` treated as
// success, and the switched-off IapBridge (verify, then complete). Dio runs
// against a stand-in adapter that answers like the gateway.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/account.dart';
import 'package:snakeladder/data/models/store.dart';
import 'package:snakeladder/data/models/subscription.dart';
import 'package:snakeladder/data/models/wallet.dart';
import 'package:snakeladder/services/account_service.dart';
import 'package:snakeladder/services/account_store.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/iap_bridge.dart';
import 'package:snakeladder/services/store_api.dart';
import 'package:snakeladder/services/store_service.dart';
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

/// status 0 = no network; status -1 = a receive timeout.
typedef _Handler = FutureOr<(int, Object?, Map<String, String>)> Function(_Req);

class _Gateway implements HttpClientAdapter {
  _Gateway(this.routes);
  final Map<String, _Handler> routes;
  final List<_Req> log = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final req = _Req(o.method, o.uri.path.replaceFirst('/api/v1', ''), o.uri.queryParameters, Map.of(o.headers), o.data);
    log.add(req);
    final handler = routes['${req.method} ${req.path}'];
    final (status, json, headers) =
        handler == null ? (404, {'error': 'NOT_FOUND', 'message': 'no route'}, const <String, String>{}) : await handler(req);
    if (status == 0) throw DioException.connectionError(requestOptions: o, reason: 'offline');
    if (status == -1) throw DioException.receiveTimeout(timeout: const Duration(seconds: 15), requestOptions: o);
    return ResponseBody.fromString(json == null ? '' : jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
      for (final e in headers.entries) e.key: [e.value],
    });
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(_Gateway g) =>
    ApiClient(dio: Dio(BaseOptions(baseUrl: 'http://test/api/v1/', contentType: 'application/json'))..httpClientAdapter = g)
      ..authToken = 'acc';

(int, Object?, Map<String, String>) _ok(Object? json, {int status = 200, bool replayed = false}) =>
    (status, json, replayed ? const {'idempotent-replayed': 'true'} : const {});

(int, Object?, Map<String, String>) _err(int status, String code, [Map<String, Object?> extra = const {}]) =>
    (status, {'error': code, 'message': 'developer text: $code', ...extra}, const {});

// ── Real replies (24 Nov 2026) ──

const _tokens550 = {
  'id': 2, 'code': 'tokens_550', 'name': 'Pouch of Tokens', 'description': '500 tokens + 50 bonus.',
  'category': 'token_pack', 'token_amount': 500, 'gold_amount': 0, 'bonus_token_amount': 50,
  'bonus_gold_amount': 0, 'power_up_id': null, 'power_up_quantity': null, 'avatar_id': null,
  'is_active': true, 'created_at': '2026-11-14T08:35:16.461863Z',
  'price_unit': 'usd', 'price_usd_cents': 499, 'price_tokens': null, 'price_gold': null,
  'price_tier': 'default', 'regular_price': 499, 'special_label': null, 'special_until': null,
};
const _gold5000 = {
  'id': 5, 'code': 'gold_5000', 'name': 'Gold Sack', 'description': '5,000 gold.', 'category': 'gold_pack',
  'token_amount': 0, 'gold_amount': 5000, 'bonus_token_amount': 0, 'bonus_gold_amount': 0,
  'power_up_id': null, 'power_up_quantity': null, 'avatar_id': null, 'is_active': true,
  'price_unit': 'usd', 'price_usd_cents': 199, 'price_tokens': null, 'price_gold': null,
  'price_tier': 'default', 'regular_price': 199, 'special_label': null, 'special_until': null,
};
const _shield5 = {
  'id': 12, 'code': 'ludo_shield_x5', 'name': 'Ludo Shield x5',
  'description': 'Five shields against the triple-six penalty.', 'category': 'power_up_pack',
  'token_amount': 0, 'gold_amount': 0, 'bonus_token_amount': 0, 'bonus_gold_amount': 0,
  'power_up_id': 28, 'power_up_quantity': 5, 'avatar_id': null, 'is_active': true,
  'price_unit': 'token', 'price_usd_cents': null, 'price_tokens': 250, 'price_gold': null,
  'price_tier': 'default', 'regular_price': 250, 'special_label': null, 'special_until': null,
};
const _crown = {
  'id': 17, 'code': 'avatar_ludo_golden_crown', 'name': 'Golden Crown', 'category': 'avatar',
  'avatar_id': 15, 'price_unit': 'token', 'price_usd_cents': null, 'price_tokens': 500,
  'price_gold': null, 'price_tier': 'default', 'regular_price': 500,
};
const _removeAds = {
  'id': 7, 'code': 'ad_free_forever', 'name': 'Remove Ads', 'description': 'Play without ads, forever.',
  'category': 'ad_free', 'token_amount': 0, 'gold_amount': 0, 'bonus_token_amount': 0,
  'bonus_gold_amount': 0, 'power_up_id': null, 'power_up_quantity': null, 'avatar_id': null,
  'is_active': true, 'price_unit': 'gold', 'price_usd_cents': 299, 'price_tokens': null, 'price_gold': 10000,
  'price_tier': 'default', 'regular_price': 299, 'special_label': null, 'special_until': null,
};

const _balance = {
  'user_id': 'da917b6d-9fea-4f27-800b-9709346d05bf',
  'balance_tokens': '650',
  'balance_gold': '500',
  'updated_at': '2026-11-24T10:45:43.564996Z',
};

ShopItem _item(Map<String, Object?> j) => ShopItem.fromJson(Map<String, dynamic>.from(j));

/// A container wired to [g]: the store, the wallet and the inventory.
/// Lets the background wallet / inventory re-reads finish before dispose.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 30));

ProviderContainer _container(_Gateway g, {List<String>? keys}) {
  final api = _client(g);
  var n = 0;
  final c = ProviderContainer(overrides: [
    storeApiProvider.overrideWithValue(RemoteStoreApi(api)),
    walletApiProvider.overrideWithValue(RemoteWalletApi(api, retryDelay: Duration.zero)),
    accountApiProvider.overrideWithValue(RemoteAccountApi(api)),
    purchaseRetryDelayProvider.overrideWithValue(Duration.zero),
    if (keys != null) purchaseKeyProvider.overrideWithValue(() => keys[n++]),
  ]);
  addTearDown(() async {
    await _settle();
    c.dispose();
  });
  return c;
}

class _FakeBilling implements BillingClient {
  final completed = <String>[];
  final controller = StreamController<List<StorePayment>>.broadcast();
  @override
  Future<bool> isAvailable() async => true;
  @override
  Stream<List<StorePayment>> get payments => controller.stream;
  @override
  Future<void> buy(String productId, {required bool consumable}) async {}
  @override
  Future<void> complete(StorePayment payment) async => completed.add(payment.transactionId);
  @override
  Future<void> restore() async {}
}

const _payment = StorePayment(
  store: BillingStore.google,
  productId: 'tokens_100',
  transactionId: 'GPA.TEST-1',
  verificationData: 'not-a-real-token',
  amountCents: 99,
);

void main() {
  group('models (real replies)', () {
    test('shop items: categories, amounts and the payment rule', () {
      final t = _item(_tokens550);
      expect(t.category, ShopCategory.tokenPack);
      expect(t.totalTokens, 550);
      expect(t.payment, ShopPayment.realMoney);
      expect(t.walletCurrency, isNull);
      expect(t.priceUsdCents, 499);
      expect(formatUsdCents(t.priceUsdCents!), '\$4.99');

      expect(_item(_gold5000).totalGold, 5000);

      final s = _item(_shield5);
      expect(s.payment, ShopPayment.tokens);
      expect(s.walletCurrency, WalletCurrency.token);
      expect(s.chargedPrice, 250);
      expect((s.powerUpId, s.powerUpQuantity), (28, 5));

      final a = _item(_crown);
      expect(a.category, ShopCategory.avatar);
      expect(a.avatarId, 15);
      expect(a.singleUnit, isTrue);

      // Remove Ads: gold only, although it has a dollar price (Known issue 5).
      final r = _item(_removeAds);
      expect(r.payment, ShopPayment.gold);
      expect(r.chargedPrice, 10000);
      expect(r.singleUnit, isTrue);
      expect(ShopCategory.parse('nope'), ShopCategory.other);
    });

    test('discounts: struck price only in the same unit (Known issue 6)', () {
      // regular_price 299 (cents) beside price_gold 10000: never struck.
      expect(_item({..._removeAds, 'price_tier': 'offer'}).struckPrice, isNull);
      final offer = _item({..._shield5, 'price_tokens': 200, 'price_tier': 'offer', 'regular_price': 250});
      expect(offer.struckPrice, 250);
      expect(_item({..._shield5, 'price_tier': 'default', 'regular_price': 300}).struckPrice, isNull);
      final until = DateTime.now().toUtc().add(const Duration(hours: 2)).toIso8601String();
      final special = _item({..._tokens550, 'price_usd_cents': 399, 'price_tier': 'special', 'special_label': 'Weekend', 'special_until': until});
      expect(special.struckPrice, 499);
      expect(special.offer.specialRunning(DateTime.now()), isTrue);
      expect(special.offer.specialLabel, 'Weekend');
    });

    test('purchase replies: string and number money', () {
      final p = ShopPurchase.fromJson({'purchase_id': 3, 'item_id': 12, 'quantity': 1, 'total_price': 250, 'currency': 'token', 'new_balance': '400'});
      expect((p.totalPrice, p.newBalance, p.currency), (250, 400, WalletCurrency.token));

      final s = SandboxPurchase.fromJson({'purchase_id': 5, 'item_id': 5, 'quantity': 2, 'tokens_credited': 0, 'gold_credited': 10000,
          'price_usd_cents': 398, 'sandbox': true, 'balances': {'tokens': 300, 'gold': 10500}});
      expect((s.goldCredited, s.balanceTokens, s.balanceGold, s.sandbox), (10000, 300, 10500, true));

      final c = CosmeticPurchase.fromJson({'item_id': 29, 'item_type': 'power_up', 'currency': 'token', 'amount_spent': 100, 'new_balance': '300'});
      expect((c.amountSpent, c.newBalance), (100, 300));

      final v = IapVerifyResult.fromJson({'receipt_id': 1, 'transaction_id': 1, 'verified': true, 'tokens_credited': '550'});
      expect((v.verified, v.tokensCredited), (true, 550));
    });

    test('iap history, ad-free, ads flow, power-ups, avatars, inventory', () {
      final page = PageList.fromJson({
        'data': [
          {'id': 1, 'receipt_id': 1, 'user_id': 'u', 'product_id': 'tokens_550', 'shop_item_id': 2, 'subscription_plan_id': null,
           'amount_cents': 499, 'currency_code': 'USD', 'store_currency_code': 'INR', 'status': 'refunded',
           'refunded_at': null, 'purchased_at': '2026-11-24T10:00:00Z', 'created_at': '2026-11-24T10:00:00Z'},
        ],
        'total': 1, 'page': 1, 'per_page': 20, 'total_pages': 1,
      }, IapTransaction.fromJson);
      expect(page.data.single.amountCents, 499);
      expect(page.data.single.refunded, isTrue);
      expect(page.data.single.storeCurrencyCode, 'INR');

      expect(AdFreeStatus.fromJson({'is_active': true, 'granted_via': 'pass', 'expires_at': null}).isActive, isTrue);

      final flow = AdsFlow.fromJson({
        'decided_by': 'ad_free_pass', 'effect': 'rewarded', 'stages': [
          {'stage': 'lobby', 'formats': [], 'placements': [], 'suppressed': [{'id': 2, 'format': 'banner', 'suppressed_by': 'ad_free_pass'}]},
          {'stage': 'post', 'formats': ['rewarded'], 'placements': [{'id': 5, 'code': 'sample_post_rewarded', 'format': 'rewarded', 'reward': '20 tokens'}], 'suppressed': []},
        ],
      });
      expect(flow.formatsAt('lobby'), isEmpty);
      expect(flow.formatsAt('post'), ['rewarded']);
      expect(flow.stage('post')!.placements.single.reward, '20 tokens');
      expect(flow.adFree, isFalse);

      final pu = StorePowerUp.fromJson({'id': 29, 'game_id': 1, 'code': 'force_six', 'name': 'Force Six',
          'icon_url': 'powerups/force_six.svg', 'effect_config': {'effect': 'force_six'}, 'is_consumable': true,
          'max_per_match': 1, 'sort_order': 2, 'price_currency': 'token', 'price_amount': 100, 'price_tier': 'default', 'regular_price': 100});
      expect((pu.powerUp.code, pu.powerUp.maxPerMatch, pu.currency), ('force_six', 1, WalletCurrency.token));

      final av = StoreAvatar.fromJson({'id': 12, 'code': 'snl_shield_bearer', 'is_premium': true, 'required_level': 15,
          'is_purchasable': true, 'price_currency': 'gold', 'price_amount': 25, 'price_tier': 'default', 'regular_price': 25});
      expect((av.forSale, av.currency, av.avatar.requiredLevel), (true, WalletCurrency.gold, 15));
      final earned = StoreAvatar.fromJson({'id': 69, 'code': 'snl_charmed_token', 'is_premium': true, 'is_purchasable': false,
          'price_currency': null, 'price_amount': null});
      expect((earned.forSale, earned.earnedOnly), (false, true));

      final inv = Inventory.fromJson({
        'power_ups': [
          {'power_up_id': 28, 'code': 'shield', 'name': 'Shield', 'game_id': 1, 'quantity': 5},
          {'power_up_id': 29, 'code': 'force_six', 'name': 'Force Six', 'game_id': 1, 'quantity': 1},
        ],
        'avatars': [],
      });
      expect(inv.quantityOf(28), 5);
      expect(inv.quantityOf(30), 0);
      expect(inv.powerUpsForGame(1).map((p) => p.code), ['shield', 'force_six']);
      expect(inv.powerUpsForGame(2), isEmpty);
    });

    test('subscriptions: both shapes of /my, cancel reply, subscribe reply, royal plans', () {
      final free = MySubscription.fromJson({'plan_id': 1, 'tier': 'free', 'status': 'default'});
      expect((free.active, free.isDefault), (false, true));
      final plans = [
        for (final j in [
          {'id': 4, 'name': 'Gold Monthly', 'tier': 'gold', 'billing_interval': 'monthly', 'price_cents': '999', 'duration_days': 30, 'features': {}, 'is_active': true},
          {'id': 7, 'name': 'Royal Yearly', 'tier': 'royal', 'billing_interval': 'yearly', 'price_cents': '15999', 'duration_days': 365, 'features': {}, 'is_active': true},
        ])
          SubscriptionPlan.fromJson(j),
      ];
      expect(plans[1].price, '\$159.99');
      final paid = MySubscription.fromJson({'id': 'f9392fb1-16ff-4115-9718-a9bc89230bde', 'user_id': 'u', 'plan_id': 4, 'status': 'active',
          'started_at': '2026-11-24T09:56:26.360989Z', 'expires_at': '2026-12-24T09:56:26.360989Z', 'cancelled_at': null, 'auto_renew': true});
      expect(paid.active, isTrue);
      expect(paid.tierIn(plans), 'gold');
      expect(paid.endsAt, DateTime.parse('2026-12-24T09:56:26.360989Z'));
      expect(paid.id, 'f9392fb1-16ff-4115-9718-a9bc89230bde');
      expect(free.tierIn(plans), 'free');
      final cancelled = MySubscription.fromJson({'id': 'x', 'plan_id': 4, 'status': 'cancelled', 'cancelled_at': '2026-11-24T09:56:29.327332Z', 'auto_renew': false});
      expect(cancelled.active, isFalse);
      expect(cancelled.cancelledAt, isNotNull);
      final sub = SubscribeResult.fromJson({'subscription_id': 'f9', 'plan_id': 4, 'plan_name': 'Gold Monthly',
          'started_at': '2026-11-24T09:56:26.360989Z', 'expires_at': '2026-12-24T09:56:26.360989Z', 'auto_renew': true});
      expect((sub.planId, sub.planName, sub.autoRenew), (4, 'Gold Monthly', true));
    });
  });

  group('RemoteStoreApi', () {
    test('catalogue: category query, one item, 404', () async {
      final g = _Gateway({
        'GET /sensitive/shop/items': (r) => _ok([_tokens550, _shield5]),
        'GET /sensitive/shop/items/12': (r) => _ok(_shield5),
        'GET /sensitive/shop/items/999': (r) => _err(404, 'NOT_FOUND'),
      });
      final api = RemoteStoreApi(_client(g));
      expect((await api.shopItems(category: ShopCategory.tokenPack)).length, 2);
      expect(g.log.last.query, {'category': 'token_pack'});
      expect((await api.shopItem(12)).code, 'ludo_shield_x5');
      await expectLater(api.shopItem(999), throwsA(isA<AppException>().having((e) => e.code, 'code', 'NOT_FOUND')));
    });

    test('purchase sends the key header and the body; a replay is success', () async {
      var calls = 0;
      final g = _Gateway({
        'POST /sensitive/shop/purchase': (r) {
          calls++;
          // The replayed reply: same body, other field order, header set.
          return calls == 1
              ? _ok({'purchase_id': 3, 'item_id': 12, 'quantity': 1, 'total_price': 250, 'currency': 'token', 'new_balance': '400'})
              : _ok({'currency': 'token', 'item_id': 12, 'new_balance': '400', 'purchase_id': 3, 'quantity': 1, 'total_price': 250}, replayed: true);
        },
      });
      final api = RemoteStoreApi(_client(g));
      final a = await api.purchase(itemId: 12, quantity: 1, currency: WalletCurrency.token, idempotencyKey: 'k-1');
      final b = await api.purchase(itemId: 12, quantity: 1, currency: WalletCurrency.token, idempotencyKey: 'k-1');
      expect(g.log.first.headers['Idempotency-Key'], 'k-1');
      expect(g.log.first.body, {'item_id': 12, 'quantity': 1, 'currency': 'token'});
      expect((a.purchaseId, b.purchaseId, b.newBalance), (3, 3, 400));
    });

    test('cosmetics answer 201; equip; power-ups by game', () async {
      final g = _Gateway({
        'POST /cosmetics/power-ups/29/purchase': (r) =>
            _ok({'item_id': 29, 'item_type': 'power_up', 'currency': 'token', 'amount_spent': 100, 'new_balance': '300'}, status: 201),
        'POST /cosmetics/avatars/2/equip': (r) => _ok({'avatar_id': 2, 'equipped': true}),
        'GET /cosmetics/power-ups': (r) => _ok([]),
      });
      final api = RemoteStoreApi(_client(g));
      expect((await api.purchasePowerUp(29, idempotencyKey: 'k')).newBalance, 300);
      expect(g.log.last.headers['Idempotency-Key'], 'k');
      expect((await api.equipAvatar(2)).equipped, isTrue);
      await api.powerUps(gameId: 1);
      expect(g.log.last.query, {'game_id': '1'});
    });

    test('verify: 503 throws UNAVAILABLE, 409 DUPLICATE_TRANSACTION is success', () async {
      var dup = false;
      final g = _Gateway({
        'POST /sensitive/iap/verify': (r) => dup ? _err(409, 'DUPLICATE_TRANSACTION') : _err(503, 'UNAVAILABLE'),
      });
      final api = RemoteStoreApi(_client(g));
      await expectLater(api.verifyIap(_payment.toVerifyRequest()),
          throwsA(isA<AppException>().having((e) => e.code, 'code', ApiErrorCode.unavailable)));
      expect(g.log.last.body, containsPair('transaction_id', 'GPA.TEST-1'));
      expect(g.log.last.headers.containsKey('Idempotency-Key'), isFalse);
      dup = true;
      expect((await api.verifyIap(_payment.toVerifyRequest())).duplicate, isTrue);
      expect(_payment.toString(), isNot(contains('not-a-real-token')));
    });
  });

  group('error text', () {
    AppException e(int s, String code, {String msg = ''}) => AppException(msg, statusCode: s, code: code);
    test('each store code maps to its own message', () {
      expect(storeErrorText(e(409, 'INSUFFICIENT_FUNDS'), StoreOp.purchase, currency: WalletCurrency.token), 'Not enough tokens.');
      expect(storeErrorText(e(409, 'INSUFFICIENT_FUNDS'), StoreOp.adFree, currency: WalletCurrency.gold), 'Not enough gold.');
      expect(storeErrorText(e(403, 'LEVEL_REQUIRED'), StoreOp.avatar, requiredLevel: 5), 'Reach level 5 to unlock.');
      expect(storeErrorText(e(409, 'CONFLICT'), StoreOp.avatar), 'You already own this avatar.');
      expect(storeErrorText(e(409, 'CONFLICT'), StoreOp.adFree), 'Ads are already removed.');
      expect(storeErrorText(e(409, 'CONFLICT'), StoreOp.subscribe), contains('Cancel it first'));
      expect(storeErrorText(e(409, 'CONFLICT'), StoreOp.powerUp), 'Something went wrong. Try again.');
      expect(storeErrorText(e(403, 'GEO_BLOCKED'), StoreOp.purchase), "The store isn't available in your region.");
      expect(storeErrorText(e(404, 'NOT_FOUND'), StoreOp.purchase), 'This item is no longer available.');
      expect(storeErrorText(e(404, 'NOT_FOUND'), StoreOp.cancel), "You don't have an active plan.");
      expect(storeErrorText(e(503, 'UNAVAILABLE'), StoreOp.subscribe), 'Subscriptions are coming soon.');
      expect(storeErrorText(e(503, 'UNAVAILABLE'), StoreOp.pack), 'Purchases are not available yet.');
      expect(storeErrorText(e(503, 'KILL_SWITCH_ENGAGED', msg: 'Store closed for maintenance'), StoreOp.purchase),
          'Store closed for maintenance');
      expect(storeErrorText(e(400, 'BAD_REQUEST'), StoreOp.avatar), "This item isn't for sale.");
      expect(storeErrorText(e(400, 'BAD_REQUEST'), StoreOp.equip), "You don't own this avatar yet.");
      expect(storeErrorText(const AppException('x', kind: AppErrorKind.offline), StoreOp.purchase), contains("Can't reach"));
    });
  });

  group('StoreController + PurchaseFlow', () {
    test('a purchase updates the chip from new_balance, re-reads wallet and inventory', () async {
      var balanceReads = 0, inventoryReads = 0;
      final g = _Gateway({
        'GET /wallet/balance': (r) {
          balanceReads++;
          return _ok(_balance);
        },
        'GET /users/me/inventory': (r) {
          inventoryReads++;
          return _ok({'power_ups': [{'power_up_id': 28, 'code': 'shield', 'name': 'Shield', 'game_id': 1, 'quantity': 5}], 'avatars': []});
        },
        'POST /sensitive/shop/purchase': (r) =>
            _ok({'purchase_id': 3, 'item_id': 12, 'quantity': 1, 'total_price': 250, 'currency': 'token', 'new_balance': '400'}),
      });
      final c = _container(g, keys: ['key-A']);
      await c.read(walletProvider.future);
      await c.read(inventoryProvider.future);
      final r = await c.read(storeControllerProvider).buyItem(_item(_shield5));
      expect(r.newBalance, 400);
      expect(c.read(walletProvider).value!.of(Currency.gems), 400);
      final buy = g.log.firstWhere((x) => x.path == '/sensitive/shop/purchase');
      expect(buy.headers['Idempotency-Key'], 'key-A');
      await Future<void>.delayed(Duration.zero);
      await c.read(inventoryProvider.future);
      expect(balanceReads, greaterThanOrEqualTo(2));
      expect(inventoryReads, 2);
    });

    test('a timeout retries once with the SAME key; a new purchase gets a NEW key', () async {
      var n = 0;
      final g = _Gateway({
        'GET /wallet/balance': (r) => _ok(_balance),
        'GET /users/me/inventory': (r) => _ok({'power_ups': [], 'avatars': []}),
        'POST /cosmetics/power-ups/29/purchase': (r) {
          n++;
          if (n == 1) return (-1, null, const <String, String>{});
          return _ok({'item_id': 29, 'item_type': 'power_up', 'currency': 'token', 'amount_spent': 100, 'new_balance': '300'},
              status: 201, replayed: n == 2);
        },
      });
      final c = _container(g, keys: ['key-1', 'key-2']);
      final pu = StorePowerUp.fromJson({'id': 29, 'game_id': 1, 'code': 'force_six', 'name': 'Force Six', 'price_currency': 'token', 'price_amount': 100});
      final ctl = c.read(storeControllerProvider);
      expect((await ctl.buyPowerUp(pu)).newBalance, 300);
      await ctl.buyPowerUp(pu);
      final keys = [for (final x in g.log) if (x.path == '/cosmetics/power-ups/29/purchase') x.headers['Idempotency-Key']];
      expect(keys, ['key-1', 'key-1', 'key-2']);
    });

    test('no retry on a server answer; INSUFFICIENT_FUNDS gets the wallet text', () async {
      final g = _Gateway({
        'POST /sensitive/shop/purchase': (r) => _err(409, 'INSUFFICIENT_FUNDS'),
      });
      final c = _container(g);
      await expectLater(c.read(storeControllerProvider).buyItem(_item(_removeAds)),
          throwsA(isA<AppException>().having((e) => e.message, 'message', 'Not enough gold.')));
      expect(g.log.where((x) => x.method == 'POST').length, 1);
      expect(g.log.single.body, {'item_id': 7, 'quantity': 1, 'currency': 'gold'});
    });

    test('LEVEL_REQUIRED uses the catalogue level', () async {
      final g = _Gateway({'POST /cosmetics/avatars/15/purchase': (r) => _err(403, 'LEVEL_REQUIRED')});
      final c = _container(g);
      final crown = StoreAvatar.fromJson({'id': 15, 'code': 'ludo_golden_crown', 'name': 'Golden Crown', 'is_premium': true,
          'required_level': 5, 'is_purchasable': true, 'price_currency': 'token', 'price_amount': 500});
      await expectLater(c.read(storeControllerProvider).buyAvatar(crown),
          throwsA(isA<AppException>().having((e) => e.message, 'message', 'Reach level 5 to unlock.')));
    });

    test('KILL_SWITCH_ENGAGED pauses the store with the operator text until reload', () async {
      final g = _Gateway({
        'POST /sensitive/shop/purchase': (r) => (503, {'error': 'KILL_SWITCH_ENGAGED', 'message': 'Shop paused tonight'}, const <String, String>{}),
      });
      final c = _container(g);
      final ctl = c.read(storeControllerProvider);
      await expectLater(ctl.buyItem(_item(_shield5)), throwsA(isA<AppException>()));
      expect(c.read(storePausedProvider), 'Shop paused tonight');
      // Buy is disabled: nothing is sent while paused.
      await expectLater(ctl.buyItem(_item(_shield5)), throwsA(isA<AppException>().having((e) => e.code, 'code', 'KILL_SWITCH_ENGAGED')));
      expect(g.log.length, 1);
      ctl.reload();
      expect(c.read(storePausedProvider), isNull);
    });

    test('sandbox pack (debug build): both balances applied from numbers', () async {
      final g = _Gateway({
        'GET /wallet/balance': (r) => _ok(_balance),
        'POST /sensitive/shop/purchase/sandbox': (r) => _ok({'purchase_id': 2, 'item_id': 2, 'quantity': 1, 'tokens_credited': 550,
            'gold_credited': 0, 'price_usd_cents': 499, 'sandbox': true, 'balances': {'tokens': 650, 'gold': 1000}}),
      });
      final c = _container(g, keys: ['pack-key']);
      await c.read(walletProvider.future);
      expect(c.read(packPurchaseModeProvider), PackPurchaseMode.sandbox); // tests run in debug
      final r = await c.read(storeControllerProvider).buyPack(_item(_tokens550));
      expect(r!.tokensCredited, 550);
      final w = c.read(walletProvider).value!;
      expect((w.tokens, w.goldCoins), (650, 1000));
      final sent = g.log.firstWhere((x) => x.path == '/sensitive/shop/purchase/sandbox');
      expect(sent.headers['Idempotency-Key'], 'pack-key');
      expect(sent.body, {'item_id': 2, 'quantity': 1});
    });

    test('release mode: packs are "coming soon" and nothing is sent', () async {
      final g = _Gateway({});
      final api = _client(g);
      final c = ProviderContainer(overrides: [
        storeApiProvider.overrideWithValue(RemoteStoreApi(api)),
        packPurchaseModeProvider.overrideWithValue(PackPurchaseMode.comingSoon),
      ]);
      addTearDown(c.dispose);
      await expectLater(c.read(storeControllerProvider).buyPack(_item(_tokens550)),
          throwsA(isA<AppException>().having((e) => e.message, 'message', 'Purchases are not available yet.')));
      expect(g.log, isEmpty);
    });

    test('product id map', () {
      expect(StoreProductIds.productId('tokens_550', BillingStore.apple), 'com.allgames.tokens.550');
      expect(StoreProductIds.productId('gold_5000', BillingStore.google), 'gold_5000');
      expect(StoreProductIds.shopCode('com.allgames.adfree', BillingStore.apple), 'ad_free_forever');
      expect(StoreProductIds.productId('ludo_shield_x5', BillingStore.google), isNull);
    });
  });

  group('IapBridge (switched off by default)', () {
    test('off: buy throws UNAVAILABLE, start does not listen', () async {
      final billing = _FakeBilling();
      final bridge = IapBridge(api: const DemoStoreApi(), client: billing);
      expect(IapBridge.serverVerifies, isFalse);
      expect(bridge.active, isFalse);
      await expectLater(bridge.buy(_item(_tokens550), BillingStore.google),
          throwsA(isA<AppException>().having((e) => e.code, 'code', ApiErrorCode.unavailable)));
      await bridge.start();
      expect(billing.controller.hasListener, isFalse);
    });

    test('verify then complete; 503 leaves it pending; duplicate completes', () async {
      var answer = _err(503, 'UNAVAILABLE');
      final g = _Gateway({'POST /sensitive/iap/verify': (r) => answer});
      final billing = _FakeBilling();
      var credited = 0;
      final bridge = IapBridge(api: RemoteStoreApi(_client(g)), client: billing, enabled: true, onCredited: (_) => credited++);

      expect(await bridge.handle(_payment), IapOutcome.pending);
      expect(billing.completed, isEmpty, reason: 'never finish a purchase the server did not credit');

      answer = _ok({'receipt_id': 1, 'transaction_id': 1, 'verified': true, 'tokens_credited': '100'});
      expect(await bridge.handle(_payment), IapOutcome.credited);
      expect(billing.completed, ['GPA.TEST-1']);

      answer = _err(409, 'DUPLICATE_TRANSACTION');
      expect(await bridge.handle(_payment), IapOutcome.alreadyCredited);
      expect(billing.completed.length, 2);
      expect(credited, 2);
    });

    test('pending purchases from the stream are sent on start', () async {
      final g = _Gateway({'POST /sensitive/iap/verify': (r) => _ok({'receipt_id': 1, 'transaction_id': 1, 'verified': true, 'tokens_credited': '100'})});
      final billing = _FakeBilling();
      final bridge = IapBridge(api: RemoteStoreApi(_client(g)), client: billing, enabled: true);
      await bridge.start();
      billing.controller.add([_payment]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(billing.completed, ['GPA.TEST-1']);
      await bridge.dispose();
    });
  });
}
