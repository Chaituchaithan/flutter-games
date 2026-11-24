import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/main_shell.dart' show mainTabProvider;
import '../../app/routes.dart';
import '../../data/models/daily_bonus.dart' show formatAmount;
import '../../data/models/rewards.dart';
import '../../services/rewards_service.dart';
import '../../widgets/aura.dart';

/// Shared bits of the rewards screens (07-rewards.md).

/// "500 Tokens + 100 Gold + 1 power-up" (non-zero parts only).
String rewardSummary({int tokens = 0, int gold = 0, int powerUps = 0, int rubies = 0}) {
  final parts = [
    if (tokens > 0) '${formatAmount(tokens)} Tokens',
    if (gold > 0) '${formatAmount(gold)} Gold',
    if (powerUps > 0) '$powerUps boost${powerUps == 1 ? '' : 's'}',
    if (rubies > 0) '$rubies rubies',
  ];
  return parts.join(' + ');
}

/// Shows [issue]'s text (if any) as a toast. Returns the issue for chaining.
RewardIssue showRewardIssue(BuildContext context, RewardIssue issue) {
  final text = issue.text;
  if (text != null && context.mounted) {
    showAuraToast(
      context,
      text,
      kind: issue.kind == RewardIssueKind.alreadyDone ? AuraToastKind.info : AuraToastKind.error,
    );
  }
  return issue;
}

/// Opens the bonus game for a free play [offer] (the welcome `free_spin` or a
/// daily claim's `bonus_game`), with exactly its trigger and reference.
/// Completes with true when the free play was used (played or refused).
Future<bool> openBonusGame(BuildContext context, BonusGameOffer offer) async =>
    await Navigator.pushNamed<Object?>(
      context,
      Routes.bonusGame,
      arguments: {'code': offer.code, 'trigger': offer.trigger, 'triggerRef': offer.triggerRef},
    ) ==
    true;

// ── Bonus games (07-rewards.md §5) ───────────────────────────────────────

/// The wheel angle that brings slice [slotIndex] (of [slots]) under the top
/// pointer, after [turns] full turns from [from]. Slice 0 sits under the
/// pointer at angle 0. The slice comes from the server's `slot_index`.
double bonusWheelTarget(double from, int slotIndex, int slots, {int turns = 5}) {
  final slice = 2 * math.pi / math.max(1, slots);
  final start = from % (2 * math.pi);
  return start + 2 * math.pi * turns + ((-(slotIndex * slice)) - start) % (2 * math.pi);
}

/// What the server paid, as the player reads it: "+50 Tokens", "Shield ×1",
/// "Your next daily bonus is x2", "No prize this time".
String bonusPrizeText(PlayPrize p) {
  if (p.prizeType == 'mult' || p.nextBonusMultiplier != null) {
    final m = p.nextBonusMultiplier ?? (p.amount / 100).toStringAsFixed(p.amount % 100 == 0 ? 0 : 1);
    return 'Your next daily bonus is x$m';
  }
  if (p.prizeType == 'none' || p.isNothing) return 'No prize this time';
  if (p.currency == 'token') return '+${formatAmount(p.amount)} Tokens';
  if (p.currency == 'gold') return '+${formatAmount(p.amount)} Gold';
  return p.label.isEmpty ? 'You won!' : p.label;
}

/// "Play for 100 Tokens" / "100 TOKENS": a bonus game's price.
String bonusCostText(BonusCost c, {bool upper = false}) {
  final noun = c.kind == 'gold' ? 'Gold' : 'Tokens';
  return '${formatAmount(c.amount)} ${upper ? noun.toUpperCase() : noun}';
}

/// "Not enough tokens." for a paid bonus game, with a way to the Store tab.
Future<void> offerBonusShop(BuildContext context, WidgetRef ref, BonusGame g) async {
  final noun = g.cost.kind == 'gold' ? 'gold' : 'tokens';
  final buy = await showAuraDialog(
    context,
    icon: Icons.warning_amber_rounded,
    title: 'Not enough $noun.',
    body: 'This game costs ${formatAmount(g.cost.amount)} $noun. Top up in the Store and come back.',
    primaryLabel: 'Go to Store',
    secondaryLabel: 'Maybe later',
    tone: AuraDialogTone.warning,
  );
  if (buy == true && context.mounted) {
    ref.read(mainTabProvider.notifier).select(2);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

/// Slice / dot colour for a prize rarity.
Color bonusRarityColor(String rarity) => switch (rarity) {
  'rare' => AuraColors.gems,
  'epic' => AuraColors.brandPurple,
  'legendary' => AuraColors.amber,
  _ => const Color(0xFF4B4470),
};

/// The odds table (only when the server sends odds: `BonusGame.hasOdds`).
class BonusOddsTable extends StatelessWidget {
  const BonusOddsTable({super.key, required this.prizes});
  final List<BonusPrize> prizes;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        children: [
          for (final p in prizes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: bonusRarityColor(p.rarity), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(p.label, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                  Text(p.oddsPct == null ? '' : '${p.oddsPct}%', style: AuraText.cardSub),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A thin brand-gradient progress bar.
class RewardProgressBar extends StatelessWidget {
  const RewardProgressBar({super.key, required this.fraction, this.height = 6, this.done = false});
  final double fraction;
  final double height;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(color: AuraColors.pagerInactive, borderRadius: BorderRadius.circular(height / 2)),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fraction.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: done ? const LinearGradient(colors: [AuraColors.green, AuraColors.green]) : AuraGradients.brand,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      ),
    );
  }
}

/// A compact Claim / Claimed / progress chip for list rows.
class ClaimChip extends StatelessWidget {
  const ClaimChip({super.key, required this.label, this.onTap, this.busy = false, this.color = AuraColors.green});
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        constraints: const BoxConstraints(minWidth: 72),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: onTap != null ? AuraGradients.brand : null,
          color: onTap != null ? null : color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(99),
          border: onTap != null ? null : Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
              )
            : Text(
                label,
                style: TextStyle(
                  color: onTap != null ? Colors.white : color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

/// Red "something to collect" dot over [child].
class RewardDot extends StatelessWidget {
  const RewardDot({super.key, required this.on, required this.child});
  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!on) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -3,
          top: -3,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: AuraColors.danger,
              shape: BoxShape.circle,
              border: Border.all(color: AuraColors.bgBase, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
