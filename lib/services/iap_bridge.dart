import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/store.dart';
import 'app_exception.dart';
import 'store_api.dart';

/// Real-money buying (docs/services/11-store.md §3), isolated from the rest of
/// the store behind two seams:
///
/// * [BillingClient]: the platform billing library (Play Billing / StoreKit).
///   The app has **no** implementation yet: `in_app_purchase` is not a
///   dependency. Write `InAppPurchaseBillingClient` against it when it is
///   added (see the class doc).
/// * [PackPurchaseMode] / [packPurchaseModeProvider]: what a coin-pack Buy
///   button does in this build — the development **sandbox** route, the store
///   ([IapBridge], switched off), or "Coming soon".
///
/// The server cannot verify a store purchase yet (`/iap/verify` always
/// answers `503 UNAVAILABLE`), so release builds must never start a store
/// payment: [IapBridge.serverVerifies] stays false until that changes.

/// `google` (Play Billing) or `apple` (StoreKit).
enum BillingStore {
  google('google'),
  apple('apple');

  const BillingStore(this.wire);
  final String wire;

  static BillingStore? get current => switch (defaultTargetPlatform) {
        TargetPlatform.android => google,
        TargetPlatform.iOS || TargetPlatform.macOS => apple,
        _ => null,
      };
}

/// Store product ids by shop `code` (§3a). Not sent by the API; read from the
/// development database on 24 Nov 2026. **Confirm with the server owner
/// before release.** Subscription plans have no product ids yet.
abstract final class StoreProductIds {
  static const google = <String, String>{
    'tokens_100': 'tokens_100',
    'tokens_550': 'tokens_550',
    'tokens_1200': 'tokens_1200',
    'tokens_6500': 'tokens_6500',
    'gold_5000': 'gold_5000',
    'gold_30000': 'gold_30000',
    'ad_free_forever': 'ad_free_forever',
  };

  static const apple = <String, String>{
    'tokens_100': 'com.allgames.tokens.100',
    'tokens_550': 'com.allgames.tokens.550',
    'tokens_1200': 'com.allgames.tokens.1200',
    'tokens_6500': 'com.allgames.tokens.6500',
    'gold_5000': 'com.allgames.gold.5000',
    'gold_30000': 'com.allgames.gold.30000',
    'ad_free_forever': 'com.allgames.adfree',
  };

  static Map<String, String> _of(BillingStore s) => s == BillingStore.google ? google : apple;

  /// The store's product id for a shop item code, or null.
  static String? productId(String shopCode, BillingStore store) => _of(store)[shopCode];

  /// The shop code a store product id belongs to, or null.
  static String? shopCode(String productId, BillingStore store) =>
      _of(store).entries.where((e) => e.value == productId).firstOrNull?.key;
}

/// A paid (or restored) store purchase handed back by the billing library —
/// the fields of `in_app_purchase`'s `PurchaseDetails` the server needs.
/// Never log [verificationData].
class StorePayment {
  const StorePayment({
    required this.store,
    required this.productId,
    required this.transactionId,
    required this.verificationData,
    required this.amountCents,
    this.currencyCode = 'USD',
    this.handle,
  });

  final BillingStore store;
  final String productId;

  /// The store's id for this purchase (Play order id `GPA....` / Apple
  /// transaction id). Makes a resend safe.
  final String transactionId;

  /// `PurchaseDetails.verificationData.serverVerificationData`.
  final String verificationData;

  /// What the store charged, in minor units (from `ProductDetails`).
  /// Recorded by the server, never trusted.
  final int amountCents;
  final String currencyCode;

  /// The library's own object (`PurchaseDetails`), passed back to
  /// [BillingClient.complete].
  final Object? handle;

  IapVerifyRequest toVerifyRequest() => IapVerifyRequest(
        store: store.wire,
        receiptData: verificationData,
        productId: productId,
        transactionId: transactionId,
        amountCents: amountCents,
        currencyCode: currencyCode,
      );

  @override
  String toString() => 'StorePayment(${store.wire}, $productId)'; // no receipt
}

/// The platform billing library. Implement with `package:in_app_purchase`:
///
/// * [isAvailable] → `InAppPurchase.instance.isAvailable()`.
/// * [payments] → `purchaseStream`, keeping `PurchaseStatus.purchased` and
///   `restored` as [StorePayment]s (`purchaseID` → transactionId,
///   `verificationData.serverVerificationData` → verificationData, price from
///   the matching `ProductDetails.rawPrice`/`currencyCode`).
/// * [buy] → `queryProductDetails({productId})` then `buyConsumable` for
///   token/gold packs (`autoConsume: false` on Android, so the app consumes
///   only after the server credits) or `buyNonConsumable` for Remove Ads.
/// * [complete] → `completePurchase(handle)`.
/// * [restore] → `restorePurchases()`.
abstract class BillingClient {
  Future<bool> isAvailable();
  Stream<List<StorePayment>> get payments;
  Future<void> buy(String productId, {required bool consumable});
  Future<void> complete(StorePayment payment);
  Future<void> restore();
}

/// The result of handing one store payment to the server.
enum IapOutcome {
  /// `200`: credited; the store transaction was completed.
  credited,

  /// `409 DUPLICATE_TRANSACTION`: credited before; completed now.
  alreadyCredited,

  /// Any other error or no network: left open. The store hands it back on the
  /// next start (`purchaseStream`) and it is sent again.
  pending,
}

/// Verify-then-complete for store purchases (§3a "Order of steps"):
/// 1. buy with the store's product id; 2. on `purchased`, send
/// `/iap/verify` — nothing is credited on the device; 3. on `200` or
/// `409 DUPLICATE_TRANSACTION` complete the purchase and re-read the wallet;
/// 4. otherwise leave it pending for the next start.
///
/// **Switched off** ([serverVerifies] false): [start] and [buy] do nothing
/// until the server verifies receipts.
class IapBridge {
  IapBridge({required this.api, this.client, this.enabled = serverVerifies, this.onCredited});

  /// Flip when `/iap/verify` stops answering `503` (Known issue 1) and credits
  /// gold packs and Remove Ads too (Known issue 2).
  static const serverVerifies = false;

  final StoreApi api;
  final BillingClient? client;
  final bool enabled;

  /// Called after a credit (re-read the wallet, inventory, ad-free status).
  final FutureOr<void> Function(StorePayment payment)? onCredited;

  StreamSubscription<List<StorePayment>>? _sub;
  final _inFlight = <String>{};

  bool get active => enabled && client != null;

  /// Listens to the store's purchase stream (call once at app start, after
  /// sign-in): pending purchases from an earlier run arrive here too.
  Future<void> start() async {
    final c = client;
    if (!active || c == null || _sub != null) return;
    if (!await c.isAvailable()) return;
    _sub = c.payments.listen((list) {
      for (final p in list) {
        unawaited(handle(p));
      }
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Starts a store payment for a shop item; the credit arrives through
  /// [payments] → [handle]. Throws when the bridge is off or the item has no
  /// product id.
  Future<void> buy(ShopItem item, BillingStore store) async {
    final c = client;
    if (!active || c == null) {
      throw const AppException('Purchases are not available yet.',
          kind: AppErrorKind.server, statusCode: 503, code: ApiErrorCode.unavailable);
    }
    final id = StoreProductIds.productId(item.code, store);
    if (id == null) throw const AppException('This item is no longer available.', code: ApiErrorCode.notFound);
    await c.buy(id, consumable: item.isPack);
  }

  /// Sends one payment to the server and completes it only on success.
  Future<IapOutcome> handle(StorePayment p) async {
    final c = client;
    if (c == null || !_inFlight.add(p.transactionId)) return IapOutcome.pending;
    try {
      final r = await api.verifyIap(p.toVerifyRequest());
      await c.complete(p);
      await onCredited?.call(p);
      return r.duplicate ? IapOutcome.alreadyCredited : IapOutcome.credited;
    } on AppException {
      // 503 UNAVAILABLE, 404 (no shop item sells it), a validation error or
      // no network: keep the store transaction open; never retry in a loop.
      return IapOutcome.pending;
    } finally {
      _inFlight.remove(p.transactionId);
    }
  }

  /// "Restore Purchases": asks the store to hand back owned items; each goes
  /// through [handle]. No-op while off.
  Future<void> restore() async {
    final c = client;
    if (active && c != null) await c.restore();
  }
}

/// The platform billing client. Null: no billing library in this build.
final billingClientProvider = Provider<BillingClient?>((ref) => null);

/// What a coin-pack Buy button does in this build (§3, "Done when").
enum PackPurchaseMode {
  /// Debug builds: `POST /sensitive/shop/purchase/sandbox` (no payment).
  sandbox,

  /// The store via [IapBridge] (once the server verifies receipts).
  store,

  /// Release builds today: show the price with "Coming soon".
  comingSoon,
}

final packPurchaseModeProvider = Provider<PackPurchaseMode>((ref) {
  if (kDebugMode) return PackPurchaseMode.sandbox;
  if (IapBridge.serverVerifies && ref.watch(billingClientProvider) != null) return PackPurchaseMode.store;
  return PackPurchaseMode.comingSoon;
});

/// Subscriptions take no receipt: subscribe only on the development sandbox
/// (debug builds). Release builds show "Coming soon".
final subscriptionsPurchasableProvider = Provider<bool>((ref) => kDebugMode);
