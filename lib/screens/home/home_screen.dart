import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/main_shell.dart';
import '../../app/routes.dart';
import '../../data/repositories/store_repository.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';
import '../match/online_play_sheet.dart';

/// Home tab (v2). Body only — MainShell provides the background, SafeArea and
/// bottom nav. The HUD header is a fixed (sticky) block; everything below it
/// scrolls. See docs/DESIGN_SPEC.md §4.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _adClosed = false;

  void _openMatchFlow() => showOnlinePlaySheet(context, onBuyMore: () => _selectTab(2));

  /// Switch bottom-tab via the shell (no-op outside MainShell, e.g. in tests).
  void _selectTab(int i) => MainShellScope.maybeOf(context)?.selectTab(i);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Sticky HUD ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: _ProfileHeaderCard(
            onProfile: () => _selectTab(3),
            onBell: () => Navigator.pushNamed(context, Routes.inbox),
            onShop: () => _selectTab(2),
          ),
        ),
        // ── Scrolling content ──
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            children: [
              // Game-picker chips removed: Chess is the only available game, so
              // play launches directly via Online Play / Quick Play below.
              _FeaturedHero(onTap: _openMatchFlow),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _QuickTile(
                      icon: Icons.play_arrow_rounded,
                      iconColor: AuraColors.green,
                      title: 'Quick Play',
                      sub: 'Play vs computer',
                      minHeight: 122,
                      onTap: () => Navigator.pushNamed(context, Routes.chessSetup),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickTile(
                      icon: Icons.group_rounded,
                      iconColor: AuraColors.brandPurple,
                      title: 'Friends',
                      sub: 'Play with a room code',
                      minHeight: 122,
                      onTap: () async {
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
              const SizedBox(height: 20),
              const SectionBar('Earn rewards'),
              const SizedBox(height: 10),
              _SeasonPassCard(
                onTap: () async {
                  // Season Pass pops 'store' from "Buy more".
                  final r = await Navigator.pushNamed(context, Routes.seasonPass);
                  if (r == 'store') _selectTab(2);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _RewardTile(
                      icon: Icons.calendar_today_rounded,
                      iconGradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                      ),
                      glowColor: AuraColors.brandPurple,
                      title: 'Daily Bonus',
                      sub: 'Day 3 ready',
                      chipColor: AuraColors.accentGlow,
                      onTap: () => Navigator.pushNamed(context, Routes.dailyRewards),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _RewardTile(
                      icon: Icons.track_changes,
                      iconGradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFEC4899), Color(0xFFF472B6)],
                      ),
                      glowColor: AuraColors.brandPink,
                      title: 'Lucky Wheel',
                      sub: '3 spins left',
                      chipColor: AuraColors.brandPink,
                      onTap: () => _selectTab(1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _RecentMatchesButton(
                onTap: () => Navigator.pushNamed(context, Routes.gameHistory),
              ),
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
    final wallet = ref.watch(walletProvider).maybeWhen(data: (w) => w, orElse: () => null);
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
                    child: CurrencyPill(kind: Currency.gems, amount: wallet?.gems ?? '5,000'),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onShop,
                    child: CurrencyPill(kind: Currency.gold, amount: wallet?.gold ?? '2,000'),
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
  const _ProgressBar({required this.fraction, this.height = 10});
  final double fraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: height,
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

class _FeaturedHero extends StatelessWidget {
  const _FeaturedHero({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
                    'FEATURED',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const AuraBadge('2P', color: Colors.white), // chess is always 2 players
                ],
              ),
              const SizedBox(height: 10),
              Text('Online Play', style: AuraText.title.copyWith(color: Colors.white)),
              const SizedBox(height: 6),
              Text(
                'Chess · stake to enter, winner takes the pot',
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
                  const Text(
                    'Play',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
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

/// Reward tile (Daily Bonus / Lucky Wheel). Matches the mockup exactly: glass
/// box (r20) with a radial glow bleeding from the top-right corner, a solid
/// gradient icon chip (46×46, r14) with a coloured glow, title, and a pill.
class _RewardTile extends StatelessWidget {
  const _RewardTile({
    required this.icon,
    required this.iconGradient,
    required this.glowColor,
    required this.title,
    required this.sub,
    required this.onTap,
    this.chipColor,
  });

  final IconData icon;

  /// Diagonal (135°) gradient filling the icon chip.
  final Gradient iconGradient;

  /// Drives both the icon chip's glow shadow and the corner radial glow.
  final Color glowColor;
  final String title;
  final String sub;
  final VoidCallback onTap;

  /// When set, the subtitle renders as a coloured pill chip (Daily/Wheel style).
  final Color? chipColor;

  /// Box min-height so the two tiles line up (mockup: 148).
  static const double _minHeight = 148;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          // Solid gradient icon chip with a coloured drop glow.
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: iconGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.6),
                  blurRadius: 18,
                  spreadRadius: -6,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const Spacer(),
          Text(title, style: AuraText.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          if (chipColor != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: chipColor!.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                sub,
                style: TextStyle(color: chipColor, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            )
          else
            Text(sub, style: AuraText.cardSub, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          decoration: AuraGlass.decoration(radius: 20),
          // Clip so the corner glow bleeds to the rounded edge (overflow: hidden).
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Positioned(
                  top: -20,
                  right: -20,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [glowColor.withValues(alpha: 0.3), Colors.transparent],
                        stops: const [0.0, 0.7],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: double.infinity, height: _minHeight, child: content),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Single glass "Recent matches" row → game history (matches the mockup, which
/// has one entry point here rather than an inline match list).
class _RecentMatchesButton extends StatelessWidget {
  const _RecentMatchesButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.history_rounded, size: 20, color: AuraColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Recent matches',
              style: AuraText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Icon(Icons.chevron_right, size: 22, color: AuraColors.textPrimary.withValues(alpha: 0.4)),
        ],
      ),
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
                Text('Tournaments', style: AuraText.cardTitle),
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
        children: const [
          _Dot(color: AuraColors.green),
          SizedBox(width: 5),
          Text(
            'LIVE',
            style: TextStyle(color: AuraColors.green, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
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
  const _AdBanner({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
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

class _SeasonPassCard extends StatelessWidget {
  const _SeasonPassCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Layout mirrors the mockup: gradient wave-icon tile on the left, then a
    // column with (title · Tier) → XP bar → (xp / rewards-to-claim).
    return AuraCard(
      onTap: onTap,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AuraColors.brandPurple.withValues(alpha: 0.26),
          AuraColors.brandPink.withValues(alpha: 0.10),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AuraGradients.brand,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: AuraColors.brandPink.withValues(alpha: 0.5),
                  blurRadius: 18,
                  spreadRadius: -6,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.waves_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Season 4 · Neon Tide',
                        style: AuraText.cardTitle.copyWith(fontSize: 14.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Tier 12',
                      style: TextStyle(color: AuraColors.accentGlow, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const _ProgressBar(fraction: 0.72, height: 6),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text('720 / 1,000 XP', style: AuraText.cardSub.copyWith(fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '3 rewards to claim',
                      style: TextStyle(color: AuraColors.goldLight, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

