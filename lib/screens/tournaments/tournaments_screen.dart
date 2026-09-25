import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/tournament.dart';
import '../../data/repositories/tournaments_repository.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';

/// Tournaments — Live / Upcoming / Ended. Reads via `tournamentEventsProvider`
/// (static source today; live API when remote sources are switched on).
/// Mirrors the mockup's `isTournaments` screen.
class TournamentsScreen extends ConsumerStatefulWidget {
  const TournamentsScreen({super.key});

  @override
  ConsumerState<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends ConsumerState<TournamentsScreen> {
  int _tab = 0; // 0 Live · 1 Upcoming · 2 Ended

  static const _states = [
    TournamentState.live,
    TournamentState.upcoming,
    TournamentState.ended,
  ];

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: AuraAppBar(
        title: 'Tournaments',
        trailing: const CurrencyPill(kind: Currency.gems, amount: '5,000', showPlus: false),
      ),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          SegmentedTabs(
            labels: const ['Live', 'Upcoming', 'Ended'],
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 16),
          if (_tab == 0) ...[
            const _NeonCupHero(),
            const SizedBox(height: 22),
            const SectionBar('Bracket'),
            const SizedBox(height: 12),
            const _Bracket(),
          ],
          const SizedBox(height: 22),
          SectionBar(_tab == 2 ? 'Past events' : 'Events'),
          const SizedBox(height: 12),
          AsyncView<List<Tournament>>(
            value: ref.watch(tournamentEventsProvider(_states[_tab])),
            onRetry: () => ref.invalidate(tournamentEventsProvider(_states[_tab])),
            data: (events) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in events) ...[
                  _EventCard(event: e),
                  const SizedBox(height: 11),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _NeonCupHero extends StatelessWidget {
  const _NeonCupHero();

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      radius: AuraRadii.xl,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AuraColors.brandPurple.withValues(alpha: 0.32),
          AuraColors.brandPink.withValues(alpha: 0.14),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _LivePill(text: 'LIVE · ROUND OF 16'),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ends in 2h 14m',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AuraText.cardSub.copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Neon Cup', style: AuraText.headline.copyWith(fontSize: 26)),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(child: _HeroStat(label: 'PRIZE POOL', value: '50,000', gem: true)),
              SizedBox(width: 8),
              Expanded(child: _HeroStat(label: 'YOUR SEED', value: '#12', valueColor: AuraColors.amber)),
              SizedBox(width: 8),
              Expanded(child: _HeroStat(label: 'PLAYERS', value: '128')),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value, this.gem = false, this.valueColor});
  final String label;
  final String value;
  final bool gem;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AuraText.section.copyWith(fontSize: 10, letterSpacing: 0.8)),
          const SizedBox(height: 3),
          Row(
            children: [
              if (gem) ...[const CurrencyGlyph(kind: Currency.gems, size: 14), const SizedBox(width: 5)],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontFamily: AuraText.displayFamily,
                      color: valueColor ?? Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AuraColors.green.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AuraColors.green.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AuraColors.green,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AuraColors.green.withValues(alpha: 0.8), blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(color: AuraColors.green, fontSize: 10.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// A tiny 3-round bracket in a horizontally-scrolling glass card.
class _Bracket extends StatelessWidget {
  const _Bracket();

  static const _rounds = [
    ('R16', [('You', 'RivalX', true), ('KZ', 'LW', false)]),
    ('QF', [('You', 'KZ', true)]),
    ('SF', [('You', '—', false)]),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AuraGlass.decoration(radius: AuraRadii.lg),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in _rounds) ...[
              _RoundColumn(round: r.$1, matches: r.$2),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoundColumn extends StatelessWidget {
  const _RoundColumn({required this.round, required this.matches});
  final String round;
  final List<(String, String, bool)> matches;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: Column(
        children: [
          Text(
            round,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: AuraColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          for (final m in matches) ...[
            _MatchCell(a: m.$1, b: m.$2, aWins: m.$3),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _MatchCell extends StatelessWidget {
  const _MatchCell({required this.a, required this.b, required this.aWins});
  final String a;
  final String b;
  final bool aWins;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          _slot(a, aWins),
          Divider(height: 1, thickness: 1, color: Colors.white.withValues(alpha: 0.12)),
          _slot(b, !aWins && b != '—'),
        ],
      ),
    );
  }

  Widget _slot(String name, bool win) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: win ? Colors.white : AuraColors.textSecondary,
                fontSize: 11.5,
                fontWeight: win ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (win)
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(color: AuraColors.green, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final Tournament event;

  @override
  Widget build(BuildContext context) {
    final ended = event.state == TournamentState.ended;
    return AuraCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AuraColors.goldLight, AuraColors.gold]),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.emoji_events, color: Color(0xFF7C2D12), size: 22),
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
                            event.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AuraText.cardTitle.copyWith(fontSize: 15.5),
                          ),
                        ),
                        if (event.state == TournamentState.live) ...[
                          const SizedBox(width: 7),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: AuraColors.green,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: AuraColors.green.withValues(alpha: 0.8), blurRadius: 8)],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${event.when} · ${event.fee}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.cardSub.copyWith(fontSize: 11.5)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _EventCta(label: event.cta, ended: ended),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const CurrencyGlyph(kind: Currency.gems, size: 14),
              const SizedBox(width: 5),
              Text.rich(
                TextSpan(
                  style: AuraText.cardSub.copyWith(fontSize: 11.5),
                  children: [
                    TextSpan(
                      text: event.prize,
                      style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.amber, fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(text: ' prize'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: 6,
                    color: Colors.black.withValues(alpha: 0.35),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: event.fill,
                      child: Container(
                        decoration: const BoxDecoration(gradient: AuraGradients.brand),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(event.players, style: AuraText.cardSub.copyWith(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventCta extends StatelessWidget {
  const _EventCta({required this.label, required this.ended});
  final String label;
  final bool ended;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final (msg, kind) = switch (label) {
          'Register' => ('Registered — good luck!', AuraToastKind.success),
          'Recap' => ('Recap coming soon', AuraToastKind.info),
          _ => ('Entering tournament…', AuraToastKind.info),
        };
        showAuraToast(context, msg, kind: kind);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: ended
            ? AuraGlass.decoration(radius: 12, shadow: false)
            : BoxDecoration(
                gradient: AuraGradients.brand,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
