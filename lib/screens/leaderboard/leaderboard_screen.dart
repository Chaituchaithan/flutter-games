import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/games/core/game_codes.dart';
import '../../configs/games/games.dart';
import '../../data/models/friend.dart' show Friend;
import '../../data/models/progress.dart';
import '../../services/catalogue_service.dart';
import '../../services/progress_service.dart';
import '../../services/session.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';
import '../../widgets/player_avatar.dart';
import '../social/player_profile_screen.dart';

/// Leaderboards (08-progress-and-history.md §4): one board per game, tabs
/// Wins / Rating / Tokens won, all time. 20 rows, "load more" by `offset`,
/// medals for the top three, and a pinned "You" row from `my-rank` (or the
/// player's own row highlighted when it is on screen). The list is cached by
/// the server for up to an hour: "Updated hourly", and a `my-rank` that
/// disagrees with the list is not an error. Re-read on open and on pull to
/// refresh; never polled.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key, this.gameCode});

  /// The game to open on; defaults to the active game.
  final String? gameCode;

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  int _tab = 0;
  late String _code = widget.gameCode ?? GameCodes.codeOf(ref.read(activeGameProvider));
  LeaderboardPager? _pager;
  int? _pagerGame;

  static const _metrics = LeaderboardMetric.values;

  @override
  void dispose() {
    _pager?.dispose();
    super.dispose();
  }

  /// The pager for the current game and tab (a new one on change).
  LeaderboardPager _pagerFor(int gameId) {
    final metric = _metrics[_tab];
    final p = _pager;
    if (p != null && _pagerGame == gameId && p.metric == metric) return p;
    p?.dispose();
    _pagerGame = gameId;
    final fresh = LeaderboardPager(ref.read(progressApiProvider), gameId: gameId, metric: metric)..refresh();
    return _pager = fresh;
  }

  @override
  Widget build(BuildContext context) {
    final gameId = ref.watch(progressGameIdProvider(_code));
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Leaderboard'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          _GamePicker(selected: _code, onChanged: (c) => setState(() => _code = c)),
          const SizedBox(height: 12),
          SegmentedTabs(
            labels: [for (final m in _metrics) m.label],
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 6),
          Text('Updated hourly', textAlign: TextAlign.center, style: AuraText.cardSub.copyWith(fontSize: 11)),
          const SizedBox(height: 10),
          Expanded(
            child: AsyncView<int?>(
              value: gameId,
              onRetry: () => ref.invalidate(progressGameIdProvider(_code)),
              data: (id) => id == null
                  ? const _Empty(text: "This game isn't available right now.")
                  : _Board(key: ValueKey('$id/${_metrics[_tab].wire}'), pager: _pagerFor(id)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The games to pick from: this app's playable games in catalogue order.
class _GamePicker extends ConsumerWidget {
  const _GamePicker({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = ref.watch(homeGamesProvider).where((g) => g.playable).toList();
    if (games.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: games.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final g = games[i];
          final on = g.code == selected;
          return GestureDetector(
            onTap: () => onChanged(g.code),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: on ? AuraGradients.brand : null,
                color: on ? null : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: on ? 0.4 : 0.16)),
              ),
              child: Text('${g.icon}  ${g.name}',
                  style: TextStyle(fontFamily: AuraText.displayFamily, fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          );
        },
      ),
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({super.key, required this.pager});
  final LeaderboardPager pager;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider).id;
    return ListenableBuilder(
      listenable: pager,
      builder: (context, _) {
        final p = pager;
        if (!p.loaded) {
          if (p.error != null) return ErrorRetry(message: p.error!, onRetry: p.refresh);
          return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
        }
        final mineShown = p.rows.any((r) => r.userId == myId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: p.refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    if (p.rows.isEmpty) _Empty(text: p.metric.offBoardText),
                    for (final r in p.rows) ...[
                      _RankRow(entry: r, metric: p.metric, mine: r.userId == myId),
                      const SizedBox(height: 8),
                    ],
                    if (p.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(p.error!, textAlign: TextAlign.center, style: AuraText.cardSub),
                      ),
                    if (p.hasMore)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SecondaryButton(label: 'Load more', loading: p.loading, onPressed: p.loadMore),
                      ),
                  ],
                ),
              ),
            ),
            if (!mineShown) ...[
              const SizedBox(height: 6),
              _YouRow(me: p.me ?? const MyRank(), metric: p.metric),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

/// The score as shown: whole numbers ("4", "1016").
String _score(num s) => s.round().toString();

class _RankRow extends StatelessWidget {
  const _RankRow({required this.entry, required this.metric, required this.mine});
  final LeaderboardEntry entry;
  final LeaderboardMetric metric;
  final bool mine;

  static const _medals = [Color(0xFFFBBF24), Color(0xFFCBD5E1), Color(0xFFF97316)];

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final medal = e.rank >= 1 && e.rank <= 3 ? _medals[e.rank - 1] : null;
    final row = Row(
      children: [
        SizedBox(
          width: 30,
          child: medal != null
              ? Icon(Icons.military_tech_rounded, color: medal, size: 24)
              : Text('${e.rank}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        AvatarDisc(glyph: e.name.isEmpty ? '?' : e.name[0].toUpperCase(), avatarUrl: e.avatarUrl, name: e.name, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Text(mine ? '${e.name} (you)' : e.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.cardTitle.copyWith(fontSize: 14)),
        ),
        Text(_score(e.score),
            style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
      ],
    );
    if (mine) {
      return Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(colors: [AuraColors.brandPurple.withValues(alpha: 0.32), AuraColors.brandPink.withValues(alpha: 0.16)]),
          border: Border.all(color: AuraColors.accentGlow.withValues(alpha: 0.6)),
        ),
        child: row,
      );
    }
    return AuraCard(
      padding: const EdgeInsets.all(11),
      onTap: e.username == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlayerProfileScreen(
                  userId: e.userId,
                  name: e.name,
                  color: Friend.colorForName(e.name),
                  level: 1,
                  rank: '#${e.rank}',
                  online: false,
                ),
              )),
      child: row,
    );
  }
}

/// The pinned "You" row from `my-rank`.
class _YouRow extends ConsumerWidget {
  const _YouRow({required this.me, required this.metric});
  final MyRank me;
  final LeaderboardMetric metric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AuraColors.brandPurple.withValues(alpha: 0.3), AuraColors.brandPink.withValues(alpha: 0.14)]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AuraColors.accentGlow.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          LetterAvatar(letter: user.initials.isEmpty ? '?' : user.initials[0], color: AuraColors.brandPurple, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('You', style: AuraText.cardTitle.copyWith(fontSize: 14)),
                const SizedBox(height: 1),
                Text(
                  me.onBoard ? '${_score(me.score ?? 0)} · ${metric.label}' : metric.offBoardText,
                  style: AuraText.cardSub.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (me.onBoard)
            Text('#${me.rank}',
                style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(text, textAlign: TextAlign.center, style: AuraText.body.copyWith(color: AuraColors.textSecondary)),
      );
}
