import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/game_area.dart';
import '../../configs/games/core/game_codes.dart';
import '../../data/models/progress.dart';
import '../../services/account_store.dart';
import '../../services/app_exception.dart';
import '../../services/progress_service.dart';
import '../../services/session.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';
import '../../widgets/player_avatar.dart';
import '../profile/game_history_screen.dart' show matchChipColor;

/// One past match (08-progress-and-history.md §6): the game and mode, date
/// and length, then every seat in place order with names (public profile,
/// cached), the result chip, the rating change for a ranked match and the
/// payout for a staked one. Ludo adds a few `custom_stats` lines; a provably
/// fair game a "Verify" section. Opened from history, a ledger row or the
/// result screen.
class MatchDetailScreen extends ConsumerWidget {
  const MatchDetailScreen({super.key, required this.matchId, this.entry});

  final String matchId;

  /// The history row it was opened from (game and mode names); optional.
  final HistoryEntry? entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(matchDetailProvider(matchId));
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Match'),
      scroll: true,
      body: detail.when(
        loading: () => const Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
        ),
        error: (e, _) {
          final gone = e is AppException && e.code == ApiErrorCode.matchNotFound;
          final text = e is AppException ? e.message : progressLoadFailed;
          if (!gone) return ErrorRetry(message: text, onRetry: () => ref.invalidate(matchDetailProvider(matchId)));
          return Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Column(
              children: [
                Text(matchGoneText, textAlign: TextAlign.center, style: AuraText.body),
                const SizedBox(height: 16),
                SecondaryButton(label: 'Back', onPressed: () => Navigator.of(context).maybePop()),
              ],
            ),
          );
        },
        data: (m) => _Body(match: m, entry: entry),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.match, this.entry});
  final MatchDetail match;
  final HistoryEntry? entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = match;
    final myId = ref.watch(currentUserProvider).id;
    final games = ref.watch(progressGamesProvider).value;
    final cat = catalogueGameById(games, m.gameId);
    final code = entry?.gameCode ?? cat?.code;
    final gameName = entry?.gameName ?? cat?.name ?? 'Match';
    final modeName = entry?.modeName;
    final icon = (code == null ? null : GameCodes.info(code)?.icon) ?? '🎮';
    final when = m.startedAt ?? m.createdAt;
    final length = m.length;
    final staked = m.participants.any((p) => p.stakeAmount > 0 || p.payoutAmount > 0);
    final ranked = m.ratingMoved;
    final mine = m.seatOf(myId);
    final ludo = code == 'ludo' ? ludoStatLines(mine?.customStats) : const <(String, String)>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        AuraCard(
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(gameName, style: AuraText.cardTitle),
                    if (modeName != null) Text(modeName, style: AuraText.cardSub),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (when != null) DateFormat('d MMM y, HH:mm').format(when.toLocal()),
                        if (length != null) _duration(length),
                      ].join(' · '),
                      style: AuraText.cardSub.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (m.inProgress) ...[
          const SizedBox(height: 12),
          _StillPlaying(gameCode: code),
        ],
        const SizedBox(height: 16),
        SectionBar('Players'),
        const SizedBox(height: 10),
        for (final p in m.byPlace) ...[
          _SeatRow(seat: p, mine: p.userId != null && p.userId == myId, showRating: ranked, showPayout: staked),
          const SizedBox(height: 8),
        ],
        if (ludo.isNotEmpty) ...[
          const SizedBox(height: 10),
          SectionBar('Your game'),
          const SizedBox(height: 10),
          AuraCard(
            child: Column(
              children: [
                for (final (label, value) in ludo)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(child: Text(label, style: AuraText.cardSub)),
                      Text(value, style: AuraText.cardTitle.copyWith(fontSize: 14)),
                    ]),
                  ),
              ],
            ),
          ),
        ],
        if (m.serverSeedHash != null) ...[
          const SizedBox(height: 16),
          SectionBar('Verify'),
          const SizedBox(height: 10),
          AuraCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Seed hash (published before play)', style: AuraText.cardSub.copyWith(fontSize: 12)),
                SelectableText(m.serverSeedHash!, style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
                const SizedBox(height: 10),
                Text('Seed', style: AuraText.cardSub.copyWith(fontSize: 12)),
                SelectableText(
                  m.serverSeed ?? 'Shown once the match has ended.',
                  style: TextStyle(color: m.serverSeed == null ? AuraColors.textSecondary : Colors.white, fontSize: 12, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  static String _duration(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }
}

class _StillPlaying extends StatelessWidget {
  const _StillPlaying({this.gameCode});
  final String? gameCode;

  @override
  Widget build(BuildContext context) {
    final id = gameCode == null ? null : GameCodes.idOf(gameCode!);
    final route = id == null ? null : GameArea.onlineRoute(id);
    return AuraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('This match is still being played.', style: AuraText.cardTitle.copyWith(fontSize: 14)),
          if (route != null) ...[
            const SizedBox(height: 10),
            GradientButton(
              label: 'Back to game',
              onPressed: () => Navigator.of(context).pushNamed(route, arguments: {'mode': 'resume'}),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeatRow extends ConsumerWidget {
  const _SeatRow({required this.seat, required this.mine, required this.showRating, required this.showPayout});
  final MatchParticipant seat;
  final bool mine;
  final bool showRating;
  final bool showPayout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = seat;
    final String name;
    String? avatarUrl;
    if (mine) {
      name = 'You';
    } else if (p.isBot || p.userId == null) {
      name = 'Bot';
    } else {
      // Names come from the public profile, read once per player (cached).
      final prof = ref.watch(playerProfileProvider(p.userId!)).value;
      name = (prof == null || prof.displayName.isEmpty) ? 'Player' : prof.displayName;
      avatarUrl = prof?.avatarUrl;
    }
    final chip = p.chip;
    final change = p.ratingChange;
    final row = Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(p.finalRank == null ? '–' : '#${p.finalRank}',
              style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        ),
        AvatarDisc(glyph: name[0].toUpperCase(), avatarUrl: avatarUrl, name: name, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.cardTitle.copyWith(fontSize: 14)),
              if (showPayout)
                Text(
                  p.payoutAmount > 0 ? 'Won ${p.payoutAmount}' : (p.stakeAmount > 0 ? 'Paid ${p.stakeAmount}' : 'No payout'),
                  style: AuraText.cardSub.copyWith(fontSize: 11.5),
                ),
            ],
          ),
        ),
        if (showRating && change != null) ...[
          Text(
            change > 0 ? '+$change' : '$change',
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: change > 0 ? AuraColors.green : (change < 0 ? AuraColors.danger : AuraColors.textSecondary),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (p.result != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: matchChipColor(chip).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(chip.label, style: TextStyle(color: matchChipColor(chip), fontSize: 11, fontWeight: FontWeight.w800)),
          ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: mine
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(colors: [AuraColors.brandPurple.withValues(alpha: 0.3), AuraColors.brandPink.withValues(alpha: 0.14)]),
              border: Border.all(color: AuraColors.accentGlow.withValues(alpha: 0.6)),
            )
          : AuraGlass.decoration(radius: 18, shadow: false),
      child: row,
    );
  }
}
