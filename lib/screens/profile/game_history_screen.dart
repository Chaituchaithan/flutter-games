import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/game_area.dart';
import '../../configs/games/core/game_codes.dart';
import '../../data/models/progress.dart';
import '../../services/progress_service.dart';
import '../../services/server_clock.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';
import '../match/match_detail_screen.dart';

/// Match history (08-progress-and-history.md §5): every match the player sat
/// in, newest first, grouped by day. "Load more" asks for the next page
/// until `total_pages`; rows already shown are dropped (new matches shift
/// the pages). Pull to refresh reloads page 1. A running match offers "Back
/// to game"; the others open the match detail.
class GameHistoryScreen extends ConsumerStatefulWidget {
  const GameHistoryScreen({super.key});

  @override
  ConsumerState<GameHistoryScreen> createState() => _GameHistoryScreenState();
}

class _GameHistoryScreenState extends ConsumerState<GameHistoryScreen> {
  late HistoryPager _pager = HistoryPager(ref.read(progressApiProvider))..refresh();

  @override
  void initState() {
    super.initState();
    // A game ended meanwhile, or the player signed in: read page 1 again.
    ref.listenManual(progressStoreProvider.select((s) => s.revision), (_, _) => _pager.refresh());
    ref.listenManual(progressApiProvider, (_, api) {
      final old = _pager;
      setState(() => _pager = HistoryPager(api)..refresh());
      old.dispose();
    });
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Game History'),
      showGlow: false,
      body: ListenableBuilder(
        listenable: _pager,
        builder: (context, _) {
          final p = _pager;
          if (!p.loaded) {
            if (p.error != null) return ErrorRetry(message: p.error!, onRetry: p.refresh);
            return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
          }
          return RefreshIndicator(
            onRefresh: p.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 4, bottom: 24),
              children: [
                if (p.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Text('No matches yet. Play your first game.',
                        textAlign: TextAlign.center, style: AuraText.body.copyWith(color: AuraColors.textSecondary)),
                  )
                else ...[
                  Text('${p.total} ${p.total == 1 ? 'match' : 'matches'}', style: AuraText.cardSub),
                  const SizedBox(height: 8),
                  ..._grouped(p.items),
                ],
                if (p.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(p.error!, textAlign: TextAlign.center, style: AuraText.cardSub),
                  ),
                if (p.hasMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SecondaryButton(label: 'Load more', loading: p.loading, onPressed: p.loadMore),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _grouped(List<HistoryEntry> rows) {
    final out = <Widget>[];
    String? day;
    for (final e in rows) {
      final label = historyDayLabel(e.createdAt);
      if (label != day) {
        day = label;
        out.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: Text(label, style: AuraText.section),
        ));
      }
      out
        ..add(HistoryRow(entry: e))
        ..add(const SizedBox(height: 10));
    }
    return out;
  }
}

/// "Today" / "Yesterday" / "24 Nov 2026", in the device's time zone; "today" from
/// the server's clock ([ServerClock]).
String historyDayLabel(DateTime? at, {DateTime? now}) {
  if (at == null) return 'Earlier';
  final local = at.toLocal();
  final today = DateUtils.dateOnly((now ?? ServerClock.now()).toLocal());
  final d = DateUtils.dateOnly(local);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('d MMM y').format(local);
}

Color matchChipColor(MatchChip c) => switch (c) {
      MatchChip.won => AuraColors.green,
      MatchChip.lost || MatchChip.forfeit => AuraColors.danger,
      MatchChip.draw => AuraColors.amber,
      MatchChip.playing => AuraColors.accentGlow,
      MatchChip.cancelled || MatchChip.finished => AuraColors.textSecondary,
    };

/// One history row: game icon, game and mode names, the result chip, and
/// for a staked match the net (`+9`, `-10`; the row carries no currency).
class HistoryRow extends StatelessWidget {
  const HistoryRow({super.key, required this.entry});
  final HistoryEntry entry;

  void _open(BuildContext context) {
    final e = entry;
    if (e.inProgress) {
      final id = e.gameCode == null ? null : GameCodes.idOf(e.gameCode!);
      final route = id == null ? null : GameArea.onlineRoute(id);
      if (route != null) {
        Navigator.of(context).pushNamed(route, arguments: {'mode': 'resume'});
        return;
      }
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: e.matchId, entry: e)));
  }

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final chip = e.chip;
    final color = matchChipColor(chip);
    final icon = (e.gameCode == null ? null : GameCodes.info(e.gameCode!)?.icon) ?? '🎮';
    final time = e.createdAt == null ? '' : DateFormat.Hm().format(e.createdAt!.toLocal());
    final net = e.net;
    return AuraCard(
      padding: const EdgeInsets.all(12),
      onTap: () => _open(context),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
            child: Text(icon, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.gameName ?? 'Match',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.cardTitle.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  [?e.modeName, if (e.bets.isNotEmpty) '${e.bets.length} ${e.bets.length == 1 ? 'bet' : 'bets'}', if (time.isNotEmpty) time]
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AuraColors.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Text(chip.label,
                    style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
              ),
              if (e.inProgress) ...[
                const SizedBox(height: 4),
                const Text('Back to game', style: TextStyle(color: AuraColors.accentGlow, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ] else if (e.staked) ...[
                const SizedBox(height: 4),
                Text(
                  net > 0 ? '+$net' : '$net',
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: net > 0 ? AuraColors.green : (net < 0 ? AuraColors.danger : AuraColors.textSecondary),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
