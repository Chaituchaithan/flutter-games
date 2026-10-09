import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/tournament.dart';
import '../../data/repositories/store_repository.dart';
import '../../data/repositories/tournaments_repository.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';

/// Tournaments (mockup `isTournaments`): header with your Tokens · Live /
/// Upcoming / Past tabs · on Live, the Neon Cup hero + bracket · Events list.
///
/// Navigation: back → Home. Join → "Not enough balance" if the fee is above
/// your Tokens (Buy more → Store tab), else "You're in!" and the button turns
/// into "Joined ✓". Live events show Watch, past events show Results.
/// Events load through [tournamentEventsProvider] (skeleton while waiting).
class TournamentsScreen extends ConsumerStatefulWidget {
  const TournamentsScreen({super.key});

  @override
  ConsumerState<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends ConsumerState<TournamentsScreen> {
  int _tab = 0; // 0 Live · 1 Upcoming · 2 Past

  static const _states = [TournamentState.live, TournamentState.upcoming, TournamentState.ended];

  String _tokens() =>
      ref.watch(walletProvider).maybeWhen(data: (w) => w.gems, orElse: () => '5,000');

  int _tokenBalance() => int.tryParse(_tokens().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  /// Events you've joined this session (their CTA turns into "Joined").
  final Set<String> _joined = {};

  /// Realistic CTA per event state (the mockup's prototype shows "Join" on
  /// past events and a "You're in!" dialog for Watch — a real app doesn't):
  /// upcoming/not-yet-live → Join (balance check → "You're in!" → Joined);
  /// live → Watch (spectating isn't available yet); past → Results.
  Future<void> _onCta(Tournament t) async {
    if (t.state == TournamentState.ended) {
      await showAuraDialog(
        context,
        icon: Icons.emoji_events_outlined,
        title: t.name,
        body: '${t.when} · ${t.players} players · ${t.prize} prize pool.',
        primaryLabel: 'Close',
      );
      return;
    }
    if (t.live) {
      showAuraToast(context, 'Live spectating opens in a future update', kind: AuraToastKind.info);
      return;
    }
    if (_joined.contains(t.name)) return;
    if (t.fee > _tokenBalance()) {
      final buyMore = await showInsufficientBalanceDialog(context);
      if (buyMore == true && mounted) Navigator.pop(context, 'store'); // Home opens the Store tab
      return;
    }
    if (!mounted) return;
    setState(() => _joined.add(t.name));
    await showAuraDialog(
      context,
      icon: Icons.check_rounded,
      title: "You're in!",
      body: 'Your seat is reserved. We will notify you when the bracket goes live.',
      primaryLabel: 'Great',
      tone: AuraDialogTone.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _states[_tab];
    return AuraScaffold(
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          _Header(tokens: _tokens()),
          const SizedBox(height: 16),
          SegmentedTabs(
            labels: const ['Live', 'Upcoming', 'Past'],
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          if (_tab == 0) ...[
            const SizedBox(height: 16),
            const _NeonCupHero(),
            const SizedBox(height: 22),
            const SectionBar('Bracket'),
            const SizedBox(height: 12),
            const _Bracket(),
          ],
          const SizedBox(height: 22),
          const SectionBar('Events'),
          const SizedBox(height: 12),
          AsyncView<List<Tournament>>(
            value: ref.watch(tournamentEventsProvider(state)),
            onRetry: () => ref.invalidate(tournamentEventsProvider(state)),
            data: (events) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in events) ...[
                  _EventCard(
                    event: e,
                    joined: _joined.contains(e.name),
                    onCta: () => _onCta(e),
                  ),
                  const SizedBox(height: 11),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Mockup header: 42px glass back button · "Tournaments" · cyan Tokens pill.
class _Header extends StatelessWidget {
  const _Header({required this.tokens});
  final String tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.05)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            ),
            child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Tournaments', style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 22, color: Colors.white)),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(7, 5, 10, 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [const Color(0xFF22D3EE).withValues(alpha: 0.24), const Color(0xFF22D3EE).withValues(alpha: 0.06)],
            ),
            border: Border.all(color: const Color(0xFF22D3EE).withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CurrencyGlyph(kind: Currency.gems, size: 15),
              const SizedBox(width: 5),
              Text(tokens, style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Live hero: "LIVE · ROUND OF 16" pill, ends-in, "Neon Cup", 3 stat tiles.
class _NeonCupHero extends StatelessWidget {
  const _NeonCupHero();

  @override
  Widget build(BuildContext context) {
    // Shadow on an opaque base: a BoxShadow under a translucent fill would
    // show through as an inner panel.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0A16),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: AuraColors.brandPurple.withValues(alpha: 0.8), blurRadius: 40, spreadRadius: -16, offset: const Offset(0, 18))],
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AuraColors.brandPurple.withValues(alpha: 0.32), AuraColors.brandPink.withValues(alpha: 0.14)],
          ),
          border: Border.all(color: AuraColors.accentGlow.withValues(alpha: 0.55), width: 1.5),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [AuraColors.brandPink.withValues(alpha: 0.4), AuraColors.brandPink.withValues(alpha: 0)], stops: const [0, 0.7]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Container(
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
                              decoration: const BoxDecoration(
                                color: AuraColors.green,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: AuraColors.green, blurRadius: 8)],
                              ),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'LIVE · ROUND OF 16',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 11, color: AuraColors.green),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ),
                      const SizedBox(width: 8),
                      Text('Ends in 2h 14m', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('Neon Cup', style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 26, color: Colors.white)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _HeroStat(
                          label: 'PRIZE POOL',
                          child: Row(
                            children: [
                              const CurrencyGlyph(kind: Currency.gems, size: 15),
                              const SizedBox(width: 5),
                              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text('50,000', style: _statValue(Colors.white)))),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _HeroStat(label: 'YOUR SEED', child: Text('#12', style: _statValue(const Color(0xFFFBBF24))))),
                      const SizedBox(width: 8),
                      Expanded(child: _HeroStat(label: 'PLAYERS', child: Text('128', style: _statValue(Colors.white)))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static TextStyle _statValue(Color c) => TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 17, color: c);
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w600, fontSize: 10, letterSpacing: 0.8, color: Colors.white.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 3),
          child,
        ],
      ),
    );
  }
}

/// Mockup bracket: QF (4 matches) → SF (2) → Final (?), winner = green dot +
/// bold, loser dimmed. Scrolls sideways on narrow screens.
class _Bracket extends StatelessWidget {
  const _Bracket();

  // (a, b, winner: 0 = a, 1 = b, -1 = not played)
  static const _rounds = [
    ('QF', [('ZeroCool', 'NovaKid', 1), ('You', 'IronByte', 0), ('LunaWolf', 'StormFox', 0), ('AcePilot', 'PixelGhost', 1)]),
    ('SF', [('ZeroCool', 'You', -1), ('LunaWolf', 'PixelGhost', -1)]),
    ('Final', [('?', '?', -1)]),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: 0.09), Colors.white.withValues(alpha: 0.03)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // Each round ≥ 96px wide (mockup min-width); scroll if they don't fit.
          final colWidth = ((c.maxWidth - 16) / 3).clamp(96.0, double.infinity);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _rounds.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    SizedBox(
                      width: colWidth,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Text(
                            _rounds[i].$1.toUpperCase(),
                            style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 1, color: Colors.white.withValues(alpha: 0.5)),
                          ),
                          for (final m in _rounds[i].$2) ...[
                            const SizedBox(height: 8),
                            _MatchCell(a: m.$1, b: m.$2, winner: m.$3),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MatchCell extends StatelessWidget {
  const _MatchCell({required this.a, required this.b, required this.winner});
  final String a;
  final String b;
  final int winner;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          _slot(a, winner == 0, winner == 1, top: true),
          _slot(b, winner == 1, winner == 0),
        ],
      ),
    );
  }

  Widget _slot(String name, bool won, bool lost, {bool top = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: top ? BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.12)))) : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: won ? FontWeight.w700 : FontWeight.w500, color: lost ? Colors.white.withValues(alpha: 0.4) : Colors.white),
            ),
          ),
          if (won) Container(width: 6, height: 6, decoration: const BoxDecoration(color: AuraColors.green, shape: BoxShape.circle)),
        ],
      ),
    );
  }
}

/// Event card (mockup): gradient icon tile · name (+ live dot) · when · fee ·
/// CTA, then prize · fill bar · players.
class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onCta, this.joined = false});
  final Tournament event;
  final VoidCallback onCta;
  final bool joined;

  String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  @override
  Widget build(BuildContext context) {
    final e = event;
    final grad = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: e.colors);
    return Container(
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
                            e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 15.5, color: Colors.white),
                          ),
                        ),
                        if (e.live) ...[
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
                      '${e.when} · ${e.fee == 0 ? 'Free entry' : '${_fmt(e.fee)} entry'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onCta,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                  decoration: BoxDecoration(
                    // Joined / past events read as secondary (glass), not a call to action.
                    gradient: joined || e.state == TournamentState.ended ? null : AuraGradients.brand,
                    color: joined || e.state == TournamentState.ended ? Colors.white.withValues(alpha: 0.08) : null,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    e.state == TournamentState.ended ? 'Results' : (e.live ? 'Watch' : (joined ? 'Joined ✓' : 'Join')),
                    style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white),
                  ),
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
                flex: 2,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: e.prize, style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, color: const Color(0xFFFBBF24))),
                    TextSpan(text: ' prize', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
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
                    widthFactor: e.fill,
                    child: Container(decoration: BoxDecoration(gradient: grad, borderRadius: BorderRadius.circular(99))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(e.players, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.55))),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
