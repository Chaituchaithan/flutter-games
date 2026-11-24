import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/store.dart';
import '../data/models/wallet.dart';
import '../data/repositories/referral_repository.dart';
import '../data/repositories/subscription_repository.dart';
import '../utils/uuid.dart';
import 'account_store.dart';
import 'app_exception.dart';
import 'iap_bridge.dart';
import 'session.dart';
import 'store_api.dart';
import 'wallet_store.dart';

/// One purchase attempt (11-store.md "For the Claude agent" 3): a new UUID
/// [key] per attempt; on no network or a timeout it retries **once with the
/// same key** (the reply says whether the first one went through). A
/// replayed reply (`Idempotent-Replayed: true`) is a normal 2xx = success.
class PurchaseFlow {
  PurchaseFlow({String Function()? newKey, this.retryDelay = const Duration(seconds: 1)})
      : key = (newKey ?? newUuidV4)();

  /// The `Idempotency-Key` of this attempt.
  final String key;
  final Duration retryDelay;

  Future<T> run<T>(Future<T> Function(String key) send) async {
    try {
      return await send(key);
    } on AppException catch (e) {
      if (!(e.isOffline || e.kind == AppErrorKind.timeout || e.isRateLimited)) rethrow;
      await Future<void>.delayed(retryDelay);
      return send(key);
    }
  }
}

/// Makes the key of each new attempt (overridden in tests).
final purchaseKeyProvider = Provider<String Function()>((ref) => newUuidV4);

/// Wait before the one retry of a purchase.
final purchaseRetryDelayProvider = Provider<Duration>((ref) => const Duration(seconds: 1));

/// The operator's store pause (`503 KILL_SWITCH_ENGAGED`): their message, or
/// null. While set every Buy button is disabled; browsing, status reads and
/// cancel keep working. Cleared on a catalogue reload.
class StorePause extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(sessionProvider.select((u) => u?.id));
    return null;
  }

  void pause(String message) => state = message;
  void clear() => state = null;
}

final storePausedProvider = NotifierProvider<StorePause, String?>(StorePause.new);

/// Catalogues, cached for the session (§Limits): reload on pull to refresh,
/// when a special ends and on a `404` for an item.
final shopItemsProvider = FutureProvider<List<ShopItem>>((ref) async {
  ref.watch(sessionProvider.select((u) => u?.id));
  final items = await ref.watch(storeApiProvider).shopItems();
  return [for (final i in items) if (i.isActive) i];
});

final storeAvatarsProvider = FutureProvider<List<StoreAvatar>>((ref) async {
  ref.watch(sessionProvider.select((u) => u?.id));
  final list = [...await ref.watch(storeApiProvider).avatars()]
    ..sort((a, b) => a.avatar.sortOrder.compareTo(b.avatar.sortOrder));
  return list;
});

/// Every game's power-ups (the Power-ups tab groups them by `game_id`).
final storePowerUpsProvider = FutureProvider<List<StorePowerUp>>((ref) async {
  ref.watch(sessionProvider.select((u) => u?.id));
  final list = [...await ref.watch(storeApiProvider).powerUps()]
    ..sort((a, b) => a.powerUp.gameId != b.powerUp.gameId
        ? a.powerUp.gameId.compareTo(b.powerUp.gameId)
        : a.powerUp.sortOrder.compareTo(b.powerUp.sortOrder));
  return list;
});

/// "Ads removed" on the Remove Ads card. Failures read as "not ad-free".
final adFreeStatusProvider = FutureProvider<AdFreeStatus>((ref) async {
  ref.watch(sessionProvider.select((u) => u?.id));
  try {
    return await ref.watch(storeApiProvider).adFreeStatus();
  } on AppException {
    return AdFreeStatus.off;
  }
});

/// Which ads to show (§5c). Ask this, not the ad-free status. Re-read after
/// Remove Ads, a subscribe or a cancel.
final adsFlowProvider = FutureProvider<AdsFlow>((ref) async {
  ref.watch(sessionProvider.select((u) => u?.id));
  return ref.watch(storeApiProvider).adsFlow();
});

/// Real-money purchase history (first page).
final iapHistoryProvider = FutureProvider.autoDispose<PageList<IapTransaction>>(
    (ref) => ref.watch(storeApiProvider).iapHistory(perPage: 50));

/// The store bridge (off until the server verifies receipts).
final iapBridgeProvider = Provider<IapBridge>((ref) {
  final bridge = IapBridge(
    api: ref.watch(storeApiProvider),
    client: ref.watch(billingClientProvider),
    onCredited: (_) => ref.read(storeControllerProvider).afterRealMoney(),
  );
  ref.onDispose(bridge.dispose);
  return bridge;
});

/// Result of a coin-pack Buy: the sandbox reply, or null when a store payment
/// was started (its credit arrives later through the [IapBridge]).
typedef PackResult = SandboxPurchase?;

/// The store's buying actions: each runs a [PurchaseFlow], updates the
/// balance chip from the reply, then re-reads the wallet and what the
/// purchase grants (inventory, ad-free, ads flow). Throws [AppException] with
/// the store's player text ([storeErrorText]).
class StoreController {
  StoreController(this._ref);
  final Ref _ref;

  StoreApi get _api => _ref.read(storeApiProvider);
  PurchaseFlow _flow() =>
      PurchaseFlow(newKey: _ref.read(purchaseKeyProvider), retryDelay: _ref.read(purchaseRetryDelayProvider));

  bool get paused => _ref.read(storePausedProvider) != null;

  Future<T> _guard<T>(Future<T> Function() run, StoreOp op, {WalletCurrency? currency, int? requiredLevel}) async {
    if (paused) {
      throw AppException(_ref.read(storePausedProvider)!, statusCode: 503, code: ApiErrorCode.killSwitch);
    }
    try {
      return await run();
    } on AppException catch (e) {
      switch (e.code) {
        case ApiErrorCode.killSwitch:
          _ref.read(storePausedProvider.notifier).pause(e.message);
        case ApiErrorCode.notFound when op != StoreOp.cancel && op != StoreOp.subscribe:
          _reloadCatalogues();
        case ApiErrorCode.conflict when op == StoreOp.avatar || op == StoreOp.adFree:
          _afterGrant(op); // already owned: show it as owned
      }
      throw storeError(e, op, currency: currency, requiredLevel: requiredLevel);
    }
  }

  void _reloadCatalogues() {
    _ref.invalidate(shopItemsProvider);
    _ref.invalidate(storeAvatarsProvider);
    _ref.invalidate(storePowerUpsProvider);
  }

  void _afterGrant(StoreOp op) {
    _ref.invalidate(inventoryProvider);
    if (op == StoreOp.adFree) {
      _ref.invalidate(adFreeStatusProvider);
      _ref.invalidate(adsFlowProvider);
    }
  }

  void _balance(WalletCurrency c, int amount) {
    _ref.read(walletProvider.notifier).applyBalance(c, amount);
    unawaited(_ref.read(walletProvider.notifier).moneyMoved());
  }

  /// Reload all catalogues and clear a store pause (pull to refresh, a
  /// special ending).
  void reload() {
    _ref.read(storePausedProvider.notifier).clear();
    _reloadCatalogues();
    _ref.invalidate(adFreeStatusProvider);
  }

  /// A shop item for tokens or gold (§2): power-up packs, avatar items,
  /// Remove Ads (gold) and gold-priced token packs.
  Future<ShopPurchase> buyItem(ShopItem item, {int quantity = 1}) {
    final currency = item.walletCurrency;
    final op = switch (item.category) {
      ShopCategory.avatar => StoreOp.avatar,
      ShopCategory.adFree => StoreOp.adFree,
      _ => StoreOp.purchase,
    };
    return _guard(() async {
      if (currency == null) {
        throw const AppException('', statusCode: 400, code: ApiErrorCode.validation);
      }
      final qty = item.singleUnit ? 1 : quantity.clamp(1, 100);
      final r = await _flow().run((key) =>
          _api.purchase(itemId: item.id, quantity: qty, currency: currency, idempotencyKey: key));
      _balance(r.currency, r.newBalance);
      _afterGrant(op);
      return r;
    }, op, currency: currency);
  }

  /// A real-money coin pack (§3): the sandbox route in debug builds, the
  /// store once it works, "Coming soon" otherwise (throws `UNAVAILABLE`).
  Future<PackResult> buyPack(ShopItem item, {int quantity = 1}) {
    final mode = _ref.read(packPurchaseModeProvider);
    return _guard(() async {
      switch (mode) {
        case PackPurchaseMode.comingSoon:
          throw const AppException('', kind: AppErrorKind.server, statusCode: 503, code: ApiErrorCode.unavailable);
        case PackPurchaseMode.store:
          final store = BillingStore.current;
          if (store == null) {
            throw const AppException('', kind: AppErrorKind.server, statusCode: 503, code: ApiErrorCode.unavailable);
          }
          await _ref.read(iapBridgeProvider).buy(item, store);
          return null;
        case PackPurchaseMode.sandbox:
          final r = await _flow().run((key) =>
              _api.sandboxPurchase(itemId: item.id, quantity: quantity.clamp(1, 100), idempotencyKey: key));
          final w = _ref.read(walletProvider.notifier);
          if (r.balanceTokens != null) w.applyBalance(WalletCurrency.token, r.balanceTokens!);
          if (r.balanceGold != null) w.applyBalance(WalletCurrency.gold, r.balanceGold!);
          afterRealMoney();
          return r;
      }
    }, StoreOp.pack);
  }

  /// After a real-money pack (sandbox or verified): the balance includes any
  /// referral reward (§3d); re-read it and the referral stats.
  void afterRealMoney() {
    unawaited(_ref.read(walletProvider.notifier).moneyMoved());
    _ref.invalidate(referralStatsProvider);
    _ref.invalidate(adFreeStatusProvider);
  }

  /// `POST /cosmetics/avatars/{id}/purchase` (the avatar picker / tab).
  Future<CosmeticPurchase> buyAvatar(StoreAvatar a) => _guard(() async {
        final r = await _flow().run((key) => _api.purchaseAvatar(a.id, idempotencyKey: key));
        _balance(r.currency, r.newBalance);
        _afterGrant(StoreOp.avatar);
        return r;
      }, StoreOp.avatar, currency: a.currency, requiredLevel: a.avatar.requiredLevel);

  /// `POST /cosmetics/avatars/{id}/equip`; then re-reads the profile.
  Future<AvatarEquip> equipAvatar(int id) => _guard(() async {
        final r = await _api.equipAvatar(id);
        _ref.read(sessionProvider.notifier).applyProfileReply({'avatar_id': id});
        unawaited(_ref.read(accountStoreProvider.notifier).load());
        return r;
      }, StoreOp.equip);

  /// One power-up (§7b). To buy several use a shop pack.
  Future<CosmeticPurchase> buyPowerUp(StorePowerUp p) => _guard(() async {
        final r = await _flow().run((key) => _api.purchasePowerUp(p.id, idempotencyKey: key));
        _balance(r.currency, r.newBalance);
        _afterGrant(StoreOp.powerUp);
        return r;
      }, StoreOp.powerUp, currency: p.currency);

  /// "Restore Purchases" (§3e): everything is owned on the account, so
  /// re-read ad-free, the inventory and the subscription (and ask the store
  /// once the bridge is on).
  Future<void> restorePurchases() async {
    _ref.invalidate(adFreeStatusProvider);
    _ref.invalidate(adsFlowProvider);
    _ref.invalidate(inventoryProvider);
    _ref.invalidate(mySubscriptionProvider);
    await Future.wait<Object?>([
      _ref.read(adFreeStatusProvider.future),
      _ref.read(inventoryProvider.future),
    ]);
    await _ref.read(iapBridgeProvider).restore();
  }
}

final storeControllerProvider = Provider<StoreController>(StoreController.new);
