import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/match_record.dart';
import '../../data/repositories/history_repository.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';

/// Game history. Reads via `matchHistoryProvider` (static source today; live API
/// when remote sources are switched on). See docs/DESIGN_SPEC.md (v2 §Game history).
class GameHistoryScreen extends ConsumerStatefulWidget {
  const GameHistoryScreen({super.key});

  @override
  ConsumerState<GameHistoryScreen> createState() => _GameHistoryScreenState();
}

class _GameHistoryScreenState extends ConsumerState<GameHistoryScreen> {
  int _filter = 0; // 0 All · 1 Wins · 2 Losses

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(matchHistoryProvider);

    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Game History'),
      showGlow: false, // mockup History has no backdrop glow
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Row(
            children: const [
              Expanded(child: StatTile(value: '248', label: 'Played')),
              SizedBox(width: 12),
              Expanded(
                child: StatTile(value: '169', label: 'Won', valueColor: AuraColors.green),
              ),
              SizedBox(width: 12),
              Expanded(child: StatTile(value: '68%', label: 'Win rate')),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedTabs(
            labels: const ['All', 'Wins', 'Losses'],
            index: _filter,
            onChanged: (i) => setState(() => _filter = i),
          ),
          const SizedBox(height: 16),
          AsyncView<List<MatchRecord>>(
            value: history,
            onRetry: () => ref.invalidate(matchHistoryProvider),
            data: _list,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _list(List<MatchRecord> all) {
    final matches = switch (_filter) {
      1 => all.where((m) => m.result == 'W'),
      2 => all.where((m) => m.result == 'L'),
      _ => all,
    }.toList();

    if (matches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          'No matches here yet',
          textAlign: TextAlign.center,
          style: AuraText.body.copyWith(color: AuraColors.textSecondary),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in matches) ...[
          _MatchRow(match: m),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match});

  final MatchRecord match;

  Color get _resultColor => switch (match.result) {
        'W' => AuraColors.green,
        'L' => AuraColors.danger,
        _ => AuraColors.amber,
      };

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _ResultBadge(letter: match.result, color: _resultColor),
          const SizedBox(width: 12),
          _OpponentAvatar(
            initials: match.opponent.substring(0, 2).toUpperCase(),
            color: match.avatarColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.opponent,
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
                  match.score,
                  style: const TextStyle(color: AuraColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  match.amount,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: match.isXp ? AuraColors.skip : AuraColors.gems,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                match.timeAgo,
                style: const TextStyle(color: AuraColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.letter, required this.color});

  final String letter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        letter,
        style: TextStyle(fontFamily: AuraText.displayFamily, color: color, fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _OpponentAvatar extends StatelessWidget {
  const _OpponentAvatar({required this.initials, required this.color});

  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.18)!,
            Color.lerp(color, Colors.black, 0.12)!,
          ],
        ),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: AuraText.displayFamily,
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
