import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Achievements — "Trophy Room". See docs/DESIGN_SPEC.md.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  static const _items = <_Achievement>[
    _Achievement(Icons.emoji_events, AuraColors.gold, 'First Win', 'Win your first match',
        unlocked: true),
    _Achievement(Icons.local_fire_department, AuraColors.brandOrange, 'On Fire', '5-win streak',
        unlocked: true),
    _Achievement(Icons.gps_fixed, AuraColors.gems, 'Sharpshooter', '10 flawless wins',
        unlocked: true),
    _Achievement(Icons.diamond, AuraColors.gems, 'High Roller', 'Win a 2k+ stake match',
        current: 3, target: 5),
    _Achievement(Icons.group_add, AuraColors.brandPurple, 'Socialite', 'Add 10 friends',
        current: 6, target: 10),
    _Achievement(Icons.timer, AuraColors.green, 'Marathon', 'Play 100 matches', unlocked: true),
    _Achievement(Icons.workspace_premium, AuraColors.brandPink, 'Champion', 'Win a tournament',
        current: 0, target: 1),
    _Achievement(Icons.replay, AuraColors.brandPurple, 'Comeback', 'Win from 0-2 down',
        current: 1, target: 3),
    _Achievement(Icons.category, AuraColors.avatarBlue, 'Collector', 'Own every power-up',
        current: 3, target: 5),
    _Achievement(Icons.calendar_month, AuraColors.brandPink, 'Streak Keeper', '30-day login streak',
        current: 3, target: 30),
    _Achievement(Icons.savings, AuraColors.gold, 'Big Spender', 'Spend 10k Gold',
        current: 2100, target: 10000, progressLabel: '2,100 / 10,000'),
    _Achievement(Icons.military_tech, AuraColors.brandOrange, 'Legend', 'Reach Level 50',
        current: 7, target: 50),
  ];

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: const AuraAppBar(
        title: 'Achievements',
        trailing: AuraBadge('4 / 12', color: AuraColors.brandPink),
      ),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          const SizedBox(height: 10),
          _TrophyRoomCard(fraction: _items.where((a) => a.unlocked).length / 12),
          const SizedBox(height: 16),
          for (final a in _items) ...[
            _AchievementRow(item: a),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Achievement {
  const _Achievement(
    this.icon,
    this.color,
    this.name,
    this.description, {
    this.unlocked = false,
    this.current = 0,
    this.target = 1,
    this.progressLabel,
  });

  final IconData icon;
  final Color color;
  final String name;
  final String description;
  final bool unlocked;
  final int current;
  final int target;
  final String? progressLabel;

  double get fraction => target == 0 ? 0 : (current / target).clamp(0.0, 1.0);
  String get statusText => progressLabel ?? '$current / $target';
}

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.item});

  final _Achievement item;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _IconTile(icon: item.icon, color: item.color, unlocked: item.unlocked),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: const TextStyle(color: AuraColors.textSecondary, fontSize: 13),
                ),
                if (!item.unlocked) ...[
                  const SizedBox(height: 8),
                  _ProgressBar(fraction: item.fraction),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          item.unlocked
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.check_circle, color: AuraColors.green, size: 18),
                    SizedBox(width: 5),
                    Text(
                      'Unlocked',
                      style: TextStyle(
                        color: AuraColors.green,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : Text(
                  item.statusText,
                  style: const TextStyle(
                    color: AuraColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.color, required this.unlocked});

  final IconData icon;
  final Color color;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: unlocked ? null : AuraColors.cardAlt,
        gradient: unlocked
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(color, Colors.white, 0.18)!,
                  Color.lerp(color, Colors.black, 0.12)!,
                ],
              )
            : null,
      ),
      child: Icon(
        icon,
        size: 22,
        color: unlocked ? Colors.white : AuraColors.skip,
      ),
    );
    // Locked tiles get a dashed outline (mockup); unlocked ones are solid gradient.
    if (unlocked) return tile;
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(radius: 14, color: AuraColors.textMuted),
      child: tile,
    );
  }
}

/// Draws a dashed rounded-rectangle border (used on locked achievement tiles).
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.radius, required this.color});
  final double radius;
  final Color color;
  static const double dash = 4;
  static const double gap = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final source = Path()..addRRect(rrect);
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        dashed.addPath(metric.extractPath(distance, distance + dash), Offset.zero);
        distance += dash + gap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: AuraColors.pagerInactive,
        borderRadius: BorderRadius.circular(3),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fraction,
        child: Container(
          decoration: BoxDecoration(
            gradient: AuraGradients.brand,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

/// Mockup "Trophy Room" card: gold-tinted glass, gold trophy tile, title,
/// subtitle and a gold progress bar (badges unlocked / total).
class _TrophyRoomCard extends StatelessWidget {
  const _TrophyRoomCard({required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFFFBBF24).withValues(alpha: 0.24), AuraColors.brandPink.withValues(alpha: 0.12)],
        ),
        border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.45), width: 1.5),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [const Color(0xFFFBBF24).withValues(alpha: 0.4), const Color(0xFFFBBF24).withValues(alpha: 0)], stops: const [0, 0.7]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)]),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  child: const Icon(Icons.emoji_events_rounded, color: Color(0xFF1A1206), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Trophy Room', style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
                      Text('Unlock badges to earn Gold & frames', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75))),
                      const SizedBox(height: 9),
                      Container(
                        height: 7,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: fraction.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              gradient: const LinearGradient(colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)]),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
