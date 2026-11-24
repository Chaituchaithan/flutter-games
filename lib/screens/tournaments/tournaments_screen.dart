import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/games/core/active_game.dart';
import '../../configs/games/core/game_codes.dart';
import '../../data/models/tournament.dart';
import '../../services/catalogue_service.dart';
import '../../services/server_clock.dart';
import '../../services/tournament_api.dart';
import '../../services/tournament_controller.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';
import '../../widgets/wallet_pill.dart';
import 'tournament_detail_screen.dart';

/// The lobby's game filter: the numeric catalogue id of the game the Home is
/// showing (06 §1: always pass `game_id` inside one game). Null = every game
/// (catalogue not loaded, demo).
final tournamentLobbyGameIdProvider = Provider<int?>((ref) {
  final active = ref.watch(activeGameProvider);
  final code = GameCodes.all.where((g) => g.id == active).firstOrNull?.code;
  if (code == null) return null;
  return ref.watch(catalogueGamesProvider).value?.where((g) => g.code == code).firstOrNull?.id;
});

/// One lobby tab's rows (one call per status; Finished newest first).
final tournamentTabProvider = FutureProvider.autoDispose.family<List<Tournament>, ({TournamentTab tab, int? gameId})>(
  (ref, q) => loadTournamentTab(ref.watch(tournamentApiProvider), q.tab, gameId: q.gameId),
);

/// The catalogue's name for a numeric game id (null when unknown).
String? tournamentGameName(WidgetRef ref, int gameId) =>
    ref.watch(catalogueGamesProvider).value?.where((g) => g.id == gameId).firstOrNull?.name;

/// Tournaments lobby (06 §1): Upcoming / Running / Finished from
/// `GET /tournaments`, one status per call, filtered by the Home's game.
/// Pull to refresh; no automatic refresh. A row opens the detail screen.
///
/// Pops 'store' when the player chose "Buy more" (Home opens the Store tab).
class TournamentsScreen extends ConsumerStatefulWidget {
  const TournamentsScreen({super.key});

  @override
  ConsumerState<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends ConsumerState<TournamentsScreen> {
  TournamentTab _tab = TournamentTab.upcoming;

  ({TournamentTab tab, int? gameId}) get _query => (tab: _tab, gameId: ref.read(tournamentLobbyGameIdProvider));

  Future<void> _refresh() async {
    ref.invalidate(tournamentTabProvider(_query));
    try {
      await ref.read(tournamentTabProvider(_query).future);
    } on Object {
      // The error view shows Retry.
    }
  }

  Future<void> _open(Tournament t) async {
    final r = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => TournamentDetailScreen(tournament: t)),
    );
    if (!mounted) return;
    if (r == 'store') {
      Navigator.pop(context, 'store');
      return;
    }
    // Back from a tournament: its status, seats or the player's entry may
    // have changed.
    unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final gameId = ref.watch(tournamentLobbyGameIdProvider);
    final q = (tab: _tab, gameId: gameId);
    final joined = ref.watch(joinedTournamentsProvider);
    return AuraScaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 14),
            const _Header(),
            const SizedBox(height: 16),
            SegmentedTabs(
              labels: [for (final t in TournamentTab.values) t.label],
              index: _tab.index,
              onChanged: (i) => setState(() => _tab = TournamentTab.values[i]),
            ),
            const SizedBox(height: 22),
            AsyncView<List<Tournament>>(
              value: ref.watch(tournamentTabProvider(q)),
              onRetry: () => ref.invalidate(tournamentTabProvider(q)),
              data: (rows) => rows.isEmpty
                  ? _Empty(tab: _tab)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final t in rows) ...[
                          TournamentCard(tournament: t, entered: joined.contains(t.id), onTap: () => _open(t)),
                          const SizedBox(height: 11),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.tab});
  final TournamentTab tab;

  @override
  Widget build(BuildContext context) {
    final text = switch (tab) {
      TournamentTab.upcoming => 'No tournaments open right now. Pull down to check again.',
      TournamentTab.running => 'No tournaments are being played right now.',
      TournamentTab.finished => 'No finished tournaments yet.',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.emoji_events_outlined, color: AuraColors.textSecondary, size: 34),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: AuraText.cardSub),
        ],
      ),
    );
  }
}

/// Mockup header: 42px glass back button · "Tournaments" · Tokens pill.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GlassIconButton(icon: Icons.chevron_left, iconSize: 24, onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Tournaments', style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 22, color: Colors.white)),
        ),
        const WalletPill(kind: Currency.gems, showPlus: false),
      ],
    );
  }
}

/// Gradient for a tournament's icon tile and fill bar.
List<Color> tournamentColors(Tournament t) {
  if (t.status.isOver) return const [Color(0xFF6366F1), Color(0xFFA855F7)];
  if (t.comingSoon) return const [Color(0xFF64748B), Color(0xFF475569)];
  return switch (t.type) {
    TournamentType.singleTableSng => const [Color(0xFF8B5CF6), Color(0xFFEC4899)],
    TournamentType.leaderboardWindow => const [Color(0xFF22D3EE), Color(0xFF3B82F6)],
    _ => const [Color(0xFFFB923C), Color(0xFFF43F5E)],
  };
}

/// "2h 14m", "3d 4h", "12m", "45s".
String formatStartsIn(Duration d) {
  if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}

/// "1:58" (a seat deadline).
String formatClock(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// The start in local time: "Mon 24 Nov, 18:00".
String formatLocalStart(DateTime t) {
  final l = t.toLocal();
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[l.weekday - 1]} ${l.day} ${months[l.month - 1]}, ${two(l.hour)}:${two(l.minute)}';
}

/// The row's "when" line (06 §1 "What the app does"): a Sit & Go never
/// shows `starts_at`.
String tournamentWhen(Tournament t, {DateTime? now}) {
  // Server time: `starts_at` is the server's clock.
  final n = now ?? ServerClock.now();
  if (t.comingSoon && !t.status.isOver) return '${t.type.label} · Coming soon';
  switch (t.status) {
    case TournamentStatus.completed:
      return '${t.type.label} · Finished';
    case TournamentStatus.cancelled:
    case TournamentStatus.refunded:
      return '${t.type.label} · Cancelled';
    case TournamentStatus.running:
      return '${t.type.label} · Live now';
    case TournamentStatus.paused:
      return '${t.type.label} · Paused';
    case TournamentStatus.unknown:
      return t.type.label;
    case TournamentStatus.announced:
    case TournamentStatus.registering:
  }
  if (t.isSitAndGo) {
    return 'Sit & Go${t.maxPlayers == null ? '' : ', ${t.maxPlayers} players'} · Starts when full';
  }
  final s = t.startsAt;
  final open = t.status == TournamentStatus.announced ? 'Opens soon · ' : '';
  if (s == null) return '$open${t.type.label}';
  final left = s.difference(n);
  return left.isNegative ? '$open${formatLocalStart(s)}' : '${open}Starts in ${formatStartsIn(left)}';
}

/// The row's chip.
String tournamentChip(Tournament t, {required bool entered}) {
  if (t.status.isOver) return t.status == TournamentStatus.completed ? 'Results' : 'Cancelled';
  if (t.comingSoon) return 'Soon';
  return switch (t.status) {
    TournamentStatus.registering => entered ? 'Entered' : 'Join',
    TournamentStatus.announced => 'Opens soon',
    TournamentStatus.running => entered ? 'Your table' : 'View',
    TournamentStatus.paused => 'Paused',
    _ => 'View',
  };
}

/// A lobby row: icon tile · name · when · chip, then pool/price · fill bar ·
/// seats. "Sit & Go, 4 players · Starts when full", "250 + 25 tokens", "3 / 4".
class TournamentCard extends StatelessWidget {
  const TournamentCard({super.key, required this.tournament, required this.onTap, this.entered = false});
  final Tournament tournament;
  final VoidCallback onTap;
  final bool entered;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final colors = tournamentColors(t);
    final grad = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors);
    final chip = tournamentChip(t, entered: entered);
    final primary = chip == 'Join' || chip == 'Your table';
    final pool = t.poolText;
    final fill = t.maxPlayers == null || t.maxPlayers == 0 || t.status.isCancelled ? null : (t.currentPlayers / t.maxPlayers!).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: 0.09), Colors.white.withValues(alpha: 0.03)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: grad,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.emoji_events_outlined, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 15.5, color: Colors.white),
                            ),
                          ),
                          if (t.status == TournamentStatus.running) ...[
                            const SizedBox(width: 7),
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: AuraColors.green,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: AuraColors.green, blurRadius: 8)],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tournamentWhen(t),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.55)),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        t.priceText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                    gradient: primary ? AuraGradients.brand : null,
                    color: primary ? null : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    chip,
                    style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.emoji_events_rounded, size: 13, color: Color(0xFFFBBF24)),
                const SizedBox(width: 4),
                Flexible(
                  flex: 3,
                  child: Text(
                    pool ?? (t.status.isCancelled ? 'Entries refunded' : 'No prize pool yet'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: pool == null ? Colors.white.withValues(alpha: 0.55) : const Color(0xFFFBBF24)),
                  ),
                ),
                if (fill != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: fill,
                        child: Container(decoration: BoxDecoration(gradient: grad, borderRadius: BorderRadius.circular(99))),
                      ),
                    ),
                  ),
                ],
                if (!t.status.isCancelled) ...[
                  const SizedBox(width: 10),
                  Text(
                    t.isSitAndGo && !t.status.isOver ? '${t.seatsText} seated' : t.seatsText,
                    maxLines: 1,
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.55)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
