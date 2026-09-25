import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../data/models/user.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';

/// Profile tab (v2). Returns a body only — MainShell provides the background,
/// SafeArea and bottom nav. The app-bar gear opens Settings via Routes.settings.
/// Identity comes from the session (`currentUserProvider`). See docs/DESIGN_SPEC.md §7.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _HeaderCard(
                user: user,
                onEdit: () => Navigator.pushNamed(context, Routes.editProfile),
              ),
              const SizedBox(height: 14),
              // 1) Top stat tiles.
              Row(
                children: [
                  const Expanded(child: StatTile(value: '248', label: 'Matches')),
                  const SizedBox(width: 10),
                  const Expanded(child: StatTile(value: '169', label: 'Wins', valueColor: AuraColors.green)),
                  const SizedBox(width: 10),
                  const Expanded(child: StatTile(value: '7', label: 'Streak', valueColor: AuraColors.amber)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pushNamed(context, Routes.leaderboard),
                      child: const StatTile(value: '#412', label: 'Rank'),
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
              // 3) Game stats.
              const SectionBar('Game stats'),
              const SizedBox(height: 12),
              const _GameStatsCard(),
              const SizedBox(height: 12),
              Row(
                children: const [
                  Expanded(child: StatTile(value: '12', label: 'Best streak')),
                  SizedBox(width: 10),
                  Expanded(child: StatTile(value: '48.2k', label: 'Tokens won')),
                  SizedBox(width: 10),
                  Expanded(child: StatTile(value: '3.1k', label: 'Gold won')),
                ],
              ),
              const SizedBox(height: 20),
              // 4) Achievements.
              const SectionBar(
                'Achievements',
                trailing: Text(
                  'See all  4 / 12 ›',
                  style: TextStyle(color: AuraColors.accentGlow, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: const [
                  Expanded(child: _Achievement(icon: Icons.emoji_events, color: AuraColors.gold, label: 'First Win')),
                  SizedBox(width: 12),
                  Expanded(child: _Achievement(icon: Icons.local_fire_department, color: AuraColors.brandOrange, label: 'On Fire')),
                  SizedBox(width: 12),
                  Expanded(child: _Achievement(icon: Icons.gps_fixed, color: AuraColors.gems, label: 'Sharpshooter')),
                  SizedBox(width: 12),
                  Expanded(child: _Achievement(icon: Icons.add, color: AuraColors.skip, label: '9 more', muted: true)),
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
      ],
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
    return AuraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                height: 72,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    LetterAvatar(
                      letter: user.initials,
                      color: user.color,
                      size: 64,
                      glow: true,
                    ),
                    Positioned(
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: AuraGradients.brand,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AuraColors.card, width: 2),
                        ),
                        child: Text(
                          'LV ${user.level}',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      style: AuraText.title.copyWith(fontSize: 21),
                    ),
                    const SizedBox(height: 2),
                    Text(user.handle, style: AuraText.cardSub),
                    const SizedBox(height: 6),
                    Text(
                      user.bio,
                      style: const TextStyle(
                        color: AuraColors.textSecondary,
                        fontSize: 12.5,
                        fontStyle: FontStyle.italic,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AuraColors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AuraColors.amber.withValues(alpha: 0.5)),
                ),
                child: Text(
                  user.tier.toUpperCase(),
                  style: const TextStyle(color: AuraColors.amber, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _ProgressBar(fraction: user.xpFraction)),
              const SizedBox(width: 10),
              Text('${_comma(user.xp)} / ${_comma(user.xpMax)} XP', style: AuraText.cardSub),
            ],
          ),
          const SizedBox(height: 14),
          _EditProfileButton(onTap: onEdit),
        ],
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
              children: const [
                Icon(Icons.edit, size: 16, color: AuraColors.textPrimary),
                SizedBox(width: 8),
                Text(
                  'Edit profile',
                  style: TextStyle(color: AuraColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600),
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

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 90,
            height: 90,
            child: CustomPaint(
              painter: _RingPainter(sweep: 0.68),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      '68%',
                      style: TextStyle(color: AuraColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    Text('Win rate', style: TextStyle(color: AuraColors.textSecondary, fontSize: 11)),
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
                _LegendDot(color: AuraColors.green, label: 'W 169'),
                SizedBox(width: 10),
                _LegendDot(color: AuraColors.amber, label: 'D 21'),
                SizedBox(width: 10),
                _LegendDot(color: AuraColors.danger, label: 'L 58'),
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
        Text(label, style: const TextStyle(color: AuraColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.sweep});
  final double sweep;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AuraColors.pagerInactive;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AuraColors.green;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * sweep, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => oldDelegate.sweep != sweep;
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
              const Expanded(
                child: Text(
                  'Last 7 days',
                  style: TextStyle(color: AuraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const AuraBadge('+12%', color: AuraColors.green),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 60,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_heights.length, (i) {
                // Explicit height (not FractionallySizedBox) so the chart can be
                // measured safely inside the IntrinsicHeight parent.
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Container(
                      height: 60 * _heights[i],
                      decoration: BoxDecoration(
                        gradient: AuraGradients.brand,
                        borderRadius: BorderRadius.circular(4),
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
                        style: const TextStyle(color: AuraColors.textSecondary, fontSize: 10),
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
        children: const [
          _GameStatRow(label: 'Online 1v1', wins: '61W', losses: '21L', pct: '74%', fraction: 0.74),
          SizedBox(height: 16),
          _GameStatRow(label: 'Online 4P', wins: '41W', losses: '30L', pct: '58%', fraction: 0.58),
          SizedBox(height: 16),
          _GameStatRow(label: 'Quick Play', wins: '67W', losses: '28L', pct: '71%', fraction: 0.71),
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
  });

  final String label;
  final String wins;
  final String losses;
  final String pct;
  final double fraction;

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
                style: const TextStyle(color: AuraColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Text.rich(
              TextSpan(
                style: const TextStyle(color: AuraColors.textSecondary, fontSize: 13),
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
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 6,
            color: AuraColors.chipDark,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: Container(
                decoration: BoxDecoration(
                  gradient: AuraGradients.brand,
                  borderRadius: BorderRadius.circular(4),
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
    required this.color,
    required this.label,
    this.muted = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: muted ? AuraColors.card : color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: muted ? AuraColors.cardBorder : color.withValues(alpha: 0.4)),
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: muted ? AuraColors.skip : AuraColors.textSecondary,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
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
    return AuraCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        children: [
          _ManageRow(label: 'Edit profile', sub: 'Name, bio, country', onTap: () => Navigator.pushNamed(context, Routes.editProfile)),
          const _Divider(),
          _ManageRow(label: 'Avatar', sub: 'Choose your look', onTap: () => Navigator.pushNamed(context, Routes.avatars)),
          const _Divider(),
          _ManageRow(label: 'Game history', sub: '248 matches', onTap: () => Navigator.pushNamed(context, Routes.gameHistory)),
          const _Divider(),
          _ManageRow(label: 'Settings', sub: 'Sound, alerts, account', onTap: onSettings),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Divider(height: 1, thickness: 1, color: AuraColors.cardBorder),
      );
}

class _ManageRow extends StatelessWidget {
  const _ManageRow({required this.label, required this.sub, required this.onTap});
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(color: AuraColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(sub, style: AuraText.cardSub),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AuraColors.textSecondary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
