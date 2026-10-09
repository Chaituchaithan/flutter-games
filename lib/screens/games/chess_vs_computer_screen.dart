import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../game/chess/chess_board_view.dart';
import '../../game/chess/chess_bot.dart';
import '../../game/chess/chess_clock.dart';
import '../../game/chess/chess_controller.dart';
import '../../game/chess/chess_engine.dart';
import '../../widgets/aura.dart';
import '../match/match_result_screen.dart';

/// Quick Play · a local game against the computer (client-side [ChessBot]).
/// You can play White, Black, or a random side; the bot takes the other colour
/// (and opens the game if it has White). The board auto-flips when you play
/// Black. Runs fully offline on the premium board with an optional chess clock.
class ChessVsComputerScreen extends StatefulWidget {
  const ChessVsComputerScreen({super.key, this.depth = 2, this.clockMs = 30 * 1000, this.playerColor});

  /// Bot search depth (difficulty). 1≈Easy, 2≈Medium, 3≈Hard.
  final int depth;

  /// Time allowed per move in milliseconds (resets every turn); null =
  /// unlimited (no clock). Running out loses the game.
  final int? clockMs;

  /// Colour the human plays; null = random (resolved when the game starts).
  final PieceColor? playerColor;

  @override
  State<ChessVsComputerScreen> createState() => _ChessVsComputerScreenState();
}

class _ChessVsComputerScreenState extends State<ChessVsComputerScreen> {
  late ChessController _game;
  ChessClock? _clock; // null when the time control is "unlimited"
  final _rng = Random();
  Timer? _botTimer; // cancellable so it never leaks past dispose

  late PieceColor _playerColor; // resolved (random → concrete) in _start
  PieceColor get _botColor => _playerColor.opposite;

  bool _thinking = false;
  bool _paused = false; // pause overlay / forfeit dialog open
  bool _resultShown = false; // navigated to the result screen already
  PieceColor? _flagged; // side that ran out of time
  bool _resigned = false; // player forfeited
  bool _perspective = false; // 2D (flat) vs 3D (tilted) board

  @override
  void initState() {
    super.initState();
    _playerColor = widget.playerColor ?? (_rng.nextBool() ? PieceColor.white : PieceColor.black);
    // Lock control to the player's colour so the bot's pieces aren't tappable.
    _game = ChessController(localColor: _playerColor)..onLocalMove = (_) => _maybeBotMove();
    _game.addListener(_onChange);
    _clock = widget.clockMs == null
        ? null
        : (ChessClock(_game, initialMs: widget.clockMs!, onFlag: _onFlag, perMove: true, handoverMs: _handoverMs)..addListener(_onChange));
    // Deferred so we never setState during initState/build. Lets the bot open
    // the game when it has White (i.e. the player chose Black).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeBotMove();
    });
  }

  @override
  void dispose() {
    _botGen++;
    _botTimer?.cancel();
    _resultTimer?.cancel();
    _clock?.dispose();
    _game.removeListener(_onChange);
    _game.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    _checkGameOver();
  }

  void _onFlag(PieceColor color) {
    if (!mounted) return;
    setState(() => _flagged = color);
    _checkGameOver();
  }

  bool get _isOver => _game.isOver || _flagged != null || _resigned;

  /// Hand-over buffer: the 280ms piece slide + a ~0.3s beat before the next
  /// mover's clock starts counting (both directions).
  static const int _handoverMs = 600;

  /// Bumped to invalidate an in-flight bot search (pause, game over, dispose).
  int _botGen = 0;

  /// If it's the bot's turn, let it move (used after the player moves, to let
  /// the bot open when it has White, and after a resume).
  ///
  /// The search runs on a background isolate ([compute]) so the UI thread —
  /// and the piece slide — never stalls (Hard blocks for ~0.4s+ otherwise).
  /// A randomised "thinking" buffer — longer at higher difficulty — hands the
  /// turn over at a natural pace: the reply lands after whichever is longer,
  /// the search or the buffer.
  void _maybeBotMove() {
    if (_isOver || _paused || _thinking || _game.state.turn != _botColor) return;
    setState(() => _thinking = true);
    final gen = ++_botGen;
    final started = DateTime.now();
    // Stronger levels "think" longer, like a real opponent:
    // Easy 0.6–1.0s · Medium 1.0–1.8s · Hard 1.6–2.6s.
    final (minMs, spreadMs) = switch (widget.depth) {
      <= 1 => (600, 400),
      2 => (1000, 800),
      _ => (1600, 1000),
    };
    final thinkMs = minMs + _rng.nextInt(spreadMs);
    compute(_searchBotMove, (_game.state, widget.depth)).then((m) {
      if (!mounted || gen != _botGen) return;
      final waitMs = thinkMs - DateTime.now().difference(started).inMilliseconds;
      // A cancellable Timer (not Future.delayed) so pause/dispose stop it cleanly.
      _botTimer?.cancel();
      _botTimer = Timer(Duration(milliseconds: waitMs.clamp(0, thinkMs)), () => _playBotMove(gen, m));
    });
  }

  void _playBotMove(int gen, Move? m) {
    if (!mounted || gen != _botGen) return;
    _thinking = false;
    if (_isOver || _paused || _game.state.turn != _botColor) {
      setState(() {});
      return;
    }
    if (m != null) _game.applyExternalCoords(m.from, m.to, promotion: m.promotion);
    if (mounted) setState(() {});
  }

  // ── Pause / forfeit (mockup overlays) ──

  void _pause() {
    _paused = true;
    _clock?.pause();
    _botTimer?.cancel(); // the bot waits too; it replies after resume
    _botGen++; // drop any search still running
    _thinking = false;
  }

  void _resume() {
    if (!mounted) return;
    _paused = false;
    _clock?.resume();
    setState(() {});
    _maybeBotMove();
  }

  void _openPause() => showGamePaused(
        context,
        subtitle: 'Move $_fullMove · the clock is stopped.',
        onPause: _pause,
        onResume: _resume,
        onForfeit: _forfeit,
      );

  /// Mockup forfeit: the game pauses while the dialog is open; Forfeit ends
  /// it as a defeat, Keep playing resumes.
  Future<void> _forfeit() async {
    _pause();
    final ok = await confirmMatchForfeit(context);
    if (!mounted) return;
    if (ok) {
      setState(() => _resigned = true);
      _checkGameOver();
    } else {
      _resume();
    }
  }

  // ── Game over → result screen ──

  Timer? _resultTimer;

  /// Once the game ends, wait a beat (so the final move lands) and replace the
  /// board with the Victory / Defeat / Draw screen.
  void _checkGameOver() {
    if (!_isOver || _resultShown) return;
    _resultShown = true;
    _botTimer?.cancel();
    _botGen++;
    _clock?.pause();
    _resultTimer = Timer(Duration(milliseconds: _resigned ? 0 : 900), _showResult);
  }

  void _showResult() {
    if (!mounted) return;
    final outcome = _isDraw ? MatchOutcome.draw : (_playerWon ? MatchOutcome.victory : MatchOutcome.defeat);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchResultScreen(
          outcome: outcome,
          subtitle: _resultSubtitle,
          youScore: _game.capturesBy(_playerColor),
          oppScore: _game.capturesBy(_botColor),
          oppName: 'Computer',
          oppInitials: 'AI',
          // Quick Play has no stake: XP only.
          reward: switch (outcome) {
            MatchOutcome.victory => '+50 XP',
            MatchOutcome.draw => '+30 XP',
            MatchOutcome.defeat => '+20 XP',
          },
          // Same side / difficulty / time control again.
          playAgain: (_) => ChessVsComputerScreen(
            depth: widget.depth,
            clockMs: widget.clockMs,
            playerColor: widget.playerColor,
          ),
        ),
      ),
    );
  }

  /// Result-screen subtitle for the non-default endings.
  String? get _resultSubtitle {
    if (_resigned) return 'You forfeited the match.';
    if (_flagged != null) return _flagged == _playerColor ? 'You ran out of time.' : 'The computer ran out of time.';
    if (_game.status == GameStatus.stalemate) return 'Stalemate — an even match.';
    if (_game.status == GameStatus.checkmate) return _playerWon ? 'Checkmate — flawless run, champion!' : 'Checkmate — run it back.';
    return null;
  }

  // ── Result helpers ──
  bool get _playerWon {
    if (_resigned) return false; // you forfeited
    if (_flagged != null) return _flagged == _botColor; // bot ran out of time
    if (_game.status == GameStatus.checkmate) {
      // Side to move is checkmated → the other side won.
      return _game.state.turn == _botColor;
    }
    return false;
  }

  bool get _isDraw =>
      _flagged == null && !_resigned && (_game.status == GameStatus.stalemate || _game.status == GameStatus.draw);

  String get _statusText {
    if (_isOver) return 'Game over';
    if (_game.status == GameStatus.check) return 'Check!';
    if (_thinking || _game.state.turn == _botColor) return 'Computer is thinking…';
    return 'Your move';
  }

  /// Current full-move number (increments after Black moves).
  int get _fullMove => (_game.history.length ~/ 2) + 1;

  String _mmss(int ms) {
    final s = (ms / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// Remaining fraction of [c]'s move time for the card's timer ring (null =
  /// unlimited → full ring).
  double? _timeLeft(PieceColor c) => _clock == null ? null : _clock!.msFor(c) / _clock!.initialMs;

  int _secs(int ms) => (ms / 1000).ceil();

  /// Turn-clock text for the side to move ("∞" when the time control is off).
  String get _timerText => _clock == null ? '∞' : _mmss(_clock!.msFor(_game.state.turn));
  bool get _timerUrgent => _clock != null && !_isOver && _clock!.msFor(_game.state.turn) <= 10000;

  @override
  Widget build(BuildContext context) {
    final myTurn = _game.state.turn == _playerColor;
    final botTurn = _game.state.turn == _botColor;
    final gameLive = !_isOver;
    final lastMove = _game.lastMoveText((c) => c == _playerColor ? 'You' : 'Computer');
    // Fixed (non-scrolling) layout: the board takes the free middle space and
    // the action bar stays pinned to the bottom, so nothing moves while playing.
    return AuraScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mockup board header: pause · ♞ Quick Play / Move n · 3D toggle
          // (no pot — Quick Play has no stake).
          GameHeader(
            title: '♞ Quick Play',
            subtitle: 'Move $_fullMove · vs Computer',
            pot: '0',
            leading: GlassIconButton(icon: Icons.pause_rounded, onTap: gameLive ? _openPause : () {}),
            trailing: GlassIconButton(
              icon: _perspective ? Icons.crop_square_rounded : Icons.view_in_ar_outlined,
              iconSize: 18,
              onTap: () => setState(() => _perspective = !_perspective),
            ),
          ),
          const SizedBox(height: 14),
          // Opponent card + last-move panel (mockup top corners).
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: BoardPlayerCard(
                    name: 'Computer',
                    initials: 'AI',
                    sub: '${_game.capturesBy(_botColor)} captures',
                    color: AuraColors.avatarBlue,
                    color2: const Color(0xFF3B82F6),
                    active: botTurn && gameLive,
                    // Same live countdown as the player's card ("Moving… · 28s").
                    turnText: botTurn && gameLive
                        ? (_clock == null ? 'Moving…' : 'Moving… · ${_secs(_clock!.msFor(_botColor))}s')
                        : null,
                    progress: _timeLeft(_botColor),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: BoardInfoPanel(label: 'Last move', value: lastMove)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Auto-flip so the player's side is always at the bottom.
          // Board + bottom cards stay together (mockup); spare height
          // collects above the pinned action bar.
          Expanded(
            child: Column(
              children: [
                Flexible(child: ChessBoardView(controller: _game, flipped: _playerColor == PieceColor.black, perspective: _perspective)),
                const SizedBox(height: 12),
                // Turn-clock panel + You card (mockup bottom corners: you bottom-right,
                // diagonal to the opponent top-left).
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: BoardInfoPanel(label: 'Turn clock', value: _timerText, big: true, urgent: _timerUrgent)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: BoardPlayerCard(
                          name: 'You',
                          initials: 'NR',
                          sub: '${_game.capturesBy(_playerColor)} captures',
                          color: AuraColors.brandPurple,
                          color2: AuraColors.brandPink,
                          active: myTurn && gameLive,
                          turnText: myTurn && gameLive
                              ? (_clock == null ? 'Your move' : 'Your move · ${_secs(_clock!.msFor(_playerColor))}s')
                              : null,
                          progress: _timeLeft(_playerColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Pinned action bar: status (lights up on your move) · forfeit.
          // No chat button — the opponent is the computer.
          BoardActionBar(statusLabel: _statusText, active: myTurn && gameLive, onResign: gameLive ? _forfeit : null),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Bot search entry point for [compute] (must be top-level): runs on a
/// background isolate on mobile/desktop. (On web, compute runs inline.)
Move? _searchBotMove((ChessState, int) args) => ChessBot(depth: args.$2).chooseMove(args.$1);
