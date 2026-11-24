import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/daily_bonus.dart' show formatAmount;
import '../../data/models/rewards.dart';
import '../../data/repositories/rewards_repository.dart';
import '../../services/app_exception.dart';
import '../../services/rewards_service.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';
import '../economy/rewards_ui.dart';

/// Achievements — "Trophy Room" (07-rewards.md §4): every badge from
/// `GET /achievements/my`, flat and tiered (bronze, silver, gold, royal),
/// secret ones as locked mystery badges, and a Claim for each reward reached.
class AchievementsScreen extends ConsumerStatefulWidget {
  const AchievementsScreen({super.key});

  @override
  ConsumerState<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends ConsumerState<AchievementsScreen> {
  /// "badge id:tier" being claimed.
  final _claiming = <String>{};
  bool _onlyClaimable = false;

  @override
  void initState() {
    super.initState();
    // Opening the screen re-reads (nothing is pushed by the server).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(myAchievementsProvider);
    });
  }

  Future<void> _claim(Achievement a, {String? tier}) async {
    final key = '${a.id}:${tier ?? ''}';
    if (_claiming.contains(key)) return;
    setState(() => _claiming.add(key));
    try {
      final c = await ref.read(rewardsApiProvider).claimAchievement(a.id, tier: a.tiered ? tier : null);
      if (!mounted) return;
      final what = [
        rewardSummary(tokens: c.tokens, gold: c.gold),
        if (c.title != null) 'the title "${c.title}"',
        if (c.avatarId != null) 'a new avatar',
      ].where((x) => x.isNotEmpty).join(' + ');
      final xp = !a.tiered && a.expReward > 0 ? ' · +${a.expReward} XP' : '';
      showAuraToast(
        context,
        what.isEmpty ? 'Claimed "${a.name}"$xp' : 'Claimed $what$xp',
        kind: c.gold > 0 ? AuraToastKind.gold : AuraToastKind.success,
      );
      if (c.paysMoney) applyRewardToWallet(ref);
    } on AppException catch (e) {
      if (mounted) showRewardIssue(context, achievementClaimIssue(e));
    } finally {
      ref.invalidate(myAchievementsProvider);
      if (mounted) setState(() => _claiming.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(myAchievementsProvider);
    final items = list.value;
    final unlocked = items?.where((a) => a.completed).length ?? 0;
    return AuraScaffold(
      appBar: AuraAppBar(
        title: 'Achievements',
        trailing: items == null ? null : AuraBadge('$unlocked / ${items.length}', color: AuraColors.brandPink),
      ),
      scroll: true,
      body: AsyncView<List<Achievement>>(
        value: list,
        onRetry: () => ref.invalidate(myAchievementsProvider),
        data: _content,
      ),
    );
  }

  Widget _content(List<Achievement> items) {
    final unlocked = items.where((a) => a.completed).length;
    final claimable = items.where((a) => a.claimable).length;
    final shown = [...items.where((a) => !_onlyClaimable || a.claimable)];
    // Claimable first, then the server's order (stable).
    final ordered = [...shown.where((a) => a.claimable), ...shown.where((a) => !a.claimable)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        _TrophyRoomCard(fraction: items.isEmpty ? 0 : unlocked / items.length),
        const SizedBox(height: 16),
        SegmentedTabs(
          labels: ['All', claimable > 0 ? 'To claim ($claimable)' : 'To claim'],
          index: _onlyClaimable ? 1 : 0,
          onChanged: (i) => setState(() => _onlyClaimable = i == 1),
        ),
        const SizedBox(height: 12),
        if (ordered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text('Nothing to claim right now.', textAlign: TextAlign.center, style: AuraText.cardSub),
          ),
        for (final a in ordered) ...[
          _AchievementRow(item: a, claiming: _claiming, onClaim: (tier) => _claim(a, tier: tier)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

Color _tierColor(String tier) => switch (tier) {
  'bronze' => const Color(0xFFCD7F32),
  'silver' => const Color(0xFFC0C7D1),
  'gold' => AuraColors.gold,
  'royal' => AuraColors.brandPurple,
  _ => AuraColors.accentGlow,
};

String _tierReward(TierReward r) => switch (r.kind) {
  'tokens' => '${formatAmount(r.amount)} Tokens',
  'gold' => '${formatAmount(r.amount)} Gold',
  'title' => 'Title: ${r.name ?? ''}',
  'avatar' => 'Avatar',
  _ => '',
};

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.item, required this.claiming, required this.onClaim});

  final Achievement item;
  final Set<String> claiming;
  final void Function(String? tier) onClaim;

  @override
  Widget build(BuildContext context) {
    final a = item;
    final mystery = a.mystery;
    final next = a.nextTier;
    final reached = a.tierReached;
    final color = reached != null ? _tierColor(reached) : (a.completed ? AuraColors.gold : AuraColors.brandPurple);
    final String sub;
    if (mystery) {
      sub = 'Keep playing to discover this badge.';
    } else {
      final reward = a.tiered
          ? ''
          : [
              rewardSummary(tokens: a.rewardTokens, gold: a.rewardGold),
              if (a.expReward > 0) '${a.expReward} XP',
            ].where((x) => x.isNotEmpty).join(' + ');
      sub = [
        if (a.description != null && a.description!.isNotEmpty) a.description!,
        if (reward.isNotEmpty) reward,
      ].join(' · ');
    }
    return AuraCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconTile(
                icon: mystery ? Icons.help_outline_rounded : (a.tiered ? Icons.military_tech : Icons.emoji_events),
                color: color,
                unlocked: a.completed,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mystery ? 'Secret achievement' : a.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AuraText.displayFamily,
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(sub, style: const TextStyle(color: AuraColors.textSecondary, fontSize: 13)),
                    ],
                    if (a.tiered && !mystery && next != null && a.progressValue != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: RewardProgressBar(
                              fraction: next.threshold <= 0 ? 0 : a.progressValue! / next.threshold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${formatAmount(a.progressValue!)} / ${formatAmount(next.threshold)}',
                            style: AuraText.cardSub.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                    if (a.titles.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Titles: ${a.titles.join(', ')}', style: const TextStyle(color: AuraColors.amber, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (!a.tiered)
                a.claimable
                    ? ClaimChip(label: 'Claim', busy: claiming.contains('${a.id}:'), onTap: () => onClaim(null))
                    : a.claimedAt != null
                    ? const _Claimed()
                    : const Icon(Icons.lock_outline_rounded, color: AuraColors.textMuted, size: 18),
            ],
          ),
          if (a.tiered && !mystery) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in a.tiers)
                  _TierChip(
                    tier: t,
                    claimed: a.claimedTiers.contains(t.tier),
                    claimable: a.claimableTiers.contains(t.tier),
                    busy: claiming.contains('${a.id}:${t.tier}'),
                    onClaim: () => onClaim(t.tier),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Claimed extends StatelessWidget {
  const _Claimed();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.check_circle, color: AuraColors.green, size: 18),
      SizedBox(width: 5),
      Text('Claimed', style: TextStyle(color: AuraColors.green, fontSize: 13, fontWeight: FontWeight.w700)),
    ],
  );
}

/// One tier: threshold and reward; Claim when reached and not yet claimed.
class _TierChip extends StatelessWidget {
  const _TierChip({
    required this.tier,
    required this.claimed,
    required this.claimable,
    required this.busy,
    required this.onClaim,
  });
  final AchievementTier tier;
  final bool claimed;
  final bool claimable;
  final bool busy;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final c = _tierColor(tier.tier);
    final active = claimed || claimable;
    return GestureDetector(
      onTap: claimable && !busy ? onClaim : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: c.withValues(alpha: active ? 0.22 : 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: c.withValues(alpha: claimable ? 0.95 : (active ? 0.5 : 0.2)),
            width: claimable ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tier.tier.toUpperCase(),
                  style: TextStyle(
                    color: active ? c : c.withValues(alpha: 0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(width: 6),
                if (claimed)
                  const Icon(Icons.check_rounded, color: AuraColors.green, size: 14)
                else if (busy)
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6))
                else if (claimable)
                  const Text('CLAIM', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${formatAmount(tier.threshold)} · ${_tierReward(tier.reward)}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
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
