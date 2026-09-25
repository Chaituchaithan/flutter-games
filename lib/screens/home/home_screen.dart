import 'package:flutter/material.dart';

import '../../app/main_shell.dart';
import '../../app/routes.dart';
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
              _GameChipsStrip(onTapGame: _openMatchFlow),
              const SizedBox(height: 14),
              _FeaturedHero(onTap: _openMatchFlow),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _QuickTile(
                      icon: Icons.play_arrow_rounded,
                      iconColor: AuraColors.green,
                      title: 'Quick Play',
                      sub: 'Free practice match',
                      minHeight: 122,
                      onTap: _openMatchFlow,
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
                      onTap: () => Navigator.pushNamed(context, Routes.playFriends),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _TournamentsRow(onTap: () => Navigator.pushNamed(context, Routes.tournaments)),
              if (!_adClosed) ...[
                const SizedBox(height: 14),
                _AdBanner(onClose: () => setState(() => _adClosed = true)),
              ],
              const SizedBox(height: 20),
              const SectionBar('Earn rewards'),
              const SizedBox(height: 10),
              _SeasonPassCard(
                onTap: () => Navigator.pushNamed(context, Routes.seasonPass),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuickTile(
                      icon: Icons.calendar_today_rounded,
                      iconColor: AuraColors.brandPurple,
                      title: 'Daily Bonus',
                      sub: 'Day 3 ready',
                      chipColor: AuraColors.accentGlow,
                      minHeight: 148,
                      onTap: () => Navigator.pushNamed(context, Routes.dailyRewards),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickTile(
                      icon: Icons.track_changes,
                      iconColor: AuraColors.brandPink,
                      title: 'Lucky Wheel',
                      sub: '3 spins left',
                      chipColor: AuraColors.brandPink,
                      minHeight: 148,
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

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.onProfile,
    required this.onBell,
    required this.onShop,
  });

  final VoidCallback onProfile;
  final VoidCallback onBell;
  final VoidCallback onShop;

  @override
  Widget build(BuildContext context) {
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
                      const AuraAvatar(initials: 'NR', size: 50, level: 7),
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
                                    'Nova Rider',
                                    style: AuraText.cardTitle,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text('🇫🇷', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text('@nova_rider', style: AuraText.cardSub.copyWith(fontSize: 12)),
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
                    child: const CurrencyPill(kind: Currency.gems, amount: '5,000'),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onShop,
                    child: const CurrencyPill(kind: Currency.gold, amount: '2,000'),
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
                  'LV 7',
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: AuraColors.accentGlow,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(child: _ProgressBar(fraction: 0.65)),
              const SizedBox(width: 10),
              Text('1,300 / 2,000', style: AuraText.cardSub.copyWith(fontSize: 11)),
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
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameChipsStrip extends StatelessWidget {
  const _GameChipsStrip({required this.onTapGame});
  final VoidCallback onTapGame;

  static const _games = [
    (Icons.extension, 'Chess'),
    (Icons.stairs, 'Snakes'),
    (Icons.casino, 'Ludo'),
    (Icons.circle, 'Othello'),
    (Icons.abc, 'Scrabble'),
    (Icons.bolt, 'Trivia Duel'),
  ];

  @override
  Widget build(BuildContext context) {
    // 3-column grid (6 games → 2 rows), matching the mockup.
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.9,
      children: [
        for (final g in _games) _GameChip(icon: g.$1, label: g.$2, onTap: onTapGame),
      ],
    );
  }
}

class _GameChip extends StatelessWidget {
  const _GameChip({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
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
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: AuraGlass.decoration(radius: 12, shadow: false),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AuraColors.accentGlow),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AuraColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
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
                  const AuraBadge('2P · 4P', color: Colors.white),
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
                    child: const Text(
                      '♦ 50 – 5K',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
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

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.sub,
    required this.onTap,
    this.chipColor,
    this.minHeight,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String sub;
  final VoidCallback onTap;

  /// When set, the subtitle renders as a coloured pill chip (Daily/Wheel style).
  final Color? chipColor;

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
    );
    return AuraCard(
      onTap: onTap,
      child: minHeight == null ? content : SizedBox(height: minHeight, child: content),
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
          const Text(
            'Banner placement',
            style: TextStyle(color: AuraColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
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

