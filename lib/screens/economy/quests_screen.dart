import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/rewards.dart';
import '../../data/repositories/rewards_repository.dart';
import '../../services/app_exception.dart';
import '../../services/rewards_service.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';
import 'rewards_ui.dart';
import '../../services/server_clock.dart';

/// Quests (07-rewards.md §3): daily, weekly, onboarding (and event) tabs.
/// Each active quest is merged with the player's progress, so quests with no
/// progress yet show `0 / target`. Progress moves on the game servers when a
/// match is settled; the app never evaluates criteria.
class QuestsScreen extends ConsumerStatefulWidget {
  const QuestsScreen({super.key});

  @override
  ConsumerState<QuestsScreen> createState() => _QuestsScreenState();
}

class _QuestsScreenState extends ConsumerState<QuestsScreen> {
  int _tab = 0;
  final _claiming = <int>{};
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Opening the screen re-reads (nothing is pushed by the server).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(questsProvider);
    });
    // Event quests' "Ends in" countdowns.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _claim(QuestRow row) async {
    final id = row.quest.id;
    if (_claiming.contains(id)) return;
    setState(() => _claiming.add(id));
    try {
      final c = await ref.read(rewardsApiProvider).claimQuest(id);
      if (!mounted) return;
      final what = rewardSummary(tokens: c.tokens, gold: c.gold, powerUps: c.powerUpQty);
      showAuraToast(context, what.isEmpty ? 'Quest reward claimed' : 'Claimed $what',
          kind: c.gold > 0 ? AuraToastKind.gold : AuraToastKind.success);
      if (c.paysMoney) applyRewardToWallet(ref);
    } on AppException catch (e) {
      if (mounted) showRewardIssue(context, questClaimIssue(e));
    } finally {
      ref.invalidate(questsProvider);
      if (mounted) setState(() => _claiming.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final quests = ref.watch(questsProvider);
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Quests'),
      scroll: true,
      body: AsyncView<List<QuestRow>>(
        value: quests,
        onRetry: () => ref.invalidate(questsProvider),
        data: _content,
      ),
    );
  }

  Widget _content(List<QuestRow> rows) {
    final scopes = [
      for (final s in questScopes)
        if (s != 'event' || rows.any((r) => r.quest.scope == 'event')) s,
    ];
    final tab = _tab.clamp(0, scopes.length - 1);
    final scope = scopes[tab];
    final shown = rows.where((r) => r.quest.scope == scope).toList()
      ..sort((a, b) => (a.claimed ? 1 : 0).compareTo(b.claimed ? 1 : 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < scopes.length; i++) ...[
              Expanded(
                child: RewardDot(
                  on: rows.any((r) => r.quest.scope == scopes[i] && r.claimable),
                  child: _TabChip(label: _scopeLabel(scopes[i]), active: i == tab, onTap: () => setState(() => _tab = i)),
                ),
              ),
              if (i < scopes.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(_resetNote(scope), style: AuraText.cardSub.copyWith(fontSize: 12)),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text('No quests here right now.', textAlign: TextAlign.center, style: AuraText.cardSub),
          ),
        for (final r in shown) ...[
          _QuestCard(row: r, busy: _claiming.contains(r.quest.id), onClaim: () => _claim(r)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
      ],
    );
  }

  static String _scopeLabel(String s) => switch (s) {
    'daily' => 'Daily',
    'weekly' => 'Weekly',
    'onboarding' => 'Starter',
    _ => 'Event',
  };

  static String _resetNote(String s) => switch (s) {
    'daily' => 'Resets every day at 00:00 UTC.',
    'weekly' => 'Resets every Monday at 00:00 UTC.',
    'onboarding' => 'Once per account.',
    _ => 'For a limited time.',
  };
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: active ? AuraGradients.brand : null,
          color: active ? null : Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: active ? 0 : 0.18)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: active ? Colors.white : AuraColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _QuestCard extends StatelessWidget {
  const _QuestCard({required this.row, required this.busy, required this.onClaim});
  final QuestRow row;
  final bool busy;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final q = row.quest;
    final reward = rewardSummary(tokens: q.rewardTokens, gold: q.rewardGold, powerUps: q.rewardPowerUpQty);
    final ends = q.endsAt;
    return AuraCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      q.title,
                      style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    if (q.description != null && q.description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(q.description!, style: const TextStyle(color: AuraColors.textSecondary, fontSize: 13)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (row.claimable)
                ClaimChip(label: 'Claim', busy: busy, onTap: onClaim)
              else if (row.claimed)
                const ClaimChip(label: 'Claimed')
              else if (row.status == 'expired')
                const ClaimChip(label: 'Ended', color: AuraColors.textMuted),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: RewardProgressBar(fraction: row.fraction, done: row.current >= row.target)),
              const SizedBox(width: 10),
              Text('${row.current} / ${row.target}', style: AuraText.cardSub.copyWith(fontSize: 12)),
            ],
          ),
          if (reward.isNotEmpty || (ends != null && ends.isAfter(ServerClock.now()))) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (reward.isNotEmpty) ...[
                  CurrencyGlyph(kind: q.rewardGold > 0 ? Currency.gold : Currency.gems, size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text(reward, style: const TextStyle(color: AuraColors.amber, fontSize: 12.5, fontWeight: FontWeight.w700))),
                ] else
                  const Spacer(),
                if (ends != null && ends.isAfter(ServerClock.now()))
                  Text('Ends in ${rewardCountdown(ends)}', style: AuraText.cardSub.copyWith(fontSize: 12)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
