import 'dart:async';

import 'package:snakeladder/game/common/local_game_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:snakeladder/game/chess/chess_board_view.dart';
import 'package:snakeladder/game/chess/chess_clock.dart';
import 'package:snakeladder/game/chess/chess_controller.dart';
import 'package:snakeladder/game/chess/chess_engine.dart';
import 'package:snakeladder/services/session.dart';
import 'package:snakeladder/widgets/aura.dart';
import 'package:snakeladder/screens/match/match_result_screen.dart';

/// Chess · interactive board. Fully playable locally (hot-seat) on a premium
/// 2.5D board driven by the rules engine. Multiplayer (socket) and a themed
/// photoreal piece set are layered on top of this later.
class ChessScreen extends StatefulWidget {
  const ChessScreen({super.key});

  @override
  State<ChessScreen> createState() => _ChessScreenState();
}

class _ChessScreenState extends State<ChessScreen> {
  // Hot-seat: both colours are tappable on one device (localColor = null).
  // White = "You" (bottom), Black = ZeroCool (top). 30s per move.
  final ChessController _game = ChessController();
  late final ChessClock _clock = ChessClock(_game, perMove: true, onFlag: _onFlag);

  PieceColor? _flagged; // side that ran out of time
  bool _forfeited = false; // You (White) forfeited
  bool _resultShown = false;
  Timer? _resultTimer;

  bool get _isOver => _game.isOver || _flagged != null || _forfeited;

  @override
  void initState() {
    super.initState();
    _game.addListener(_onGame);
    _clock.addListener(_onGame);
  }

  @override
  void dispose() {
    _resultTimer?.cancel();
    _clock.dispose();
    _game.removeListener(_onGame);
    _game.dispose();
    super.dispose();
  }

  void _onGame() {
    setState(() {});
    _checkGameOver();
  }

  void _onFlag(PieceColor c) {
    setState(() => _flagged = c);
    _checkGameOver();
  }

  void _openPause() => showGamePaused(
        context,
        subtitle: 'Move $_fullMove · the clock is stopped for everyone.',
        onPause: _clock.pause,
        onResume: _clock.resume,
        onForfeit: _forfeit,
      );

  Future<void> _forfeit() async {
    _clock.pause();
    final ok = await confirmMatchForfeit(context, stake: 200);
    if (!mounted) return;
    if (ok) {
      setState(() => _forfeited = true);
      _checkGameOver(immediate: true);
    } else {
      _clock.resume();
    }
  }

  void _checkGameOver({bool immediate = false}) {
    if (!_isOver || _resultShown) return;
    _resultShown = true;
    _clock.pause();
    _resultTimer = Timer(Duration(milliseconds: immediate ? 0 : 900), _showResult);
  }

  void _showResult() {
    if (!mounted) return;
    final PieceColor? winner = _forfeited
        ? PieceColor.black
        : _flagged?.opposite ?? (_game.status == GameStatus.checkmate ? _game.state.turn.opposite : null);
    final outcome = winner == null
        ? MatchOutcome.draw
        : (winner == PieceColor.white ? MatchOutcome.victory : MatchOutcome.defeat);
    final subtitle = _forfeited
        ? 'You forfeited the match.'
        : _flagged != null
            ? (_flagged == PieceColor.white ? 'You ran out of time.' : 'ZeroCool ran out of time.')
            : _game.status == GameStatus.stalemate
                ? 'Stalemate — an even match.'
                : null;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchResultScreen(
          outcome: outcome,
          subtitle: subtitle,
          youScore: _game.capturesBy(PieceColor.white),
          oppScore: _game.capturesBy(PieceColor.black),
          oppName: 'ZeroCool',
          oppInitials: 'ZE',
          playAgain: (_) => const ChessScreen(),
        ),
      ),
    );
  }

  String get _statusText {
    if (_isOver) return 'Game over';
    if (_game.status == GameStatus.check) return 'Check!';
    return _game.state.turn == PieceColor.white ? 'Your move' : 'ZeroCool to move';
  }

  /// Current full-move number (chess numbering: increments after Black moves).
  int get _fullMove => (_game.history.length ~/ 2) + 1;

  /// Milliseconds → "M:SS".
  String _mmss(int ms) {
    final s = (ms / 1000).ceil();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final whiteToMove = _game.state.turn == PieceColor.white;
    final live = !_isOver;
    final activeMs = _clock.msFor(_game.state.turn);
    final lastMove = _game.lastMoveText((c) => c == PieceColor.white ? 'You' : 'ZeroCool');
    double timeLeft(PieceColor c) => _clock.msFor(c) / _clock.initialMs;
    // Fixed layout: board fills the middle, the action bar stays at the bottom.
    return GameBackGuard(
      active: live && !_resultShown,
      onBack: _openPause,
      child: AuraScaffold(
      // Slimmer side margins so the board can be as large as possible.
      padding: const EdgeInsets.symmetric(horizontal: 12),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GameHeader(
            title: '♞ Chess',
            subtitle: 'Move $_fullMove · 1v1',
            pot: '400',
            leading: GlassIconButton(icon: Icons.pause_rounded, onTap: live ? _openPause : () {}),
          ),
          const SizedBox(height: 14),
          // Opponent card + last-move panel (mockup top corners).
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: BoardPlayerCard(
                    name: 'ZeroCool',
                    initials: 'ZE',
                    sub: '${_game.capturesBy(PieceColor.black)} captures',
                    color: AuraColors.avatarBlue,
                    color2: const Color(0xFF3B82F6),
                    active: !whiteToMove && live,
                    turnText: !whiteToMove && live ? 'Moving…' : null,
                    progress: timeLeft(PieceColor.black),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: BoardInfoPanel(label: 'Last move', value: lastMove)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            // The board, centred in the space between the top and bottom rows.
            child: Center(
              child: ChessBoardView(controller: _game),
            ),
          ),
          const SizedBox(height: 12),
          // Turn clock + You card, just above the action bar.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: BoardInfoPanel(label: 'Turn clock', value: _mmss(activeMs), big: true, urgent: live && activeMs <= 10000)),
                const SizedBox(width: 10),
                Expanded(
                  child: BoardPlayerCard(
                    name: 'You',
                    initials: ProviderScope.containerOf(context).read(currentUserProvider).initials,
                    sub: '${_game.capturesBy(PieceColor.white)} captures',
                    color: AuraColors.brandPurple,
                    color2: AuraColors.brandPink,
                    active: whiteToMove && live,
                    turnText: whiteToMove && live ? 'Your move · ${(activeMs / 1000).ceil()}s' : null,
                    progress: timeLeft(PieceColor.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Pinned action bar: chat · status · forfeit.
          BoardActionBar(
            statusLabel: _statusText,
            active: live,
            onChat: () => showGameChatSheet(context),
            onResign: live ? _forfeit : null,
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
    );
  }
}
