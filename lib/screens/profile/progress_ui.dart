import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../configs/games/core/game_codes.dart';
import '../../configs/games/games.dart';
import '../../data/models/progress.dart';
import '../../services/catalogue_service.dart';
import '../../services/progress_service.dart';
import '../../services/rewards_service.dart';
import '../../widgets/aura.dart';
import '../leaderboard/leaderboard_screen.dart';
import 'level_up_screen.dart';

/// Progress widgets (docs/services/08-progress-and-history.md): the Profile
/// cards (one per game played), the game page header and the result screen's
/// "+N XP" line, plus [progressAfterGame], run when a game ends.

/// A game's name and icon from the catalogue by numeric id.
({String name, String icon, String? code}) progressGameLabel(List<CatalogueGame>? games, int gameId, {String? fallbackName, String? code}) {
  final g = catalogueGameById(games, gameId);
  final c = g?.code ?? code;
  final info = c == null ? null : GameCodes.info(c);
  return (name: g?.name ?? fallbackName ?? 'Game', icon: info?.icon ?? '🎮', code: c);
}

/// The XP bar: `xp / (100 × level)`.
class XpBar extends StatelessWidget {
  const XpBar({super.key, required this.fraction, this.height = 8});
  final double fraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: height,
        color: Colors.black.withValues(alpha: 0.35),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0.0, 1.0),
          heightFactor: 1,
          child: const DecoratedBox(decoration: BoxDecoration(gradient: AuraGradients.brand)),
        ),
      ),
    );
  }
}

/// "Rating 1016 (best 1016)" / "Rating 1016" / "Unranked".
String ratingText(GameRating? r, {GameMmr? mmr}) {
  if (r == null) return 'Unranked';
  final best = mmr?.peakMmr;
  return best == null || best <= r.whole ? 'Rating ${r.whole}' : 'Rating ${r.whole} (best $best)';
}

/// Profile → Progress: one card per game in `GET /progression/levels`. An
/// empty list shows a hint, never an error.
class ProgressCards extends ConsumerStatefulWidget {
  const ProgressCards({super.key});

  @override
  ConsumerState<ProgressCards> createState() => _ProgressCardsState();
}

class _ProgressCardsState extends ConsumerState<ProgressCards> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(progressStoreProvider.notifier).refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(progressStoreProvider);
    final games = ref.watch(progressGamesProvider).value;
    if (!s.loaded) {
      if (s.error != null) return _note(s.error!, retry: true);
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2))),
      );
    }
    if (s.levels.isEmpty) return _note('Finish a match to start levelling up.');
    return Column(
      children: [
        for (final l in s.levels) ...[
          _GameCard(level: l, rating: s.ratingFor(l.gameId), label: progressGameLabel(games, l.gameId)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _note(String text, {bool retry = false}) => AuraCard(
        child: Row(
          children: [
            Expanded(child: Text(text, style: AuraText.cardSub)),
            if (retry)
              TextButton(
                onPressed: () => ref.read(progressStoreProvider.notifier).refresh(force: true),
                child: const Text('Retry'),
              ),
          ],
        ),
      );
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.level, required this.rating, required this.label});
  final GameLevel level;
  final GameRating? rating;
  final ({String name, String icon, String? code}) label;

  @override
  Widget build(BuildContext context) {
    final r = rating;
    return AuraCard(
      padding: const EdgeInsets.all(14),
      onTap: label.code == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LeaderboardScreen(gameCode: label.code))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label.icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.cardTitle),
              ),
              AuraBadge('Level ${level.level}', color: AuraColors.accentGlow),
            ],
          ),
          const SizedBox(height: 10),
          XpBar(fraction: level.fraction),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('${level.xp} / ${level.xpNeeded} XP', style: AuraText.cardSub.copyWith(fontSize: 11.5)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  // W / L / D over every mode; forfeits are in none of them.
                  r == null ? 'Unranked' : '${ratingText(r)}  ·  ${r.wins}/${r.losses}/${r.draws} W/L/D',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AuraText.cardSub.copyWith(fontSize: 11.5, color: r == null ? null : Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Game page header: "Level 2", the XP bar and "Rating 1016 (best 1016)" or
/// "Unranked" for [gameCode] (`GET /progression/{game_id}/stats`). Each part
/// may be null on its own; nothing here ever fails loudly.
class GameProgressHeader extends ConsumerWidget {
  const GameProgressHeader({super.key, required this.gameCode});
  final String gameCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(progressGameIdProvider(gameCode)).value;
    if (id == null) return const SizedBox.shrink();
    final stats = ref.watch(gameStatsProvider(id)).value;
    if (stats == null) return const SizedBox.shrink();
    final level = stats.level ?? GameLevel.none(id);
    return AuraCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LeaderboardScreen(gameCode: gameCode))),
      child: Row(
        children: [
          AuraBadge('Level ${level.level}', color: AuraColors.accentGlow),
          const SizedBox(width: 10),
          Expanded(child: XpBar(fraction: level.fraction, height: 7)),
          const SizedBox(width: 10),
          Text(ratingText(stats.rating, mmr: stats.mmr), style: AuraText.cardSub.copyWith(fontSize: 11.5)),
        ],
      ),
    );
  }
}

/// The result screen's progress line ("+100 XP · +16 rating"), shown once
/// the re-read after this game lands. Hidden until then, and for changes
/// from before this screen opened.
class PostMatchProgressLine extends ConsumerStatefulWidget {
  const PostMatchProgressLine({super.key});

  @override
  ConsumerState<PostMatchProgressLine> createState() => _PostMatchProgressLineState();
}

class _PostMatchProgressLineState extends ConsumerState<PostMatchProgressLine> {
  late final int _openedAt = ref.read(progressStoreProvider).revision;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(progressStoreProvider);
    final d = s.lastDelta;
    if (d == null || s.revision <= _openedAt || !d.changed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        [d.summary, if (d.leveledUp) 'Level ${d.newLevel}!'].join('  ·  '),
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.goldLight, fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// After a game ends ("After a game"): re-read that game's stats (one retry
/// after 2 s when nothing moved), update the [ProgressStore] and, on a
/// level-up, show the celebration with the `level_up` bonus game when one is
/// offered. Nothing is shown once [context] unmounts.
Future<void> progressAfterGame(WidgetRef ref, BuildContext context, {GameConfig? game, String? result}) async {
  if (game == null) return;
  final code = GameCodes.all.where((g) => g.id == game.id).firstOrNull?.code;
  if (code == null) return;
  final repo = ref.read(catalogueRepositoryProvider);
  final CatalogueGame? cat;
  try {
    cat = await repo.gameByCode(code);
  } on Object catch (_) {
    return;
  }
  if (cat == null || !context.mounted) return;
  final delta = await ref.read(progressStoreProvider.notifier).afterGame(cat.id, result: result);
  if (delta == null || !delta.leveledUp || !context.mounted) return;
  final level = delta.newLevel!;
  final gameId = cat.id;
  final offer = await levelUpBonusGame(ref.read(rewardsApiProvider));
  if (!context.mounted) return;
  final nav = Navigator.of(context);
  await showLevelUp(
    context,
    level: level,
    gameName: cat.name,
    rewardLabel: offer?.name,
    onReward: offer == null
        ? null
        : () => nav.pushNamed(Routes.bonusGame, arguments: {
              'code': offer.code,
              'trigger': 'level_up',
              'triggerRef': levelUpTriggerRef(gameId, level),
            }),
  );
}

/// `trigger_ref` of a `level_up` bonus play: `"<game_id>:<level>"`.
String levelUpTriggerRef(int gameId, int level) => '$gameId:$level';

/// The `level_up` bonus game the player may play now, or null (none
/// published, blocked, or the read failed).
Future<BonusGameOffer?> levelUpBonusGame(RewardsApi api) async {
  try {
    final games = await api.bonusGames(trigger: 'level_up');
    final g = games.where((g) => g.me.blockReason == null).firstOrNull;
    return g == null ? null : (code: g.code, name: g.name);
  } on Object catch (_) {
    return null;
  }
}

typedef BonusGameOffer = ({String code, String name});
