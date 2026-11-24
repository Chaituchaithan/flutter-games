import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/tournament.dart';
import '../../services/session.dart';
import '../../services/tournament_api.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';

/// `GET /tournaments/{id}/standings` (06 §8).
final tournamentStandingsProvider = FutureProvider.autoDispose.family<List<Standing>, String>(
  (ref, id) => ref.watch(tournamentApiProvider).standings(id),
);

/// Results (06 §8): place, name and prize per entry, best first; the
/// player's own row highlighted, a trophy for places with a prize. While the
/// tournament is not over it is "Players", without places.
class TournamentResultsScreen extends ConsumerWidget {
  const TournamentResultsScreen({super.key, required this.tournament, this.initial = const []});

  final Tournament tournament;

  /// Standings already read by the detail screen (shown while reloading).
  final List<Standing> initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tournament;
    final over = t.status == TournamentStatus.completed;
    final value = ref.watch(tournamentStandingsProvider(t.id));
    final me = ref.watch(currentUserProvider).id;
    return AuraScaffold(
      appBar: AuraAppBar(title: over ? 'Results' : 'Players'),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(tournamentStandingsProvider(t.id).future).then((_) {}, onError: (Object _) {}),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 6),
            Text(t.name, style: AuraText.title),
            const SizedBox(height: 2),
            Text(
              over && t.prizePool > 0 ? 'Prize pool ${formatCount(t.prizePool)} ${t.currency.noun}' : t.type.label,
              style: AuraText.cardSub,
            ),
            const SizedBox(height: 16),
            AsyncView<List<Standing>>(
              value: value.hasValue || initial.isEmpty ? value : AsyncData(initial),
              onRetry: () => ref.invalidate(tournamentStandingsProvider(t.id)),
              data: (rows) {
                if (rows.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Text(
                      t.status.isCancelled ? 'No results: this tournament was cancelled.' : 'No players yet.',
                      textAlign: TextAlign.center,
                      style: AuraText.cardSub,
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final s in rows) StandingRow(standing: s, mine: s.playerId == me, showPlace: over)],
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class StandingRow extends StatelessWidget {
  const StandingRow({super.key, required this.standing, required this.mine, required this.showPlace});
  final Standing standing;
  final bool mine;
  final bool showPlace;

  @override
  Widget build(BuildContext context) {
    final s = standing;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AuraGlass.decoration(radius: 14, shadow: false, border: mine ? AuraColors.accentGlow : null),
      child: Row(
        children: [
          if (showPlace) SizedBox(width: 38, child: Text(s.place == null ? '–' : '#${s.place}', style: AuraText.cardTitle)),
          if (showPlace && s.hasPrize) ...[
            const Icon(Icons.emoji_events_rounded, size: 18, color: AuraColors.amber),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(mine ? '${s.username} (you)' : s.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.cardTitle),
          ),
          if (s.hasPrize)
            Text(s.prizeText, style: AuraText.cardTitle.copyWith(color: AuraColors.amber))
          else if (!showPlace && s.entryStatus != null)
            Text(s.entryStatus!.label, style: AuraText.cardSub),
        ],
      ),
    );
  }
}
