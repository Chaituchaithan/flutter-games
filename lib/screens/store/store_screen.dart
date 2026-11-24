import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../data/models/account.dart';
import '../../data/models/store.dart';
import '../../data/models/subscription.dart';
import '../../data/models/wallet.dart';
import '../../data/repositories/subscription_repository.dart';
import '../../services/account_store.dart';
import '../../services/app_exception.dart';
import '../../configs/games/core/game_codes.dart';
import '../../configs/games/games.dart';
import '../../services/catalogue_service.dart';
import '../../services/progress_service.dart';
import '../../services/iap_bridge.dart';
import '../../services/server_clock.dart';
import '../../services/session.dart';
import '../../services/store_api.dart';
import '../../services/store_service.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';
import '../../widgets/player_avatar.dart';
import '../../widgets/wallet_pill.dart';
import '../economy/purchase_confirm_screen.dart';
import '../system/loading_skeleton_screen.dart' show Shimmer, SkeletonBox;

/// Store tab (docs/services/11-store.md). Body only — the shell provides
/// scaffold + nav. Tabs: Coins (token and gold packs, Remove Ads, prize
/// games, purchase history) · Power-ups · Avatars · VIP. Everything comes from
/// the store routes ([storeApiProvider]: live when signed in, a demo
/// catalogue otherwise); buying goes through [StoreController].
///
/// Active Store sub-tab (0 Coins · 1 Power-ups · 2 Avatars · 3 VIP). A
/// provider so other screens can deep-link, e.g. Settings → "Upgrade to VIP".
class StoreTabController extends Notifier<int> {
  @override
  int build() => 0;
  void select(int index) => state = index;
}

final storeTabProvider = NotifierProvider<StoreTabController, int>(StoreTabController.new);

class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  int get _tab => ref.watch(storeTabProvider);

  static const List<String> _tabs = ['Coins', 'Boosts', 'Avatars', 'VIP'];

  @override
  Widget build(BuildContext context) {
    final paused = ref.watch(storePausedProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WalletTitleBar(title: 'Store'),
          const SizedBox(height: 16),
          SegmentedTabs(
            labels: _tabs,
            index: _tab,
            onChanged: (i) => ref.read(storeTabProvider.notifier).select(i),
          ),
          if (paused != null) ...[
            const SizedBox(height: 10),
            _Notice(icon: Icons.pause_circle_outline, text: paused, danger: true),
          ],
          const SizedBox(height: 16),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() => switch (_tab) {
        1 => const _PowerUpsTab(),
        2 => const _AvatarsTab(),
        3 => const _VipTab(),
        _ => const _CoinsTab(),
      };
}

/// Opens the buy sheet; "Get more …" switches to the Coins tab.
Future<Object?> _openBuy(BuildContext context, WidgetRef ref, BuyRequest request) async {
  final r = await showBuySheet(context, request);
  if (r == PurchaseSheet.getMore) ref.read(storeTabProvider.notifier).select(0);
  return r;
}

/// A one-line notice (store paused, sandbox / coming soon).
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.danger = false});
  final IconData icon;
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = danger ? AuraColors.dangerText : AuraColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: AuraGlass.decoration(radius: 14, shadow: false),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: c, fontSize: 12.5, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

/// Reloads the catalogue when the earliest running special ends (its price
/// goes back) and redraws the countdowns every minute.
mixin _SpecialsClock<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Timer? _tick;
  DateTime? _watching;

  void watchSpecials(Iterable<PriceOffer> offers) {
    final now = ServerClock.now();
    DateTime? first;
    for (final o in offers) {
      if (o.specialRunning(now) && (first == null || o.specialUntil!.isBefore(first))) first = o.specialUntil;
    }
    if (first == _watching) return;
    _watching = first;
    _tick?.cancel();
    if (first == null) return;
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (_watching != null && !_watching!.isAfter(ServerClock.now())) {
        _watching = null;
        _tick?.cancel();
        ref.read(storeControllerProvider).reload();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}

/// "Ends in 2h 05m" for a running special.
String _endsIn(DateTime until) {
  final d = ServerClock.until(until);
  if (d == Duration.zero) return 'Ending';
  if (d.inDays > 0) return 'Ends in ${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours > 0) return 'Ends in ${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
  return 'Ends in ${d.inMinutes < 1 ? 1 : d.inMinutes}m';
}

/// The offer / special badge text of an item, or null.
String? _badgeFor(PriceOffer o, int? struck) {
  if (o.specialRunning(ServerClock.now())) return (o.specialLabel ?? 'SALE').toUpperCase();
  if (o.isOffer && struck != null) return 'OFFER';
  return null;
}

// ── Coins tab ──

class _CoinsTab extends ConsumerStatefulWidget {
  const _CoinsTab();

  @override
  ConsumerState<_CoinsTab> createState() => _CoinsTabState();
}

class _CoinsTabState extends ConsumerState<_CoinsTab> with _SpecialsClock {
  Future<void> _refresh() async {
    ref.read(storeControllerProvider).reload();
    try {
      await ref.read(shopItemsProvider.future);
    } on Object catch (_) {/* the view shows the error */}
  }

  Future<void> _buy(ShopItem item) async {
    final r = await _openBuy(context, ref, BuyRequest.shopItem(item));
    if (!mounted || r is! SandboxPurchase) return;
    final gold = r.goldCredited > 0 && r.tokensCredited == 0;
    Navigator.of(context).pushNamed(Routes.purchaseComplete, arguments: {
      'amount': Wallet.formatAmount(gold ? r.goldCredited : r.tokensCredited),
      'unit': gold ? 'Gold' : 'Tokens',
      'gold': gold,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<ShopItem>>(
      value: ref.watch(shopItemsProvider),
      onRetry: _refresh,
      loading: const _PackGridSkeleton(),
      data: (items) {
        watchSpecials(items.map((i) => i.offer));
        final mode = ref.watch(packPurchaseModeProvider);
        final paused = ref.watch(storePausedProvider) != null;
        final tokens = [for (final i in items) if (i.category == ShopCategory.tokenPack && i.payment != ShopPayment.none) i];
        final gold = [for (final i in items) if (i.category == ShopCategory.goldPack && i.payment != ShopPayment.none) i];
        final adFree = items.where((i) => i.category == ShopCategory.adFree).firstOrNull;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (mode != PackPurchaseMode.store && (tokens.isNotEmpty || gold.isNotEmpty))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _Notice(
                      icon: Icons.info_outline,
                      text: mode == PackPurchaseMode.sandbox
                          ? 'Test purchases: coin packs are credited without payment.'
                          : 'Buying coin packs with real money is coming soon.',
                    ),
                  ),
                ),
              if (tokens.isNotEmpty) ...[
                const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(bottom: 10), child: SectionBar('Tokens'))),
                _packGrid(tokens, Currency.gems, mode, paused),
              ],
              if (gold.isNotEmpty) ...[
                const SliverToBoxAdapter(
                    child: Padding(padding: EdgeInsets.only(top: 18, bottom: 10), child: SectionBar('Gold'))),
                _packGrid(gold, Currency.gold, mode, paused),
              ],
              if (adFree != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: _RemoveAdsCard(item: adFree, paused: paused, onBuy: () => _buy(adFree)),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Column(
                    children: [
                      _LinkRow(
                        icon: Icons.auto_awesome,
                        label: 'Prize games',
                        sub: 'Scratch cards and more',
                        onTap: () => Navigator.of(context).pushNamed(Routes.bonusGames),
                      ),
                      const SizedBox(height: 10),
                      _LinkRow(
                        icon: Icons.receipt_long,
                        label: 'Purchase history',
                        sub: 'Real-money purchases',
                        onTap: () => _showPurchaseHistory(context),
                      ),
                    ],
                  ),
                ),
              ),
              // Just enough clearance for the floating bottom nav.
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }

  Widget _packGrid(List<ShopItem> packs, Currency kind, PackPurchaseMode mode, bool paused) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.82,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final p = packs[i];
          final wallet = p.payment != ShopPayment.realMoney;
          return _PackCard(
            pack: p,
            kind: kind,
            enabled: !paused && (wallet || mode != PackPurchaseMode.comingSoon),
            comingSoon: !wallet && mode == PackPurchaseMode.comingSoon,
            onBuy: () => _buy(p),
          );
        },
        childCount: packs.length,
      ),
    );
  }
}

/// Real-money purchase history (`GET /sensitive/iap/history`). Sandbox
/// packs are not listed here; they show in the wallet history.
void _showPurchaseHistory(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PurchaseHistorySheet(),
  );
}

class _PurchaseHistorySheet extends ConsumerWidget {
  const _PurchaseHistorySheet();

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF17112C), Color(0xFF0B0916)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Purchase history', style: AuraText.title.copyWith(fontSize: 18)),
          const SizedBox(height: 12),
          Flexible(
            child: AsyncView<PageList<IapTransaction>>(
              value: ref.watch(iapHistoryProvider),
              onRetry: () => ref.invalidate(iapHistoryProvider),
              data: (page) => page.data.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No real-money purchases yet. Test purchases show in your wallet history.',
                        textAlign: TextAlign.center,
                        style: AuraText.cardSub,
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final t in page.data)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(t.productId, style: AuraText.cardTitle),
                            subtitle: Text(
                              [
                                if (t.purchasedAt != null)
                                  '${t.purchasedAt!.toLocal().day} ${_months[t.purchasedAt!.toLocal().month - 1]} ${t.purchasedAt!.toLocal().year}',
                                if (t.refunded) 'Refunded',
                              ].join(' · '),
                              style: AuraText.cardSub,
                            ),
                            trailing: Text(formatUsdCents(t.amountCents), style: AuraText.numeric.copyWith(fontSize: 15)),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.label, required this.sub, required this.onTap});
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: AuraGlass.decoration(radius: 18, shadow: false),
          child: Row(
            children: [
              Icon(icon, color: AuraColors.accentGlow, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AuraText.cardTitle.copyWith(fontSize: 15)),
                    Text(sub, style: AuraText.cardSub),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AuraColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Remove Ads: sold for gold only (Known issue 5); "Ads removed" once the
/// ad-free status is active.
class _RemoveAdsCard extends ConsumerWidget {
  const _RemoveAdsCard({required this.item, required this.paused, required this.onBuy});
  final ShopItem item;
  final bool paused;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned = ref.watch(adFreeStatusProvider).value?.isActive ?? false;
    final price = item.priceGold;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AuraGlass.decoration(radius: AuraRadii.lg),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AuraGradients.goldCoin,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.block, color: Color(0xFF1A1206)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: AuraText.cardTitle.copyWith(fontSize: 15)),
                const SizedBox(height: 3),
                Text(owned ? 'Ads removed' : (item.description ?? ''), style: AuraText.cardSub),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (owned)
            const Icon(Icons.check_circle, color: AuraColors.green)
          else if (price != null)
            _BuyChip(price: Wallet.formatAmount(price), gold: true, onTap: paused ? null : onBuy),
        ],
      ),
    );
  }
}

/// Shimmering pack-grid placeholder (2-col grid of pack-card boxes).
class _PackGridSkeleton extends StatelessWidget {
  const _PackGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: CustomScrollView(
        slivers: [
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.82,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => Container(
                padding: const EdgeInsets.all(14),
                decoration: AuraGlass.decoration(radius: AuraRadii.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    SkeletonBox(width: 48, height: 10),
                    Spacer(),
                    Center(child: SkeletonBox(width: 36, height: 36, shape: BoxShape.circle)),
                    SizedBox(height: 12),
                    Center(child: SkeletonBox(width: 70, height: 18)),
                    Spacer(),
                    SkeletonBox(height: 38, radius: 12),
                  ],
                ),
              ),
              childCount: 6,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.pack,
    required this.kind,
    required this.onBuy,
    this.enabled = true,
    this.comingSoon = false,
  });
  final ShopItem pack;
  final Currency kind;
  final VoidCallback onBuy;
  final bool enabled;
  final bool comingSoon;

  @override
  Widget build(BuildContext context) {
    final accent = kind == Currency.gems ? AuraColors.gems : AuraColors.gold;
    final base = kind == Currency.gems ? pack.tokenAmount : pack.goldAmount;
    final bonus = kind == Currency.gems ? pack.bonusTokenAmount : pack.bonusGoldAmount;
    final struck = pack.struckPrice;
    final special = pack.offer.specialRunning(ServerClock.now()) ? pack.offer.specialUntil : null;
    final badge = _badgeFor(pack.offer, struck);
    final hot = badge != null;
    final price = switch (pack.payment) {
      ShopPayment.realMoney => formatUsdCents(pack.priceUsdCents!),
      _ => Wallet.formatAmount(pack.chargedPrice ?? 0),
    };
    final struckText = struck == null
        ? null
        : (pack.payment == ShopPayment.realMoney ? formatUsdCents(struck) : Wallet.formatAmount(struck));

    final content = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            pack.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: AuraColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          Center(child: CurrencyGlyph(kind: kind, size: 36)),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              Wallet.formatAmount(base),
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: AuraColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (bonus > 0) ...[
            const SizedBox(height: 2),
            Text(
              '+ ${Wallet.formatAmount(bonus)} bonus',
              textAlign: TextAlign.center,
              style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
          if (special != null)
            Text(_endsIn(special), textAlign: TextAlign.center, style: AuraText.caption.copyWith(fontSize: 10)),
          const Spacer(),
          if (struckText != null)
            Text(
              struckText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AuraColors.textSecondary,
                fontSize: 11,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          _PriceButton(
            price: comingSoon ? '$price · Soon' : price,
            accent: accent,
            walletCurrency: pack.payment == ShopPayment.realMoney ? null : pack.walletCurrency,
            onTap: enabled ? onBuy : null,
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AuraRadii.lg),
        boxShadow: hot
            ? [BoxShadow(color: accent.withValues(alpha: 0.14), blurRadius: 22, spreadRadius: -12)]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AuraRadii.lg),
        child: Stack(
          children: [
            DecoratedBox(
              decoration: hot
                  ? BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [accent.withValues(alpha: 0.12), accent.withValues(alpha: 0.04)],
                      ),
                      borderRadius: BorderRadius.circular(AuraRadii.lg),
                      border: Border.all(color: accent.withValues(alpha: 0.45), width: 1),
                    )
                  : AuraGlass.decoration(radius: AuraRadii.lg, shadow: false),
              child: content,
            ),
            if (badge != null) Positioned(top: 0, right: 0, child: _CornerTag(label: badge, kind: kind)),
          ],
        ),
      ),
    );
  }
}

/// Top-right corner ribbon on a pack card (offer / special).
class _CornerTag extends StatelessWidget {
  const _CornerTag({required this.label, required this.kind});
  final String label;
  final Currency kind;

  @override
  Widget build(BuildContext context) {
    final colors = kind == Currency.gems
        ? const [Color(0xFF67E8F9), Color(0xFF22D3EE)]
        : const [Color(0xFFFDE68A), Color(0xFFF59E0B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AuraText.displayFamily,
          color: const Color(0xFF0A0816),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _PriceButton extends StatelessWidget {
  const _PriceButton({required this.price, required this.accent, required this.onTap, this.walletCurrency});
  final String price;
  final Color accent;
  final VoidCallback? onTap;

  /// Shown as a glyph before the price for wallet-priced packs.
  final WalletCurrency? walletCurrency;

  @override
  Widget build(BuildContext context) {
    final gold = accent == AuraColors.gold;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: gold
                  ? AuraGradients.goldCoin
                  : const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (walletCurrency != null) ...[
                    CurrencyGlyph(kind: walletCurrency!.currency, size: 14),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    price,
                    style: TextStyle(
                      fontFamily: AuraText.displayFamily,
                      color: gold ? const Color(0xFF1A1206) : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Power-ups tab ──

/// Power-up packs from the shop, then every game's power-ups with "You have
/// N" from the inventory. Power-ups are spent inside a game over its socket;
/// the store never calls `/cosmetics/power-ups/{id}/use`.
class _PowerUpsTab extends ConsumerStatefulWidget {
  const _PowerUpsTab();

  @override
  ConsumerState<_PowerUpsTab> createState() => _PowerUpsTabState();
}

class _PowerUpsTabState extends ConsumerState<_PowerUpsTab> with _SpecialsClock {
  Future<void> _refresh() async {
    ref.read(storeControllerProvider).reload();
    ref.invalidate(inventoryProvider);
    try {
      await ref.read(storePowerUpsProvider.future);
    } on Object catch (_) {/* the view shows the error */}
  }

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(inventoryProvider).value ?? const Inventory();
    final packs = [
      for (final i in ref.watch(shopItemsProvider).value ?? const <ShopItem>[])
        if (i.category == ShopCategory.powerUpPack && i.walletCurrency != null) i,
    ];
    final games = {for (final g in ref.watch(catalogueGamesProvider).value ?? const []) g.id: g.name};
    // Only the game being played: its boosts (the catalogue's numeric id).
    final gameId = ref.watch(progressGameIdProvider(GameCodes.codeOf(ref.watch(activeGameProvider)))).value;
    final paused = ref.watch(storePausedProvider) != null;
    return AsyncView<List<StorePowerUp>>(
      value: ref.watch(storePowerUpsProvider),
      onRetry: _refresh,
      data: (everyGame) {
        final all = gameId == null ? everyGame : [for (final p in everyGame) if (p.powerUp.gameId == gameId) p];
        final mine = {for (final p in all) p.id};
        // A pack of another game's boost is hidden; one with no boost id stays.
        final packsHere = [for (final p in packs) if (p.powerUpId == null || mine.contains(p.powerUpId)) p];
        watchSpecials([...all.map((p) => p.offer), ...packsHere.map((p) => p.offer)]);
        final byGame = <int, List<StorePowerUp>>{};
        for (final p in all) {
          (byGame[p.powerUp.gameId] ??= []).add(p);
        }
        final names = {for (final p in all) p.id: p.powerUp.name};
        if (all.isEmpty && packsHere.isEmpty) {
          return Center(child: Text('No boosts for this game right now.', style: AuraText.cardSub));
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (packsHere.isNotEmpty) ...[
                const SectionBar('Boost packs'),
                const SizedBox(height: 10),
                for (final pack in packsHere) ...[
                  _PowerUpRow(
                    name: pack.name,
                    desc: pack.description ?? '',
                    detail: pack.powerUpId == null ? null : 'You have ${inventory.quantityOf(pack.powerUpId!)} ${names[pack.powerUpId] ?? ''}'.trim(),
                    icon: Icons.inventory_2_outlined,
                    price: pack.chargedPrice,
                    struck: pack.struckPrice,
                    currency: pack.walletCurrency,
                    badge: _badgeFor(pack.offer, pack.struckPrice),
                    onBuy: paused ? null : () => _openBuy(context, ref, BuyRequest.shopItem(pack)),
                  ),
                  const SizedBox(height: 11),
                ],
                const SizedBox(height: 8),
              ],
              for (final entry in byGame.entries) ...[
                SectionBar('${games[entry.key] ?? 'Game'} boosts'),
                const SizedBox(height: 10),
                for (final p in entry.value) ...[
                  _PowerUpRow(
                    name: p.powerUp.name,
                    desc: p.powerUp.description ?? '',
                    detail: [
                      'You have ${inventory.quantityOf(p.id)}',
                      if (p.powerUp.maxPerMatch != null) '${p.powerUp.maxPerMatch} per game',
                    ].join(' · '),
                    icon: Icons.bolt,
                    price: p.powerUp.priceAmount,
                    struck: p.struckPrice,
                    currency: p.currency,
                    badge: _badgeFor(p.offer, p.struckPrice),
                    onBuy: paused || p.currency == null || p.powerUp.priceAmount == null
                        ? null
                        : () => _openBuy(
                              context,
                              ref,
                              BuyRequest(
                                name: p.powerUp.name,
                                detail: p.powerUp.description,
                                currency: p.currency,
                                price: p.powerUp.priceAmount,
                                struckPrice: p.struckPrice,
                                icon: Icons.bolt,
                                successText: '${p.powerUp.name} added to your boosts',
                                buy: (c) => c.buyPowerUp(p),
                              ),
                            ),
                  ),
                  const SizedBox(height: 11),
                ],
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PowerUpRow extends StatelessWidget {
  const _PowerUpRow({
    required this.name,
    required this.desc,
    required this.icon,
    required this.onBuy,
    this.detail,
    this.price,
    this.struck,
    this.currency,
    this.badge,
  });
  final String name;
  final String desc;
  final String? detail;
  final IconData icon;
  final int? price;
  final int? struck;
  final WalletCurrency? currency;
  final String? badge;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    const grad = [Color(0xFF8B5CF6), Color(0xFF6366F1)];
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: AuraGlass.decoration(radius: 18),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: grad),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(name, style: AuraText.cardTitle.copyWith(fontSize: 15))),
                    if (badge != null) ...[const SizedBox(width: 7), _RarityChip(badge!, color: AuraColors.amber)],
                  ],
                ),
                if (desc.isNotEmpty) ...[const SizedBox(height: 3), Text(desc, style: AuraText.cardSub)],
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(detail!, style: AuraText.caption),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (price != null && currency != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _BuyChip(price: Wallet.formatAmount(price!), gold: currency == WalletCurrency.gold, onTap: onBuy),
                if (struck != null)
                  Text(
                    Wallet.formatAmount(struck!),
                    style: const TextStyle(
                        color: AuraColors.textSecondary, fontSize: 11, decoration: TextDecoration.lineThrough),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _BuyChip extends StatelessWidget {
  const _BuyChip({required this.price, required this.gold, required this.onTap});
  final String price;
  final bool gold;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: AuraGlass.decoration(radius: 12, shadow: false),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CurrencyGlyph(kind: gold ? Currency.gold : Currency.gems, size: 15),
                const SizedBox(width: 5),
                Text(
                  price,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RarityChip extends StatelessWidget {
  const _RarityChip(this.label, {required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AuraText.displayFamily,
          color: c,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ── Avatars tab ──

/// Owned, free and locked avatars with level and price (§6). Buy uses
/// `POST /cosmetics/avatars/{id}/purchase`; Equip is offered only for free
/// or owned avatars.
class _AvatarsTab extends ConsumerStatefulWidget {
  const _AvatarsTab();

  @override
  ConsumerState<_AvatarsTab> createState() => _AvatarsTabState();
}

class _AvatarsTabState extends ConsumerState<_AvatarsTab> with _SpecialsClock {
  bool _busy = false;

  Future<void> _refresh() async {
    ref.read(storeControllerProvider).reload();
    ref.invalidate(inventoryProvider);
    try {
      await ref.read(storeAvatarsProvider.future);
    } on Object catch (_) {/* the view shows the error */}
  }

  Future<void> _equip(StoreAvatar a) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(storeControllerProvider).equipAvatar(a.id);
      if (mounted) showAuraToast(context, '${a.avatar.name} equipped', kind: AuraToastKind.success);
    } on AppException catch (e) {
      if (mounted) showAuraToast(context, e.message, kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tap(StoreAvatar a, bool owned) {
    if (owned || a.avatar.isFree) {
      _equip(a);
    } else if (a.forSale) {
      final lvl = a.avatar.requiredLevel;
      // The server refuses a buy below the level (403 LEVEL_REQUIRED): say so
      // up front instead of offering Buy.
      final mine = ref.read(playerLevelProvider);
      if (lvl != null && mine < lvl) {
        showAuraToast(context, 'Reach level $lvl to unlock ${a.avatar.name}. You are level $mine.', kind: AuraToastKind.info);
        return;
      }
      _openBuy(
        context,
        ref,
        BuyRequest(
          name: a.avatar.name,
          detail: lvl == null ? null : 'Needs level $lvl',
          currency: a.currency,
          price: a.avatar.priceAmount,
          struckPrice: a.offer.struckPrice(a.avatar.priceAmount),
          icon: Icons.face_retouching_natural,
          successText: '${a.avatar.name} unlocked',
          buy: (c) => c.buyAvatar(a),
        ),
      );
    } else {
      showAuraToast(context, "${a.avatar.name} is earned in play, not sold.", kind: AuraToastKind.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(inventoryProvider).value ?? const Inventory();
    final me = ref.watch(accountStoreProvider);
    final user = ref.watch(currentUserProvider);
    final current = me?.profile.avatarId ?? int.tryParse(user.avatarId ?? '');
    final glyph = me?.glyph ?? user.initials;
    return AsyncView<List<StoreAvatar>>(
      value: ref.watch(storeAvatarsProvider),
      onRetry: _refresh,
      data: (list) {
        watchSpecials(list.map((a) => a.offer));
        return RefreshIndicator(
          onRefresh: _refresh,
          child: LayoutBuilder(
            builder: (context, c) {
              const gap = 12.0;
              final w = (c.maxWidth - gap * 2) / 3;
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final a in list)
                        _AvatarCard(
                          avatar: a,
                          glyph: glyph,
                          width: w,
                          owned: inventory.ownsAvatar(a.id),
                          equipped: a.id == current,
                          levelLocked: (a.avatar.requiredLevel ?? 0) > ref.watch(playerLevelProvider),
                          onTap: _busy ? null : () => _tap(a, inventory.ownsAvatar(a.id)),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _AvatarCard extends StatelessWidget {
  const _AvatarCard({
    required this.avatar,
    required this.glyph,
    required this.width,
    required this.owned,
    required this.equipped,
    required this.onTap,
    this.levelLocked = false,
  });
  final StoreAvatar avatar;

  /// Above the player's level: locked until then, even if it is for sale.
  final bool levelLocked;
  final String glyph;
  final double width;
  final bool owned;
  final bool equipped;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final a = avatar.avatar;
    final usable = owned || a.isFree;
    final String action;
    if (equipped) {
      action = 'Equipped';
    } else if (usable) {
      action = 'Equip';
    } else if (levelLocked) {
      action = 'Lv ${a.requiredLevel}';
    } else if (avatar.forSale) {
      action = Wallet.formatAmount(a.priceAmount!);
    } else {
      action = 'Locked';
    }
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: equipped ? null : onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
            decoration: AuraGlass.decoration(radius: 18, shadow: false),
            child: Column(
              children: [
                Opacity(
                  opacity: usable ? 1 : 0.5,
                  child: AvatarDisc(glyph: glyph, code: a.code, avatarUrl: a.imageUrl, name: a.name, size: 54),
                ),
                const SizedBox(height: 8),
                Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.cardTitle.copyWith(fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  usable ? (owned ? 'Owned' : 'Free') : (a.requiredLevel != null ? 'Level ${a.requiredLevel}' : 'Special'),
                  style: AuraText.caption,
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!usable && avatar.forSale && !levelLocked) ...[
                      CurrencyGlyph(kind: avatar.currency!.currency, size: 13),
                      const SizedBox(width: 4),
                    ] else if (!usable) ...[
                      const Icon(Icons.lock_rounded, size: 13, color: AuraColors.textSecondary),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        action,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: equipped ? AuraColors.green : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── VIP tab ──

/// A VIP tier definition (Free / Silver / Gold / Royal) with its accent colours and
/// per-tier perks. Mirrors the mockup's `vipTiers`.
class _VipTier {
  const _VipTier({
    required this.key,
    required this.name,
    required this.price,
    required this.per,
    required this.c1,
    required this.c2,
    required this.ink,
    required this.icon,
    required this.badge,
    required this.perks,
    this.plan,
  });
  final String key;
  final String name;
  final String price;
  final String per;
  final Color c1; // light accent
  final Color c2; // deep accent
  final Color ink; // text colour on the tier's gradient button
  final IconData icon;
  final String badge;
  final List<String> perks;

  /// The API plan behind this card (null = the tier has no plan for the
  /// chosen billing period).
  final SubscriptionPlan? plan;
}

/// Look + perks per tier. Prices, plan ids and billing come from
/// `GET /subscriptions/plans`; `features` is empty, so the copy is the app's
/// and promises only what the server applies today (11-store.md §4e): the
/// daily bonus / prize-game multiplier, VIP tables and tournaments, and the
/// ad rules. Not the stored-but-unapplied win multipliers, welcome tokens or
/// "includes ad-free".
const _tierStyles = <String, _VipTier>{
  'free': _VipTier(
    key: 'free', name: 'Free', price: '\$0', per: 'forever',
    c1: Color(0xFF94A3B8), c2: Color(0xFF64748B), ink: Colors.white,
    icon: Icons.shield_outlined, badge: 'BASIC',
    perks: ['Standard rewards', 'Ads between matches'],
  ),
  'silver': _VipTier(
    key: 'silver', name: 'Silver', price: '', per: '',
    c1: Color(0xFFE2E8F0), c2: Color(0xFF94A3B8), ink: Color(0xFF0F172A),
    icon: Icons.star, badge: 'STARTER',
    perks: ['Daily bonus and prize games ×1.5', 'Silver VIP tables and tournaments', 'Fewer ads'],
  ),
  'gold': _VipTier(
    key: 'gold', name: 'Gold', price: '', per: '',
    c1: Color(0xFFFDE68A), c2: Color(0xFFF59E0B), ink: Color(0xFF1A1206),
    icon: Icons.workspace_premium, badge: 'BEST VALUE',
    perks: ['Daily bonus and prize games ×2', 'Gold VIP tables and tournaments', 'Fewer ads'],
  ),
  'royal': _VipTier(
    key: 'royal', name: 'Royal', price: '', per: '',
    c1: Color(0xFFF0ABFC), c2: Color(0xFFA855F7), ink: Color(0xFF1A0626),
    icon: Icons.diamond_outlined, badge: 'ROYAL',
    perks: ['Daily bonus and prize games ×8', 'Every VIP table and tournament', 'No ads'],
  ),
};

/// VIP tab: Free · Silver · Gold · Royal cards with a Monthly / Yearly
/// switch, built from the live plans (Free is monthly only). Subscribe works
/// on the development sandbox only (debug builds; no receipt is taken);
/// release builds show "Coming soon". There is no upgrade route: a player on
/// a plan must cancel first. Cancel ends the plan at once.
class _VipTab extends ConsumerStatefulWidget {
  const _VipTab();

  @override
  ConsumerState<_VipTab> createState() => _VipTabState();
}

class _VipTabState extends ConsumerState<_VipTab> {
  String _selected = 'gold'; // highlighted tier
  bool _yearly = false;
  bool _busy = false;

  /// One card per tier for the chosen billing period.
  List<_VipTier> _tiers(List<SubscriptionPlan> plans) {
    SubscriptionPlan? pick(String tier) {
      final forTier = plans.where((p) => p.tier == tier).toList();
      if (forTier.isEmpty) return null;
      if (tier == 'free') return forTier.first; // same in both periods
      return forTier.where((p) => p.yearly == _yearly).firstOrNull;
    }

    final out = <_VipTier>[];
    for (final key in const ['free', 'silver', 'gold', 'royal']) {
      final style = _tierStyles[key]!;
      final plan = pick(key);
      if (plan == null && key != 'free') continue;
      final saving = plan != null && plan.yearly ? _yearlySaving(plans, plan) : null;
      final features = plan?.features ?? const {};
      out.add(_VipTier(
        key: key,
        name: style.name,
        price: plan == null || plan.free ? '\$0' : plan.price,
        per: plan == null || plan.free ? 'forever' : (plan.yearly ? '/ year' : '/ month'),
        c1: style.c1,
        c2: style.c2,
        ink: style.ink,
        icon: style.icon,
        badge: saving != null ? 'SAVE $saving%' : style.badge,
        perks: features.isNotEmpty ? [for (final e in features.entries) _featureText(e.key, e.value)] : style.perks,
        plan: plan,
      ));
    }
    return out;
  }

  /// Yearly vs 12 × monthly for the same tier, in whole percent.
  static int? _yearlySaving(List<SubscriptionPlan> plans, SubscriptionPlan yearly) {
    final monthly = plans.where((p) => p.tier == yearly.tier && !p.yearly).firstOrNull;
    if (monthly == null || monthly.priceCents == 0) return null;
    final pct = (100 - yearly.priceCents * 100 / (monthly.priceCents * 12)).round();
    return pct > 0 ? pct : null;
  }

  /// A server feature as a perk line ("ad_free": true → "Ad free").
  static String _featureText(String key, Object? value) {
    final name = key.replaceAll('_', ' ');
    final label = name.isEmpty ? key : '${name[0].toUpperCase()}${name.substring(1)}';
    return value == true || value == null ? label : '$label: $value';
  }

  /// The player's current tier ('free' when no live paid subscription).
  String _activeTier(MySubscription my, List<SubscriptionPlan> plans) => my.tierIn(plans);

  Future<void> _subscribe(_VipTier t, MySubscription my, String activeTier) async {
    if (_busy) return;
    // Free while on a paid plan = cancel.
    if (t.key == 'free') {
      if (activeTier != 'free') await _cancel(_tierStyles[activeTier]?.name ?? 'VIP');
      return;
    }
    final plan = t.plan;
    if (plan == null || (my.active && my.planId == plan.id)) return;
    // Release builds: the server can't take a store payment for a plan yet.
    if (!ref.read(subscriptionsPurchasableProvider)) {
      showAuraToast(context, 'Subscriptions are coming soon.', kind: AuraToastKind.info);
      return;
    }
    // No upgrade / downgrade route: cancel first (409 otherwise).
    if (my.active) {
      showAuraToast(context, 'You already have a plan. Cancel it first to switch.', kind: AuraToastKind.info);
      return;
    }
    if (ref.read(storePausedProvider) != null) return;
    setState(() => _busy = true);
    try {
      await ref.read(subscriptionSourceProvider).subscribe(plan.id);
      if (!mounted) return;
      ref.invalidate(mySubscriptionProvider);
      ref.invalidate(adsFlowProvider);
      showAuraToast(context, '${t.name} VIP activated',
          kind: t.key == 'gold' ? AuraToastKind.gold : AuraToastKind.success);
    } on AppException catch (e) {
      if (!mounted) return;
      if (e.code == ApiErrorCode.killSwitch) ref.read(storePausedProvider.notifier).pause(e.message);
      if (e.code == ApiErrorCode.notFound) ref.invalidate(subscriptionPlansProvider);
      if (e.code == ApiErrorCode.conflict) ref.invalidate(mySubscriptionProvider);
      showAuraToast(
        context,
        storeErrorText(e, StoreOp.subscribe),
        kind: e.code == ApiErrorCode.unavailable || e.statusCode == 503 ? AuraToastKind.info : AuraToastKind.error,
      );
    } on Object catch (_) {
      if (mounted) showAuraToast(context, "Couldn't start the subscription. Try again.", kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Cancel ends the plan at once (Known issue 4), with no refund: warn.
  Future<void> _cancel([String tierName = 'VIP']) async {
    final ok = await showAuraDialog(
      context,
      icon: Icons.cancel_outlined,
      title: 'Cancel $tierName VIP?',
      body: "Your $tierName benefits end now. This can't be undone.",
      primaryLabel: 'Cancel VIP',
      secondaryLabel: 'Keep VIP',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(subscriptionSourceProvider).cancel();
      if (!mounted) return;
      ref.invalidate(mySubscriptionProvider);
      ref.invalidate(adsFlowProvider);
      showAuraToast(context, 'Subscription cancelled', kind: AuraToastKind.info);
    } on AppException catch (e) {
      if (e.code == ApiErrorCode.notFound) ref.invalidate(mySubscriptionProvider);
      if (mounted) showAuraToast(context, storeErrorText(e, StoreOp.cancel), kind: AuraToastKind.error);
    } on Object catch (_) {
      if (mounted) showAuraToast(context, "Couldn't cancel. Try again.", kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<SubscriptionPlan>>(
      value: ref.watch(subscriptionPlansProvider),
      onRetry: () => ref.invalidate(subscriptionPlansProvider),
      loading: const _VipSkeleton(),
      data: (plans) {
        final my = ref.watch(mySubscriptionProvider).asData?.value ?? MySubscription.none;
        return _content(plans, my);
      },
    );
  }

  Widget _content(List<SubscriptionPlan> plans, MySubscription my) {
    final tiers = _tiers(plans);
    final activeTier = _activeTier(my, plans);
    final sel = tiers.firstWhere((t) => t.key == _selected, orElse: () => tiers.last);
    final selIsActive = sel.key == activeTier && (sel.key == 'free' || my.planId == null || my.planId == sel.plan?.id);
    final hasYearly = plans.any((p) => p.yearly);

    final canBuy = ref.watch(subscriptionsPurchasableProvider);
    final label = _busy
        ? 'Please wait…'
        : selIsActive
            ? (sel.key == 'free' ? 'Current plan' : '${sel.name} VIP active ✓')
            : sel.key == 'free'
                ? (activeTier == 'free' ? 'Current plan' : 'Switch to Free')
                : canBuy
                    ? 'Subscribe · ${sel.price} ${sel.per}'
                    : 'Coming soon · ${sel.price} ${sel.per}';

    final caption = my.active && my.endsAt != null
        ? '${my.autoRenew ? 'Renews' : 'Ends'} on ${_date(my.endsAt!.toLocal())}'
        : sel.plan?.yearly == true
            ? 'Cancel anytime · renews yearly'
            : 'Cancel anytime · renews monthly';

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (hasYearly) ...[
          Center(
            child: SizedBox(
              width: 240,
              child: SegmentedTabs(
                labels: const ['Monthly', 'Yearly'],
                index: _yearly ? 1 : 0,
                onChanged: (i) => setState(() => _yearly = i == 1),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            for (var i = 0; i < tiers.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _VipTierCard(
                  tier: tiers[i],
                  selected: sel.key == tiers[i].key,
                  active: activeTier == tiers[i].key,
                  onTap: () => setState(() => _selected = tiers[i].key),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: AuraGlass.decoration(radius: AuraRadii.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${sel.name.toUpperCase()} PLAN INCLUDES', style: AuraText.section.copyWith(letterSpacing: 1.2)),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(sel.price, style: AuraText.numeric.copyWith(fontSize: 30)),
                            const SizedBox(width: 6),
                            Text(sel.per, style: AuraText.cardSub),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [sel.c1, sel.c2],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                    ),
                    child: Icon(sel.icon, color: sel.ink, size: 28),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: AuraColors.glassStroke),
              const SizedBox(height: 14),
              for (final perk in sel.perks) ...[
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: sel.c1.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: sel.c1.withValues(alpha: 0.4)),
                      ),
                      child: Icon(Icons.check, size: 13, color: sel.c1),
                    ),
                    const SizedBox(width: 11),
                    Expanded(child: Text(perk, style: AuraText.body.copyWith(fontSize: 14))),
                  ],
                ),
                const SizedBox(height: 11),
              ],
              const SizedBox(height: 4),
              _VipSubscribeButton(
                tier: sel,
                active: selIsActive || _busy || (sel.key == 'free' && activeTier == 'free'),
                label: label,
                onTap: () => _subscribe(sel, my, activeTier),
              ),
              const SizedBox(height: 10),
              Center(child: Text(caption, style: AuraText.caption)),
              if (my.active)
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : () => _cancel(_tierStyles[activeTier]?.name ?? 'VIP'),
                    child: const Text(
                      'Cancel subscription',
                      style: TextStyle(color: AuraColors.dangerText, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Loading placeholder for the VIP tab (toggle, three cards, details).
class _VipSkeleton extends StatelessWidget {
  const _VipSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Center(child: SkeletonBox(width: 240, height: 40, radius: 99)),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                const Expanded(child: SkeletonBox(height: 150, radius: 20)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          const SkeletonBox(height: 320, radius: 28),
        ],
      ),
    );
  }
}

/// VIP subscribe/switch button. Tinted to the selected tier; when that tier is
/// already active it renders as a flat, disabled "… active ✓" button (mockup).
class _VipSubscribeButton extends StatelessWidget {
  const _VipSubscribeButton({
    required this.tier,
    required this.active,
    required this.label,
    required this.onTap,
  });
  final _VipTier tier;
  final bool active;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: active ? null : onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: active
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [tier.c1, tier.c2],
                    ),
              color: active ? Colors.white.withValues(alpha: 0.07) : null,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              boxShadow: active
                  ? null
                  : [
                      BoxShadow(
                        color: tier.c2.withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: -6,
                        offset: const Offset(0, 10),
                      ),
                    ],
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: active ? Colors.white.withValues(alpha: 0.6) : tier.ink,
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VipTierCard extends StatelessWidget {
  const _VipTierCard({
    required this.tier,
    required this.selected,
    required this.active,
    required this.onTap,
  });

  final _VipTier tier;
  final bool selected;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AuraRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AuraRadii.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AuraRadii.lg),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [tier.c1.withValues(alpha: 0.25), tier.c2.withValues(alpha: 0.08)],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0x14FFFFFF), Color(0x08FFFFFF)],
                  ),
            border: Border.all(
              color: selected ? tier.c1.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.2),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tier.c1.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tier.c1.withValues(alpha: 0.5)),
                ),
                child: Icon(tier.icon, color: tier.c1, size: 22),
              ),
              const SizedBox(height: 10),
              Text(tier.name, style: AuraText.cardTitle.copyWith(fontSize: 15)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(tier.price, style: AuraText.numeric.copyWith(fontSize: 16)),
              ),
              Text(tier.per, style: AuraText.caption),
              const SizedBox(height: 8),
              // Badge: the tier's label, or ACTIVE when it's the live plan.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (active ? AuraColors.green : tier.c1).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: (active ? AuraColors.green : tier.c1).withValues(alpha: 0.5)),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    active ? 'ACTIVE' : tier.badge,
                    style: TextStyle(
                      fontFamily: AuraText.displayFamily,
                      color: active ? AuraColors.green : tier.c1,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
