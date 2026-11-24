import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/game_socket_login.dart';
import '../../../app/routes.dart';
import '../../../configs/games/core/game_id.dart';
import '../../../data/models/store.dart';
import '../../../screens/profile/progress_ui.dart';
import '../../../screens/safety/report_sheets.dart';
import '../../../services/account_store.dart';
import '../../../services/catalogue_service.dart';
import '../../../services/session.dart';
import '../../../services/socket/app_socket.dart';
import '../../../services/wallet_store.dart';
import '../../../widgets/aura.dart';
import '../../common/dice_game_kit.dart';
import '../../common/dice_view.dart';
import '../../common/online_room/room_widgets.dart';
import '../snakes_board_view.dart';
import '../snakes_engine.dart';
import 'snakes_online_board.dart';
import 'snakes_online_catalogue.dart';
import 'snakes_online_controller.dart';
import 'snakes_online_models.dart';

/// How the screen was opened (the shared Online Play / Play with friends
/// screens, or a game to go back to).
enum SnlEntry { match, create, join, resume }

const _title = 'Snake & Ladder';

/// Pawn colour per seat: 0 red, 1 green, 2 yellow, 3 blue.
const snlSeatColors = [Color(0xFFF43F5E), Color(0xFF22C55E), Color(0xFFFBBF24), Color(0xFF3B82F6)];
Color snlSeatColor(int seat) => snlSeatColors[seat.clamp(0, 3)];

/// Online Snake & Ladder over its socket (docs/services/snake-and-ladder.md):
/// searching → waiting room → board → result. Every token move comes from
/// the server.
class SnlOnlineScreen extends ConsumerStatefulWidget {
  const SnlOnlineScreen({
    super.key,
    required this.entry,
    this.players = 2,
    this.stake = 0,
    this.tokens = true,
    this.code,
    this.modeCode,
    this.tournament = false,
  });

  final SnlEntry entry;
  final int players;

  /// Per player; 0 = a free game.
  final int stake;
  final bool tokens;

  /// Join: the friend's room code (or a tournament table's `room_code`).
  final String? code;

  /// A mode from the catalogue (default: Quick 50 / Casual with Friends).
  final String? modeCode;

  /// Opened from a tournament's table hand-off: the result and
  /// `game.cancelled` go back to the tournament screen.
  final bool tournament;

  @override
  ConsumerState<SnlOnlineScreen> createState() => _SnlOnlineScreenState();
}

class _SnlOnlineScreenState extends ConsumerState<SnlOnlineScreen> {
  SnlController? _c;
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
    // The turn ring and the "Reconnecting…" countdowns.
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _c?.phase == RoomPhase.game) setState(() {});
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

  /// Sign in on Snake & Ladder's server if needed, then do what the entry asked.
  Future<void> _start() async {
    try {
      if (!_socket.isConnected || _socket.game?.id != GameId.snakesLadders) {
        await ref.read(gameSocketLoginProvider).connect(username: ref.read(sessionProvider)?.username);
      }
    } on Object catch (e) {
      if (mounted) setState(() => _fatal = GameSocketLogin.errorText(e));
      return;
    }
    final client = _socket.client;
    if (!mounted || client == null || _socket.game?.id != GameId.snakesLadders) {
      if (mounted) setState(() => _fatal = client == null ? 'Sign in to play online.' : 'Snake & Ladder online isn’t available right now.');
      return;
    }
    final c = SnlController(
      request: (event, data) => (_socket.client ?? client).request(event, data),
      events: _socket.events,
      myUserId: ref.read(currentUserProvider).id,
      serverNow: () => (_socket.client ?? client).serverNow(),
      onWalletChanged: () => ref.read(walletProvider.notifier).gameEnded(),
      onModeError: (code, message) {
        final events = ref.read(catalogueEventsProvider);
        if (code == 'invalid_mode') {
          events.invalidMode(snlCode).ignore();
          ref.invalidate(snlCatalogueProvider);
        } else {
          events.killSwitch(snlCode, message);
        }
      },
      onBoostsChanged: () => ref.invalidate(inventoryProvider),
      onUnknownPlayers: _lookUpNames,
    )..addListener(_onChange);
    setState(() => _c = c);
    // This screen handles reconnect frames itself (the controller hears them).
    _resumeSub = _socket.resumes.listen((_) => _socket.takeResume());

    // A game to go back to wins over a new one (snake-and-ladder.md §7).
    final resume = _socket.takeResume();
    if (resume != null) {
      c.handle(resume);
      return;
    }
    RoomCatalogue? cat;
    try {
      cat = await ref.read(snlCatalogueProvider.future).timeout(const Duration(seconds: 6));
    } on Object {
      cat = null; // play with the server's defaults
    }
    if (!mounted) return;
    final currency = widget.tokens ? 'token' : 'gold';
    final bet = widget.stake > 0 ? widget.stake : null;
    switch (widget.entry) {
      case SnlEntry.match:
        final mode = cat?.mode(widget.modeCode ?? snlQuickMode);
        final code = mode?.code ?? widget.modeCode ?? snlQuickMode;
        c.maxTimeouts = mode?.maxTimeouts ?? 3;
        c.turnMs = mode == null ? null : mode.turnSeconds * 1000;
        // Always send player_count (it defaults to 2), within the mode's seats.
        final seats = mode == null ? widget.players : widget.players.clamp(mode.minPlayers, mode.seats);
        await c.quickMatch(modeCode: code, playerCount: seats, currency: currency, betAmount: bet);
      case SnlEntry.create:
        final mode = cat?.mode(widget.modeCode ?? snlFriendsMode);
        c.maxTimeouts = mode?.maxTimeouts ?? 5;
        c.turnMs = mode == null ? null : mode.turnSeconds * 1000;
        final seats = mode == null ? widget.players : widget.players.clamp(mode.minPlayers, mode.seats);
        await c.createRoom(modeCode: mode?.code ?? widget.modeCode ?? snlFriendsMode, maxPlayers: seats, currency: currency, betAmount: bet);
      case SnlEntry.join:
        await c.joinRoom(widget.code ?? '');
      case SnlEntry.resume:
        break;
    }
    if (mounted && c.phase == RoomPhase.lobby && widget.entry != SnlEntry.resume) {
      setState(() => _fatal = c.notice?.text ?? 'Couldn’t start the game.');
    }
  }

  /// After a cold start the state has no names: read the public profiles.
  void _lookUpNames(List<String> ids) {
    for (final id in ids) {
      ref.read(playerProfileProvider(id).future).then((p) {
        if (mounted) _c?.setName(id, p.displayName);
      }, onError: (_) {});
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
    // A cancelled tournament table: back to the tournament.
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
      case RoomPhase.searching:
        await c.cancelSearch();
        return true;
      case RoomPhase.room:
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
      case RoomPhase.game:
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
      case RoomPhase.result:
        await c.leave();
        return true;
      case RoomPhase.lobby:
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
      body = RoomMessage(title: _title, text: _fatal!, onBack: () => Navigator.of(context).maybePop());
    } else if (c == null) {
      body = const RoomMessage(title: _title, text: 'Connecting to the Snake & Ladder server…', busy: true);
    } else {
      body = switch (c.phase) {
        RoomPhase.lobby => RoomMessage(
          title: _title,
          text: c.killSwitchMessage ?? 'You left the room.',
          onBack: () => Navigator.of(context).maybePop(),
        ),
        RoomPhase.searching => _Searching(players: widget.players, onCancel: _back),
        RoomPhase.room => _WaitingRoom(c: c, onLeave: _back),
        RoomPhase.game => _Board(c: c, onForfeit: _forfeit, onLeave: _back),
        RoomPhase.result => _Result(
          c: c,
          tournament: widget.tournament,
          onHome: widget.tournament
              ? _backToTournament
              : () async {
                  await c.leave();
                  if (context.mounted) Navigator.popUntil(context, ModalRoute.withName(Routes.home));
                },
        ),
      };
    }
    return PopScope(
      canPop: c == null || _fatal != null || c.phase == RoomPhase.lobby,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: body,
    );
  }
}

// ── Searching (quick match) ──

class _Searching extends StatelessWidget {
  const _Searching({required this.players, required this.onCancel});
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
            Text('$_title · $players players', style: AuraText.cardSub),
            const SizedBox(height: 28),
            SecondaryButton(label: 'Cancel', onPressed: onCancel),
          ],
        ),
      ),
    );
  }
}

// ── Waiting room ──

class _WaitingRoom extends StatefulWidget {
  const _WaitingRoom({required this.c, required this.onLeave});
  final SnlController c;
  final VoidCallback onLeave;

  @override
  State<_WaitingRoom> createState() => _WaitingRoomState();
}

class _WaitingRoomState extends State<_WaitingRoom> {
  SnlBoardGame? _preview;

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  /// A still board for the room's layout (pawns on START).
  SnlBoardGame? _previewFor(SnakesLayout? layout, int seats) {
    if (layout == null) return null;
    final n = seats.clamp(2, 4);
    final p = _preview;
    if (p != null && p.layout == layout && p.players == n) return p;
    p?.dispose();
    return _preview = SnlBoardGame(players: n, layout: layout);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final room = c.room!;
    final me = room.players.where((p) => p.userId == c.myUserId).firstOrNull;
    final ready = me?.ready ?? false;
    final bySeat = {for (final p in room.players) p.seat: p};
    final seats = [for (var s = 0; s < room.maxPlayers.clamp(2, 4); s++) s];
    final preview = _previewFor(c.previewBoard, room.maxPlayers);
    final timer = (room.raw['turn_timer_sec'] as num?)?.toInt();
    return AuraScaffold(
      appBar: AuraAppBar(title: room.quickMatch ? 'Quick match' : 'Waiting room', onBack: widget.onLeave),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (room.tournament != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Round ${room.tournament!.round}, Table ${room.tournament!.table}', style: AuraText.cardTitle),
            ),
          if (!room.quickMatch) RoomCodeCard(code: room.roomCode, gameName: _title),
          const SizedBox(height: 18),
          SectionHeader('Players ${room.players.length}/${room.maxPlayers}'),
          const SizedBox(height: 10),
          for (final s in seats) _SeatRow(seat: s, player: bySeat[s], you: bySeat[s]?.userId == c.myUserId),
          const SizedBox(height: 14),
          Text(
            [
              room.modeName ?? _modeLabel(room.modeCode),
              if (timer != null) '${timer}s turns',
              room.staked ? 'Stake ${room.betAmount} ${room.currency == 'gold' ? 'gold' : 'tokens'} each · taken when the game starts' : 'Free game',
            ].join(' · '),
            style: AuraText.cardSub,
          ),
          const SizedBox(height: 6),
          Text(
            room.full ? 'The game starts when everyone is ready.' : 'Waiting for players to join…',
            style: AuraText.cardSub,
          ),
          if (preview != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: preview.layout.rows >= 10 ? 300 : 190,
              child: IgnorePointer(child: SnakesBoardView(game: preview, colors: [for (var s = 0; s < preview.players; s++) snlSeatColor(s)], onMoveAnimated: () {})),
            ),
            if (preview.layout.venom.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Venom squares (green drops) make you sit out a turn.', style: AuraText.cardSub, textAlign: TextAlign.center),
              ),
          ],
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
          SecondaryButton(label: 'Quick chat', onPressed: () => showRoomChat(context, c)),
          const SizedBox(height: 10),
          SecondaryButton(label: 'Leave room', onPressed: widget.onLeave),
        ],
      ),
    );
  }
}

String _modeLabel(String? code) => switch (code) {
  'quick_50' => 'Quick 50',
  'classic_2' => 'Classic 1v1',
  'classic_4' => 'Classic 4 Players',
  'venom' => 'Venom',
  'duel_ranked' => '1v1 Duel ranked',
  'casual' => 'Casual with Friends',
  'quick_friends' => 'Quick 50 with Friends',
  'venom_friends' => 'Venom with Friends',
  'duel_casual' => '1v1 Duel casual',
  'team_2v2' => 'Team 2v2',
  _ => _title,
};

class _SeatRow extends StatelessWidget {
  const _SeatRow({required this.seat, required this.player, required this.you});
  final int seat;
  final RoomSeat? player;
  final bool you;

  @override
  Widget build(BuildContext context) {
    final p = player;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AuraGlass.decoration(radius: 14, shadow: false),
      child: Row(
        children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(color: snlSeatColor(seat), shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p == null ? 'Waiting…' : (you ? 'You' : p.username),
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

class _Board extends ConsumerStatefulWidget {
  const _Board({required this.c, required this.onForfeit, required this.onLeave});
  final SnlController c;
  final VoidCallback onForfeit;
  final VoidCallback onLeave;

  @override
  ConsumerState<_Board> createState() => _BoardState();
}

class _BoardState extends ConsumerState<_Board> {
  bool _perspective = false;

  SnlController get c => widget.c;

  DiceSeatView _seat(SnlPlayer p, Duration? left, int turnMs) {
    final active = c.state?.currentTurnUserId == p.userId && c.phase == RoomPhase.game;
    final you = p.userId == c.myUserId;
    final name = you ? 'You' : c.nameOf(p.userId);
    final initials = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    final awaySince = c.away[p.userId];
    final strikes = c.timeouts[p.userId] ?? p.timeouts;
    String sub;
    if (p.forfeited) {
      sub = 'Out';
    } else if (awaySince != null) {
      final s = 30 - DateTime.now().difference(awaySince).inSeconds;
      sub = 'Reconnecting… ${s.clamp(0, 30)}s';
    } else {
      sub = [
        p.position == 0 ? 'Start' : 'Square ${p.position}',
        if (p.skipTurns > 0) 'sits out (venom)',
        if (c.skipped.contains(p.userId)) 'skipped (venom)',
        if (p.activePowerups.isNotEmpty) p.activePowerups.map(snlBoostName).join(', '),
        if (strikes > 0) "Time's up ×$strikes",
      ].join(' · ');
    }
    final secs = left == null ? null : (left.inMilliseconds / 1000).ceil();
    return DiceSeatView(
      player: DicePlayer(name: name, initials: initials, color: snlSeatColor(p.seat), isYou: you),
      sub: sub,
      active: active,
      turnText: active ? (you ? 'Your roll${secs == null ? '' : ' · ${secs}s'}' : 'Rolling${secs == null ? '' : ' · ${secs}s'}') : null,
      progress: active && left != null && turnMs > 0 ? (left.inMilliseconds / turnMs).clamp(0.0, 1.0) : null,
    );
  }

  Widget? _banner(SnlState st) {
    final cur = st.player(st.currentTurnUserId ?? '');
    if (cur == null) return null;
    final color = snlSeatColor(cur.seat);
    if (c.canRoll) return TurnBanner(text: 'Your turn · tap the dice', color: color, emphasis: true, icon: Icons.touch_app_rounded);
    return TurnBanner(text: '${c.nameOf(cur.userId)}’s turn', color: color);
  }

  @override
  Widget build(BuildContext context) {
    final st = c.state;
    final board = c.board;
    if (st == null || board == null) return const RoomMessage(title: _title, text: 'Loading the game…', busy: true);
    final left = c.turnLeft;
    final turnMs = c.turnRingMs;
    final ringMs = left == null ? 0 : (left.inMilliseconds > turnMs ? left.inMilliseconds : turnMs);
    final me = st.player(c.myUserId);
    final rivals = st.players.where((p) => p.userId != c.myUserId).toList();
    final cur = st.player(st.currentTurnUserId ?? '');
    final strikes = c.timeouts[c.myUserId] ?? me?.timeouts ?? 0;
    final warn = me != null && !me.forfeited && strikes > 0 && strikes >= c.timeoutsAllowed - 1;
    return AuraScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      body: DiceBoardLayout(
        header: _OnlineHeader(
          subtitle: switch (c.room?.tournament) {
            final t? => 'Round ${t.round}, Table ${t.table}',
            null => '${st.players.length} players · ${st.board?.size ?? 100} squares${(st.board?.venom.isNotEmpty ?? false) ? ' · venom' : ''}',
          },
          onBack: widget.onLeave,
          perspective: _perspective,
          onTogglePerspective: () => setState(() => _perspective = !_perspective),
          onPlayers: rivals.isEmpty ? null : () => _showPlayers(context, c, rivals),
        ),
        opponents: [for (final p in rivals) _seat(p, left, ringMs)],
        you: me == null ? _seat(st.players.first, left, ringMs) : _seat(me, left, ringMs),
        lastMove: warn ? "Play your turn or you'll be removed." : board.lastText,
        clockText: left == null ? '--' : '${(left.inMilliseconds / 1000).ceil()}s',
        clockUrgent: (left?.inSeconds ?? 99) <= 3,
        dice: DiceView(
          value: board.lastRoll,
          rollId: board.rollId,
          size: 38,
          enabled: c.canRoll,
          onTap: c.roll,
          glow: cur == null ? AuraColors.accentGlow : snlSeatColor(cur.seat),
          prompt: 'Tap',
        ),
        board: Column(
          children: [
            Expanded(
              child: SnakesBoardView(
                game: board,
                colors: [for (final p in st.players) snlSeatColor(p.seat)],
                onMoveAnimated: board.clearPending,
                perspective: _perspective,
                banner: _banner(st),
                turnColor: cur == null ? null : snlSeatColor(cur.seat),
                yourTurn: c.myTurn,
              ),
            ),
            if (c.boostsOn) _BoostBar(c: c),
          ],
        ),
        actionBar: BoardActionBar(
          statusLabel: c.canRoll ? 'Roll' : '${c.nameOf(st.currentTurnUserId)} rolling',
          active: c.canRoll,
          onStatusTap: c.canRoll ? c.roll : null,
          onChat: () => showRoomChat(context, c),
          onResign: widget.onForfeit,
        ),
      ),
    );
  }
}

class _OnlineHeader extends StatelessWidget {
  const _OnlineHeader({
    required this.subtitle,
    required this.onBack,
    required this.perspective,
    required this.onTogglePerspective,
    this.onPlayers,
  });
  final String subtitle;
  final VoidCallback onBack;
  final bool perspective;
  final VoidCallback onTogglePerspective;
  final VoidCallback? onPlayers;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🐍 $_title', style: AuraText.cardTitle),
              Text(subtitle, style: AuraText.cardSub.copyWith(fontSize: 12)),
            ],
          ),
        ),
        if (onPlayers != null)
          IconButton(
            tooltip: 'Players',
            onPressed: onPlayers,
            icon: const Icon(Icons.people_alt_rounded, color: Colors.white),
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

/// The player's own Snake & Ladder boosts (inventory, `GET /games/{id}/power-ups`
/// for names), usable on their turn before rolling.
class _BoostBar extends ConsumerWidget {
  const _BoostBar({required this.c});
  final SnlController c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(gamePowerUpsProvider(snlCode)).value ?? const <PowerUp>[];
    final inventory = ref.watch(inventoryProvider).value;
    final gameId = catalogue.firstOrNull?.gameId ?? ref.watch(snlCatalogueProvider).value?.gameId ?? 0;
    final owned = inventory == null || gameId == 0 ? const <OwnedPowerUp>[] : inventory.powerUpsForGame(gameId);
    final on = c.myBoosts;
    final shown = [
      for (final o in owned)
        if (c.boostAllowed(o.code)) o,
    ];
    if (shown.isEmpty && on.isEmpty) return const SizedBox(height: 4);
    String nameOf(String code) => catalogue.where((p) => p.code == code).firstOrNull?.name ?? snlBoostName(code);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          Center(child: Text('Boosts ', style: AuraText.cardSub.copyWith(fontSize: 12))),
          for (final code in on)
            if (!shown.any((o) => o.code == code))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Chip(label: Text('${nameOf(code)} · on'), backgroundColor: AuraColors.green.withValues(alpha: 0.3)),
              ),
          for (final o in shown)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                label: Text(on.contains(o.code) ? '${nameOf(o.code)} · on' : '${nameOf(o.code)} ×${o.quantity}'),
                backgroundColor: on.contains(o.code) ? AuraColors.green.withValues(alpha: 0.3) : null,
                onPressed: c.canBoost && !on.contains(o.code) ? () => c.usePowerup(o.code) : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// Opponents: send a gift or report.
Future<void> _showPlayers(BuildContext context, SnlController c, List<SnlPlayer> rivals) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF17112C),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Players', style: AuraText.title),
          const SizedBox(height: 10),
          for (final p in rivals)
            Row(
              children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: snlSeatColor(p.seat), shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(child: Text(c.nameOf(p.userId), style: AuraText.cardTitle)),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _sendGift(context, c, p.userId);
                  },
                  child: const Text('Gift'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    showReportPlayerSheet(context, playerId: p.userId, playerName: c.nameOf(p.userId), matchId: c.state?.matchId);
                  },
                  child: const Text('Report'),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

/// A gift can't be undone: confirm first.
Future<void> _sendGift(BuildContext context, SnlController c, String userId) async {
  final ok = await showAuraDialog(
    context,
    icon: Icons.card_giftcard_rounded,
    title: 'Send a gift?',
    body: '${c.nameOf(userId)} gets 5 tokens from your wallet. This can’t be undone.',
    primaryLabel: 'Send 5 tokens',
    secondaryLabel: 'Cancel',
  );
  if (ok == true) await c.sendGift(receiverId: userId, amount: 5, itemType: 'rose');
}

// ── Result ──

class _Result extends ConsumerWidget {
  const _Result({required this.c, required this.onHome, this.tournament = false});
  final SnlController c;
  final VoidCallback onHome;

  /// A tournament table: no rematch; back to the tournament.
  final bool tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = c.state;
    final cancelled = c.cancelledReason != null;
    final won = !cancelled && c.iWon;
    final payout = c.walletUpdate?.payoutFor(c.myUserId);
    // After a resume there is no room: the payout frame says it was staked.
    final staked = (c.room?.betAmount ?? 0) > 0 || c.walletUpdate != null;
    final gold = c.room?.currency == 'gold';
    final balance = ref.watch(walletProvider).value?.of(gold ? Currency.gold : Currency.gems);
    final offer = c.rematchOffer;
    final rematchOn = c.rematchAllowed && !cancelled && !c.readOnly && !tournament && c.room?.tournament == null;
    final rivals = st?.players.where((p) => p.userId != c.myUserId).toList() ?? const <SnlPlayer>[];
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
            cancelled ? 'This table was cancelled' : (won ? 'You won!' : (st == null ? 'That game has ended' : 'Game over')),
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
            for (final (i, p) in c.standings.indexed)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: AuraGlass.decoration(radius: 14, shadow: false),
                child: Row(
                  children: [
                    SizedBox(width: 34, child: Text('#${i + 1}', style: AuraText.cardTitle)),
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: snlSeatColor(p.seat), shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(c.nameOf(p.userId), style: AuraText.cardTitle)),
                    Text(p.forfeited ? 'out' : (p.position == 0 ? 'start' : 'square ${p.position}'), style: AuraText.cardSub),
                  ],
                ),
              ),
          if (staked) ...[
            const SizedBox(height: 10),
            Text(
              payout == null
                  ? 'Settling the pot…'
                  : (payout.amount > 0 ? 'You won ${payout.amount} ${gold ? 'gold' : 'tokens'}' : 'No payout this time'),
              textAlign: TextAlign.center,
              style: AuraText.cardTitle,
            ),
            if (payout != null && balance != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Balance: $balance ${gold ? 'gold' : 'tokens'}', textAlign: TextAlign.center, style: AuraText.cardSub),
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
          if (rivals.isNotEmpty && !cancelled) ...[
            SecondaryButton(label: 'Players', onPressed: () => _showPlayers(context, c, rivals)),
            const SizedBox(height: 10),
          ],
          SecondaryButton(label: tournament ? 'Back to tournament' : 'Back to home', onPressed: onHome),
        ],
      ),
    );
  }
}
