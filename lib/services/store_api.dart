import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/configs.dart';
import '../data/models/account.dart';
import '../data/models/game_catalogue.dart' show PowerUp;
import '../data/models/store.dart';
import '../data/models/wallet.dart';
import 'api_client.dart';
import 'app_exception.dart';
import 'session.dart';

/// The store routes (docs/services/11-store.md): shop catalogue, wallet
/// purchases, sandbox coin packs, store-receipt verification, real-money
/// history, ad-free, the ad flow, avatars and power-ups. Subscriptions are in
/// `lib/data/sources/subscription_source.dart`; the inventory is
/// `inventoryProvider` (account_store.dart).
///
/// Every buying method takes an [idempotencyKey] (sent as `Idempotency-Key`);
/// use [PurchaseFlow] (store_service.dart) rather than calling them directly.
/// Never logs request or reply bodies, receipts or purchase tokens.
abstract class StoreApi {
  /// `GET /sensitive/shop/items[?category=]`, in display order.
  Future<List<ShopItem>> shopItems({ShopCategory? category});

  /// `GET /sensitive/shop/items/{id}`.
  Future<ShopItem> shopItem(int id);

  /// `POST /sensitive/shop/purchase` (wallet: tokens or gold).
  Future<ShopPurchase> purchase({
    required int itemId,
    required int quantity,
    required WalletCurrency currency,
    required String idempotencyKey,
  });

  /// `POST /sensitive/shop/purchase/sandbox` (development servers only).
  Future<SandboxPurchase> sandboxPurchase({required int itemId, required int quantity, required String idempotencyKey});

  /// `POST /sensitive/iap/verify`. `409 DUPLICATE_TRANSACTION` is returned
  /// as [IapVerifyResult.alreadyCredited], not thrown.
  Future<IapVerifyResult> verifyIap(IapVerifyRequest request);

  /// `GET /sensitive/iap/history` (page list, [perPage] 1-100).
  Future<PageList<IapTransaction>> iapHistory({int page = 1, int perPage = 20});

  /// `GET /sensitive/ad-free/status`.
  Future<AdFreeStatus> adFreeStatus();

  /// `GET /me/ads/flow`.
  Future<AdsFlow> adsFlow();

  /// `GET /cosmetics/avatars`.
  Future<List<StoreAvatar>> avatars();

  /// `POST /cosmetics/avatars/{id}/purchase` (201).
  Future<CosmeticPurchase> purchaseAvatar(int id, {required String idempotencyKey});

  /// `POST /cosmetics/avatars/{id}/equip`.
  Future<AvatarEquip> equipAvatar(int id);

  /// `GET /cosmetics/power-ups[?game_id=]`.
  Future<List<StorePowerUp>> powerUps({int? gameId});

  /// `POST /cosmetics/power-ups/{id}/purchase` (201): adds one.
  Future<CosmeticPurchase> purchasePowerUp(int id, {required String idempotencyKey});

  // `POST /cosmetics/power-ups/{id}/use` is deliberately missing: it spends a
  // power-up outside any game (§7d). Games spend them over their socket.
}

/// The `/iap/verify` body (§3a). Never log it: [receiptData] is the proof.
class IapVerifyRequest {
  const IapVerifyRequest({
    required this.store,
    required this.receiptData,
    required this.productId,
    required this.transactionId,
    required this.amountCents,
    this.currencyCode = 'USD',
  });

  /// `google` or `apple`.
  final String store;
  final String receiptData;
  final String productId;
  final String transactionId;
  final int amountCents;
  final String currencyCode;

  Map<String, dynamic> toJson() => {
        'store': store,
        'receipt_data': receiptData,
        'product_id': productId,
        'transaction_id': transactionId,
        'amount_cents': amountCents,
        'currency_code': currencyCode,
      };

  @override
  String toString() => 'IapVerifyRequest($store, $productId)'; // no receipt
}

Map<String, dynamic> _obj(Object? body) =>
    body is Map ? body.cast<String, dynamic>() : throw const AppException('Something went wrong. Try again.');

List<Map<String, dynamic>> _list(Object? body) {
  final list = body is List ? body : (body is Map && body['data'] is List ? body['data'] as List : const []);
  return [for (final e in list) if (e is Map) e.cast<String, dynamic>()];
}

class RemoteStoreApi implements StoreApi {
  RemoteStoreApi(this._api);
  final ApiClient _api;

  static Map<String, String> _key(String k) => {'Idempotency-Key': k};

  @override
  Future<List<ShopItem>> shopItems({ShopCategory? category}) async => [
        for (final j in _list(await _api.get(ApiEndpoints.shopItems,
            query: category == null || category == ShopCategory.other ? null : {'category': category.wire})))
          ShopItem.fromJson(j),
      ];

  @override
  Future<ShopItem> shopItem(int id) async => ShopItem.fromJson(_obj(await _api.get(ApiEndpoints.shopItem(id))));

  @override
  Future<ShopPurchase> purchase({
    required int itemId,
    required int quantity,
    required WalletCurrency currency,
    required String idempotencyKey,
  }) async =>
      ShopPurchase.fromJson(
        _obj(await _api.post(ApiEndpoints.shopPurchase,
            body: {'item_id': itemId, 'quantity': quantity, 'currency': currency.wire}, headers: _key(idempotencyKey))),
        fallback: currency,
      );

  @override
  Future<SandboxPurchase> sandboxPurchase({required int itemId, required int quantity, required String idempotencyKey}) async =>
      SandboxPurchase.fromJson(_obj(await _api.post(ApiEndpoints.shopPurchaseSandbox,
          body: {'item_id': itemId, 'quantity': quantity}, headers: _key(idempotencyKey))));

  @override
  Future<IapVerifyResult> verifyIap(IapVerifyRequest request) async {
    try {
      return IapVerifyResult.fromJson(_obj(await _api.post(ApiEndpoints.iapVerify, body: request.toJson())));
    } on AppException catch (e) {
      if (e.code == ApiErrorCode.duplicateTransaction) return IapVerifyResult.alreadyCredited;
      rethrow;
    }
  }

  @override
  Future<PageList<IapTransaction>> iapHistory({int page = 1, int perPage = 20}) async => PageList.fromJson(
        _obj(await _api.get(ApiEndpoints.iapHistory, query: {'page': page, 'per_page': perPage})),
        IapTransaction.fromJson,
      );

  @override
  Future<AdFreeStatus> adFreeStatus() async => AdFreeStatus.fromJson(_obj(await _api.get(ApiEndpoints.adFreeStatus)));

  @override
  Future<AdsFlow> adsFlow() async => AdsFlow.fromJson(_obj(await _api.get(ApiEndpoints.adsFlow)));

  @override
  Future<List<StoreAvatar>> avatars() async =>
      [for (final j in _list(await _api.get(ApiEndpoints.cosmeticsAvatars))) StoreAvatar.fromJson(j)];

  @override
  Future<CosmeticPurchase> purchaseAvatar(int id, {required String idempotencyKey}) async => CosmeticPurchase.fromJson(
      _obj(await _api.post(ApiEndpoints.cosmeticsAvatarPurchase(id), headers: _key(idempotencyKey))));

  @override
  Future<AvatarEquip> equipAvatar(int id) async =>
      AvatarEquip.fromJson(_obj(await _api.post(ApiEndpoints.cosmeticsAvatarEquip(id))));

  @override
  Future<List<StorePowerUp>> powerUps({int? gameId}) async => [
        for (final j in _list(
            await _api.get(ApiEndpoints.cosmeticsPowerUps, query: gameId == null ? null : {'game_id': gameId})))
          StorePowerUp.fromJson(j),
      ];

  @override
  Future<CosmeticPurchase> purchasePowerUp(int id, {required String idempotencyKey}) async => CosmeticPurchase.fromJson(
      _obj(await _api.post(ApiEndpoints.cosmeticsPowerUpPurchase(id), headers: _key(idempotencyKey))));
}

/// Offline demo store (no server): a snapshot of the development catalogue.
/// Purchases succeed against the demo wallet; nothing is kept.
class DemoStoreApi implements StoreApi {
  const DemoStoreApi();

  static const _demoBalance = Wallet.demo;

  static ShopItem _pack(int id, String code, String name, ShopCategory c, int cents, {int tokens = 0, int gold = 0, int bonus = 0}) =>
      ShopItem(
        id: id,
        code: code,
        name: name,
        category: c,
        tokenAmount: tokens,
        goldAmount: gold,
        bonusTokenAmount: c == ShopCategory.tokenPack ? bonus : 0,
        bonusGoldAmount: c == ShopCategory.goldPack ? bonus : 0,
        priceUnit: 'usd',
        priceUsdCents: cents,
        offer: PriceOffer(tier: 'default', regularPrice: cents),
      );

  static final _items = <ShopItem>[
    _pack(1, 'tokens_100', 'Handful of Tokens', ShopCategory.tokenPack, 99, tokens: 100),
    _pack(2, 'tokens_550', 'Pouch of Tokens', ShopCategory.tokenPack, 499, tokens: 500, bonus: 50),
    _pack(3, 'tokens_1200', 'Bag of Tokens', ShopCategory.tokenPack, 999, tokens: 1000, bonus: 200),
    _pack(4, 'tokens_6500', 'Chest of Tokens', ShopCategory.tokenPack, 4999, tokens: 5000, bonus: 1500),
    _pack(5, 'gold_5000', 'Gold Sack', ShopCategory.goldPack, 199, gold: 5000),
    _pack(6, 'gold_30000', 'Gold Vault', ShopCategory.goldPack, 999, gold: 30000),
    const ShopItem(
      id: 12, code: 'ludo_shield_x5', name: 'Ludo Shield x5', category: ShopCategory.powerUpPack,
      description: 'Five shields against the triple-six penalty.', powerUpId: 28, powerUpQuantity: 5,
      priceUnit: 'token', priceTokens: 200, offer: PriceOffer(tier: 'offer', regularPrice: 250),
    ),
    const ShopItem(
      id: 7, code: 'ad_free_forever', name: 'Remove Ads', category: ShopCategory.adFree,
      description: 'Play without ads, forever.', priceUnit: 'gold', priceUsdCents: 299, priceGold: 10000,
      offer: PriceOffer(tier: 'default', regularPrice: 299),
    ),
  ];

  static PowerUp _pu(int id, String code, String name, int price, int max, String desc) => PowerUp(
      id: id, gameId: 1, code: code, name: name, description: desc, priceCurrency: 'token', priceAmount: price,
      isConsumable: true, maxPerMatch: max, sortOrder: id);

  static final _powerUps = <StorePowerUp>[
    StorePowerUp(_pu(28, 'shield', 'Shield', 50, 2, 'Block the three-consecutive-sixes penalty this turn.')),
    StorePowerUp(_pu(29, 'force_six', 'Force Six', 100, 1, 'Guarantee a 6 on your next dice roll.')),
    StorePowerUp(_pu(30, 'extra_turn', 'Extra Turn', 100, 1, 'Get another turn after this one.')),
    StorePowerUp(_pu(31, 'home_rush', 'Home Rush', 75, 2, 'Move a token closer to home.')),
  ];

  static final _avatars = <StoreAvatar>[
    for (final (i, c) in const ['blue', 'green', 'red', 'purple'].indexed)
      StoreAvatar(AvatarItem(id: i + 1, code: 'default_$c', name: '${c[0].toUpperCase()}${c.substring(1)} Buddy', sortOrder: i + 1)),
    const StoreAvatar(
      AvatarItem(id: 15, code: 'ludo_golden_crown', name: 'Golden Crown', isPremium: true, isPurchasable: true,
          requiredLevel: 5, priceCurrency: 'token', priceAmount: 500, sortOrder: 201),
      offer: PriceOffer(tier: 'default', regularPrice: 500),
    ),
    const StoreAvatar(AvatarItem(id: 69, code: 'snl_charmed_token', name: 'Charmed Token', isPremium: true, sortOrder: 105)),
  ];

  @override
  Future<List<ShopItem>> shopItems({ShopCategory? category}) async =>
      [for (final i in _items) if (category == null || i.category == category) i];

  @override
  Future<ShopItem> shopItem(int id) async => _items.firstWhere((i) => i.id == id,
      orElse: () => throw const AppException('Not found.', kind: AppErrorKind.notFound, statusCode: 404, code: ApiErrorCode.notFound));

  @override
  Future<ShopPurchase> purchase({
    required int itemId,
    required int quantity,
    required WalletCurrency currency,
    required String idempotencyKey,
  }) async {
    final item = await shopItem(itemId);
    final total = (item.chargedPrice ?? 0) * quantity;
    final have = _demoBalance.of(currency.currency);
    if (total > have) {
      throw const AppException('', statusCode: 409, code: ApiErrorCode.insufficientFunds);
    }
    return ShopPurchase(
        purchaseId: 1, itemId: itemId, quantity: quantity, totalPrice: total, currency: currency, newBalance: have - total);
  }

  @override
  Future<SandboxPurchase> sandboxPurchase({required int itemId, required int quantity, required String idempotencyKey}) async {
    final item = await shopItem(itemId);
    return SandboxPurchase(
      purchaseId: 1,
      itemId: itemId,
      quantity: quantity,
      tokensCredited: item.totalTokens * quantity,
      goldCredited: item.totalGold * quantity,
      priceUsdCents: (item.priceUsdCents ?? 0) * quantity,
      sandbox: true,
      balanceTokens: _demoBalance.tokens + item.totalTokens * quantity,
      balanceGold: _demoBalance.goldCoins + item.totalGold * quantity,
    );
  }

  @override
  Future<IapVerifyResult> verifyIap(IapVerifyRequest request) async => throw const AppException('',
      kind: AppErrorKind.server, statusCode: 503, code: ApiErrorCode.unavailable);

  @override
  Future<PageList<IapTransaction>> iapHistory({int page = 1, int perPage = 20}) async =>
      PageList(page: page, perPage: perPage);

  @override
  Future<AdFreeStatus> adFreeStatus() async => AdFreeStatus.off;

  @override
  Future<AdsFlow> adsFlow() async => AdsFlow.none;

  @override
  Future<List<StoreAvatar>> avatars() async => _avatars;

  @override
  Future<CosmeticPurchase> purchaseAvatar(int id, {required String idempotencyKey}) async =>
      throw const AppException('', kind: AppErrorKind.unauthorized, statusCode: 403, code: ApiErrorCode.levelRequired);

  @override
  Future<AvatarEquip> equipAvatar(int id) async => AvatarEquip(avatarId: id, equipped: true);

  @override
  Future<List<StorePowerUp>> powerUps({int? gameId}) async =>
      [for (final p in _powerUps) if (gameId == null || p.powerUp.gameId == gameId) p];

  @override
  Future<CosmeticPurchase> purchasePowerUp(int id, {required String idempotencyKey}) async {
    final p = _powerUps.firstWhere((x) => x.id == id).powerUp;
    final price = p.priceAmount ?? 0;
    return CosmeticPurchase(
        itemId: id, itemType: 'power_up', currency: WalletCurrency.token, amountSpent: price, newBalance: _demoBalance.tokens - price);
  }
}

/// The live store when signed in against the real API; the demo otherwise.
final storeApiProvider = Provider<StoreApi>((ref) {
  final live = ref.watch(useRemoteAuthProvider) && ref.watch(sessionProvider.select((u) => u != null));
  return live ? RemoteStoreApi(ref.watch(apiClientProvider)) : const DemoStoreApi();
});

/// What a store call was doing, for the player text of its errors.
enum StoreOp { catalogue, purchase, pack, avatar, adFree, powerUp, equip, verify, subscribe, cancel }

/// The store's player-facing text for [e] (11-store.md error tables). Decide
/// on `error`, never on `message` (Known issue 11). [requiredLevel] comes
/// from the catalogue (`required_level`) for `LEVEL_REQUIRED`.
String storeErrorText(AppException e, StoreOp op, {WalletCurrency? currency, int? requiredLevel}) {
  if (e.isOffline || e.kind == AppErrorKind.timeout) return "Can't reach the server. Check your connection.";
  // A bare 503 (no code) on a buying route reads as "not available yet".
  final code = e.code ?? (e.statusCode == 503 ? ApiErrorCode.unavailable : null);
  return switch (code) {
    ApiErrorCode.insufficientFunds => 'Not enough ${(currency ?? WalletCurrency.token).noun}.',
    ApiErrorCode.levelRequired =>
      requiredLevel == null ? 'Reach a higher level to unlock this.' : 'Reach level $requiredLevel to unlock.',
    ApiErrorCode.geoBlocked => "The store isn't available in your region.",
    ApiErrorCode.notFound => switch (op) {
        StoreOp.subscribe => 'That plan is no longer available.',
        StoreOp.cancel => "You don't have an active plan.",
        _ => 'This item is no longer available.',
      },
    // Avatars and Remove Ads: already owned. Elsewhere only a reused key
    // answers 409 CONFLICT (an app bug).
    ApiErrorCode.conflict => switch (op) {
        StoreOp.avatar => 'You already own this avatar.',
        StoreOp.adFree => 'Ads are already removed.',
        StoreOp.subscribe => 'You already have a plan. Cancel it first to switch.',
        _ => 'Something went wrong. Try again.',
      },
    ApiErrorCode.unavailable => op == StoreOp.subscribe
        ? 'Subscriptions are coming soon.'
        : 'Purchases are not available yet.',
    ApiErrorCode.rateLimited => 'Too many requests. Try again in a minute.',
    ApiErrorCode.validation || ApiErrorCode.badRequest => switch (op) {
        StoreOp.avatar || StoreOp.powerUp when code == ApiErrorCode.badRequest => "This item isn't for sale.",
        StoreOp.equip => "You don't own this avatar yet.",
        _ => 'Something went wrong. Try again.',
      },
    // KILL_SWITCH_ENGAGED keeps the operator's text; session codes keep
    // "Your session has ended…" from the client.
    _ => e.message.isEmpty ? 'Something went wrong. Try again.' : e.message,
  };
}

/// [e] with the store's player-facing text; status / code / field kept.
AppException storeError(AppException e, StoreOp op, {WalletCurrency? currency, int? requiredLevel}) {
  final text = storeErrorText(e, op, currency: currency, requiredLevel: requiredLevel);
  if (text == e.message) return e;
  return AppException(text,
      kind: e.kind, statusCode: e.statusCode, code: e.code, field: e.field, until: e.until, detail: e.detail);
}
