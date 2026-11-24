/// Shared lobby screens for every rooms-family game
/// (docs/services/05-matchmaking-and-rooms.md "For the Claude agent" 4–5):
/// Searching (timer, Cancel, "No players found"), Waiting room (seats, room
/// code with Copy and Share, Ready), Open tables (a list with Join), a mode
/// picker, and Bingo's live rooms.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/game_area.dart';
import '../../app/game_socket_login.dart';
import '../../configs/configs.dart';
import '../../configs/games/core/game_codes.dart';
import '../../data/models/game_catalogue.dart';
import '../../data/repositories/store_repository.dart';
import '../../services/lobby/live_rooms.dart';
import '../../services/lobby/lobby_controller.dart';
import '../../services/lobby/lobby_models.dart';
import '../../services/lobby/lobby_providers.dart';
import '../../services/session.dart';
import '../../services/socket/app_socket.dart';
import '../../widgets/aura.dart';

String _stakeLabel(String? currency, int? stake) =>
    (stake ?? 0) == 0 ? 'Free' : '$stake ${currency == 'gold' ? 'gold' : 'tokens'}';

String _mmss(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

const _title = TextStyle(color: AuraColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700);
const _body = TextStyle(color: AuraColors.textSecondary, fontSize: 14);

/// Shows each new [LobbyController.failure] once as a toast.
mixin LobbyFailureToasts<T extends StatefulWidget> on State<T> {
  int _shownFailure = 0;
  void showFailures(LobbyController c) {
    if (c.failureId == _shownFailure || c.failure == null) return;
    _shownFailure = c.failureId;
    final text = c.failure!.text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showAuraToast(context, text, kind: AuraToastKind.error);
    });
  }
}

// ── Mode picker ──

/// Quick match modes or Play with friends modes, never both (doc §1).
class ModePickerList extends StatelessWidget {
  const ModePickerList({super.key, required this.picker, required this.friends, required this.onPick, this.selected});

  final ModePicker picker;
  final bool friends;
  final ValueChanged<GameMode> onPick;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final modes = friends ? picker.withFriends : picker.quickMatch;
    if (modes.isEmpty) return const Text('No modes are available right now.', style: _body);
    return Column(
      children: [
        for (final m in modes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AuraCard(
              onTap: () => onPick(m),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(child: Text(m.name, style: _title.copyWith(fontSize: 15))),
                  Text(
                    friends ? '${m.minPlayers}–${m.playerCount} players' : '${m.playerCount} players',
                    style: _body,
                  ),
                  if (m.code == selected) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.check_circle, color: AuraColors.brandPurple, size: 18),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Searching / waiting room / in game ──

/// The seated part of the lobby for a [LobbyController]: Searching or the
/// Waiting room. Once the game starts, [boardBuilder] draws the game.
class LobbyRoomView extends StatefulWidget {
  const LobbyRoomView({super.key, required this.controller, required this.gameName, this.boardBuilder, this.onExit});

  final LobbyController controller;
  final String gameName;
  final WidgetBuilder? boardBuilder;

  /// Back in the lobby state (cancelled, left, or after the result).
  final VoidCallback? onExit;

  @override
  State<LobbyRoomView> createState() => _LobbyRoomViewState();
}

class _LobbyRoomViewState extends State<LobbyRoomView> with LobbyFailureToasts {
  Timer? _tick;
  LobbyController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && c.phase == LobbyPhase.searching) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    showFailures(c);
    if (c.phase == LobbyPhase.idle) widget.onExit?.call();
    setState(() {});
  }

  Future<void> _leave() async {
    if (c.leavingForfeits) {
      final ok = await showAuraDialog(
        context,
        icon: Icons.flag_rounded,
        title: 'Leave the game?',
        body: 'Leaving now counts as a forfeit.',
        primaryLabel: 'Leave',
        secondaryLabel: 'Stay',
        destructive: true,
      );
      if (ok != true) return;
    }
    await c.leave();
  }

  @override
  Widget build(BuildContext context) {
    return switch (c.phase) {
      LobbyPhase.searching => _searching(),
      LobbyPhase.waitingRoom => _waitingRoom(),
      LobbyPhase.inGame => widget.boardBuilder?.call(context) ?? _message('The game has started.'),
      LobbyPhase.result => _message('Game over.', action: ('Back to lobby', c.backToLobby)),
      LobbyPhase.idle => const SizedBox.shrink(),
    };
  }

  Widget _message(String text, {(String, Future<void> Function())? action}) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: _title),
        if (action != null) ...[
          const SizedBox(height: 16),
          GradientButton(label: action.$1, onPressed: () => action.$2()),
        ],
      ],
    ),
  );

  Widget _searching() {
    final s = c.seat;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: 72, height: 72, child: CircularProgressIndicator(color: AuraColors.brandPurple)),
        const SizedBox(height: 24),
        Text('Finding players... ${_mmss(c.searchElapsed)}', style: _title),
        if (s != null) ...[
          const SizedBox(height: 8),
          Text('${s.players.length}/${s.maxPlayers} seated · ${_stakeLabel(s.currency, s.stake)}', style: _body),
        ],
        const SizedBox(height: 24),
        if (c.noPlayersFound) ...[
          const Text('No players found right now.', style: _title),
          const SizedBox(height: 12),
          GradientButton(label: 'Keep waiting', onPressed: c.keepWaiting),
          const SizedBox(height: 8),
        ],
        if (c.canCancel)
          TextButton(
            onPressed: c.busy ? null : c.cancelSearch,
            child: const Text('Cancel', style: TextStyle(color: AuraColors.textPrimary)),
          ),
      ],
    );
  }

  Widget _waitingRoom() {
    final s = c.seat!;
    final code = s.displayCode;
    return ListView(
      children: [
        if (!s.quickMatch) ...[
          const Text('Room code', style: _body, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          SelectableText(
            code,
            textAlign: TextAlign.center,
            style: _title.copyWith(fontSize: 36, letterSpacing: 6),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (mounted) showAuraToast(context, 'Code copied', kind: AuraToastKind.info);
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Share'),
                onPressed: () => SharePlus.instance.share(ShareParams(text: 'Join my ${widget.gameName} table: code $code')),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Text('${s.players.length}/${s.maxPlayers} players · ${_stakeLabel(s.currency, s.stake)}', style: _body, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        for (final p in s.players)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AuraCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(p.isBot ? Icons.smart_toy_outlined : Icons.person_rounded, color: AuraColors.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p.userId == c.myUserId ? '${p.username} (you)' : p.username,
                      style: _title.copyWith(fontSize: 15),
                    ),
                  ),
                  if (p.ready) const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                ],
              ),
            ),
          ),
        for (var i = s.players.length; i < s.maxPlayers; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: AuraCard(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text('Waiting for a player...', style: _body),
            ),
          ),
        const SizedBox(height: 16),
        GradientButton(
          label: c.iAmReady ? 'Not ready' : 'Ready',
          loading: c.busy,
          enabled: c.playEnabled,
          onPressed: () => c.setReady(!c.iAmReady),
        ),
        TextButton(
          onPressed: c.busy ? null : _leave,
          child: const Text('Leave room', style: TextStyle(color: AuraColors.textPrimary)),
        ),
      ],
    );
  }
}

// ── Open tables (Flow C) ──

/// The open tables list for [game]: waiting quick-match lobbies and listed
/// private rooms, with Join. Pull to refresh (at most every 10 s; there is no
/// push). A game with its own online screen joins there; others join here.
class OpenTablesScreen extends ConsumerStatefulWidget {
  const OpenTablesScreen({super.key, required this.game, this.variant});

  final GameId game;
  final String? variant;

  @override
  ConsumerState<OpenTablesScreen> createState() => _OpenTablesScreenState();
}

class _OpenTablesScreenState extends ConsumerState<OpenTablesScreen> with LobbyFailureToasts {
  LobbyController? _c;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final socket = ref.read(appSocketProvider);
    try {
      // Sign in on the game's socket before showing any lobby button.
      if (!socket.isConnected || socket.game?.id != widget.game) {
        await ref.read(gameSocketLoginProvider).connect(username: ref.read(sessionProvider)?.username);
      }
      if (!mounted) return;
      if (socket.game?.id != widget.game || !socket.isConnected) {
        setState(() => _error = 'Online tables aren’t available for this game yet.');
        return;
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = GameSocketLogin.errorText(e));
      return;
    }
    final c = lobbyControllerFor(ref, widget.game, myUserId: ref.read(currentUserProvider).id)..addListener(_changed);
    setState(() => _c = c);
    await c.refreshOpenRooms(variant: widget.variant, force: true);
  }

  void _changed() {
    if (!mounted) return;
    showFailures(_c!);
    setState(() {});
  }

  @override
  void dispose() {
    _c?.removeListener(_changed);
    _c?.dispose();
    super.dispose();
  }

  bool _canAfford(String currency, int amount) {
    final have = walletBalance(ref, currency == 'gold' ? Currency.gold : Currency.gems);
    return have == null || have >= amount;
  }

  Future<void> _join(OpenRoom r) async {
    final c = _c!;
    final route = GameArea.onlineRoute(widget.game);
    if (route != null) {
      // The game's own online screen seats the player and plays.
      await Navigator.pushNamed(context, route, arguments: {'mode': 'join', 'code': r.roomCode});
      if (mounted) await c.refreshOpenRooms(variant: widget.variant, force: true);
      return;
    }
    if (!await c.joinByCode(r.roomCode) || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (ctx) => AuraScaffold(
          appBar: const AuraAppBar(title: 'Table'),
          body: LobbyRoomView(
            controller: c,
            gameName: GameRegistry.of(widget.game).displayName,
            onExit: () => Navigator.maybePop(ctx),
          ),
        ),
      ),
    );
    if (c.phase != LobbyPhase.idle) await c.leave();
    if (mounted) await c.refreshOpenRooms(variant: widget.variant, force: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final picker = ref.watch(modePickerProvider(GameCodes.codeOf(widget.game))).value;
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Open tables'),
      body: switch ((c, _error)) {
        (_, final String e) => Center(child: Text(e, style: _body, textAlign: TextAlign.center)),
        (null, _) => const Center(child: CircularProgressIndicator(color: AuraColors.brandPurple)),
        (final LobbyController c, _) => RefreshIndicator(
          onRefresh: () => c.refreshOpenRooms(variant: widget.variant),
          child: _list(c, picker),
        ),
      },
    );
  }

  Widget _list(LobbyController c, ModePicker? picker) {
    final rooms = c.visibleRooms(_canAfford);
    if (c.killSwitchMessage != null) {
      return ListView(children: [Text(c.killSwitchMessage!, style: _body, textAlign: TextAlign.center)]);
    }
    if (rooms.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Text(c.loadingRooms ? 'Loading tables...' : 'No open tables right now. Pull to refresh.', style: _body, textAlign: TextAlign.center),
        ],
      );
    }
    return ListView.builder(
      itemCount: rooms.length,
      itemBuilder: (_, i) {
        final r = rooms[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AuraCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(picker?.nameOf(r.modeCode) ?? r.modeCode, style: _title.copyWith(fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('${_stakeLabel(r.currency, r.stake)} · ${r.players}/${r.maxPlayers} players', style: _body),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: c.canStart ? () => _join(r) : null,
                  style: FilledButton.styleFrom(backgroundColor: AuraColors.brandPurple),
                  child: const Text('Join'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Bingo live rooms (doc §3) ──

/// Bingo's live rooms from `GET /live-rooms?is_active=true`. Tapping a room
/// calls [onJoin] with it; the Bingo socket then sends `live.join` with its
/// `id`. Rooms the wallet can't pay a card for are greyed out.
class LiveRoomsScreen extends ConsumerWidget {
  const LiveRoomsScreen({super.key, this.onJoin});

  final ValueChanged<LiveRoom>? onJoin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(liveRoomsProvider);
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Live rooms'),
      body: rooms.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AuraColors.brandPurple)),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Couldn’t load the rooms.', style: _body),
              TextButton(onPressed: () => ref.invalidate(liveRoomsProvider), child: const Text('Retry')),
            ],
          ),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(liveRoomsProvider.future),
          child: ListView(
            children: [
              if (list.isEmpty) const Padding(padding: EdgeInsets.only(top: 80), child: Text('No live rooms right now.', style: _body, textAlign: TextAlign.center)),
              for (final r in list) _LiveRoomCard(room: r, onJoin: onJoin),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveRoomCard extends ConsumerWidget {
  const _LiveRoomCard({required this.room, this.onJoin});
  final LiveRoom room;
  final ValueChanged<LiveRoom>? onJoin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final have = walletBalance(ref, room.currency == 'gold' ? Currency.gold : Currency.gems);
    final affordable = have == null || have >= room.ticketPrice;
    return Opacity(
      opacity: affordable && room.isActive ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AuraCard(
          onTap: affordable && room.isActive && onJoin != null ? () => onJoin!(room) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(room.name, style: _title.copyWith(fontSize: 16)),
              const SizedBox(height: 4),
              Text('${room.variantLabel} · ${room.priceLabel} · up to ${room.maxTickets} cards', style: _body),
              if (room.prizes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text([for (final p in room.prizes) '${p.displayName} ${p.sharePct}%'].join(' · '), style: _body.copyWith(fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
