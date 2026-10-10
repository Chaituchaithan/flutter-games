import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/store_pack.dart';
import '../../data/repositories/store_repository.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';
import '../economy/purchase_confirm_screen.dart';
import '../system/loading_skeleton_screen.dart' show Shimmer, SkeletonBox;

/// Store tab (v2). Body only — the shell provides scaffold + nav.
/// Wallet + packs come from `storeRepositoryProvider` (static source today; live
/// API when remote sources are switched on). See docs/DESIGN_SPEC.md.
/// Active Store sub-tab (0 Tokens · 1 Gold · 2 Power-Ups · 3 VIP). A provider
/// so other screens can deep-link, e.g. Settings → "Upgrade to VIP".
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

  static const List<String> _tabs = ['Tokens', 'Gold', 'Power-Ups', 'VIP'];

  /// Open the purchase sheet for a specific pack, carrying its real name,
  /// amount, price, currency and the resulting balance.
  void _buyPack(StorePack pack, Currency kind) {
    final wallet = ref.read(walletProvider).maybeWhen(data: (w) => w, orElse: () => null);
    final current = wallet == null ? null : (kind == Currency.gems ? wallet.gems : wallet.gold);
    showPurchaseSheet(
      context,
      name: pack.name,
      amount: pack.amount,
      price: pack.price,
      kind: kind,
      bonus: pack.bonus,
      balanceAfter: _addAmounts(current, pack.amount),
    );
  }

  /// Sum two comma-formatted currency strings and re-format with thousands commas.
  static String _addAmounts(String? a, String b) {
    int parse(String? s) => int.tryParse((s ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final total = parse(a) + parse(b);
    return total.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final gems = wallet.maybeWhen(data: (w) => w.gems, orElse: () => '—');
    final gold = wallet.maybeWhen(data: (w) => w.gold, orElse: () => '—');

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Store', style: AuraText.title)),
              CurrencyPill(kind: Currency.gems, amount: gems, showPlus: false),
              const SizedBox(width: 8),
              CurrencyPill(kind: Currency.gold, amount: gold, showPlus: false),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedTabs(
            labels: _tabs,
            index: _tab,
            onChanged: (i) => ref.read(storeTabProvider.notifier).select(i),
          ),
          const SizedBox(height: 16),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_tab) {
      case 1:
        return _packTab(
          kind: Currency.gold,
          banner: _Banner(
            kind: Currency.gold,
            title: 'Gold',
            sub: 'Premium currency · rare power-ups',
            tag: 'PREMIUM',
          ),
        );
      case 2:
        return const _PowerUpsTab();
      case 3:
        return const _VipTab();
      case 0:
      default:
        return _packTab(
          kind: Currency.gems,
          banner: _Banner(
            kind: Currency.gems,
            title: 'Tokens',
            sub: 'Stake in Online Play & buy boosts',
            tag: '2× WEEKEND',
          ),
        );
    }
  }

  Widget _packTab({required Currency kind, required Widget banner}) {
    return AsyncView<List<StorePack>>(
      value: ref.watch(storePacksProvider(kind)),
      onRetry: () => ref.invalidate(storePacksProvider(kind)),
      // Grid-shaped skeleton so the loading state matches the pack layout
      // (not the generic list skeleton).
      loading: _PackGridSkeleton(banner: banner),
      data: (packs) => _PackTab(kind: kind, banner: banner, packs: packs, onBuy: _buyPack),
    );
  }
}

/// Shimmering pack-grid placeholder (banner + 2-col grid of pack-card boxes).
class _PackGridSkeleton extends StatelessWidget {
  const _PackGridSkeleton({required this.banner});
  final Widget banner;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: banner),
          const SliverToBoxAdapter(child: SizedBox(height: 14)),
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

// ── Token / Gold pack tab ──

class _PackTab extends StatelessWidget {
  const _PackTab({
    required this.kind,
    required this.banner,
    required this.packs,
    required this.onBuy,
  });

  final Currency kind;
  final Widget banner;
  final List<StorePack> packs;
  final void Function(StorePack pack, Currency kind) onBuy;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: banner),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.82,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _PackCard(pack: packs[i], kind: kind, onBuy: () => onBuy(packs[i], kind)),
            childCount: packs.length,
          ),
        ),
        // Just enough clearance for the floating bottom nav (no extra scroll).
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.kind, required this.title, required this.sub, this.tag});
  final Currency kind;
  final String title;
  final String sub;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final accent = kind == Currency.gems ? AuraColors.gems : AuraColors.gold;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AuraGlass.decoration(
        radius: AuraRadii.lg,
        accentGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.22), accent.withValues(alpha: 0.06)],
        ),
        border: accent.withValues(alpha: 0.45),
      ),
      child: Row(
        children: [
          CurrencyGlyph(kind: kind, size: 40),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AuraText.cardTitle),
                const SizedBox(height: 2),
                Text(sub, style: AuraText.cardSub),
              ],
            ),
          ),
          if (tag != null) AuraBadge(tag!, color: accent),
        ],
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({required this.pack, required this.kind, required this.onBuy});
  final StorePack pack;
  final Currency kind;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final accent = kind == Currency.gems ? AuraColors.gems : AuraColors.gold;
    // "Hot" packs (POPULAR / MEGA) get a currency-tinted fill + glow border
    // instead of plain glass — matches the mockup's packCard(hot, tint).
    final hot = pack.badge == 'POPULAR' || pack.badge == 'MEGA';

    // Consistent column: name pinned top, icon+amount centered, price pinned
    // bottom — so every box lines up regardless of bonus/size (box consistency).
    final content = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            pack.name,
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
              pack.amount,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: AuraColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (pack.bonus != null) ...[
            const SizedBox(height: 2),
            Text(
              pack.bonus!,
              textAlign: TextAlign.center,
              style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
          const Spacer(),
          _PriceButton(price: pack.price, accent: accent, onTap: onBuy),
        ],
      ),
    );

    return Container(
      // Shadow lives on the outer box so the inner ClipRRect can clip the tag.
      // Hot tiles get only a soft accent glow — toned well down from the old
      // bright halo so the tiles read as subtly as the mockup (not a spotlight).
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
            // Corner-ribbon tag tucked into the top-right (mockup): gradient fill,
            // dark text, only the inner (bottom-left) corner rounded.
            if (pack.badge != null)
              Positioned(top: 0, right: 0, child: _CornerTag(label: pack.badge!, kind: kind)),
          ],
        ),
      ),
    );
  }
}

/// Top-right corner ribbon on a pack card (mockup: gradient bg, dark 9px text,
/// bottom-left corner rounded, flush to the card's clipped corner).
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
  const _PriceButton({required this.price, required this.accent, required this.onTap});
  final String price;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final gold = accent == AuraColors.gold;
    return Material(
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
            child: Text(
              price,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: gold ? const Color(0xFF1A1206) : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Power-Ups tab ──

class _PowerUp {
  const _PowerUp({
    required this.icon,
    required this.grad,
    required this.rarityColor,
    required this.name,
    required this.rarity,
    required this.desc,
    required this.price,
    required this.gold,
    this.owned = 0,
  });
  final IconData icon;

  /// Solid gradient filling the icon chip (mockup `g`).
  final List<Color> grad;

  /// Rarity chip tint (mockup `rc`) — distinct from the icon gradient.
  final Color rarityColor;
  final String name;
  final String rarity;
  final String desc;
  final String price;
  final bool gold;
  final int owned;
}

const _powerUps = [
  _PowerUp(icon: Icons.bolt, grad: [Color(0xFF8B5CF6), Color(0xFF6366F1)], rarityColor: Color(0xFFC084FC), name: 'Double XP', rarity: 'EPIC', desc: '2× XP for the next hour', price: '500', gold: true, owned: 2),
  _PowerUp(icon: Icons.autorenew, grad: [Color(0xFFEC4899), Color(0xFFF472B6)], rarityColor: Color(0xFFF9A8D4), name: 'Extra Spins', rarity: 'RARE', desc: '+3 Lucky Wheel spins', price: '300', gold: true),
  _PowerUp(icon: Icons.shield_outlined, grad: [Color(0xFF22D3EE), Color(0xFF3B82F6)], rarityColor: Color(0xFF67E8F9), name: 'Streak Shield', rarity: 'LEGENDARY', desc: 'Protect your streak once', price: '1,200', gold: false, owned: 1),
  _PowerUp(icon: Icons.lightbulb_outline, grad: [Color(0xFFFBBF24), Color(0xFFF59E0B)], rarityColor: Color(0xFFFDE68A), name: 'Hint Boost', rarity: 'RARE', desc: 'Reveal one clue per match', price: '800', gold: false),
  _PowerUp(icon: Icons.schedule, grad: [Color(0xFF34D399), Color(0xFF14B8A6)], rarityColor: Color(0xFF6EE7B7), name: 'Time Freeze', rarity: 'COMMON', desc: '+15 seconds on the clock', price: '600', gold: false, owned: 3),
];

class _PowerUpsTab extends StatefulWidget {
  const _PowerUpsTab();

  @override
  State<_PowerUpsTab> createState() => _PowerUpsTabState();
}

class _PowerUpsTabState extends State<_PowerUpsTab> {
  /// Live inventory counts, seeded from each power-up's starting `owned`.
  late final Map<String, int> _owned = {for (final p in _powerUps) p.name: p.owned};

  void _buy(_PowerUp p) {
    setState(() => _owned[p.name] = (_owned[p.name] ?? 0) + 1);
    showAuraToast(context, '${p.name} added to your inventory', kind: AuraToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Banner(
          kind: Currency.gems,
          title: 'Power-Ups',
          sub: 'Boosts stack in your inventory',
        ),
        const SizedBox(height: 14),
        for (final p in _powerUps) ...[
          _PowerUpRow(p: p, owned: _owned[p.name] ?? 0, onBuy: () => _buy(p)),
          const SizedBox(height: 11),
        ],
      ],
    );
  }
}

class _PowerUpRow extends StatelessWidget {
  const _PowerUpRow({required this.p, required this.owned, required this.onBuy});
  final _PowerUp p;
  final int owned;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final grad = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: p.grad,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: AuraGlass.decoration(radius: 18),
        child: Stack(
          children: [
            // Soft corner glow blob tinted to the power-up (mockup: blur 18, 0.18).
            Positioned(
              left: -20,
              top: -20,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [p.grad.first.withValues(alpha: 0.25), Colors.transparent],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(13),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Solid gradient icon chip with a coloured glow (mockup).
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: grad,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: p.grad.first.withValues(alpha: 0.55),
                              blurRadius: 16,
                              spreadRadius: -4,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(p.icon, color: Colors.white, size: 24),
                      ),
                      if (owned > 0)
                        Positioned(
                          top: -6,
                          right: -6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(color: AuraColors.bgBase, width: 2),
                            ),
                            child: Text(
                              '×$owned',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10, color: Color(0xFF0A0816)),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(p.name, style: AuraText.cardTitle.copyWith(fontSize: 15))),
                            const SizedBox(width: 7),
                            _RarityChip(p.rarity, color: p.rarityColor),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(p.desc, style: AuraText.cardSub),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _BuyChip(price: p.price, gold: p.gold, onTap: onBuy),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuyChip extends StatelessWidget {
  const _BuyChip({required this.price, required this.gold, required this.onTap});
  final String price;
  final bool gold;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
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
    );
  }
}

class _RarityChip extends StatelessWidget {
  const _RarityChip(this.rarity, {required this.color});
  final String rarity;

  /// The chip is tinted to the power-up's own accent colour (mockup).
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
        rarity,
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

// ── VIP tab ──

/// A VIP tier definition (Free / Silver / Gold) with its accent colours and
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
}

const _vipTiers = <_VipTier>[
  _VipTier(
    key: 'free', name: 'Free', price: '\$0', per: 'forever',
    c1: Color(0xFF94A3B8), c2: Color(0xFF64748B), ink: Colors.white,
    icon: Icons.shield_outlined, badge: 'CURRENT',
    perks: ['Standard matchmaking', 'Ads between matches', '1 daily spin'],
  ),
  _VipTier(
    key: 'silver', name: 'Silver', price: '\$4.99', per: '/ month',
    c1: Color(0xFFE2E8F0), c2: Color(0xFF94A3B8), ink: Color(0xFF0F172A),
    icon: Icons.star, badge: 'STARTER',
    perks: ['No banner ads', '1.5× match rewards', '3 daily spins', 'Silver profile frame'],
  ),
  _VipTier(
    key: 'gold', name: 'Gold', price: '\$9.99', per: '/ month',
    c1: Color(0xFFFDE68A), c2: Color(0xFFF59E0B), ink: Color(0xFF1A1206),
    icon: Icons.workspace_premium, badge: 'BEST VALUE',
    perks: [
      'Remove all ads forever', '2× match rewards', 'Daily 500 Gold bonus',
      'Exclusive avatars & frames', 'Priority matchmaking', 'Gold VIP badge',
    ],
  ),
];

class _VipTab extends StatefulWidget {
  const _VipTab();

  @override
  State<_VipTab> createState() => _VipTabState();
}

class _VipTabState extends State<_VipTab> {
  String _selected = 'gold'; // highlighted tier
  String _active = 'free'; // currently-subscribed tier

  _VipTier get _sel => _vipTiers.firstWhere((t) => t.key == _selected);
  bool get _isActive => _active == _selected;

  void _subscribe() {
    if (_isActive) return;
    setState(() => _active = _selected);
    final t = _sel;
    showAuraToast(
      context,
      t.key == 'free' ? 'Switched to the Free plan' : '${t.name} VIP activated',
      kind: t.key == 'gold' ? AuraToastKind.gold : AuraToastKind.success,
    );
  }

  String get _buttonLabel {
    final t = _sel;
    if (_isActive) return t.key == 'free' ? 'Current plan' : '${t.name} VIP active ✓';
    return t.key == 'free' ? 'Switch to Free' : 'Subscribe · ${t.price} ${t.per}';
  }

  @override
  Widget build(BuildContext context) {
    final sel = _sel;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Row(
          children: [
            for (var i = 0; i < _vipTiers.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _VipTierCard(
                  tier: _vipTiers[i],
                  selected: _selected == _vipTiers[i].key,
                  active: _active == _vipTiers[i].key,
                  onTap: () => setState(() => _selected = _vipTiers[i].key),
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
                        Text(
                          '${sel.name.toUpperCase()} PLAN INCLUDES',
                          style: AuraText.section.copyWith(letterSpacing: 1.2),
                        ),
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
                active: _isActive,
                label: _buttonLabel,
                onTap: _subscribe,
              ),
              const SizedBox(height: 10),
              Center(
                child: Text('Cancel anytime · renews monthly', style: AuraText.caption),
              ),
            ],
          ),
        ),
      ],
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
