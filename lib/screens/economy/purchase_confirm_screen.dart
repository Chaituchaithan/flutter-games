import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/store.dart';
import '../../data/models/wallet.dart';
import '../../services/app_exception.dart';
import '../../services/iap_bridge.dart';
import '../../services/store_service.dart';
import '../../services/wallet_store.dart';
import '../../widgets/aura.dart';

/// What the buy sheet sells (11-store.md "Buy sheet"): the item, the price in
/// force, and the action that buys it through [StoreController].
class BuyRequest {
  const BuyRequest({
    required this.name,
    required this.buy,
    this.detail,
    this.currency,
    this.price,
    this.struckPrice,
    this.usdCents,
    this.icon = Icons.shopping_bag_outlined,
    this.successText,
  });

  /// A shop item: a wallet purchase, or a real-money pack (sandbox / store).
  factory BuyRequest.shopItem(ShopItem item, {String? detail}) {
    final pack = item.payment == ShopPayment.realMoney;
    return BuyRequest(
      name: item.name,
      detail: detail ?? item.description,
      currency: item.walletCurrency,
      price: pack ? null : item.chargedPrice,
      struckPrice: item.struckPrice,
      usdCents: pack ? item.priceUsdCents : null,
      icon: switch (item.category) {
        ShopCategory.adFree => Icons.block,
        ShopCategory.avatar => Icons.face_retouching_natural,
        ShopCategory.powerUpPack => Icons.bolt,
        _ => Icons.toll,
      },
      successText: pack ? null : '${item.name} is yours!',
      buy: (c) => pack ? c.buyPack(item) : c.buyItem(item),
    );
  }

  final String name;
  final String? detail;

  /// Wallet price (tokens / gold); null for real money.
  final WalletCurrency? currency;
  final int? price;
  final int? struckPrice;

  /// Real-money price in US cents (coin packs).
  final int? usdCents;
  final IconData icon;

  /// The toast on success (null = the caller shows its own result).
  final String? successText;

  /// Runs the purchase; its value is what the sheet pops with.
  final Future<Object?> Function(StoreController c) buy;

  bool get realMoney => usdCents != null;
}

/// The buy sheet. Pops with the purchase's result, or null when closed /
/// failed. Errors are shown in the sheet as toasts with the store's text.
Future<Object?> showBuySheet(BuildContext context, BuyRequest request) {
  return showModalBottomSheet<Object?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xBD05040C), // rgba(5,4,12,0.74)
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: PurchaseSheet(request: request),
    ),
  );
}

/// Item, price, the wallet balance in that currency and Confirm. Confirm is
/// greyed out when the balance is short, with "Get more gold / tokens".
/// Real-money packs: debug builds buy through the sandbox route (no payment);
/// release builds show "Coming soon" and start no payment.
class PurchaseSheet extends ConsumerStatefulWidget {
  const PurchaseSheet({super.key, required this.request, this.onGetMore});

  final BuyRequest request;

  /// "Get more gold / tokens" (defaults to closing the sheet with
  /// [PurchaseSheet.getMore]).
  final VoidCallback? onGetMore;

  /// Popped when the player taps "Get more …": open the coin packs.
  static const getMore = #getMore;

  @override
  ConsumerState<PurchaseSheet> createState() => _PurchaseSheetState();
}

class _PurchaseSheetState extends ConsumerState<PurchaseSheet> {
  bool _busy = false;

  BuyRequest get r => widget.request;

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await r.buy(ref.read(storeControllerProvider));
      if (!mounted) return;
      if (r.successText != null) showAuraToast(context, r.successText!, kind: AuraToastKind.success);
      Navigator.of(context).pop(result ?? true);
    } on AppException catch (e) {
      if (!mounted) return;
      showAuraToast(context, e.message.isEmpty ? 'Something went wrong. Try again.' : e.message,
          kind: e.code == ApiErrorCode.unavailable ? AuraToastKind.info : AuraToastKind.error);
      // Owned already / the store paused: nothing more to do here.
      if (e.code == ApiErrorCode.conflict || e.code == ApiErrorCode.killSwitch) Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = r.currency;
    final isGold = currency == WalletCurrency.gold;
    final paused = ref.watch(storePausedProvider);
    final balance = currency == null ? null : ref.watch(walletProvider).value?.of(currency.currency);
    final short = currency != null && balance != null && r.price != null && balance < r.price!;
    final mode = ref.watch(packPurchaseModeProvider);

    final String label;
    var enabled = paused == null && !short;
    if (r.realMoney) {
      final p = formatUsdCents(r.usdCents!);
      switch (mode) {
        case PackPurchaseMode.sandbox:
          label = 'Buy $p · test, no payment';
        case PackPurchaseMode.store:
          label = 'Pay $p';
        case PackPurchaseMode.comingSoon:
          label = 'Coming soon';
          enabled = false;
      }
    } else {
      label = short ? 'Not enough ${currency.noun}' : 'Confirm';
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF17112C), Color(0xFF0B0916)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.22), width: 1.5)),
          ),
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text('Confirm purchase', style: AuraText.title.copyWith(fontSize: 22))),
                  Material(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AuraGlass.decoration(radius: 20, shadow: false),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Icon(r.icon, color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.name, style: AuraText.cardTitle.copyWith(fontSize: 17)),
                          if (r.detail != null && r.detail!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(r.detail!, style: AuraText.cardSub),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _Price(request: r),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (currency != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _KvRow(
                    label: 'Your ${currency.noun}',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CurrencyGlyph(kind: currency.currency, size: 15),
                        const SizedBox(width: 5),
                        Text(
                          balance == null ? '…' : Wallet.formatAmount(balance),
                          style: TextStyle(
                            fontFamily: AuraText.displayFamily,
                            color: short ? AuraColors.dangerText : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (r.realMoney && mode == PackPurchaseMode.sandbox)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Development server: credited without payment.', style: AuraText.caption),
                ),
              if (r.realMoney && mode == PackPurchaseMode.comingSoon)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Buying with real money is coming soon.', style: AuraText.caption),
                ),
              if (paused != null) ...[
                const SizedBox(height: 8),
                Text(paused, style: const TextStyle(color: AuraColors.dangerText, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              _PayButton(
                label: _busy ? 'Please wait…' : label,
                gold: isGold,
                onPressed: enabled && !_busy ? _confirm : null,
              ),
              if (short) ...[
                const SizedBox(height: 10),
                SecondaryButton(
                  label: 'Get more ${currency.noun}',
                  onPressed: widget.onGetMore ?? () => Navigator.of(context).pop(PurchaseSheet.getMore),
                ),
              ],
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Restore purchases in Settings',
                  style: TextStyle(
                    fontFamily: AuraText.bodyFamily,
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Price extends StatelessWidget {
  const _Price({required this.request});
  final BuyRequest request;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: AuraText.displayFamily,
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.w700,
    );
    final r = request;
    if (r.realMoney) return Text(formatUsdCents(r.usdCents!), style: style);
    final c = r.currency;
    final p = r.price;
    if (c == null || p == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CurrencyGlyph(kind: c.currency, size: 18),
            const SizedBox(width: 5),
            Text(Wallet.formatAmount(p), style: style),
          ],
        ),
        if (r.struckPrice != null)
          Text(
            Wallet.formatAmount(r.struckPrice!),
            style: const TextStyle(
              color: AuraColors.textSecondary,
              fontSize: 12,
              decoration: TextDecoration.lineThrough,
            ),
          ),
      ],
    );
  }
}

/// Routed fallback (kept for deep-links / tests): the buy sheet for the
/// `item` passed as route argument, or a sample pack.
class PurchaseConfirmScreen extends StatelessWidget {
  const PurchaseConfirmScreen({super.key, this.item});
  final ShopItem? item;

  static const _sample = ShopItem(
    id: 2, code: 'tokens_550', name: 'Pouch of Tokens', category: ShopCategory.tokenPack,
    description: '500 tokens + 50 bonus.', tokenAmount: 500, bonusTokenAmount: 50, priceUnit: 'usd', priceUsdCents: 499,
  );

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          const Spacer(),
          PurchaseSheet(request: BuyRequest.shopItem(item ?? _sample)),
        ],
      ),
    );
  }
}

/// Currency-tinted confirm CTA (mockup `confirmPurchaseBtn`): gold gradient with
/// dark ink for Gold, cyan→blue with white ink for Tokens. Dimmed when off.
class _PayButton extends StatelessWidget {
  const _PayButton({required this.label, required this.gold, required this.onPressed});
  final String label;
  final bool gold;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final glow = gold ? AuraColors.gold : AuraColors.gems;
    final on = onPressed != null;
    return Opacity(
      opacity: on ? 1 : 0.5,
      child: SizedBox(
        height: 56,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: onPressed,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: gold
                    ? AuraGradients.goldCoin
                    : const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)]),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                boxShadow: on
                    ? [
                        BoxShadow(
                          color: glow.withValues(alpha: 0.45),
                          blurRadius: 30,
                          spreadRadius: -10,
                          offset: const Offset(0, 14),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: AuraText.displayFamily,
                  color: gold ? const Color(0xFF1A1206) : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AuraColors.textSecondary, fontSize: 13),
          ),
        ),
        child,
      ],
    );
  }
}
