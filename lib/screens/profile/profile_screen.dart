import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/main_shell.dart';
import '../../app/routes.dart';
import '../../data/languages.dart';
import '../../data/models/user.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';

/// Profile tab (v2). Returns a body only — MainShell provides the background,
/// SafeArea and bottom nav. The app-bar gear opens Settings via Routes.settings.
/// Identity comes from the session (`currentUserProvider`). See docs/DESIGN_SPEC.md.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// Bottom-nav index of this tab in MainShell.
  static const _tabIndex = 3;

  @override
  Widget build(BuildContext context) {
    // MainShell builds every tab up front, so re-read account + profile when
    // the player actually opens this tab — not at Home right after login
    // (login just fetched them; reloadProfile skips data under a minute old).
    ref.listen<int>(mainTabProvider, (prev, next) {
      if (next == _tabIndex && prev != _tabIndex) ref.read(sessionProvider.notifier).reloadProfile();
    });
    final user = ref.watch(currentUserProvider);
    return Column(
      children: [
        AuraAppBar(
          title: 'Profile',
          showBack: false,
          trailing: CircleActionButton(
            icon: Icons.settings,
            onTap: () => Navigator.pushNamed(context, Routes.settings),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AuraColors.accentGlow,
            backgroundColor: const Color(0xFF1A1330),
            onRefresh: () => ref.read(sessionProvider.notifier).reloadProfile(force: true),
            child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _HeaderCard(
                user: user,
                onEdit: () => Navigator.pushNamed(context, Routes.editProfile),
              ),
              const SizedBox(height: 14),
              // 1) Top stat tiles (icon + corner glow, mockup colours).
              Row(
                children: [
                  const Expanded(child: _ProfileStat(icon: Icons.grid_view_rounded, color: AuraColors.accentGlow, value: '248', label: 'Matches')),
                  const SizedBox(width: 10),
                  const Expanded(child: _ProfileStat(icon: Icons.emoji_events_outlined, color: AuraColors.green, value: '169', label: 'Wins')),
                  const SizedBox(width: 10),
                  const Expanded(child: _ProfileStat(icon: Icons.local_fire_department, color: AuraColors.brandOrange, value: '7', label: 'Streak')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pushNamed(context, Routes.leaderboard),
                      child: const _ProfileStat(icon: Icons.leaderboard_outlined, color: AuraColors.gems, value: '#412', label: 'Rank'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 2) Win-rate ring + weekly bars.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    Expanded(child: _WinRateCard()),
                    SizedBox(width: 12),
                    Expanded(child: _WeeklyCard()),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // 3) Game stats (per-mode coloured bars + Best streak/Tokens/Gold grid).
              const SectionBar('Game stats'),
              const SizedBox(height: 12),
              const _GameStatsCard(),
              const SizedBox(height: 20),
              // 4) Achievements — "See all" navigates to the full list.
              SectionBar(
                'Achievements',
                trailing: GestureDetector(
                  onTap: () => Navigator.pushNamed(context, Routes.achievements),
                  child: const Text(
                    'See all  4 / 12 ›',
                    style: TextStyle(color: AuraColors.accentGlow, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: const [
                  Expanded(child: _Achievement(icon: Icons.emoji_events, colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)], label: 'First Win')),
                  SizedBox(width: 12),
                  Expanded(child: _Achievement(icon: Icons.local_fire_department, colors: [Color(0xFFFB923C), Color(0xFFF43F5E)], label: 'On Fire')),
                  SizedBox(width: 12),
                  Expanded(child: _Achievement(icon: Icons.gps_fixed, colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)], label: 'Sharpshooter')),
                  SizedBox(width: 12),
                  Expanded(child: _Achievement(icon: Icons.add, label: '9 more', muted: true)),
                ],
              ),
              const SizedBox(height: 20),
              // 5) Manage.
              const SectionBar('Manage'),
              const SizedBox(height: 12),
              _ManageCard(
                onSettings: () => Navigator.pushNamed(context, Routes.settings),
              ),
            ],
          ),
          ),
        ),
      ],
    );
  }
}

/// Top profile stat box: glass card with a coloured icon, value, label and a
/// soft corner glow tinted to the stat (mockup).
class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.icon, required this.color, required this.value, required this.label});
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: AuraGlass.decoration(radius: 18),
        child: Stack(
          // Centre the (min-width) content block; the Stack defaults to
          // top-left, which was pinning icon/number/label to the left edge.
          alignment: Alignment.center,
          children: [
            // Soft corner glow (mockup: tile colour @ 0.18, softly blurred).
            Positioned(
              top: -16,
              right: -16,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [color.withValues(alpha: 0.18), Colors.transparent],
                    stops: const [0.0, 0.85],
                  ),
                ),
              ),
            ),
            // Full-width so crossAxisAlignment.center truly centres the content
            // (a min-width Column would hug the left edge).
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(value, style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 3),
                    Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Color(0x8CF4F1FB), fontSize: 10.5)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.user, required this.onEdit});
  final User user;
  final VoidCallback onEdit;

  static String _comma(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  @override
  Widget build(BuildContext context) {
    // Purple→pink gradient hero card with a pink corner glow (mockup hero).
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x478B5CF6), Color(0x1FEC4899), Color(0x08FFFFFF)], // 0.28 / 0.12 / 0.03
            stops: [0.0, 0.6, 1.0],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AuraColors.accentGlow.withValues(alpha: 0.45), width: 1.5),
        ),
        child: Stack(
          children: [
            // Pink glow bleeding from the top-right corner.
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [AuraColors.brandPink.withValues(alpha: 0.35), Colors.transparent],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HeroAvatar(user: user, onEditAvatar: () => Navigator.pushNamed(context, Routes.avatars)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _MiniBadge('LV ${user.level}', color: AuraColors.accentGlow),
                                if (user.isGuest) const _MiniBadge('GUEST', color: AuraColors.gold),
                                Text(user.displayName, style: AuraText.title.copyWith(fontSize: 20)),
                                // Country flag beside the name (mockup), once set.
                                if (user.country != null && user.country!.length == 2)
                                  Text(_flag(user.country!), style: const TextStyle(fontSize: 15)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(user.handle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.cardSub.copyWith(fontSize: 12.5)),
                            const SizedBox(height: 6),
                            // Language + birthday from the profile.
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                Consumer(
                                  builder: (_, ref, _) => _InfoChip(icon: Icons.translate_rounded, text: _languageText(user, ref)),
                                ),
                                if (DateTime.tryParse(user.dateOfBirth ?? '') case final dob?)
                                  _InfoChip(icon: Icons.cake_outlined, text: _birthdayText(dob)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // No bio yet (new accounts) → a prompt instead of empty quotes.
                            if (user.bio.trim().isEmpty)
                              GestureDetector(
                                onTap: onEdit,
                                child: const Text(
                                  '+ Add a bio',
                                  style: TextStyle(color: AuraColors.accentGlow, fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                              )
                            else
                              Text(
                                '"${user.bio}"',
                                style: const TextStyle(
                                  color: AuraColors.textSecondary,
                                  fontSize: 12.5,
                                  fontStyle: FontStyle.italic,
                                  height: 1.4,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Rank bar: tier badge + XP progress + XP text.
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: AuraColors.amber.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AuraColors.amber.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, color: AuraColors.amber, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              user.tier.toUpperCase(),
                              style: TextStyle(
                                fontFamily: AuraText.displayFamily,
                                color: AuraColors.amber,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(flex: 3, child: _ProgressBar(fraction: user.xpFraction)),
                      const SizedBox(width: 9),
                      // Shrinks on narrow phones instead of overflowing.
                      Flexible(
                        flex: 2,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text('${_comma(user.xp)} / ${_comma(user.xpMax)} XP', style: AuraText.cardSub.copyWith(fontSize: 11)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _EditProfileButton(onTap: onEdit),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 92px hero avatar: conic XP ring, dark gap, gradient initials disc, and an
/// edit-avatar pencil button (mockup).
class _HeroAvatar extends StatelessWidget {
  const _HeroAvatar({required this.user, required this.onEditAvatar});
  final User user;
  final VoidCallback onEditAvatar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Conic ring (XP) with a glow.
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AuraColors.accentGlow.withValues(alpha: 0.6), blurRadius: 26, spreadRadius: -4)],
              gradient: SweepGradient(
                startAngle: -1.5708,
                endAngle: 4.7124,
                colors: [AuraColors.accentGlow, AuraColors.accentGlow, Colors.white.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0.14)],
                stops: [0.0, user.xpFraction, user.xpFraction, 1.0],
              ),
            ),
          ),
          // Dark gap.
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0C0A16))),
            ),
          ),
          // Gradient initials disc.
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.lerp(user.color, Colors.white, 0.1)!, Color.lerp(user.color, Colors.black, 0.2)!],
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Text(
                  user.initials,
                  style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          // Edit-avatar pencil button.
          Positioned(
            right: -2,
            bottom: -2,
            child: GestureDetector(
              onTap: onEditAvatar,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)]),
                  border: Border.all(color: const Color(0xFF0C0A16), width: 2.5),
                  boxShadow: [BoxShadow(color: AuraColors.brandPink.withValues(alpha: 0.8), blurRadius: 14, spreadRadius: -4, offset: const Offset(0, 6))],
                ),
                child: const Icon(Icons.edit, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pill badge (e.g. "LV 7") used in the hero.
class _MiniBadge extends StatelessWidget {
  const _MiniBadge(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(7)),
      child: Text(
        text,
        style: TextStyle(fontFamily: AuraText.displayFamily, color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}


/// Dark outline pill with a leading icon — matches [SecondaryButton] styling.
class _EditProfileButton extends StatelessWidget {
  const _EditProfileButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.edit, size: 16, color: AuraColors.textPrimary),
                const SizedBox(width: 8),
                Text(
                  'Edit profile',
                  style: TextStyle(fontFamily: AuraText.bodyFamily, color: AuraColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
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
        color: AuraColors.chipDark,
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

class _WinRateCard extends StatelessWidget {
  const _WinRateCard();

  // Win / Draw / Loss counts drive the tri-colour ring (mockup colours).
  static const _wins = 169, _draws = 21, _losses = 58;
  static const _green = Color(0xFF34D399);
  static const _yellow = Color(0xFFFBBF24);
  static const _red = Color(0xFFFB7185);

  @override
  Widget build(BuildContext context) {
    const total = _wins + _draws + _losses;
    return AuraCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 90,
            height: 90,
            child: CustomPaint(
              painter: const _RingPainter(segments: [
                (color: _green, fraction: _wins / total),
                (color: _yellow, fraction: _draws / total),
                (color: _red, fraction: _losses / total),
              ]),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '68%',
                      style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 23, fontWeight: FontWeight.w700),
                    ),
                    const Text('Win rate', style: TextStyle(color: Color(0x8CF4F1FB), fontSize: 9.5)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // FittedBox keeps the W/D/L legend within the (narrow) half-width card.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                _LegendDot(color: _green, label: 'W $_wins'),
                SizedBox(width: 9),
                _LegendDot(color: _yellow, label: 'D $_draws'),
                SizedBox(width: 9),
                _LegendDot(color: _red, label: 'L $_losses'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Color(0xB3F4F1FB), fontSize: 10, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Segmented (W/D/L) win-rate ring: contiguous green → yellow → red arcs on a
/// dark inner disc, matching the mockup.
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.segments});
  final List<({Color color, double fraction})> segments;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 8.0;
    final center = size.center(Offset.zero);
    final r = size.width / 2 - stroke / 2;
    // Dark inner disc (mockup #0d0b18) so the ring reads as a band.
    canvas.drawCircle(center, r - stroke / 2, Paint()..color = const Color(0xFF0D0B18));
    final rect = Rect.fromCircle(center: center, radius: r);
    var start = -math.pi / 2;
    for (final s in segments) {
      final sweep = 2 * math.pi * s.fraction;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt
          ..color = s.color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.segments != segments;
}

class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard();

  static const _heights = [0.5, 0.75, 0.4, 0.9, 0.6, 1.0, 0.35];
  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Last 7 days',
                  style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white.withValues(alpha: 0.8), fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              const AuraBadge('+12%', color: AuraColors.green),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 74,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_heights.length, (i) {
                // Explicit height (not FractionallySizedBox) so the chart can be
                // measured safely inside the IntrinsicHeight parent.
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Container(
                      height: 74 * _heights[i],
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFC084FC), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(5), bottom: Radius.circular(2)),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: _labels
                .map((l) => Expanded(
                      child: Text(
                        l,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 9.5),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _GameStatsCard extends StatelessWidget {
  const _GameStatsCard();

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      child: Column(
        children: [
          const _GameStatRow(
            label: 'Online 1v1', wins: '61W', losses: '21L', pct: '74%', fraction: 0.74,
            colors: [Color(0xFF8B5CF6), Color(0xFFC084FC)], glow: Color(0xFFC084FC),
          ),
          const SizedBox(height: 16),
          const _GameStatRow(
            label: 'Online 4P', wins: '41W', losses: '30L', pct: '58%', fraction: 0.58,
            colors: [Color(0xFFEC4899), Color(0xFFF472B6)], glow: Color(0xFFF472B6),
          ),
          const SizedBox(height: 16),
          const _GameStatRow(
            label: 'Quick Play', wins: '67W', losses: '28L', pct: '71%', fraction: 0.71,
            colors: [Color(0xFF06B6D4), Color(0xFF67E8F9)], glow: Color(0xFF67E8F9),
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.14)),
          const SizedBox(height: 14),
          // Summary grid (mockup): Best streak / Tokens won / Gold won.
          Row(
            children: const [
              Expanded(child: _MiniStat(value: '12', label: 'Best streak')),
              Expanded(child: _MiniStat(value: '48.2k', label: 'Tokens won', valueColor: Color(0xFF67E8F9), dividers: true)),
              Expanded(child: _MiniStat(value: '3.1k', label: 'Gold won', valueColor: Color(0xFFFBBF24))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Centered value + label used in the Game-stats summary grid. [valueColor]
/// tints the number (mockup: Tokens = cyan, Gold = gold) and [dividers] adds
/// the left/right column separators (used on the middle cell).
class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label, this.valueColor = Colors.white, this.dividers = false});
  final String value;
  final String label;
  final Color valueColor;
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    const divider = BorderSide(color: Color(0x1FFFFFFF)); // white @ 0.12
    return Container(
      decoration: dividers ? const BoxDecoration(border: Border(left: divider, right: divider)) : null,
      child: Column(
        children: [
          Text(value, style: TextStyle(fontFamily: AuraText.displayFamily, color: valueColor, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Color(0x80F4F1FB), fontSize: 10)),
        ],
      ),
    );
  }
}

class _GameStatRow extends StatelessWidget {
  const _GameStatRow({
    required this.label,
    required this.wins,
    required this.losses,
    required this.pct,
    required this.fraction,
    required this.colors,
    required this.glow,
  });

  final String label;
  final String wins;
  final String losses;
  final String pct;
  final double fraction;

  /// Per-mode bar gradient + glow colour (mockup).
  final List<Color> colors;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Text.rich(
              TextSpan(
                style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.textSecondary, fontSize: 13),
                children: [
                  TextSpan(text: '$wins · $losses · '),
                  TextSpan(
                    text: pct,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // No IntrinsicHeight here — FractionallySizedBox is safe.
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Container(
            height: 9,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.53), blurRadius: 12)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Achievement extends StatelessWidget {
  const _Achievement({
    required this.icon,
    required this.label,
    this.colors,
    this.muted = false,
  });

  final IconData icon;
  final String label;

  /// Solid gradient for an unlocked tile (mockup). Null when [muted].
  final List<Color>? colors;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = colors ?? const [Color(0xFF8B5CF6), Color(0xFFEC4899)];
    return Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: muted
              ? BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                )
              : BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  boxShadow: [BoxShadow(color: c.last.withValues(alpha: 0.6), blurRadius: 16, spreadRadius: -6, offset: const Offset(0, 8))],
                ),
          child: Icon(icon, color: muted ? AuraColors.textMuted : Colors.white, size: 22),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AuraColors.textPrimary.withValues(alpha: muted ? 0.4 : 0.7),
            fontSize: 9.5,
          ),
        ),
      ],
    );
  }
}

class _ManageCard extends StatelessWidget {
  const _ManageCard({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    // 2×2 grid of gradient-icon cards (mockup), not a vertical list.
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _ManageTile(icon: Icons.person_outline, colors: const [Color(0xFF8B5CF6), Color(0xFFEC4899)], title: 'Edit profile', sub: 'Name, bio, country', onTap: () => Navigator.pushNamed(context, Routes.editProfile))),
            const SizedBox(width: 10),
            Expanded(child: _ManageTile(icon: Icons.face_retouching_natural, colors: const [Color(0xFF22D3EE), Color(0xFF3B82F6)], title: 'Avatar', sub: 'Choose your look', onTap: () => Navigator.pushNamed(context, Routes.avatars))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _ManageTile(icon: Icons.history_rounded, colors: const [Color(0xFF34D399), Color(0xFF14B8A6)], title: 'Game history', sub: '248 matches', onTap: () => Navigator.pushNamed(context, Routes.gameHistory))),
            const SizedBox(width: 10),
            Expanded(child: _ManageTile(icon: Icons.settings_outlined, colors: const [Color(0xFFFB923C), Color(0xFFF43F5E)], title: 'Settings', sub: 'Sound, alerts, account', onTap: onSettings)),
          ],
        ),
      ],
    );
  }
}

/// A Manage grid card: gradient icon tile + title + sub (mockup).
class _ManageTile extends StatelessWidget {
  const _ManageTile({required this.icon, required this.colors, required this.title, required this.sub, required this.onTap});
  final IconData icon;
  final List<Color> colors;
  final String title;
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
          decoration: AuraGlass.decoration(radius: 18),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.45), blurRadius: 14, spreadRadius: -6, offset: const Offset(0, 6))],
                ),
                child: Icon(icon, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 1),
                    Text(sub, style: TextStyle(color: AuraColors.textPrimary.withValues(alpha: 0.5), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "IN" → 🇮🇳.
String _flag(String code) =>
    String.fromCharCodes(code.toUpperCase().codeUnits.map((u) => 0x1F1E6 + u - 0x41));

/// Profile language, else the app language picked on first launch.
String _languageText(User user, WidgetRef ref) =>
    appLanguages[languageIndexFor(user.preferredLanguage) ?? ref.watch(languageProvider)].english;

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "12 Mar" — the birthday without the year.
String _birthdayText(DateTime d) => '${d.day} ${_monthNames[d.month - 1]}';

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AuraColors.textMuted),
        const SizedBox(width: 4),
        Text(text, style: AuraText.cardSub.copyWith(fontSize: 12)),
      ],
    );
  }
}
