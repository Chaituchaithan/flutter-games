import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/store_pack.dart';
import '../../data/repositories/store_repository.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';
import '../economy/purchase_confirm_screen.dart';

/// Store tab (v2). Body only — the shell provides scaffold + nav.
/// Wallet + packs come from `storeRepositoryProvider` (static source today; live
/// API when remote sources are switched on). See docs/MOCKUP_AUDIT.md §3.
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  int _tab = 0;

  static const List<String> _tabs = ['Tokens', 'Gold', 'Power-Ups', 'VIP'];

  void _buy() => showPurchaseSheet(context);

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
            onChanged: (i) => setState(() => _tab = i),
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
        return _PowerUpsTab(onBuy: _buy);
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
      data: (packs) => _PackTab(kind: kind, banner: banner, packs: packs, onBuy: _buy),
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
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: banner),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.78,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _PackCard(pack: packs[i], kind: kind, onBuy: onBuy),
            childCount: packs.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AuraGlass.decoration(radius: AuraRadii.lg),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Text(
              pack.name,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: AuraColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(child: CurrencyGlyph(kind: kind, size: pack.big ? 44 : 34)),
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
              const SizedBox(height: 12),
              _PriceButton(price: pack.price, accent: accent, onTap: onBuy),
            ],
          ),
          if (pack.badge != null)
            Positioned(top: 0, right: 0, child: AuraBadge(pack.badge!, color: accent)),
        ],
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
    required this.color,
    required this.name,
    required this.rarity,
    required this.desc,
    required this.price,
    required this.gold,
    this.owned = 0,
  });
  final IconData icon;
  final Color color;
  final String name;
  final String rarity;
  final String desc;
  final String price;
  final bool gold;
  final int owned;
}

const _powerUps = [
  _PowerUp(icon: Icons.bolt, color: AuraColors.brandPurple, name: 'Double XP', rarity: 'EPIC', desc: '2× XP for the next hour', price: '500', gold: true, owned: 2),
  _PowerUp(icon: Icons.autorenew, color: AuraColors.brandPink, name: 'Extra Spins', rarity: 'RARE', desc: '+3 Lucky Wheel spins', price: '300', gold: true),
  _PowerUp(icon: Icons.shield_outlined, color: AuraColors.storeBlueA, name: 'Streak Shield', rarity: 'LEGENDARY', desc: 'Protect your streak once', price: '1,200', gold: false, owned: 1),
  _PowerUp(icon: Icons.lightbulb_outline, color: AuraColors.gold, name: 'Hint Boost', rarity: 'RARE', desc: 'Reveal one clue per match', price: '800', gold: false),
  _PowerUp(icon: Icons.schedule, color: AuraColors.green, name: 'Time Freeze', rarity: 'COMMON', desc: '+15 seconds on the clock', price: '600', gold: false, owned: 3),
];

class _PowerUpsTab extends StatelessWidget {
  const _PowerUpsTab({required this.onBuy});
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: [
        _Banner(
          kind: Currency.gems,
          title: 'Power-Ups',
          sub: 'Boosts stack in your inventory',
        ),
        const SizedBox(height: 14),
        for (final p in _powerUps) ...[
          _PowerUpRow(p: p, onBuy: onBuy),
          const SizedBox(height: 11),
        ],
      ],
    );
  }
}

class _PowerUpRow extends StatelessWidget {
  const _PowerUpRow({required this.p, required this.onBuy});
  final _PowerUp p;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: AuraGlass.decoration(radius: 18),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: p.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.color.withValues(alpha: 0.4)),
                ),
                child: Icon(p.icon, color: p.color, size: 24),
              ),
              if (p.owned > 0)
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
                      '×${p.owned}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        color: Color(0xFF0A0816),
                      ),
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
                    _RarityChip(p.rarity, color: p.color),
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

class _VipTab extends StatelessWidget {
  const _VipTab();

  static const _perks = [
    'Remove all ads forever',
    '2× match rewards',
    'Daily 500 Gold bonus',
    'Exclusive avatars & frames',
    'Priority matchmaking',
    'Gold VIP badge',
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: [
        Row(
          children: const [
            Expanded(child: _VipTierCard(name: 'Free', price: '\$0', per: 'forever', icon: Icons.shield_outlined, tint: Color(0xFF94A3B8))),
            SizedBox(width: 10),
            Expanded(child: _VipTierCard(name: 'Silver', price: '\$4.99', per: '/ month', icon: Icons.star, tint: Color(0xFFE2E8F0))),
            SizedBox(width: 10),
            Expanded(child: _VipTierCard(name: 'Gold', price: '\$9.99', per: '/ month', icon: Icons.workspace_premium, tint: AuraColors.goldLight, selected: true)),
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
                          'GOLD PLAN INCLUDES',
                          style: AuraText.section.copyWith(letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('\$9.99', style: AuraText.numeric.copyWith(fontSize: 30)),
                            const SizedBox(width: 6),
                            Text('/ month', style: AuraText.cardSub),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: AuraGradients.goldCoin,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                    ),
                    child: const Icon(Icons.workspace_premium, color: Color(0xFF7C2D12), size: 28),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: AuraColors.glassStroke),
              const SizedBox(height: 14),
              for (final perk in _perks) ...[
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AuraColors.green.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 13, color: AuraColors.green),
                    ),
                    const SizedBox(width: 11),
                    Expanded(child: Text(perk, style: AuraText.body.copyWith(fontSize: 14))),
                  ],
                ),
                const SizedBox(height: 11),
              ],
              const SizedBox(height: 4),
              Builder(
                builder: (context) => _GoldSubscribeButton(
                  onTap: () => showAuraToast(context, 'VIP Gold activated', kind: AuraToastKind.gold),
                ),
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

/// Gold-gradient VIP subscribe button (mockup: "Subscribe · $9.99 / month").
class _GoldSubscribeButton extends StatelessWidget {
  const _GoldSubscribeButton({required this.onTap});
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
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AuraGradients.goldCoin,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: AuraColors.gold.withValues(alpha: 0.35),
                  blurRadius: 24,
                  spreadRadius: -6,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Text(
              'Subscribe · \$9.99 / month',
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: const Color(0xFF1A1206),
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
    required this.name,
    required this.price,
    required this.per,
    required this.icon,
    required this.tint,
    this.selected = false,
  });

  final String name;
  final String price;
  final String per;
  final IconData icon;
  final Color tint;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: AuraGlass.decoration(
        radius: AuraRadii.lg,
        border: selected ? AuraColors.goldLight.withValues(alpha: 0.7) : null,
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tint.withValues(alpha: 0.5)),
            ),
            child: Icon(icon, color: tint, size: 22),
          ),
          const SizedBox(height: 10),
          Text(name, style: AuraText.cardTitle.copyWith(fontSize: 15)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(price, style: AuraText.numeric.copyWith(fontSize: 16)),
          ),
          Text(per, style: AuraText.caption),
        ],
      ),
    );
  }
}
