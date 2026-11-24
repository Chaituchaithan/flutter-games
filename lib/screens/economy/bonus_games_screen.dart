import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../data/models/daily_bonus.dart' show formatAmount;
import '../../data/models/rewards.dart';
import '../../data/repositories/rewards_repository.dart';
import '../../services/rewards_service.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';

/// Prize games any time (07-rewards.md §5a, trigger `store`) and the prize
/// history (§5d). Free games are not listed here: the list doesn't know the
/// player's entitlements, so they are offered only from their trigger (the
/// welcome spin, a spin-day daily claim, …).
class BonusGamesScreen extends ConsumerWidget {
  const BonusGamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(bonusGamesProvider('store'));
    final plays = ref.watch(bonusPlaysProvider);
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Prize games'),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          AsyncView<List<BonusGame>>(
            value: games,
            onRetry: () => ref.invalidate(bonusGamesProvider('store')),
            data: (list) {
              final shown = list.where((g) => g.supported).toList();
              if (shown.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Text('No prize games right now.', textAlign: TextAlign.center, style: AuraText.cardSub),
                );
              }
              return Column(
                children: [
                  for (final g in shown) ...[
                    _GameTile(game: g),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          const SectionBar('Prize history'),
          const SizedBox(height: 10),
          AsyncView<CursorPage<BonusPlayRecord>>(
            value: plays,
            onRetry: () => ref.invalidate(bonusPlaysProvider),
            data: (page) => page.items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text('No plays yet.', textAlign: TextAlign.center, style: AuraText.cardSub),
                  )
                : AuraCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Column(
                      children: [
                        for (final p in page.items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                                      if (p.playedAt != null)
                                        Text(_when(p.playedAt!), style: AuraText.cardSub.copyWith(fontSize: 11.5)),
                                    ],
                                  ),
                                ),
                                Text(
                                  p.prizeType == 'none' ? 'No prize' : p.prizeLabel,
                                  style: TextStyle(
                                    color: p.prizeType == 'none' ? AuraColors.textSecondary : AuraColors.amber,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  static String _when(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.game});
  final BonusGame game;

  @override
  Widget build(BuildContext context) {
    final g = game;
    final blocked = g.me.blockReason;
    final note = blocked == null
        ? '${g.me.playsLeftToday} plays left today'
        : (blockedText(blocked, cooldownUntil: g.me.cooldownUntil).text ?? '');
    return AuraCard(
      onTap: () => Navigator.pushNamed(context, Routes.bonusGame, arguments: {'code': g.code, 'trigger': g.trigger}),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(gradient: AuraGradients.brand, borderRadius: BorderRadius.circular(14)),
            child: Icon(
              switch (g.gameType) {
                'wheel' => Icons.casino_rounded,
                'chest' => Icons.inventory_2_rounded,
                'scratch' => Icons.auto_awesome,
                _ => Icons.style_rounded,
              },
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.name, style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(note, style: AuraText.cardSub.copyWith(fontSize: 12)),
              ],
            ),
          ),
          AuraBadge(
            g.cost.free ? 'FREE' : '${formatAmount(g.cost.amount)} ${g.cost.kind == 'gold' ? 'GOLD' : 'TOKENS'}',
            color: AuraColors.amber,
          ),
        ],
      ),
    );
  }
}
