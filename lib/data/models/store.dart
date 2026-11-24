import 'package:flutter/foundation.dart';

import '../../utils/amount.dart';
import 'account.dart';
import 'game_catalogue.dart' show PowerUp;
import 'wallet.dart';

/// Store models (docs/services/11-store.md). Money fields accept a number and
/// a numeric string ([parseAmount]); unknown fields are ignored.

Map<String, dynamic> _m(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
String? _s(Object? v) => v is String && v.isNotEmpty ? v : null;
int? _iOrNull(Object? v) => v == null ? null : (v is num ? v.toInt() : (v is String ? int.tryParse(v.trim()) : null));
DateTime? _d(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// `category` of a shop item: picks the tab.
enum ShopCategory {
  tokenPack('token_pack'),
  goldPack('gold_pack'),
  powerUpPack('power_up_pack'),
  avatar('avatar'),
  adFree('ad_free'),
  other('');

  const ShopCategory(this.wire);
  final String wire;

  static ShopCategory parse(Object? v) =>
      ShopCategory.values.firstWhere((c) => c.wire == v && c != other, orElse: () => other);
}

/// The discount fields shared by shop items, avatars and power-ups (§1c):
/// `price_tier`, `regular_price`, `special_label`, `special_until`.
@immutable
class PriceOffer {
  const PriceOffer({this.tier, this.regularPrice, this.specialLabel, this.specialUntil});

  /// `default`, `offer` (standing discount) or `special` (timed sale); null
  /// when the item has no price.
  final String? tier;
  final int? regularPrice;
  final String? specialLabel;
  final DateTime? specialUntil;

  bool get isOffer => tier == 'offer';
  bool get isSpecial => tier == 'special';

  /// The regular price to strike through next to [charged], or null. Only for
  /// a discount tier with a higher regular price.
  int? struckPrice(int? charged) {
    final r = regularPrice;
    if (charged == null || r == null || !(isOffer || isSpecial)) return null;
    return r > charged ? r : null;
  }

  /// A running special that ends in the future (countdown + reload when over).
  bool specialRunning(DateTime now) => isSpecial && specialUntil != null && specialUntil!.isAfter(now);

  factory PriceOffer.fromJson(Map<String, dynamic> j) => PriceOffer(
        tier: _s(j['price_tier']),
        regularPrice: j['regular_price'] == null ? null : parseAmount(j['regular_price']),
        specialLabel: _s(j['special_label']),
        specialUntil: _d(j['special_until']),
      );

  static const none = PriceOffer();
}

/// How an item is bought (§1c "Which price to show and charge").
enum ShopPayment {
  /// `price_tokens`: the wallet, in tokens (§2).
  tokens,

  /// `price_gold`: the wallet, in gold (§2). Remove Ads is always this.
  gold,

  /// Only `price_usd_cents`: a real-money pack (§3).
  realMoney,

  /// Nothing set: not for sale.
  none,
}

/// One row of `GET /sensitive/shop/items` (§1).
@immutable
class ShopItem {
  const ShopItem({
    required this.id,
    required this.code,
    required this.name,
    required this.category,
    this.description,
    this.tokenAmount = 0,
    this.goldAmount = 0,
    this.bonusTokenAmount = 0,
    this.bonusGoldAmount = 0,
    this.powerUpId,
    this.powerUpQuantity,
    this.avatarId,
    this.isActive = true,
    this.priceUnit,
    this.priceUsdCents,
    this.priceTokens,
    this.priceGold,
    this.offer = PriceOffer.none,
  });

  final int id;
  final String code;
  final String name;
  final String? description;
  final ShopCategory category;
  final int tokenAmount;
  final int goldAmount;
  final int bonusTokenAmount;
  final int bonusGoldAmount;
  final int? powerUpId;
  final int? powerUpQuantity;
  final int? avatarId;
  final bool isActive;

  /// `usd`, `token`, `gold`, `both`, `free` or null.
  final String? priceUnit;
  final int? priceUsdCents;
  final int? priceTokens;
  final int? priceGold;
  final PriceOffer offer;

  bool get isPack => category == ShopCategory.tokenPack || category == ShopCategory.goldPack;

  /// Tokens / gold the pack gives per unit, bonus included.
  int get totalTokens => tokenAmount + bonusTokenAmount;
  int get totalGold => goldAmount + bonusGoldAmount;

  /// The server's rule: tokens, then gold, then real money; Remove Ads is
  /// sold for gold only (Known issue 5).
  ShopPayment get payment {
    if (category == ShopCategory.adFree) return priceGold != null ? ShopPayment.gold : ShopPayment.none;
    if (priceTokens != null) return ShopPayment.tokens;
    if (priceGold != null) return ShopPayment.gold;
    if (priceUsdCents != null) return ShopPayment.realMoney;
    return ShopPayment.none;
  }

  /// The wallet currency to send as `currency`, or null (real money / none).
  WalletCurrency? get walletCurrency => switch (payment) {
        ShopPayment.tokens => WalletCurrency.token,
        ShopPayment.gold => WalletCurrency.gold,
        _ => null,
      };

  /// The charged price in [walletCurrency], or the cents for real money.
  int? get chargedPrice => switch (payment) {
        ShopPayment.tokens => priceTokens,
        ShopPayment.gold => priceGold,
        ShopPayment.realMoney => priceUsdCents,
        ShopPayment.none => null,
      };

  /// Only one per purchase (avatars and Remove Ads).
  bool get singleUnit => category == ShopCategory.avatar || category == ShopCategory.adFree;

  /// The struck-through regular price, only when `regular_price` is in the
  /// unit shown (Known issue 6: with both a wallet and a dollar price,
  /// `regular_price` is in cents).
  int? get struckPrice {
    final sameUnit = payment == ShopPayment.realMoney || priceUsdCents == null;
    return sameUnit ? offer.struckPrice(chargedPrice) : null;
  }

  factory ShopItem.fromJson(Map<String, dynamic> j) => ShopItem(
        id: _iOrNull(j['id']) ?? 0,
        code: _s(j['code']) ?? '',
        name: _s(j['name']) ?? '',
        description: _s(j['description']),
        category: ShopCategory.parse(j['category']),
        tokenAmount: parseAmount(j['token_amount']),
        goldAmount: parseAmount(j['gold_amount']),
        bonusTokenAmount: parseAmount(j['bonus_token_amount']),
        bonusGoldAmount: parseAmount(j['bonus_gold_amount']),
        powerUpId: _iOrNull(j['power_up_id']),
        powerUpQuantity: _iOrNull(j['power_up_quantity']),
        avatarId: _iOrNull(j['avatar_id']),
        isActive: j['is_active'] != false,
        priceUnit: _s(j['price_unit']),
        priceUsdCents: j['price_usd_cents'] == null ? null : parseAmount(j['price_usd_cents']),
        priceTokens: j['price_tokens'] == null ? null : parseAmount(j['price_tokens']),
        priceGold: j['price_gold'] == null ? null : parseAmount(j['price_gold']),
        offer: PriceOffer.fromJson(j),
      );
}

/// "$4.99" from US cents.
String formatUsdCents(int cents) => '\$${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

/// `POST /sensitive/shop/purchase` reply (§2). `new_balance` is a string.
@immutable
class ShopPurchase {
  const ShopPurchase({
    required this.purchaseId,
    required this.itemId,
    required this.quantity,
    required this.totalPrice,
    required this.currency,
    required this.newBalance,
  });

  final int purchaseId;
  final int itemId;
  final int quantity;
  final int totalPrice;
  final WalletCurrency currency;

  /// The balance in [currency] afterwards.
  final int newBalance;

  factory ShopPurchase.fromJson(Map<String, dynamic> j, {WalletCurrency fallback = WalletCurrency.token}) =>
      ShopPurchase(
        purchaseId: _iOrNull(j['purchase_id']) ?? 0,
        itemId: _iOrNull(j['item_id']) ?? 0,
        quantity: _iOrNull(j['quantity']) ?? 1,
        totalPrice: parseAmount(j['total_price']),
        currency: WalletCurrency.tryParse(j['currency']) ?? fallback,
        newBalance: parseAmount(j['new_balance']),
      );
}

/// `POST /sensitive/shop/purchase/sandbox` reply (§3c). `balances` are numbers.
@immutable
class SandboxPurchase {
  const SandboxPurchase({
    required this.purchaseId,
    required this.itemId,
    required this.quantity,
    required this.tokensCredited,
    required this.goldCredited,
    required this.priceUsdCents,
    required this.sandbox,
    this.balanceTokens,
    this.balanceGold,
  });

  final int purchaseId;
  final int itemId;
  final int quantity;
  final int tokensCredited;
  final int goldCredited;
  final int priceUsdCents;
  final bool sandbox;

  /// The balances afterwards (include a referral reward); null if missing.
  final int? balanceTokens;
  final int? balanceGold;

  factory SandboxPurchase.fromJson(Map<String, dynamic> j) {
    final b = _m(j['balances']);
    return SandboxPurchase(
      purchaseId: _iOrNull(j['purchase_id']) ?? 0,
      itemId: _iOrNull(j['item_id']) ?? 0,
      quantity: _iOrNull(j['quantity']) ?? 1,
      tokensCredited: parseAmount(j['tokens_credited']),
      goldCredited: parseAmount(j['gold_credited']),
      priceUsdCents: parseAmount(j['price_usd_cents']),
      sandbox: j['sandbox'] == true,
      balanceTokens: b['tokens'] == null ? null : parseAmount(b['tokens']),
      balanceGold: b['gold'] == null ? null : parseAmount(b['gold']),
    );
  }
}

/// `POST /sensitive/iap/verify` reply (§3a, from the code).
@immutable
class IapVerifyResult {
  const IapVerifyResult({this.receiptId, this.transactionId, this.verified = false, this.tokensCredited = 0, this.duplicate = false});

  final int? receiptId;

  /// The server's record id (not the store's).
  final int? transactionId;
  final bool verified;
  final int tokensCredited;

  /// `409 DUPLICATE_TRANSACTION`: already credited; counts as success.
  final bool duplicate;

  static const alreadyCredited = IapVerifyResult(verified: true, duplicate: true);

  factory IapVerifyResult.fromJson(Map<String, dynamic> j) => IapVerifyResult(
        receiptId: _iOrNull(j['receipt_id']),
        transactionId: _iOrNull(j['transaction_id']),
        verified: j['verified'] == true,
        tokensCredited: parseAmount(j['tokens_credited']),
      );
}

/// One row of `GET /sensitive/iap/history` (§3b).
@immutable
class IapTransaction {
  const IapTransaction({
    required this.id,
    required this.productId,
    required this.amountCents,
    required this.status,
    this.receiptId,
    this.shopItemId,
    this.subscriptionPlanId,
    this.currencyCode = 'USD',
    this.storeCurrencyCode,
    this.refundedAt,
    this.purchasedAt,
  });

  final int id;
  final int? receiptId;
  final String productId;
  final int? shopItemId;
  final int? subscriptionPlanId;

  /// Always US cents.
  final int amountCents;
  final String currencyCode;
  final String? storeCurrencyCode;

  /// `completed` or `refunded`.
  final String status;
  final DateTime? refundedAt;
  final DateTime? purchasedAt;

  bool get refunded => status == 'refunded';

  factory IapTransaction.fromJson(Map<String, dynamic> j) => IapTransaction(
        id: _iOrNull(j['id']) ?? 0,
        receiptId: _iOrNull(j['receipt_id']),
        productId: _s(j['product_id']) ?? '',
        shopItemId: _iOrNull(j['shop_item_id']),
        subscriptionPlanId: _iOrNull(j['subscription_plan_id']),
        amountCents: parseAmount(j['amount_cents']),
        currencyCode: _s(j['currency_code']) ?? 'USD',
        storeCurrencyCode: _s(j['store_currency_code']),
        status: _s(j['status']) ?? 'completed',
        refundedAt: _d(j['refunded_at']),
        purchasedAt: _d(j['purchased_at']) ?? _d(j['created_at']),
      );
}

/// Page list shape 2 (`data`, `total`, `page`, `per_page`, `total_pages`).
@immutable
class PageList<T> {
  const PageList({this.data = const [], this.total = 0, this.page = 1, this.perPage = 20, this.totalPages = 0});
  final List<T> data;
  final int total;
  final int page;
  final int perPage;
  final int totalPages;

  bool get hasMore => page < totalPages;

  factory PageList.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) item) => PageList(
        data: [for (final e in (j['data'] is List ? j['data'] as List : const [])) if (e is Map) item(e.cast<String, dynamic>())],
        total: parseAmount(j['total']),
        page: _iOrNull(j['page']) ?? 1,
        perPage: _iOrNull(j['per_page']) ?? 20,
        totalPages: parseAmount(j['total_pages']),
      );
}

/// `POST /cosmetics/avatars/{id}/purchase` and
/// `POST /cosmetics/power-ups/{id}/purchase` (both `201`, §6b / §7b).
@immutable
class CosmeticPurchase {
  const CosmeticPurchase({
    required this.itemId,
    required this.itemType,
    required this.currency,
    required this.amountSpent,
    required this.newBalance,
  });

  final int itemId;

  /// `avatar` or `power_up`.
  final String itemType;
  final WalletCurrency currency;
  final int amountSpent;
  final int newBalance;

  factory CosmeticPurchase.fromJson(Map<String, dynamic> j, {WalletCurrency fallback = WalletCurrency.token}) =>
      CosmeticPurchase(
        itemId: _iOrNull(j['item_id']) ?? 0,
        itemType: _s(j['item_type']) ?? '',
        currency: WalletCurrency.tryParse(j['currency']) ?? fallback,
        amountSpent: parseAmount(j['amount_spent']),
        newBalance: parseAmount(j['new_balance']),
      );
}

/// `GET /sensitive/ad-free/status` (§5b).
@immutable
class AdFreeStatus {
  const AdFreeStatus({this.isActive = false, this.grantedVia, this.expiresAt});
  final bool isActive;

  /// `pass`, `purchase`, `subscription`, `promo` or null. Display only.
  final String? grantedVia;

  /// Null = for good.
  final DateTime? expiresAt;

  static const off = AdFreeStatus();

  factory AdFreeStatus.fromJson(Map<String, dynamic> j) => AdFreeStatus(
        isActive: j['is_active'] == true,
        grantedVia: _s(j['granted_via']),
        expiresAt: _d(j['expires_at']),
      );
}

/// One ad placement of a stage in `GET /me/ads/flow`.
@immutable
class AdPlacement {
  const AdPlacement({required this.id, required this.code, required this.format, this.reward});
  final int id;
  final String code;
  final String format;
  final String? reward;

  factory AdPlacement.fromJson(Map<String, dynamic> j) => AdPlacement(
        id: _iOrNull(j['id']) ?? 0,
        code: _s(j['code']) ?? '',
        format: _s(j['format']) ?? '',
        reward: _s(j['reward']),
      );
}

/// One stage of the ad flow (`launch`, `lobby`, `pre`, `in`, `post`, `results`).
@immutable
class AdsStage {
  const AdsStage({required this.stage, this.formats = const [], this.placements = const []});
  final String stage;
  final List<String> formats;
  final List<AdPlacement> placements;

  factory AdsStage.fromJson(Map<String, dynamic> j) => AdsStage(
        stage: _s(j['stage']) ?? '',
        formats: [for (final f in (j['formats'] is List ? j['formats'] as List : const [])) if (f is String) f],
        placements: [
          for (final p in (j['placements'] is List ? j['placements'] as List : const []))
            if (p is Map) AdPlacement.fromJson(p.cast<String, dynamic>()),
        ],
      );
}

/// `GET /me/ads/flow` (§5c): which ads to show. Show only the formats and
/// placements a stage lists.
@immutable
class AdsFlow {
  const AdsFlow({this.decidedBy, this.effect, this.stages = const []});
  final String? decidedBy;
  final String? effect;
  final List<AdsStage> stages;

  AdsStage? stage(String name) => stages.where((s) => s.stage == name).firstOrNull;

  /// The formats [stage] allows (empty = no ads there).
  List<String> formatsAt(String name) => stage(name)?.formats ?? const [];

  /// No ad at all in any stage.
  bool get adFree => stages.every((s) => s.formats.isEmpty);

  static const none = AdsFlow();

  factory AdsFlow.fromJson(Map<String, dynamic> j) => AdsFlow(
        decidedBy: _s(j['decided_by']),
        effect: _s(j['effect']),
        stages: [
          for (final s in (j['stages'] is List ? j['stages'] as List : const []))
            if (s is Map) AdsStage.fromJson(s.cast<String, dynamic>()),
        ],
      );
}

/// A power-up from `GET /cosmetics/power-ups` (§7a): the catalogue
/// [PowerUp] plus its discount fields.
@immutable
class StorePowerUp {
  const StorePowerUp(this.powerUp, {this.offer = PriceOffer.none, this.iconUrl});
  final PowerUp powerUp;
  final PriceOffer offer;
  final String? iconUrl;

  int get id => powerUp.id;
  WalletCurrency? get currency => WalletCurrency.tryParse(powerUp.priceCurrency);
  int? get struckPrice => offer.struckPrice(powerUp.priceAmount);

  factory StorePowerUp.fromJson(Map<String, dynamic> j) =>
      StorePowerUp(PowerUp.fromJson(j), offer: PriceOffer.fromJson(j), iconUrl: _s(j['icon_url']));
}

/// An avatar from `GET /cosmetics/avatars` (§6a) plus its discount fields.
@immutable
class StoreAvatar {
  const StoreAvatar(this.avatar, {this.offer = PriceOffer.none});
  final AvatarItem avatar;
  final PriceOffer offer;

  int get id => avatar.id;
  WalletCurrency? get currency => WalletCurrency.tryParse(avatar.priceCurrency);

  /// Sold here, with a wallet price.
  bool get forSale => avatar.isPurchasable && currency != null && avatar.priceAmount != null;

  /// Earned another way (achievement / grant): locked, no price.
  bool get earnedOnly => avatar.isPremium && !avatar.isPurchasable;

  factory StoreAvatar.fromJson(Map<String, dynamic> j) =>
      StoreAvatar(AvatarItem.fromJson(j), offer: PriceOffer.fromJson(j));
}

/// One owned power-up from `GET /users/me/inventory` (§7c).
@immutable
class OwnedPowerUp {
  const OwnedPowerUp({required this.powerUpId, required this.code, required this.gameId, required this.quantity, this.name});
  final int powerUpId;
  final String code;
  final String? name;
  final int gameId;
  final int quantity;

  factory OwnedPowerUp.fromJson(Map<String, dynamic> j) => OwnedPowerUp(
        powerUpId: _iOrNull(j['power_up_id']) ?? 0,
        code: _s(j['code']) ?? '',
        name: _s(j['name']),
        gameId: _iOrNull(j['game_id']) ?? 0,
        quantity: parseAmount(j['quantity']),
      );
}

/// Typed reads of the account [Inventory] for the store.
extension InventoryStore on Inventory {
  List<OwnedPowerUp> get ownedPowerUps => [for (final p in powerUps) OwnedPowerUp.fromJson(p)];

  /// "You have N".
  int quantityOf(int powerUpId) {
    var n = 0;
    for (final p in ownedPowerUps) {
      if (p.powerUpId == powerUpId) n += p.quantity;
    }
    return n;
  }

  /// The game's owned power-ups with quantity above 0 (the in-game bar).
  List<OwnedPowerUp> powerUpsForGame(int gameId) =>
      [for (final p in ownedPowerUps) if (p.gameId == gameId && p.quantity > 0) p];

  bool ownsAvatar(int id) => avatarIds.contains(id);
}

/// `POST /cosmetics/avatars/{id}/equip` reply.
@immutable
class AvatarEquip {
  const AvatarEquip({required this.avatarId, required this.equipped});
  final int avatarId;
  final bool equipped;

  factory AvatarEquip.fromJson(Map<String, dynamic> j) =>
      AvatarEquip(avatarId: _iOrNull(j['avatar_id']) ?? 0, equipped: j['equipped'] == true);
}
