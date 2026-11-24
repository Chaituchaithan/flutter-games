import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_profile.dart';
import '../../configs/games/core/game_codes.dart';
import '../../configs/games/core/game_id.dart';
import '../../data/models/tournament.dart';
import '../../services/catalogue_service.dart';
import '../../services/session.dart';
import '../../services/tournament_api.dart';
import '../../services/tournament_controller.dart';
import '../../services/wallet_store.dart';
import '../../widgets/aura.dart';
import '../../widgets/wallet_pill.dart';
import 'tournament_results_screen.dart';
import 'tournaments_screen.dart';

/// Games whose app screen can play a tournament table today (the socket's
/// `room.join` with the table's `room_code`, 06 §6).
const tournamentTableGames = {GameId.ludo, GameId.snakesLadders};

/// Tournament detail (06 §2-§7): name, game, format, price, seats, prize
/// pool, start, the player's entry, and one main button (Join / Leave / Go
/// to table / Results). Re-reads every 10 s while registering or running
/// ([TournamentController]); opens the table at once when it is ready.
///
/// Pops 'store' for "Buy more", 'reload' when the tournament was removed.
class TournamentDetailScreen extends ConsumerStatefulWidget {
  const TournamentDetailScreen({super.key, required this.tournament, this.autoOpenTable = true});

  /// The lobby row (shown until the first read).
  final Tournament tournament;

  /// Open the game as soon as the table is ready (tests turn it off).
  final bool autoOpenTable;

  @override
  ConsumerState<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends ConsumerState<TournamentDetailScreen> {
  late final TournamentController _c;
  late final AppLifecycleListener _life;
  Timer? _clock;
  final Set<String> _autoOpened = {};
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    final joined = ref.read(joinedTournamentsProvider.notifier);
    _c = TournamentController(
      api: ref.read(tournamentApiProvider),
      id: widget.tournament.id,
      initial: widget.tournament,
      gameName: _gameName(widget.tournament.gameId) ?? 'this game',
      onMoneyMoved: () => unawaited(ref.read(walletProvider.notifier).moneyMoved()),
      onEntered: joined.add,
      onLeft: joined.remove,
    )..addListener(_onChange);
    _life = AppLifecycleListener(onHide: _c.pause, onShow: () => unawaited(_c.resume()));
    // Countdowns (seat deadline, start).
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_c.phase == TournamentPhase.tableReady || _c.startsIn != null)) setState(() {});
    });
    unawaited(_c.start());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _life.dispose();
    _c
      ..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }

  String? _gameName(int gameId) =>
      ref.read(catalogueGamesProvider).value?.where((g) => g.id == gameId).firstOrNull?.name;

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (_c.phase == TournamentPhase.gone && !_leaving) {
      _leaving = true;
      showAuraToast(context, 'This tournament is no longer available.', kind: AuraToastKind.info);
      Navigator.of(context).maybePop('reload');
      return;
    }
    // The table is ready and the player is here: open the game at once.
    final table = _c.myTable?.table;
    final route = ModalRoute.of(context);
    if (widget.autoOpenTable &&
        _c.phase == TournamentPhase.tableReady &&
        table != null &&
        (route?.isCurrent ?? false) &&
        _autoOpened.add(table.matchId ?? table.roomCode ?? '')) {
      unawaited(_goToTable());
    }
  }

  // ── The game hand-off (06 §6) ──

  /// The app's module for the tournament's game, when it can play a table.
  ({GameId id, String route})? _tableRoute() {
    final t = _c.tournament ?? widget.tournament;
    final code = ref.read(catalogueGamesProvider).value?.where((g) => g.id == t.gameId).firstOrNull?.code;
    GameId? id = code == null ? null : GameCodes.info(code)?.id;
    if (!AppProfile.isSet) return null;
    final profile = AppProfile.current;
    // Catalogue not loaded: a one-game app plays its own game.
    id ??= profile.singleGame ? profile.modules.first.id : null;
    if (id == null || !tournamentTableGames.contains(id)) return null;
    final route = profile.module(id)?.onlineRoute;
    return route == null ? null : (id: id, route: route);
  }

  Future<void> _goToTable() async {
    final table = _c.myTable?.table;
    final code = table?.roomCode;
    if (table == null || code == null || code.isEmpty) return;
    final target = _tableRoute();
    if (target == null) {
      showAuraToast(context, 'Open ${_gameName(_c.tournament?.gameId ?? 0) ?? 'this game'} to play your table.', kind: AuraToastKind.info);
      return;
    }
    _c.wentToTable();
    await Navigator.of(context).pushNamed(target.route, arguments: {
      'mode': 'join',
      'code': code,
      'tournament': true,
      'players': table.players.length,
    });
    if (!mounted) return;
    // Back from the game: place, then the tournament, my-table, standings.
    await _c.backFromTable();
  }

  // ── Join / leave (06 §4) ──

  Future<void> _join() async {
    final t = _c.tournament!;
    final have = walletBalance(ref, t.currency.currency);
    final ok = await showJoinTournamentSheet(context, tournament: t, balance: have);
    if (ok != true || !mounted) return;
    final issue = await _c.join();
    if (!mounted) return;
    if (issue == null) {
      showAuraToast(context, "You're in");
      return;
    }
    await _handle(issue);
  }

  Future<void> _leave() async {
    final t = _c.tournament!;
    final ok = await showAuraDialog(
      context,
      icon: Icons.logout_rounded,
      title: 'Leave the tournament?',
      body: t.isFree ? 'You can join again while it is open.' : 'Your ${formatCount(t.totalCost)} ${t.currency.noun} will be refunded.',
      primaryLabel: 'Leave',
      secondaryLabel: 'Stay',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final issue = await _c.leave();
    if (!mounted) return;
    if (issue == null) {
      showAuraToast(context, t.isFree ? 'You left the tournament' : 'You left. ${formatCount(t.totalCost)} ${t.currency.noun} refunded');
      return;
    }
    await _handle(issue);
  }

  Future<void> _handle(TournamentIssue issue) async {
    switch (issue.fix) {
      case TournamentFix.shop:
        final buy = await showInsufficientBalanceDialog(context);
        if (buy == true && mounted) Navigator.pop(context, 'store');
      case TournamentFix.membership:
        final see = await showAuraDialog(
          context,
          icon: Icons.workspace_premium_rounded,
          title: issue.text ?? 'Members only',
          body: 'This tournament is for members. See the membership plans in the Store.',
          primaryLabel: 'See membership',
          secondaryLabel: 'Not now',
          tone: AuraDialogTone.warning,
        );
        if (see == true && mounted) Navigator.pop(context, 'store');
      case TournamentFix.nextCopy:
        await _offerNextCopy(issue.text);
      case TournamentFix.reloadLobby:
        // The controller turned to `gone`: _onChange goes back.
        break;
      case TournamentFix.none:
      case TournamentFix.refresh:
      case TournamentFix.disableJoin:
        if (issue.text != null) showAuraToast(context, issue.text!, kind: AuraToastKind.error);
    }
  }

  /// `TOURNAMENT_FULL`: reload the list and offer the Sit & Go's new copy.
  Future<void> _offerNextCopy(String? text) async {
    final t = _c.tournament!;
    Tournament? next;
    try {
      next = await findNextCopy(ref.read(tournamentApiProvider), t);
    } on Object {
      next = null;
    }
    if (!mounted) return;
    if (next == null) {
      showAuraToast(context, text ?? 'This tournament is full.', kind: AuraToastKind.error);
      return;
    }
    final go = await showAuraDialog(
      context,
      icon: Icons.event_seat_rounded,
      title: text ?? 'This tournament is full.',
      body: 'A new ${t.name} is open (${next.seatsText}). Join that one?',
      primaryLabel: 'Open it',
      secondaryLabel: 'Not now',
    );
    if (go == true && mounted) {
      final copy = next;
      unawaited(Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TournamentDetailScreen(tournament: copy, autoOpenTable: widget.autoOpenTable)),
      ));
    }
  }

  void _results() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TournamentResultsScreen(tournament: _c.tournament ?? widget.tournament, initial: _c.standings),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = _c.tournament ?? widget.tournament;
    final gameName = _gameName(t.gameId);
    return AuraScaffold(
      appBar: AuraAppBar(title: t.name, trailing: WalletPill(kind: t.currency.currency, showPlus: false)),
      body: RefreshIndicator(
        onRefresh: _c.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 6),
            _Hero(t: t, gameName: gameName, startsIn: _c.startsIn),
            const SizedBox(height: 16),
            _StatusPanel(c: _c, onGo: _goToTable),
            if (_c.myTable?.table != null && _c.phase != TournamentPhase.cancelled) ...[
              const SizedBox(height: 16),
              _TablePanel(table: _c.myTable!.table!, myUserId: ref.watch(currentUserProvider).id),
            ],
            const SizedBox(height: 20),
            _MainButton(c: _c, onJoin: _join, onLeave: _leave, onGo: _goToTable, onResults: _results),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Top card: format · status chips, name, game, then prize pool / price /
/// seats tiles and the start line.
class _Hero extends StatelessWidget {
  const _Hero({required this.t, required this.gameName, required this.startsIn});
  final Tournament t;
  final String? gameName;
  final Duration? startsIn;

  @override
  Widget build(BuildContext context) {
    final colors = tournamentColors(t);
    final pool = t.status.isCancelled ? '—' : (t.prizePool > 0 ? formatCount(t.prizePool) : '0');
    final start = t.isSitAndGo
        ? 'Starts when full'
        : t.startsAt == null
            ? null
            : (startsIn != null && startsIn! > Duration.zero && !t.status.isOver && t.status != TournamentStatus.running
                ? 'Starts in ${formatStartsIn(startsIn!)} · ${formatLocalStart(t.startsAt!)}'
                : formatLocalStart(t.startsAt!));
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.first.withValues(alpha: 0.32), colors.last.withValues(alpha: 0.14)],
        ),
        border: Border.all(color: AuraColors.accentGlow.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Chip(text: t.type.label, color: Colors.white),
              _Chip(
                text: t.comingSoon && !t.status.isOver ? 'Coming soon' : t.status.label,
                color: switch (t.status) {
                  TournamentStatus.running => AuraColors.green,
                  TournamentStatus.cancelled || TournamentStatus.refunded => AuraColors.dangerText,
                  TournamentStatus.paused || TournamentStatus.announced => AuraColors.amber,
                  _ => AuraColors.badgeCyan,
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(t.name, style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 24, color: Colors.white)),
          if (gameName != null) ...[
            const SizedBox(height: 2),
            Text(gameName!, style: AuraText.cardSub),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Stat(label: 'PRIZE POOL', value: pool, glyph: t.currency.currency)),
              const SizedBox(width: 8),
              Expanded(child: _Stat(label: 'ENTRY', value: t.isFree ? 'Free' : '${formatCount(t.entryFee)} + ${formatCount(t.feeAmount)}')),
              const SizedBox(width: 8),
              Expanded(child: _Stat(label: 'SEATS', value: t.status.isCancelled ? '—' : t.seatsText)),
            ],
          ),
          const SizedBox(height: 10),
          if (t.poolText != null && t.prizePool == 0) Text(t.poolText!, style: AuraText.cardSub.copyWith(color: AuraColors.amber)),
          if (!t.isFree) Text('Entry: ${t.priceText} (buy-in + fee)', style: AuraText.cardSub),
          if (start != null) Text(start, style: AuraText.cardSub),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 10.5, letterSpacing: 0.6, color: color)),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.glyph});
  final String label;
  final String value;
  final Currency? glyph;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w600, fontSize: 10, letterSpacing: 0.8, color: Colors.white.withValues(alpha: 0.55))),
            const SizedBox(height: 3),
            Row(
              children: [
                if (glyph != null) ...[CurrencyGlyph(kind: glyph!, size: 14), const SizedBox(width: 4)],
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

/// The player's situation for the current phase (06 "Controller states").
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.c, required this.onGo});
  final TournamentController c;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final t = c.tournament;
    final m = c.myTable;
    if (t == null) return const SizedBox.shrink();
    switch (c.phase) {
      case TournamentPhase.loading:
        return const _Note(icon: Icons.hourglass_empty_rounded, title: 'Loading…');
      case TournamentPhase.failed:
        return _Note(icon: Icons.cloud_off_rounded, title: "Couldn't load", body: c.loadError?.message, color: AuraColors.dangerText);
      case TournamentPhase.gone:
        return const _Note(icon: Icons.info_outline_rounded, title: 'This tournament is no longer available.');
      case TournamentPhase.notEntered:
        if (t.comingSoon && !t.status.isOver) {
          return const _Note(
            icon: Icons.schedule_rounded,
            title: 'Coming soon',
            body: "This format can't be played in the app yet.",
          );
        }
        if (t.status == TournamentStatus.announced) {
          return const _Note(icon: Icons.schedule_rounded, title: 'Registration opens soon');
        }
        if (m?.entryStatus == EntryStatus.withdrawn && t.status == TournamentStatus.registering) {
          return const _Note(icon: Icons.logout_rounded, title: 'You left this tournament', body: 'Your entry was refunded. You can join again.');
        }
        return const SizedBox.shrink();
      case TournamentPhase.entered:
        final opening = m?.entryStatus == EntryStatus.active || t.status == TournamentStatus.running;
        if (opening) {
          return const _Note(icon: Icons.table_restaurant_rounded, title: 'Opening your table…', body: 'Stay on this screen; it takes a few seconds.', color: AuraColors.green);
        }
        return _Note(
          icon: Icons.check_circle_rounded,
          color: AuraColors.green,
          title: t.isSitAndGo ? "You're in. Waiting for players (${t.seatsText})" : "You're in",
          body: t.isSitAndGo
              ? "Stay on this screen, your table opens when it's full."
              : (t.startsAt == null ? null : 'Starts ${formatLocalStart(t.startsAt!)}.'),
        );
      case TournamentPhase.tableReady:
        final table = m!.table!;
        final left = c.seatTimeLeft;
        return _HandOff(table: table, left: left, onGo: onGo);
      case TournamentPhase.atTable:
        return const _Note(icon: Icons.sports_esports_rounded, title: 'At your table');
      case TournamentPhase.waitingResult:
        return const _Note(icon: Icons.hourglass_top_rounded, title: 'Results coming', body: 'The other tables may still be playing.');
      case TournamentPhase.finished:
        if (m?.entered != true) return const _Note(icon: Icons.emoji_events_rounded, title: 'Finished', color: AuraColors.amber);
        return _FinishedNote(c: c);
      case TournamentPhase.cancelled:
        final cost = '${formatCount(t.totalCost)} ${t.currency.noun}';
        final entered = m?.entered == true;
        if (!entered) return const _Note(icon: Icons.cancel_outlined, title: 'This tournament was cancelled.', color: AuraColors.dangerText);
        if (t.isFree) return const _Note(icon: Icons.cancel_outlined, title: 'This tournament was cancelled.', color: AuraColors.dangerText);
        return t.status == TournamentStatus.refunded
            ? _Note(icon: Icons.replay_rounded, title: 'This tournament was cancelled.', body: 'Your $cost have been refunded.', color: AuraColors.amber)
            : const _Note(icon: Icons.replay_rounded, title: 'Cancelled.', body: 'Your refund is on its way.', color: AuraColors.amber);
    }
  }
}

class _FinishedNote extends ConsumerWidget {
  const _FinishedNote({required this.c});
  final TournamentController c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = c.standingOf(ref.watch(currentUserProvider).id);
    final place = me?.place ?? c.myTable?.table?.place;
    final prize = me?.hasPrize == true ? 'Prize ${me!.prizeText}' : 'No prize this time';
    return _Note(
      icon: Icons.emoji_events_rounded,
      color: AuraColors.amber,
      title: place == null ? 'Finished' : 'You finished #$place',
      body: me == null ? null : prize,
    );
  }
}

/// "Your table is ready. Round 1, Table 1 · join within 1:58" + Go.
class _HandOff extends StatelessWidget {
  const _HandOff({required this.table, required this.left, required this.onGo});
  final TournamentTable table;
  final Duration? left;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    final late = left == Duration.zero;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AuraColors.green.withValues(alpha: 0.1),
        border: Border.all(color: AuraColors.green.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.table_restaurant_rounded, color: AuraColors.green),
              const SizedBox(width: 10),
              Expanded(child: Text('Your table is ready', style: AuraText.title)),
            ],
          ),
          const SizedBox(height: 6),
          Text(table.label, style: AuraText.cardTitle),
          if (left != null) ...[
            const SizedBox(height: 4),
            Text(
              late ? 'The seat deadline has passed.' : 'Join within ${formatClock(left!)}',
              style: AuraText.cardSub.copyWith(color: late ? AuraColors.dangerText : AuraColors.amber),
            ),
          ],
          const SizedBox(height: 12),
          GradientButton(label: 'Go', onPressed: onGo),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.title, this.body, this.color = AuraColors.badgeCyan});
  final IconData icon;
  final String title;
  final String? body;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AuraText.cardTitle),
                  if (body != null) ...[const SizedBox(height: 3), Text(body!, style: AuraText.cardSub)],
                ],
              ),
            ),
          ],
        ),
      );
}

/// Everyone at the player's table, in draw order.
class _TablePanel extends StatelessWidget {
  const _TablePanel({required this.table, required this.myUserId});
  final TournamentTable table;
  final String myUserId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionBar(table.label),
        const SizedBox(height: 10),
        for (final p in table.players)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: AuraGlass.decoration(radius: 14, shadow: false, border: p.playerId == myUserId ? AuraColors.accentGlow : null),
            child: Row(
              children: [
                SizedBox(width: 34, child: Text(p.place == null ? '–' : '#${p.place}', style: AuraText.cardTitle)),
                Expanded(
                  child: Text(p.playerId == myUserId ? '${p.username} (you)' : p.username,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.cardTitle),
                ),
                if (p.leaveReason != null) Text(p.leaveReason!.label, style: AuraText.cardSub),
              ],
            ),
          ),
      ],
    );
  }
}

/// The one main button per status (06 "Formats and statuses").
class _MainButton extends ConsumerWidget {
  const _MainButton({required this.c, required this.onJoin, required this.onLeave, required this.onGo, required this.onResults});
  final TournamentController c;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  final VoidCallback onGo;
  final VoidCallback onResults;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = c.tournament;
    if (t == null) return const SizedBox.shrink();
    Widget off(String label) => GradientButton(label: label, onPressed: () {}, enabled: false);
    final phase = c.phase;
    if (phase == TournamentPhase.loading || phase == TournamentPhase.gone) return const SizedBox.shrink();
    if (phase == TournamentPhase.failed) return SecondaryButton(label: 'Retry', onPressed: c.refresh);
    switch (t.status) {
      case TournamentStatus.announced:
        return off(t.comingSoon ? 'Coming soon' : 'Opens soon');
      case TournamentStatus.registering:
        if (phase == TournamentPhase.tableReady) return GradientButton(label: 'Go to table', onPressed: onGo);
        if (phase == TournamentPhase.entered) return SecondaryButton(label: 'Leave', onPressed: onLeave, loading: c.busy);
        if (t.comingSoon) return off('Coming soon');
        return _JoinButton(c: c, onJoin: onJoin);
      case TournamentStatus.running:
      case TournamentStatus.paused:
        if (phase == TournamentPhase.tableReady) return GradientButton(label: 'Go to table', onPressed: onGo);
        if (t.status == TournamentStatus.paused) return off('Paused');
        return SecondaryButton(label: 'Players', onPressed: onResults);
      case TournamentStatus.completed:
        return GradientButton(label: 'Results', onPressed: onResults);
      case TournamentStatus.cancelled:
        return off('Cancelled');
      case TournamentStatus.refunded:
        return off(c.myTable?.entered == true ? 'Cancelled, entry refunded' : 'Cancelled');
      case TournamentStatus.unknown:
        return off('Unavailable');
    }
  }
}

/// Join, greyed out (and why) when the wallet can't cover buy-in + fee.
class _JoinButton extends ConsumerWidget {
  const _JoinButton({required this.c, required this.onJoin});
  final TournamentController c;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = c.tournament!;
    final have = ref.watch(walletProvider).value?.of(t.currency.currency);
    final short = !t.isFree && have != null && have < t.totalCost;
    final paused = c.joinPausedText;
    final full = t.isFull;
    final reason = paused ??
        (full
            ? 'This tournament is full.'
            : short
                ? 'You need ${formatCount(t.totalCost)} ${t.currency.noun}. You have ${formatCount(have)}.'
                : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GradientButton(
          label: t.isFree ? 'Join for free' : 'Join · ${t.priceText}',
          onPressed: onJoin,
          loading: c.busy,
          enabled: paused == null && !short,
        ),
        if (reason != null) ...[
          const SizedBox(height: 8),
          Text(reason, textAlign: TextAlign.center, style: AuraText.cardSub.copyWith(color: AuraColors.amber)),
        ],
        if (short && paused == null) ...[
          const SizedBox(height: 6),
          TextButton(onPressed: () => Navigator.pop(context, 'store'), child: const Text('Get more in the Store')),
        ],
      ],
    );
  }
}

/// Join confirm sheet (06 §4): "Join Weekday Ladder Final for 250 + 25
/// tokens?" with the balance. True = join.
Future<bool?> showJoinTournamentSheet(BuildContext context, {required Tournament tournament, int? balance}) {
  final t = tournament;
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: const Color(0xFF17112C),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.isFree ? 'Join ${t.name} for free?' : 'Join ${t.name} for ${t.priceText}?', style: AuraText.title),
            const SizedBox(height: 8),
            if (!t.isFree)
              Text('${formatCount(t.entryFee)} goes into the prize pool; ${formatCount(t.feeAmount)} is the entry fee.', style: AuraText.cardSub),
            if (balance != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('Balance: ', style: AuraText.cardSub),
                  CurrencyGlyph(kind: t.currency.currency, size: 14),
                  const SizedBox(width: 4),
                  Text('${formatCount(balance)} ${t.currency.noun}', style: AuraText.cardTitle),
                ],
              ),
            ],
            if (t.isSitAndGo) ...[
              const SizedBox(height: 6),
              Text('It starts as soon as every seat is taken. You can leave for a full refund until then.', style: AuraText.cardSub),
            ],
            const SizedBox(height: 18),
            GradientButton(label: 'Join', onPressed: () => Navigator.pop(ctx, true)),
            const SizedBox(height: 10),
            SecondaryButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
          ],
        ),
      ),
    ),
  );
}
