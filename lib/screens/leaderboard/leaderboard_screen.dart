import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/rank_entry.dart';
import '../../data/repositories/leaderboard_repository.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';
import '../social/player_profile_screen.dart';

/// Leaderboard — top-3 podium + your-rank strip + ranked list.
/// Reads via `leaderboardProvider` (static source today; live API when remote
/// sources are switched on). Mirrors the mockup's `isLeaderboard`.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  int _tab = 0;

  static const _scopes = ['global', 'friends', 'weekly'];

  @override
  Widget build(BuildContext context) {
    final scope = _scopes[_tab];
    final board = ref.watch(leaderboardProvider(scope));

    return AuraScaffold(
      appBar: AuraAppBar(
        title: 'Leaderboard',
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AuraColors.accentGlow.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AuraColors.accentGlow.withValues(alpha: 0.35)),
          ),
          child: Text(
            'Season 4',
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: AuraColors.accentGlow,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          SegmentedTabs(
            labels: const ['Global', 'Friends', 'Weekly'],
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 24),
          AsyncView<List<RankEntry>>(
            value: board,
            onRetry: () => ref.invalidate(leaderboardProvider(scope)),
            data: _board,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _board(List<RankEntry> entries) {
    if (entries.length < 3) return const SizedBox.shrink();
    final rest = entries.skip(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Podium(first: entries[0], second: entries[1], third: entries[2]),
        _YourRankStrip(),
        const SizedBox(height: 16),
        for (final r in rest) ...[
          _RankRow(rank: r),
          const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.first, required this.second, required this.third});
  final RankEntry first;
  final RankEntry second;
  final RankEntry third;

  static const _silver = LinearGradient(colors: [Color(0xFFE2E8F0), Color(0xFF94A3B8)]);
  static const _gold = LinearGradient(colors: [AuraColors.goldLight, AuraColors.gold]);
  static const _bronze = LinearGradient(colors: [Color(0xFFFDBA74), Color(0xFFC2410C)]);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _spot(second, _silver, 64, 44)),
          Expanded(child: _spot(first, _gold, 82, 66)),
          Expanded(child: _spot(third, _bronze, 64, 30)),
        ],
      ),
    );
  }

  Widget _spot(RankEntry r, Gradient medal, double avatar, double pedestal) {
    return Column(
      children: [
        SizedBox(
          width: avatar,
          height: avatar + 8,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                width: avatar,
                height: avatar,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: medal),
                child: LetterAvatar(letter: r.name[0], color: r.color, size: avatar - 8),
              ),
              Positioned(
                bottom: -6,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: medal,
                    shape: BoxShape.circle,
                    border: Border.all(color: AuraColors.bgBase, width: 2),
                  ),
                  child: Text('${r.rank}',
                      style: TextStyle(fontFamily: AuraText.displayFamily, color: const Color(0xFF1A1206), fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(r.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(r.pts, style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.amber, fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Container(
          height: pedestal,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0.03)],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
        ),
      ],
    );
  }
}

class _YourRankStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AuraColors.brandPurple.withValues(alpha: 0.3), AuraColors.brandPink.withValues(alpha: 0.14)],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
        border: Border.all(color: AuraColors.accentGlow.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const LetterAvatar(letter: 'N', color: AuraColors.brandPurple, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your rank', style: AuraText.cardTitle.copyWith(fontSize: 14)),
                const SizedBox(height: 1),
                Text('4,930 pts · Gold III', style: AuraText.cardSub.copyWith(fontSize: 11.5)),
              ],
            ),
          ),
          Text('#17',
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(color: AuraColors.accentGlow.withValues(alpha: 0.8), blurRadius: 18)],
              )),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank});
  final RankEntry rank;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      padding: const EdgeInsets.all(11),
      onTap: () {
        final lv = int.tryParse((rank.level ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PlayerProfileScreen(
            name: rank.name,
            color: rank.color,
            level: lv,
            rank: '#${rank.rank}',
            online: false,
          ),
        ));
      },
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('${rank.rank}',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          LetterAvatar(letter: rank.name[0], color: rank.color, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rank.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.cardTitle.copyWith(fontSize: 14)),
                const SizedBox(height: 1),
                Text(rank.level ?? '', style: AuraText.cardSub.copyWith(fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.star_rounded, color: AuraColors.amber, size: 15),
          const SizedBox(width: 4),
          Text(rank.pts,
              style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
