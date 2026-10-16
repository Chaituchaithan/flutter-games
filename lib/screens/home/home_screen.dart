import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/main_shell.dart';
import '../../app/routes.dart';
import '../../services/session.dart';
import '../../l10n/l10n.dart';
import '../../widgets/aura.dart';
import '../../widgets/wallet_pill.dart';
import '../match/online_play_sheet.dart';
import '../../app/app_profile.dart';
import '../../app/game_area.dart';
import '../../configs/games/games.dart';

/// Home tab (v2). Body only — MainShell provides the background, SafeArea and
/// bottom nav. The HUD header is a fixed (sticky) block; everything below it
/// scrolls. See docs/DESIGN_SPEC.md.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _adClosed = false;

  void _openMatchFlow() {
    if (!_hasOnline()) return;
    showOnlinePlaySheet(context, onBuyMore: () => _selectTab(2));
  }

  /// Online play / rooms exist for the active game; otherwise say so (Quick
  /// Play still works) instead of doing nothing.
  bool _hasOnline() {
    final game = ProviderScope.containerOf(context).read(activeGameConfigProvider);
    if (GameArea.onlineRoute(game.id) != null) return true;
    showAuraToast(context, context.l10n.onlineComingSoon(game.displayName), kind: AuraToastKind.info);
    return false;
  }

  Widget _quickPlayTile(BuildContext context) => _QuickTile(
    icon: Icons.play_arrow_rounded,
    iconColor: AuraColors.green,
    title: context.l10n.quickPlay,
    sub: context.l10n.quickPlaySub,
    minHeight: 122,
    onTap: () {
      // The active game's practice / vs-computer setup.
      final route = GameArea.practiceRoute(ProviderScope.containerOf(context).read(activeGameProvider));
      if (route != null) Navigator.pushNamed(context, route);
    },
  );

  Widget _friendsTile(BuildContext context) => _QuickTile(
    icon: Icons.group_rounded,
    iconColor: AuraColors.brandPurple,
    title: context.l10n.friends,
    sub: context.l10n.friendsSub,
    minHeight: 122,
    onTap: () async {
      if (!_hasOnline()) return;
      // Play with Friends pops 'store' from its "Buy more".
      final r = await Navigator.pushNamed(context, Routes.playFriends);
      if (r == 'store') _selectTab(2);
    },
  );

  Widget _tournaments(BuildContext context) => _TournamentsRow(
    onTap: () async {
      // Tournaments pops 'store' from "Buy more".
      final r = await Navigator.pushNamed(context, Routes.tournaments);
      if (r == 'store') _selectTab(2);
    },
  );

  /// Single-game Home: Online Play, Quick Play + Friends, Tournaments and
  /// the banner on one screen. Cards keep their normal size; spare height
  /// sits above the banner at the bottom. On short
  /// phones the banner goes first, and only if it still doesn't fit does the
  /// page scroll (nothing is ever cut off).
  Widget _singleGameBody(BuildContext context) {
    const gap = 12.0;
    return LayoutBuilder(
      builder: (context, box) {
        // Short phones drop the banner first (the core actions stay).
        final banner = !_adClosed && box.maxHeight >= 440;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(kPageGutter, 12, kPageGutter, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 24),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cards at their normal design size (never stretched).
                  _FeaturedHero(onTap: _openMatchFlow),
                  const SizedBox(height: gap),
                  Row(
                    children: [
                      Expanded(child: _quickPlayTile(context)),
                      const SizedBox(width: gap),
                      Expanded(child: _friendsTile(context)),
                    ],
                  ),
                  const SizedBox(height: gap),
                  _tournaments(context),
                  // Spare height sits above the banner (an ad slot at the
                  // bottom, just over the bottom bar).
                  const Spacer(),
                  if (banner) ...[
                    const SizedBox(height: gap),
                    _AdBanner(compact: true, onClose: () => setState(() => _adClosed = true)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Switch bottom-tab via the shell (no-op outside MainShell, e.g. in tests).
  void _selectTab(int i) => MainShellScope.maybeOf(context)?.selectTab(i);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Sticky HUD ──
        Padding(
          padding: const EdgeInsets.fromLTRB(kPageGutter, 8, kPageGutter, 0),
          child: _ProfileHeaderCard(
            onProfile: () => _selectTab(3),
            onBell: () => Navigator.pushNamed(context, Routes.inbox),
            onShop: () => _selectTab(2),
          ),
        ),
        // ── Single-game app: one screen, no scrolling ──
        if (AppProfile.current.singleGame)
          Expanded(child: _singleGameBody(context))
        else
        // ── All games: scrolling content ──
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(kPageGutter, 14, kPageGutter, 20),
            children: [
              // Mockup game chips: pick the active game (registry-driven).
              // Games without a built game area show as "Soon".
              // A single-game app has no game picker.
              if (!AppProfile.current.singleGame) const _GameChips(),
              const SizedBox(height: 14),
              _FeaturedHero(onTap: _openMatchFlow),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _QuickTile(
                      icon: Icons.play_arrow_rounded,
                      iconColor: AuraColors.green,
                      title: context.l10n.quickPlay,
                      sub: context.l10n.quickPlaySub,
                      minHeight: 122,
                      onTap: () {
                        // The active game's practice / vs-computer setup.
                        final route = GameArea.practiceRoute(ProviderScope.containerOf(context).read(activeGameProvider));
                        if (route != null) Navigator.pushNamed(context, route);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickTile(
                      icon: Icons.group_rounded,
                      iconColor: AuraColors.brandPurple,
                      title: context.l10n.friends,
                      sub: context.l10n.friendsSub,
                      minHeight: 122,
                      onTap: () async {
                        if (!_hasOnline()) return;
                        // Play with Friends pops 'store' from its "Buy more".
                        final r = await Navigator.pushNamed(context, Routes.playFriends);
                        if (r == 'store') _selectTab(2);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _TournamentsRow(
                onTap: () async {
                  // Tournaments pops 'store' from "Buy more".
                  final r = await Navigator.pushNamed(context, Routes.tournaments);
                  if (r == 'store') _selectTab(2);
                },
              ),
              if (!_adClosed) ...[
                const SizedBox(height: 14),
                _AdBanner(onClose: () => setState(() => _adClosed = true)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// HUD (mockup): avatar + level, name + country flag, @handle, bell, wallet
/// pills, then the level/XP bar — all from the signed-in player and wallet.
class _ProfileHeaderCard extends ConsumerWidget {
  const _ProfileHeaderCard({
    required this.onProfile,
    required this.onBell,
    required this.onShop,
  });

  final VoidCallback onProfile;
  final VoidCallback onBell;
  final VoidCallback onShop;

  static String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  /// "IN" → 🇮🇳.
  static String _flag(String code) =>
      String.fromCharCodes(code.toUpperCase().codeUnits.map((u) => 0x1F1E6 + u - 0x41));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final country = user.country;
    return AuraCard(
      child: Column(
        children: [
          Row(
            children: [
              // Avatar + name/handle → Profile.
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onProfile,
                  child: Row(
                    children: [
                      AuraAvatar(initials: user.initials, size: 50, level: user.level),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    user.displayName,
                                    style: AuraText.cardTitle,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (country != null && country.length == 2) ...[
                                  const SizedBox(width: 6),
                                  Text(_flag(country), style: const TextStyle(fontSize: 13)),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(user.handle, overflow: TextOverflow.ellipsis, style: AuraText.cardSub.copyWith(fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _NotificationBell(count: '6', onTap: onBell),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: onShop,
                    child: const WalletPill(kind: Currency.gems),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onShop,
                    child: const WalletPill(kind: Currency.gold),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AuraColors.accentGlow.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  'LV ${user.level}',
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: AuraColors.accentGlow,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _ProgressBar(fraction: user.xpFraction)),
              const SizedBox(width: 10),
              Text('${_fmt(user.xp)} / ${_fmt(user.xpMax)}', style: AuraText.cardSub.copyWith(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.count, required this.onTap});
  final String count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: onTap,
              child: DecoratedBox(
                decoration: AuraGlass.decoration(radius: 13, shadow: false),
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.notifications_none_rounded, size: 19, color: AuraColors.textPrimary),
                ),
              ),
            ),
          ),
          Positioned(
            top: -5,
            right: -5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AuraColors.brandPink, AuraColors.danger]),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: AuraColors.bgBase, width: 2),
              ),
              child: Text(
                count,
                style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 10,
        color: Colors.white.withValues(alpha: 0.1),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction,
          child: Container(
            decoration: BoxDecoration(
              gradient: AuraGradients.brand,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedHero extends ConsumerWidget {
  const _FeaturedHero({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(activeGameConfigProvider);
    return AuraCard(
      gradient: AuraGradients.brandDeep,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            top: -30,
            right: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.l10n.featured,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  AuraBadge(game.playersLabel, color: Colors.white),
                ],
              ),
              const SizedBox(height: 10),
              Text(context.l10n.onlinePlay, style: AuraText.title.copyWith(color: Colors.white)),
              const SizedBox(height: 6),
              Text(
                context.l10n.onlinePlaySub(game.displayName),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13.5),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '♦ 50 – 5K',
                      style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    context.l10n.play,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}

/// Plain action tile (Quick Play / Friends): glass box with a translucent
/// bordered icon tile, title and a muted subtitle. No glow/pill.
class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.sub,
    required this.onTap,
    this.minHeight,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String sub;
  final VoidCallback onTap;

  /// Optional fixed content height so tiles line up (mockup min-height).
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: minHeight == null ? MainAxisSize.min : MainAxisSize.max,
      children: [
        _IconTile(icon: icon, color: iconColor),
        if (minHeight == null) const SizedBox(height: 12) else const Spacer(),
        Text(title, style: AuraText.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        Text(sub, style: AuraText.cardSub, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
    return AuraCard(
      onTap: onTap,
      child: minHeight == null ? content : SizedBox(height: minHeight, child: content),
    );
  }
}


class _TournamentsRow extends StatelessWidget {
  const _TournamentsRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      onTap: onTap,
      child: Row(
        children: [
          const _IconTile(icon: Icons.emoji_events, color: AuraColors.gold),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.tournaments, style: AuraText.cardTitle),
                const SizedBox(height: 2),
                Text('Neon Cup live · 50,000 prize pool', style: AuraText.cardSub),
              ],
            ),
          ),
          const _LiveBadge(),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AuraColors.green.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AuraColors.green.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Dot(color: AuraColors.green),
          const SizedBox(width: 5),
          Text(
            context.l10n.live,
            style: const TextStyle(color: AuraColors.green, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _AdBanner extends StatelessWidget {
  const _AdBanner({required this.onClose, this.compact = false});
  final VoidCallback onClose;

  /// A real 320×50-style strip (single-game Home) instead of the card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        height: 56,
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
        decoration: BoxDecoration(
          color: AuraColors.card.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AuraColors.textSecondary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
              child: Text('AD', style: AuraText.cardSub.copyWith(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Banner placement',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  Text('House ad fallback · remove with VIP', maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.cardSub.copyWith(fontSize: 11.5)),
                ],
              ),
            ),
            IconButton(
              onPressed: onClose,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 16, color: AuraColors.textPrimary.withValues(alpha: 0.6)),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AuraColors.card.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AuraColors.textSecondary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'AD · 320 × 50',
                style: AuraText.cardSub.copyWith(fontSize: 11, letterSpacing: 0.5),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: Icon(Icons.close, size: 12, color: AuraColors.textPrimary.withValues(alpha: 0.6)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Banner placement',
            style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text('House ad fallback · remove with VIP', style: AuraText.cardSub),
        ],
      ),
    );
  }
}

/// Game-chip row (scrolls sideways to the screen edges): every registered game. The active one is highlighted;
/// tapping a playable game switches to it, others show "Soon" and a toast.
class _GameChips extends ConsumerWidget {
  const _GameChips();

  /// This app's games, then (dev build) the not-yet-built ones as "Soon".
  static List<GameConfig> get _chips {
    final profile = AppProfile.current;
    return [
      for (final m in profile.modules) m.config,
      if (profile.showComingSoon)
        for (final g in GameRegistry.homeChips)
          if (!profile.includes(g.id)) g,
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeGameProvider);
    final chips = _chips;
    // One sideways-scrolling row running to the screen edges (12 games no
    // longer wrap into four rows); the active game is scrolled into view.
    return SizedBox(
      height: 38,
      child: EdgeBleed(
        builder: (pad) => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: pad,
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final g = chips[i];
            return _GameChip(
              game: g,
              selected: g.id == active,
              onTap: () {
                if (GameRegistry.isAvailable(g.id)) {
                  ref.read(activeGameProvider.notifier).select(g.id);
                  Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
                } else {
                  showAuraToast(context, context.l10n.gameComingSoon(g.displayName), kind: AuraToastKind.info);
                }
              },
            );
          },
        ),
      ),
    );
  }
}

class _GameChip extends StatelessWidget {
  const _GameChip({required this.game, required this.selected, required this.onTap});
  final GameConfig game;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: GameRegistry.isAvailable(game.id) ? 1 : 0.55,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: selected ? AuraGradients.brand : null,
            color: selected ? null : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withValues(alpha: selected ? 0.4 : 0.16)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(game.icon, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(
                game.chipName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 11.5, color: Colors.white),
              ),
              if (!GameRegistry.isAvailable(game.id)) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                  child: Text(context.l10n.soon, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
