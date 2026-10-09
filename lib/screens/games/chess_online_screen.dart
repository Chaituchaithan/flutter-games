import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../game/chess/chess_board_view.dart';
import '../../game/chess/chess_controller.dart';
import '../../game/chess/chess_engine.dart';
import '../../services/socket/app_socket.dart';
import '../../services/socket/chess_session.dart';
import '../../services/socket/socket_client.dart';
import '../../services/token_store.dart';
import '../../widgets/aura.dart';
import '../match/match_result_screen.dart';

/// How the online game is entered.
enum ChessEntryMode { match, create, join }

/// Online Chess: connects to the chess WebSocket service, matchmakes (or
/// creates/joins a room by code), and plays a live game via [ChessSession].
/// Falls back to local practice when the server can't be reached.
class ChessOnlineScreen extends ConsumerStatefulWidget {
  const ChessOnlineScreen({
    super.key,
    this.stake = 0,
    this.tokens = true,
    this.mode = ChessEntryMode.match,
    this.joinCode,
  });

  /// Wager amount (0 = free/quick play) and currency.
  final int stake;
  final bool tokens;

  /// Quick-match (default), create a room (get a code), or join a room by code.
  final ChessEntryMode mode;
  final String? joinCode;

  @override
  ConsumerState<ChessOnlineScreen> createState() => _ChessOnlineScreenState();
}

class _ChessOnlineScreenState extends ConsumerState<ChessOnlineScreen> {
  SocketClient? _socket;
  ChessSession? _session;
  bool _readied = false;
  bool _ownsSocket = false; // true only when THIS screen created the socket

  // Offline practice fallback (hot-seat).
  ChessController? _offline;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _stopClock();
    _resultTimer?.cancel();
    _session?.removeListener(_onSession);
    _session?.dispose(); // cancels its broadcast listener; does NOT own the socket
    if (_ownsSocket) _socket?.dispose(); // only dispose a socket we created
    _offline?.dispose();
    super.dispose();
  }

  bool _noAuth = false;

  /// 2D (flat) vs 3D (tilted) board, toggled from the app bar.
  bool _perspective = false;

  // ── Per-move clock (server-driven via game.turn_start) ──
  /// Fallback budget shown before the first `game.turn_start` arrives.
  static const int _fallbackLimitMs = 30 * 1000;

  /// UI render ticker only — the values come from the session's server clock
  /// ([ChessSession.clockRemainingMs]); the server owns the authoritative time
  /// and ends the game on timeout (game.turn_timeout → game.completed).
  Timer? _clockTimer;

  /// Remaining ms to display for [c]: the active side counts down from the
  /// server's turn_start; the idle side shows a full per-move budget.
  int _clockMsFor(PieceColor c) {
    final s = _session;
    if (s == null) return _fallbackLimitMs;
    final isActive = s.clockColor == (c == PieceColor.white ? 'white' : 'black');
    return isActive ? s.clockRemainingMs() : s.turnLimitMs;
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final s = _session;
      if (s == null || s.phase != ChessPhase.inGame) return;
      if (mounted) setState(() {});
    });
  }

  void _stopClock() {
    _clockTimer?.cancel();
    _clockTimer = null;
  }

  Future<void> _connect() async {
    // Socket bypassed: skip matchmaking and open the offline practice board.
    if (!kSocketEnabled) {
      _offline = ChessController();
      return;
    }
    final appSocket = ref.read(appSocketProvider);
    final shared = appSocket.client;
    // Identity = the socket username (test1/test2) — matches what the server
    // knows us as, so colour assignment + own-move dedup are correct.
    if (shared != null && appSocket.isConnected) {
      // Reuse the app-wide socket authenticated at login (single connection).
      final session = ChessSession(socket: shared, userId: appSocket.username)..addListener(_onSession);
      _session = session;
      _ownsSocket = false;
      session.attachAuthenticated();
      await _matchmake(session);
      return;
    }
    // Fallback: no shared socket (not signed in) → open our own.
    final token = await ref.read(tokenStoreProvider).readAccess() ?? '';
    if (token.isEmpty) {
      if (mounted) setState(() => _noAuth = true);
      return;
    }
    // Native sends the token as a Bearer header; through the web proxy it rides
    // as a query param instead (browsers can't set WS headers).
    final socket = SocketClient(
      url: Uri.parse(chessWsUrlWithToken(token)),
      headers: chessWsHeaders(token),
      requestTimeout: const Duration(seconds: 8),
    );
    final session = ChessSession(socket: socket, userId: appSocket.username)..addListener(_onSession);
    _socket = socket;
    _session = session;
    _ownsSocket = true;
    await session.start(token: token, username: appSocket.username);
    if (!mounted) return;
    if (session.phase != ChessPhase.authenticated) return;
    await _matchmake(session);
  }

  Future<void> _matchmake(ChessSession session) async {
    final currency = widget.tokens ? 'tokens' : 'gold';
    try {
      switch (widget.mode) {
        case ChessEntryMode.match:
          await session.findMatch(currency: currency, betAmount: widget.stake);
        case ChessEntryMode.create:
          await session.createRoom(currency: currency, betAmount: widget.stake);
        case ChessEntryMode.join:
          await session.joinRoom(widget.joinCode ?? '');
      }
    } on Object catch (e) {
      session.lastError = '$e';
      if (mounted) setState(() {});
    }
  }

  void _onSession() {
    final s = _session;
    if (s == null) return;
    // Auto-ready once we're in a room (server starts when both ready).
    if (s.phase == ChessPhase.inRoom && !_readied) {
      _readied = true;
      s.ready();
    }
    // Run the render ticker only while a game is live; the session holds the
    // server-driven clock values.
    if (s.phase == ChessPhase.inGame) {
      if (_clockTimer == null) _startClock();
    } else {
      _stopClock();
    }
    if (mounted) setState(() {});
    _checkGameOver();
  }

  void _goOffline() {
    setState(() => _offline = ChessController());
  }

  /// Mockup forfeit: confirm, then resign on the server and go straight to
  /// the Defeat screen (as the mockup's endGame(forfeit)).
  Future<void> _forfeit() async {
    final ok = await confirmMatchForfeit(context, stake: widget.stake);
    if (!ok || !mounted) return;
    _forfeited = true;
    try {
      await _session?.resign();
    } on Object catch (_) {
      // Offline/failed send: the match still counts as a defeat locally.
    }
    _checkGameOver(immediate: true);
  }

  /// Online can't stop the server's move clock, so the overlay says so.
  void _openPause() => showGamePaused(
        context,
        subtitle: 'Online match · your move clock keeps running.',
        onForfeit: _forfeit,
      );

  bool _forfeited = false;
  bool _resultShown = false;
  Timer? _resultTimer;

  bool _isOver(ChessSession s) =>
      _forfeited || s.game.isOver || s.phase == ChessPhase.completed || s.result != null;

  /// Once the match ends, wait a beat for the final move to land, then
  /// replace the board with the Victory / Defeat / Draw screen.
  void _checkGameOver({bool immediate = false}) {
    final s = _session;
    if (s == null || _resultShown || !_isOver(s)) return;
    _resultShown = true;
    _stopClock();
    _resultTimer = Timer(Duration(milliseconds: immediate ? 0 : 900), _showResult);
  }

  void _showResult() {
    final s = _session;
    if (!mounted || s == null) return;
    final myColor = s.myColor ?? PieceColor.white;
    final mine = myColor == PieceColor.white ? 'white' : 'black';
    final status = s.game.status;
    // Server result wins; fall back to the local engine (mate/stalemate seen
    // before game.completed arrives).
    final MatchOutcome outcome;
    if (_forfeited) {
      outcome = MatchOutcome.defeat;
    } else if (s.result == 'draw' || (s.result == null && (status == GameStatus.stalemate || status == GameStatus.draw))) {
      outcome = MatchOutcome.draw;
    } else if (s.result != null) {
      outcome = s.result == '${mine}_wins' ? MatchOutcome.victory : MatchOutcome.defeat;
    } else {
      // Checkmate: the side to move is mated.
      outcome = s.game.state.turn == myColor ? MatchOutcome.defeat : MatchOutcome.victory;
    }
    final String? subtitle = _forfeited
        ? 'You forfeited the match.'
        : s.timedOutColor != null
            ? (s.timedOutColor == mine ? 'You ran out of time.' : 'Your opponent ran out of time.')
            : status == GameStatus.checkmate
                ? (outcome == MatchOutcome.victory ? 'Checkmate — flawless run, champion!' : 'Checkmate — run it back.')
                : status == GameStatus.stalemate
                    ? 'Stalemate — an even match.'
                    : null;
    final currency = widget.tokens ? 'Tokens' : 'Gold';
    final opp = s.opponentName ?? 'Opponent';
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchResultScreen(
          outcome: outcome,
          subtitle: subtitle,
          youScore: s.game.capturesBy(myColor),
          oppScore: s.game.capturesBy(myColor.opposite),
          oppName: opp,
          // Wagered win: what the server actually paid out (pot − 5% rake).
          // Draws refund nothing (Chess API), so XP only there.
          reward: switch (outcome) {
            MatchOutcome.victory => s.payout != null ? '+${s.payout} $currency   ·   +50 XP' : '+50 XP',
            MatchOutcome.draw => '+30 XP',
            MatchOutcome.defeat => '+20 XP',
          },
          // A fresh online match with the same stake.
          playAgain: (_) => ChessOnlineScreen(stake: widget.stake, tokens: widget.tokens),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_offline != null) return _OfflineBoard(game: _offline!);
    if (_noAuth) return _noAuthView();

    final s = _session;
    final phase = s?.phase ?? ChessPhase.connecting;
    final inGame = phase == ChessPhase.inGame;

    return AuraScaffold(
      // In-game uses the mockup board header (inside the body); other phases
      // keep the standard app bar.
      appBar: inGame ? null : const AuraAppBar(title: 'Online Chess'),
      // The live board is a fixed layout (board fills the middle, actions
      // pinned to the bottom); the lobby/error phases scroll.
      scroll: !(inGame || phase == ChessPhase.completed),
      body: switch (phase) {
        // Completed shows the final position until the result screen opens.
        ChessPhase.inGame || ChessPhase.completed => _liveGame(s!),
        ChessPhase.error => _error(s),
        _ => _searching(phase),
      },
    );
  }

  /// Current full-move number (increments after Black moves).
  int _fullMove(ChessSession s) => (s.game.history.length ~/ 2) + 1;

  String _mmss(int ms) {
    final sec = (ms / 1000).ceil();
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  }

  void _openChat(ChessSession s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ChatSheet(session: s),
    );
  }

  // ── Searching / lobby ──
  Widget _searching(ChessPhase phase) {
    final creating = widget.mode == ChessEntryMode.create;
    final roomCode = _session?.roomCode;
    final label = switch (phase) {
      ChessPhase.connecting => 'Connecting to game server…',
      ChessPhase.authenticated => 'Signing in…',
      ChessPhase.searching => 'Finding an opponent…',
      ChessPhase.inRoom => creating ? 'Waiting for a player to join…' : 'Opponent found — getting ready…',
      _ => 'Please wait…',
    };
    return Column(
      children: [
        const SizedBox(height: 60),
        const SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation(AuraColors.accentGlow)),
        ),
        const SizedBox(height: 24),
        Text(label, style: AuraText.cardTitle, textAlign: TextAlign.center),
        // Share the room code so a friend can join (create mode).
        if (creating && roomCode != null) ...[
          const SizedBox(height: 20),
          Text('ROOM CODE', style: AuraText.section.copyWith(color: AuraColors.accentGlow)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: AuraGlass.decoration(radius: 14),
            child: Text(
              roomCode,
              style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 4),
            ),
          ),
        ],
        if (widget.stake > 0) ...[
          const SizedBox(height: 6),
          Text('Stake ${widget.stake} ${widget.tokens ? 'Tokens' : 'Gold'}', style: AuraText.cardSub),
        ],
        const SizedBox(height: 40),
        SecondaryButton(label: 'Practice offline instead', onPressed: _goOffline),
        const SizedBox(height: 12),
        SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).maybePop()),
      ],
    );
  }

  // ── Live game ──
  Widget _liveGame(ChessSession s) {
    final myColor = s.myColor ?? PieceColor.white;
    final oppColor = myColor.opposite;
    final myTurn = s.myTurn;
    final over = _isOver(s);
    final gameLive = !over;
    final drawFromOpponent = !over && s.drawOfferedBy != null && s.drawOfferedBy != s.userId;
    final activeColor = s.game.state.turn;
    final activeMs = _clockMsFor(activeColor);
    final lastMove = s.game.lastMoveText((c) => c == myColor ? 'You' : 'Opponent');
    final limitMs = s.turnLimitMs > 0 ? s.turnLimitMs : _fallbackLimitMs;
    double timeLeft(PieceColor c) => _clockMsFor(c) / limitMs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mockup board header: back · ♞ Online Chess / Move n · 3D toggle.
        GameHeader(
          title: '♞ Online Chess',
          subtitle: 'Move ${_fullMove(s)} · 1v1',
          pot: widget.stake > 0 ? '${widget.stake}' : '0',
          // Top-left pause button (mockup); its Forfeit resigns in place.
          leading: GlassIconButton(icon: Icons.pause_rounded, onTap: gameLive ? _openPause : () {}),
          // Mockup pot pill (both stakes) + the 3D toggle.
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GamePotPill(amount: '${widget.stake * 2}', currency: widget.tokens ? Currency.gems : Currency.gold),
              const SizedBox(width: 8),
              GlassIconButton(
                icon: _perspective ? Icons.crop_square_rounded : Icons.view_in_ar_outlined,
                iconSize: 18,
                onTap: () => setState(() => _perspective = !_perspective),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Opponent card + last-move panel.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: BoardPlayerCard(
                  name: 'Opponent',
                  initials: 'OP',
                  sub: '${s.game.capturesBy(oppColor)} captures',
                  color: AuraColors.avatarBlue,
                  color2: const Color(0xFF3B82F6),
                  active: !myTurn && gameLive,
                  turnText: !myTurn && gameLive ? 'Moving…' : null,
                  progress: timeLeft(oppColor),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: BoardInfoPanel(label: 'Last move', value: lastMove)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Board + bottom cards stay together (mockup); spare height
        // collects above the pinned action bar.
        Expanded(
          child: Column(
            children: [
              Flexible(child: ChessBoardView(controller: s.game, flipped: myColor == PieceColor.black, perspective: _perspective)),
              const SizedBox(height: 12),
              // Turn-clock panel + You card (mockup: you bottom-right, diagonal to
              // the opponent top-left).
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: BoardInfoPanel(
                        label: 'Turn clock',
                        value: _mmss(activeMs),
                        big: true,
                        urgent: gameLive && activeMs <= 10000,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BoardPlayerCard(
                        name: 'You',
                        initials: 'NR',
                        sub: '${s.game.capturesBy(myColor)} captures',
                        color: AuraColors.brandPurple,
                        color2: AuraColors.brandPink,
                        active: myTurn && gameLive,
                        turnText: myTurn && gameLive ? 'Your move · ${(activeMs / 1000).ceil()}s' : null,
                        progress: timeLeft(myColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (drawFromOpponent)
          Row(
            children: [
              Expanded(child: GradientButton(label: 'Accept draw', onPressed: () => s.acceptDraw())),
              const SizedBox(width: 12),
              Expanded(child: SecondaryButton(label: 'Decline', onPressed: () => s.declineDraw())),
            ],
          )
        else
          // Pinned action bar: chat · status · offer draw · forfeit.
          BoardActionBar(
            statusLabel: over ? 'Game over' : _liveStatus(s, myTurn),
            active: myTurn && gameLive,
            onChat: () => _openChat(s),
            onDraw: gameLive ? () => s.offerDraw() : null,
            onResign: gameLive ? _forfeit : null,
          ),
        const SizedBox(height: 8),
      ],
    );
  }


  String _liveStatus(ChessSession s, bool myTurn) {
    if (s.game.status == GameStatus.check) return 'Check!';
    return myTurn ? 'Your move' : "Opponent's move";
  }

  // ── Not signed in ──
  Widget _noAuthView() {
    return Column(
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.lock_outline_rounded, color: AuraColors.accentGlow, size: 64),
        const SizedBox(height: 16),
        Text('Sign in to play online', style: AuraText.cardTitle, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text('Online Chess needs a signed-in account for the game server. Log in, then try again.',
            style: AuraText.cardSub, textAlign: TextAlign.center),
        const SizedBox(height: 32),
        GradientButton(label: 'Go to login', onPressed: () => Navigator.pushNamedAndRemoveUntil(context, Routes.login, (r) => false)),
        const SizedBox(height: 12),
        SecondaryButton(label: 'Practice offline', onPressed: _goOffline),
      ],
    );
  }

  // ── Error ──
  Widget _error(ChessSession? s) {
    return Column(
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.cloud_off_rounded, color: AuraColors.danger, size: 64),
        const SizedBox(height: 16),
        Text('Couldn’t reach the game server', style: AuraText.cardTitle, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(s?.lastError ?? '', style: AuraText.cardSub, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 32),
        GradientButton(label: 'Practice offline', onPressed: _goOffline),
        const SizedBox(height: 12),
        SecondaryButton(label: 'Back', onPressed: () => Navigator.of(context).maybePop()),
      ],
    );
  }
}

/// Local hot-seat board used as the offline-practice fallback.
class _OfflineBoard extends StatefulWidget {
  const _OfflineBoard({required this.game, this.ownsGame = false});
  final ChessController game;

  /// True when this board created [game] (Play Again) and must dispose it.
  final bool ownsGame;

  @override
  State<_OfflineBoard> createState() => _OfflineBoardState();
}

class _OfflineBoardState extends State<_OfflineBoard> {
  bool _perspective = false;

  // Hot-seat clock (local two-player): 30s per move — each turn starts fresh.
  static const int _initialClockMs = 30 * 1000;
  int _whiteMs = _initialClockMs;
  int _blackMs = _initialClockMs;
  Timer? _clockTimer;
  DateTime? _lastTick;
  PieceColor? _lastTurn;

  bool _paused = false;
  PieceColor? _flagged; // side that ran out of time
  PieceColor? _forfeitedBy; // side that forfeited
  bool _resultShown = false;
  Timer? _resultTimer;

  bool get _isOver => widget.game.isOver || _flagged != null || _forfeitedBy != null;

  @override
  void initState() {
    super.initState();
    widget.game.addListener(_c);
    _lastTick = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _resultTimer?.cancel();
    widget.game.removeListener(_c);
    if (widget.ownsGame) widget.game.dispose();
    super.dispose();
  }

  void _tick() {
    final now = DateTime.now();
    if (_isOver || _paused) {
      _lastTick = now;
      return;
    }
    final active = widget.game.state.turn;
    // Per-move control: fresh 30s whenever the turn flips to a new side.
    if (active != _lastTurn) {
      _lastTurn = active;
      if (active == PieceColor.white) {
        _whiteMs = _initialClockMs;
      } else {
        _blackMs = _initialClockMs;
      }
      _lastTick = now;
    }
    final dt = now.difference(_lastTick ?? now).inMilliseconds;
    _lastTick = now;
    if (active == PieceColor.white) {
      _whiteMs = (_whiteMs - dt).clamp(0, _initialClockMs);
    } else {
      _blackMs = (_blackMs - dt).clamp(0, _initialClockMs);
    }
    // Out of time → that side loses.
    if ((active == PieceColor.white ? _whiteMs : _blackMs) <= 0) _flagged = active;
    if (mounted) setState(() {});
    _checkGameOver();
  }

  void _c() {
    setState(() {});
    _checkGameOver();
  }

  void _pause() => _paused = true;
  void _resume() {
    _paused = false;
    _lastTick = DateTime.now();
    if (mounted) setState(() {});
  }

  void _openPause() => showGamePaused(
        context,
        subtitle: 'Move ${(widget.game.history.length ~/ 2) + 1} · the clock is stopped.',
        onPause: _pause,
        onResume: _resume,
        onForfeit: _forfeit,
      );

  /// The side to move forfeits (hot-seat). Paused while the dialog is open.
  Future<void> _forfeit() async {
    _pause();
    final ok = await confirmMatchForfeit(context);
    if (!mounted) return;
    if (ok) {
      setState(() => _forfeitedBy = widget.game.state.turn);
      _checkGameOver(immediate: true);
    } else {
      _resume();
    }
  }

  void _checkGameOver({bool immediate = false}) {
    if (!_isOver || _resultShown) return;
    _resultShown = true;
    _resultTimer = Timer(Duration(milliseconds: immediate ? 0 : 900), _showResult);
  }

  /// Hot-seat result, told from White's side (the bottom player).
  void _showResult() {
    if (!mounted) return;
    final g = widget.game;
    String name(PieceColor c) => c == PieceColor.white ? 'White' : 'Black';
    final PieceColor? winner = _forfeitedBy?.opposite ??
        _flagged?.opposite ??
        (g.status == GameStatus.checkmate ? g.state.turn.opposite : null);
    final outcome = winner == null
        ? MatchOutcome.draw
        : (winner == PieceColor.white ? MatchOutcome.victory : MatchOutcome.defeat);
    final subtitle = winner == null
        ? (g.status == GameStatus.stalemate ? 'Stalemate — an even match.' : null)
        : _forfeitedBy != null
            ? '${name(_forfeitedBy!)} forfeited — ${name(winner)} wins.'
            : _flagged != null
                ? '${name(_flagged!)} ran out of time — ${name(winner)} wins.'
                : 'Checkmate — ${name(winner)} wins.';
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchResultScreen(
          outcome: outcome,
          subtitle: subtitle,
          youInitials: 'WH',
          youScore: g.capturesBy(PieceColor.white),
          oppScore: g.capturesBy(PieceColor.black),
          oppName: 'Black',
          oppInitials: 'BK',
          reward: 'Practice match · no stake',
          playAgain: (_) => _OfflineBoard(game: ChessController(), ownsGame: true),
        ),
      ),
    );
  }

  int _mmssSecs(int ms) => (ms / 1000).ceil();
  String _mmss(int ms) => '${_mmssSecs(ms) ~/ 60}:${(_mmssSecs(ms) % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final white = g.state.turn == PieceColor.white;
    final live = !_isOver;
    final activeMs = white ? _whiteMs : _blackMs;
    final lastMove = g.lastMoveText((c) => c == PieceColor.white ? 'White' : 'Black');
    final status = !live
        ? 'Game over'
        : g.status == GameStatus.check
            ? 'Check!'
            : (white ? 'White to move' : 'Black to move');
    // Fixed layout: board fills the middle, the action bar stays at the bottom.
    return AuraScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GameHeader(
            title: '♞ Practice',
            subtitle: 'Move ${(g.history.length ~/ 2) + 1} · hot-seat',
            pot: '0',
            leading: GlassIconButton(icon: Icons.pause_rounded, onTap: live ? _openPause : () {}),
            trailing: GlassIconButton(
              icon: _perspective ? Icons.crop_square_rounded : Icons.view_in_ar_outlined,
              iconSize: 18,
              onTap: () => setState(() => _perspective = !_perspective),
            ),
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: BoardPlayerCard(
                    name: 'Black',
                    initials: 'BK',
                    sub: '${g.capturesBy(PieceColor.black)} captures',
                    color: AuraColors.avatarBlue,
                    color2: const Color(0xFF3B82F6),
                    active: !white && live,
                    turnText: !white && live ? 'Your move · ${_mmssSecs(_blackMs)}s' : null,
                    progress: _blackMs / _initialClockMs,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: BoardInfoPanel(label: 'Last move', value: lastMove)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Board + bottom cards stay together (mockup); spare height
          // collects above the pinned action bar.
          Expanded(
            child: Column(
              children: [
                Flexible(child: ChessBoardView(controller: g, perspective: _perspective)),
                const SizedBox(height: 12),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: BoardInfoPanel(
                          label: 'Turn clock',
                          value: _mmss(activeMs),
                          big: true,
                          urgent: live && activeMs <= 10000,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: BoardPlayerCard(
                          name: 'White',
                          initials: 'WH',
                          sub: '${g.capturesBy(PieceColor.white)} captures',
                          color: AuraColors.brandPurple,
                          color2: AuraColors.brandPink,
                          active: white && live,
                          turnText: white && live ? 'Your move · ${_mmssSecs(_whiteMs)}s' : null,
                          progress: _whiteMs / _initialClockMs,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          BoardActionBar(statusLabel: status, active: live, onResign: live ? _forfeit : null),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// In-game quick-chat sheet: the message log + predefined phrase buttons
/// (the server only accepts predefined phrases).
class _ChatSheet extends StatefulWidget {
  const _ChatSheet({required this.session});
  final ChessSession session;

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_c);
  }

  @override
  void dispose() {
    widget.session.removeListener(_c);
    super.dispose();
  }

  void _c() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final log = widget.session.chat;
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF17112C), Color(0xFF0B0916)]),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: Color(0x33FFFFFF))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 42, height: 5, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 14),
            Text('Quick chat', style: AuraText.title.copyWith(fontSize: 18)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: log.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text('No messages yet', style: AuraText.cardSub, textAlign: TextAlign.center),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final line in log)
                          Align(
                            alignment: line.mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: line.mine ? AuraColors.accentGlow.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(line.message, style: const TextStyle(color: Colors.white, fontSize: 14)),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final phrase in quickChatPhrases)
                  GestureDetector(
                    onTap: () => widget.session.sendChat(phrase),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Text(phrase, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
