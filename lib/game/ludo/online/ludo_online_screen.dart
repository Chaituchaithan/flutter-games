import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/game_socket_login.dart';
import '../../../app/routes.dart';
import '../../../configs/games/core/game_id.dart';
import '../../../screens/profile/progress_ui.dart';
import '../../../services/catalogue_service.dart';
import '../../../services/session.dart';
import '../../../services/socket/app_socket.dart';
import '../../../services/wallet_store.dart';
import '../../../widgets/aura.dart';
import '../../common/dice_game_kit.dart';
import '../../common/dice_view.dart';
import '../../common/online_room/room_widgets.dart';
import '../ludo_board_view.dart';
import '../ludo_engine.dart';
import 'ludo_catalogue.dart';
import 'ludo_controller.dart';
import 'ludo_models.dart';

/// How the screen was opened (the shared Online Play / Play with friends
/// screens, or a game to go back to).
enum LudoEntry { match, create, join, resume }

/// Online Ludo over the Ludo socket (docs/services/ludo.md): searching →
/// waiting room → board → result. Every pawn move comes from the server.
class LudoOnlineScreen extends ConsumerStatefulWidget {
  const LudoOnlineScreen({
    super.key,
    required this.entry,
    this.players = 2,
    this.stake = 0,
    this.tokens = true,
    this.code,
    this.tournament = false,
  });

  final LudoEntry entry;
  final int players;

  /// Per player; 0 = a free game.
  final int stake;
  final bool tokens;

  /// Join: the friend's room code (or a tournament table's `room_code`).
  final String? code;

  /// Opened from a tournament's table hand-off (06-tournaments.md §6): the
  /// result and `game.cancelled` go back to the tournament screen.
  final bool tournament;

  @override
  ConsumerState<LudoOnlineScreen> createState() => _LudoOnlineScreenState();
}

class _LudoOnlineScreenState extends ConsumerState<LudoOnlineScreen> {
  LudoController? _c;
  String? _fatal;
  Timer? _tick;
  int _lastNotice = 0;
  late final AppSocket _socket = ref.read(appSocketProvider);
  StreamSubscription<Object>? _resumeSub;

  @override
  void initState() {
    super.initState();
    _socket.gameScreenOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    // Turn ring and Rush clock.
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _c?.phase == LudoPhase.game) setState(() {});
    });
  }

  @override
  void dispose() {
    _socket.gameScreenOpen = false;
    _tick?.cancel();
    _resumeSub?.cancel();
    _c?.removeListener(_onChange);
    _c?.dispose();
    super.dispose();
  }

  /// Sign in on Ludo's server if needed, then do what the entry asked.
  Future<void> _start() async {
    try {
      if (!_socket.isConnected || _socket.game?.id != GameId.ludo) {
        await ref.read(gameSocketLoginProvider).connect(username: ref.read(sessionProvider)?.username);
      }
    } on Object catch (e) {
      if (mounted) setState(() => _fatal = GameSocketLogin.errorText(e));
      return;
    }
    final client = _socket.client;
    if (!mounted || client == null) {
      if (mounted) setState(() => _fatal = 'Sign in to play online.');
      return;
    }
    final c = LudoController(
      request: (event, data) => (_socket.client ?? client).request(event, data),
      events: _socket.events,
      myUserId: ref.read(currentUserProvider).id,
      serverNow: () => (_socket.client ?? client).serverNow(),
      onWalletChanged: () => ref.read(walletProvider.notifier).gameEnded(),
      onModeError: (code, message) {
        final events = ref.read(catalogueEventsProvider);
        if (code == 'invalid_mode') {
          events.invalidMode('ludo');
        } else {
          events.killSwitch('ludo', message);
        }
      },
    )..addListener(_onChange);
    setState(() => _c = c);
    // This screen handles reconnect frames itself (the controller hears them).
    _resumeSub = _socket.resumes.listen((_) => _socket.takeResume());

    // A game to go back to wins over a new one (ludo.md §7).
    final resume = _socket.takeResume();
    if (resume != null) {
      c.handle(resume);
      return;
    }
    final cat = ref.read(ludoCatalogueProvider).value;
    final currency = widget.tokens ? 'token' : 'gold';
    final bet = widget.stake > 0 ? widget.stake : null;
    switch (widget.entry) {
      case LudoEntry.match:
        final mode = widget.players >= 4 ? 'casual_4p' : 'casual_2p';
        c.maxTimeouts = cat?.mode(mode)?.maxTimeouts ?? 3;
        c.turnMs = switch (cat?.mode(mode)) { final m? => m.turnSeconds * 1000, _ => null };
        await c.quickMatch(modeCode: mode, playerCount: widget.players, currency: currency, betAmount: bet);
      case LudoEntry.create:
        c.maxTimeouts = cat?.mode('friends_room')?.maxTimeouts ?? 3;
        c.turnMs = switch (cat?.mode('friends_room')) { final m? => m.turnSeconds * 1000, _ => null };
        await c.createRoom(modeCode: 'friends_room', maxPlayers: widget.players, currency: currency, betAmount: bet);
      case LudoEntry.join:
        await c.joinRoom(widget.code ?? '');
      case LudoEntry.resume:
        break;
    }
    if (mounted && c.phase == LudoPhase.lobby && widget.entry != LudoEntry.resume) {
      setState(() => _fatal = c.notice?.text ?? 'Couldn’t start the game.');
    }
  }

  void _onChange() {
    final c = _c;
    if (!mounted || c == null) return;
    if (c.noticeId != _lastNotice && c.notice != null) {
      _lastNotice = c.noticeId;
      final n = c.notice!;
      showAuraToast(context, n.text, kind: n.error ? AuraToastKind.error : AuraToastKind.info);
    }
    setState(() {});
    // A cancelled tournament table: back to the tournament (the refund
    // follows there).
    if (widget.tournament && c.cancelledReason != null && !_leftForCancel) {
      _leftForCancel = true;
      unawaited(_backToTournament());
    }
  }

  bool _leftForCancel = false;

  Future<void> _backToTournament() async {
    await _c?.leave();
    if (mounted) Navigator.of(context).maybePop();
  }

  // ── Leaving ──

  Future<bool> _confirmLeave() async {
    final c = _c;
    if (c == null) return true;
    switch (c.phase) {
      case LudoPhase.searching:
        await c.cancelSearch();
        return true;
      case LudoPhase.room:
        final ok = await showAuraDialog(
          context,
          icon: Icons.logout_rounded,
          title: 'Leave the room?',
          body: 'Your seat will be freed.',
          primaryLabel: 'Leave room',
          secondaryLabel: 'Stay',
          destructive: true,
        );
        if (ok != true) return false;
        await c.leave();
        return true;
      case LudoPhase.game:
        final ok = await showAuraDialog(
          context,
          icon: Icons.flag_rounded,
          title: 'Leave the game?',
          body: "You'll lose.",
          primaryLabel: 'Leave',
          secondaryLabel: 'Keep playing',
          destructive: true,
        );
        if (ok != true) return false;
        await c.leave();
        return true;
      case LudoPhase.result:
        await c.leave();
        return true;
      case LudoPhase.lobby:
        return true;
    }
  }

  Future<void> _back() async {
    if (await _confirmLeave() && mounted) Navigator.of(context).maybePop();
  }

  Future<void> _forfeit() async {
    final ok = await showAuraDialog(
      context,
      icon: Icons.flag_rounded,
      title: 'Give up?',
      body: (_c?.state?.players.length ?? 2) <= 2 ? 'Your opponent wins.' : 'You’re out; the others play on.',
      primaryLabel: 'Give up',
      secondaryLabel: 'Keep playing',
      destructive: true,
    );
    if (ok == true) await _c?.forfeit();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final Widget body;
    if (_fatal != null) {
      body = RoomMessage(title: 'Ludo', text: _fatal!, onBack: () => Navigator.of(context).maybePop());
    } else if (c == null) {
      body = const RoomMessage(title: 'Ludo', text: 'Connecting to the Ludo server…', busy: true);
    } else {
      body = switch (c.phase) {
        LudoPhase.lobby => RoomMessage(
          title: 'Ludo',
          text: c.killSwitchMessage ?? 'You left the room.',
          onBack: () => Navigator.of(context).maybePop(),
        ),
        LudoPhase.searching => _Searching(c: c, players: widget.players, onCancel: _back),
        LudoPhase.room => _WaitingRoom(c: c, onLeave: _back),
        LudoPhase.game => _Board(c: c, onForfeit: _forfeit, onLeave: _back),
        LudoPhase.result => _Result(
          c: c,
          tournament: widget.tournament,
          onHome: widget.tournament ? _backToTournament : () async {
            await c.leave();
            if (context.mounted) Navigator.popUntil(context, ModalRoute.withName(Routes.home));
          },
        ),
      };
    }
    return PopScope(
      canPop: c == null || _fatal != null || c.phase == LudoPhase.lobby,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: body,
    );
  }
}

// ── Searching (quick match) ──

class _Searching extends StatelessWidget {
  const _Searching({required this.c, required this.players, required this.onCancel});
  final LudoController c;
  final int players;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Quick match'),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 64, height: 64, child: CircularProgressIndicator(strokeWidth: 3, color: AuraColors.accentGlow)),
            const SizedBox(height: 24),
            Text('Finding players…', style: AuraText.title),
            const SizedBox(height: 8),
            Text('Ludo · $players players', style: AuraText.cardSub),
            const SizedBox(height: 28),
            SecondaryButton(label: 'Cancel', onPressed: onCancel),
          ],
        ),
      ),
    );
  }
}

// ── Waiting room ──

class _WaitingRoom extends StatelessWidget {
  const _WaitingRoom({required this.c, required this.onLeave});
  final LudoController c;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final room = c.room!;
    final me = room.players.where((p) => p.userId == c.myUserId).firstOrNull;
    final ready = me?.ready ?? false;
    final bySeat = {for (final p in room.players) p.seat: p};
    // Seats in play: the taken ones plus free ones up to max_players.
    final seats = <int>[...bySeat.keys];
    for (final s in [0, 2, 1, 3]) {
      if (seats.length >= room.maxPlayers) break;
      if (!seats.contains(s)) seats.add(s);
    }
    seats.sort();
    return AuraScaffold(
      appBar: AuraAppBar(title: room.quickMatch ? 'Quick match' : 'Waiting room', onBack: onLeave),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (room.tournament != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Round ${room.tournament!.round}, Table ${room.tournament!.table}', style: AuraText.cardTitle),
            ),
          if (!room.quickMatch) RoomCodeCard(code: room.roomCode, gameName: 'Ludo'),
          const SizedBox(height: 18),
          SectionHeader('Players ${room.players.length}/${room.maxPlayers}'),
          const SizedBox(height: 10),
          for (final s in seats) _SeatRow(seat: s, player: bySeat[s], you: bySeat[s]?.userId == c.myUserId),
          const SizedBox(height: 14),
          Text(
            room.staked
                ? 'Stake ${room.betAmount} ${room.currency == 'gold' ? 'gold' : 'tokens'} each · taken when the game starts'
                : 'Free game',
            style: AuraText.cardSub,
          ),
          const SizedBox(height: 6),
          Text(
            room.full ? 'The game starts when everyone is ready.' : 'Waiting for players to join…',
            style: AuraText.cardSub,
          ),
          if (c.killSwitchMessage != null) ...[
            const SizedBox(height: 10),
            Text(c.killSwitchMessage!, style: const TextStyle(color: AuraColors.dangerText)),
          ],
          const SizedBox(height: 22),
          GradientButton(
            label: ready ? 'Not ready' : 'Ready',
            loading: c.busy,
            enabled: c.killSwitchMessage == null,
            onPressed: () => ready ? c.unready() : c.ready(),
          ),
          const SizedBox(height: 10),
          SecondaryButton(label: 'Quick chat', onPressed: () => showLudoChat(context, c)),
          const SizedBox(height: 10),
          SecondaryButton(label: 'Leave room', onPressed: onLeave),
        ],
      ),
    );
  }
}

class _SeatRow extends StatelessWidget {
  const _SeatRow({required this.seat, required this.player, required this.you});
  final int seat;
  final LudoSeat? player;
  final bool you;

  @override
  Widget build(BuildContext context) {
    final color = ludoColor(seatColor(seat));
    final p = player;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AuraGlass.decoration(radius: 14, shadow: false),
      child: Row(
        children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p == null ? 'Waiting…' : '${p.username}${you ? ' (you)' : ''}${p.isBot ? ' · bot' : ''}',
              style: AuraText.cardTitle.copyWith(color: p == null ? AuraColors.textMuted : null),
            ),
          ),
          if (p != null)
            Icon(
              p.ready ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded,
              color: p.ready ? AuraColors.green : AuraColors.textMuted,
              size: 20,
            ),
        ],
      ),
    );
  }
}

// ── The board ──

class _Board extends StatefulWidget {
  const _Board({required this.c, required this.onForfeit, required this.onLeave});
  final LudoController c;
  final VoidCallback onForfeit;
  final VoidCallback onLeave;

  @override
  State<_Board> createState() => _BoardState();
}

class _BoardState extends State<_Board> {
  bool _perspective = false;

  LudoController get c => widget.c;

  DiceSeatView _seat(LudoPlayerState p, Duration? left, int turnMs) {
    final active = c.state?.currentTurnUserId == p.userId && c.phase == LudoPhase.game;
    final you = p.userId == c.myUserId;
    final name = you ? 'You' : c.nameOf(p.userId);
    final initials = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    final awaySince = c.away[p.userId];
    String sub;
    if (p.forfeited) {
      sub = 'Out';
    } else if (awaySince != null) {
      final s = 30 - DateTime.now().difference(awaySince).inSeconds;
      sub = 'Reconnecting… ${s.clamp(0, 30)}s';
    } else if (p.place != null) {
      sub = 'Finished #${p.place}';
    } else {
      final out = p.pawns.where((x) => x.type == 'on_board' || x.type == 'home_stretch').length;
      sub = '${p.homeCount} home · $out out${c.state!.matchDeadline != null ? ' · ${p.score} pts' : ''}';
    }
    final secs = left == null ? null : (left.inMilliseconds / 1000).ceil();
    return DiceSeatView(
      player: DicePlayer(name: name, initials: initials, color: ludoColor(p.color), isYou: you),
      sub: sub,
      active: active,
      turnText: active ? (you ? (c.canMove ? 'Pick a pawn${secs == null ? '' : ' · ${secs}s'}' : 'Your roll${secs == null ? '' : ' · ${secs}s'}') : 'Playing${secs == null ? '' : ' · ${secs}s'}') : null,
      progress: active && left != null && turnMs > 0 ? (left.inMilliseconds / turnMs).clamp(0.0, 1.0) : null,
    );
  }

  Widget? _banner(LudoGame board) {
    final st = c.state!;
    final cur = st.player(st.currentTurnUserId ?? '');
    if (cur == null) return null;
    final color = ludoColor(cur.color);
    if (c.canMove) {
      return TurnBanner(text: 'You rolled ${board.lastRoll} · pick a pawn', color: color, emphasis: true, icon: Icons.touch_app_rounded);
    }
    if (c.canRoll) return TurnBanner(text: 'Your turn · tap the dice', color: color, emphasis: true, icon: Icons.touch_app_rounded);
    return TurnBanner(text: '${c.nameOf(cur.userId)}’s turn', color: color);
  }

  @override
  Widget build(BuildContext context) {
    final st = c.state;
    final board = c.board;
    if (st == null || board == null) return const RoomMessage(title: 'Ludo', text: 'Loading the game…', busy: true);
    final left = c.turnLeft;
    final turnMs = c.turnRingMs;
    final ringMs = left == null ? 0 : (left.inMilliseconds > turnMs ? left.inMilliseconds : turnMs);
    final me = st.player(c.myUserId);
    final rivals = st.players.where((p) => p.userId != c.myUserId).toList();
    final match = c.matchLeft;
    final clockText = match != null
        ? '${match.inMinutes}:${(match.inSeconds % 60).toString().padLeft(2, '0')}'
        : left == null
        ? '--'
        : '${(left.inMilliseconds / 1000).ceil()}s';
    return AuraScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      body: DiceBoardLayout(
        header: _OnlineHeader(
          title: '🎲 Ludo',
          subtitle: switch (c.room?.tournament) {
            final t? => 'Round ${t.round}, Table ${t.table}',
            null => '${st.players.length} players · online${match != null ? ' · Rush' : ''}',
          },
          onBack: widget.onLeave,
          perspective: _perspective,
          onTogglePerspective: () => setState(() => _perspective = !_perspective),
        ),
        opponents: [for (final p in rivals) _seat(p, left, ringMs)],
        you: me == null ? _seat(st.players.first, left, ringMs) : _seat(me, left, ringMs),
        lastMove: board.lastText,
        clockText: clockText,
        clockUrgent: (left?.inSeconds ?? 99) <= 3,
        dice: DiceView(
          value: board.lastRoll,
          rollId: board.rollId,
          size: 38,
          enabled: c.canRoll,
          onTap: c.roll,
          glow: ludoColor(board.current),
          prompt: 'Tap',
        ),
        board: LudoBoardView(
          game: board,
          bottomLeft: c.myColor,
          perspective: _perspective,
          canPick: c.canMove,
          onPick: c.move,
          onMoveAnimated: board.clearPending,
          banner: _banner(board),
          turnColor: ludoColor(board.current),
          yourTurn: c.myTurn,
        ),
        actionBar: BoardActionBar(
          statusLabel: c.canRoll ? 'Roll' : (c.canMove ? 'Pick a pawn' : '${c.nameOf(st.currentTurnUserId)} playing'),
          active: c.canRoll || c.canMove,
          onStatusTap: c.canRoll ? c.roll : null,
          onChat: () => showLudoChat(context, c),
          onResign: widget.onForfeit,
        ),
      ),
    );
  }
}

class _OnlineHeader extends StatelessWidget {
  const _OnlineHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.perspective,
    required this.onTogglePerspective,
  });
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final bool perspective;
  final VoidCallback onTogglePerspective;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AuraText.cardTitle),
              Text(subtitle, style: AuraText.cardSub.copyWith(fontSize: 12)),
            ],
          ),
        ),
        IconButton(
          tooltip: '3D board',
          onPressed: onTogglePerspective,
          icon: Icon(perspective ? Icons.view_in_ar_rounded : Icons.grid_view_rounded, color: Colors.white),
        ),
      ],
    );
  }
}

// ── Result ──

class _Result extends StatelessWidget {
  const _Result({required this.c, required this.onHome, this.tournament = false});
  final LudoController c;
  final VoidCallback onHome;

  /// A tournament table: no rematch; back to the tournament.
  final bool tournament;

  @override
  Widget build(BuildContext context) {
    final st = c.state;
    final cancelled = c.cancelledReason != null;
    final won = !cancelled && c.iWon;
    final payout = c.walletUpdate?.payoutFor(c.myUserId);
    // After a resume there is no room: the payout frame says it was staked.
    final staked = (c.room?.betAmount ?? 0) > 0 || c.walletUpdate != null;
    final offer = c.rematchOffer;
    final rematchOn = c.room?.rules['rematch'] != false && !cancelled && !c.readOnly && !tournament && c.room?.tournament == null;
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Result', showBack: false),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Icon(
            cancelled ? Icons.cancel_outlined : (won ? Icons.emoji_events_rounded : Icons.sentiment_neutral_rounded),
            size: 72,
            color: won ? AuraColors.amber : AuraColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            cancelled ? 'This table was cancelled' : (won ? 'You won!' : 'Game over'),
            textAlign: TextAlign.center,
            style: AuraText.headline.copyWith(fontSize: 30),
          ),
          if (c.readOnly)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('The game ended while you were away.', textAlign: TextAlign.center, style: AuraText.cardSub),
            ),
          const SizedBox(height: 20),
          if (st != null && !cancelled)
            for (final p in c.standings)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: AuraGlass.decoration(radius: 14, shadow: false),
                child: Row(
                  children: [
                    SizedBox(width: 34, child: Text(p.place == null ? '–' : '#${p.place}', style: AuraText.cardTitle)),
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: ludoColor(p.color), shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(c.nameOf(p.userId), style: AuraText.cardTitle)),
                    Text(p.forfeited ? 'out' : '${p.homeCount}/4 home', style: AuraText.cardSub),
                  ],
                ),
              ),
          if (staked) ...[
            const SizedBox(height: 10),
            Text(
              payout == null
                  ? 'Settling the pot…'
                  : (payout.amount > 0 ? 'You won ${payout.amount} ${c.room?.currency == 'gold' ? 'gold' : 'tokens'}' : 'No payout this time'),
              textAlign: TextAlign.center,
              style: AuraText.cardTitle,
            ),
          ],
          // "+N XP" (and a level-up) once the progress re-read lands (08).
          if (!c.readOnly && !cancelled) ...[const SizedBox(height: 10), const PostMatchProgressLine()],
          const SizedBox(height: 24),
          if (offer != null) ...[
            Text('${c.nameOf(offer.fromUserId)} wants a rematch', textAlign: TextAlign.center, style: AuraText.cardTitle),
            const SizedBox(height: 10),
            GradientButton(label: 'Join rematch', onPressed: c.acceptRematch, loading: c.busy),
            const SizedBox(height: 10),
          ] else if (rematchOn) ...[
            GradientButton(label: 'Rematch', onPressed: c.rematch, loading: c.busy),
            const SizedBox(height: 10),
          ],
          SecondaryButton(label: tournament ? 'Back to tournament' : 'Back to home', onPressed: onHome),
        ],
      ),
    );
  }
}

// ── Quick chat ──

/// The 12 preset lines as buttons, and the latest lines.
Future<void> showLudoChat(BuildContext context, LudoController c) => showRoomChat(context, c);
