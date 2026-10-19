import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:snakeladder/services/session.dart';
import '../../l10n/l10n.dart';
import '../../screens/match/match_result_screen.dart';
import '../../widgets/aura.dart';
import '../common/board_game_setup.dart';
import '../common/dice_game_kit.dart';
import '../common/local_game_flow.dart';
import '../common/turn_timer.dart';
import 'checkers_board_view.dart';
import 'checkers_engine.dart';

/// Quick Play setup → [CheckersScreen].
class CheckersSetupScreen extends StatelessWidget {
  const CheckersSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => BoardGameSetupScreen(
    title: 'Checkers',
    blurb: context.l10n.checkersBlurb,
    sides: [
      SetupSide(
        label: context.l10n.checkersDark,
        icon: const CheckerPiece(piece: Checker(CheckerSide.dark), size: 28),
      ),
      SetupSide(
        label: context.l10n.checkersLight,
        icon: const CheckerPiece(piece: Checker(CheckerSide.light), size: 28),
      ),
    ],
    start: (side, difficulty, clockMs) =>
        CheckersScreen(you: side == null ? null : CheckerSide.values[side], difficulty: difficulty, clockMs: clockMs),
  );
}

/// Checkers vs the computer, in the chess game-area layout. Your side is at
/// the bottom; running out of time on a move loses, as in chess.
class CheckersScreen extends StatefulWidget {
  const CheckersScreen({super.key, this.you = CheckerSide.dark, this.difficulty = 2, this.clockMs = 30 * 1000});

  /// Your side (null = random). Red (dark) moves first.
  final CheckerSide? you;

  /// 1 easy · 2 medium · 3 hard.
  final int difficulty;
  final int? clockMs;

  @override
  State<CheckersScreen> createState() => _CheckersScreenState();
}

class _CheckersScreenState extends State<CheckersScreen> with LocalGameFlow {
  final _rng = math.Random();
  late final CheckerSide _you = widget.you ?? (_rng.nextBool() ? CheckerSide.dark : CheckerSide.light);
  CheckerSide get _bot => _you.other;
  final CheckersGame _game = CheckersGame();

  late final TurnTimer _clock = TurnTimer(limitMs: widget.clockMs, onExpire: _onTimeUp)..addListener(_onChange);
  int _clockMove = -1;
  CheckerSide? _timedOut;
  bool _thinking = false;
  int _botGen = 0;
  bool _perspective = false;

  int get _depth => switch (widget.difficulty) {
    <= 1 => 2,
    2 => 4,
    _ => 6,
  };

  @override
  void initState() {
    super.initState();
    _game.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncClock();
      _maybeBot();
    });
  }

  @override
  void dispose() {
    _botGen++;
    disposeFlow();
    _clock.dispose();
    _game.removeListener(_onChange);
    _game.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    _syncClock();
    setState(() {});
  }

  bool get _isOver => _game.state.isOver || resigned || _timedOut != null;
  bool get _myTurn => !_isOver && _game.state.turn == _you;

  void _syncClock() {
    if (_isOver) {
      if (_clock.running) _clock.stop();
      return;
    }
    if (_clockMove == _game.moveCount) return;
    _clockMove = _game.moveCount;
    _clock.start();
    if (paused) _clock.pause();
  }

  void _onTimeUp() {
    if (!mounted || _isOver) return;
    setState(() => _timedOut = _game.state.turn);
    _finish();
  }

  void _play(CheckerMove m) {
    _game.play(m);
    if (_game.state.isOver) {
      _finish();
    } else {
      _maybeBot();
    }
  }

  void _onPlayerMove(CheckerMove m) {
    if (!_myTurn || paused || _thinking) return;
    _play(m);
  }

  String _name(CheckerSide s) => s == _you ? context.l10n.you : context.l10n.computer;

  void _maybeBot() {
    if (_isOver || paused || _thinking || _game.state.turn != _bot) return;
    setState(() => _thinking = true);
    final gen = ++_botGen;
    final started = DateTime.now();
    final (minMs, spread) = switch (widget.difficulty) {
      <= 1 => (600, 400),
      2 => (1000, 800),
      _ => (1500, 1000),
    };
    final last = _game.lastMove;
    final think = minMs + _rng.nextInt(spread) + (last == null ? 0 : CheckersBoardView.durationMs(last));
    compute(_searchCheckers, (_game.state, _depth)).then((m) {
      if (!mounted || gen != _botGen) return;
      final wait = think - DateTime.now().difference(started).inMilliseconds;
      scheduleBot(Duration(milliseconds: wait.clamp(0, think)), () {
        _thinking = false;
        if (m != null && _game.state.turn == _bot && !_isOver) _play(m);
        if (mounted) setState(() {});
      }, stillValid: () => gen == _botGen);
    });
  }

  @override
  void pauseGame() {
    super.pauseGame();
    _botGen++;
    _thinking = false;
    _clock.pause();
  }

  @override
  void resumeGame() {
    super.resumeGame();
    _clock.resume();
  }

  @override
  String get pauseSubtitle => context.l10n.moveOnHold(_game.moveCount);

  @override
  void onResumeGame() => _maybeBot();

  void _finish() {
    _botGen++;
    _clock.stop();
    endGame(immediate: resigned);
  }

  @override
  void showResult() {
    final l = context.l10n;
    final s = _game.state;
    final MatchOutcome outcome;
    final String subtitle;
    if (resigned) {
      outcome = MatchOutcome.defeat;
      subtitle = l.youForfeitedMatch;
    } else if (_timedOut != null) {
      final mine = _timedOut == _you;
      outcome = mine ? MatchOutcome.defeat : MatchOutcome.victory;
      subtitle = mine ? l.youRanOutOfTime : l.computerRanOutOfTime;
    } else if (s.winner == null) {
      outcome = MatchOutcome.draw;
      subtitle = l.checkersDrawSub;
    } else if (s.winner == _you) {
      outcome = MatchOutcome.victory;
      subtitle = l.checkersWinSub;
    } else {
      outcome = MatchOutcome.defeat;
      subtitle = l.checkersLoseSub;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchResultScreen(
          outcome: outcome,
          subtitle: subtitle,
          // Pieces captured by each side.
          youScore: 12 - s.countOf(_bot),
          oppScore: 12 - s.countOf(_you),
          oppName: l.computer,
          oppInitials: 'AI',
          // Quick Play vs the computer: nothing to earn.
          practice: true,
          playAgain: (_) => CheckersScreen(you: widget.you, difficulty: widget.difficulty, clockMs: widget.clockMs),
        ),
      ),
    );
  }

  int get _secs => (_clock.remainingMs / 1000).ceil();

  DiceSeatView _seat(CheckerSide side) {
    final active = !_isOver && _game.state.turn == side;
    final l = context.l10n;
    String? turn;
    if (active) {
      turn = side == _you
          ? (_clock.unlimited ? l.yourMove : l.yourMoveSecs(_secs))
          : (_clock.unlimited ? l.thinking : l.thinkingSecs(_secs));
    }
    final player = side == _you
        ? DicePlayer(name: l.you, initials: ProviderScope.containerOf(context).read(currentUserProvider).initials, color: AuraColors.brandPurple, isYou: true)
        : DicePlayer(name: l.computer, initials: 'AI', color: AuraColors.avatarBlue);
    return DiceSeatView(
      player: player,
      sub: l.piecesKings(_game.state.countOf(side), _game.state.kingsOf(side)),
      active: active,
      turnText: turn,
      progress: active ? _clock.fraction : null,
    );
  }

  String get _lastMoveText {
    final m = _game.lastMove;
    if (m == null) return '—';
    final mover = _game.state.board[m.to]?.side;
    if (mover == null) return '—';
    final l = context.l10n;
    return m.isCapture
        ? l.checkersCaptured(_name(mover), m.captures.length)
        : l.checkersMoved(_name(mover), checkersSquareNumber(m.from), checkersSquareNumber(m.to));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final live = !_isOver;
    final moves = _myTurn && !_thinking && !paused ? _game.state.legalMoves() : const <CheckerMove>[];
    return guardBack(
      AuraScaffold(
      // Slimmer side margins so the board can be as large as possible.
      padding: const EdgeInsets.symmetric(horizontal: 12),
      body: DiceBoardLayout(
        header: LocalGameHeader(
          title: '⛀ Checkers',
          subtitle: l.moveAndPlayers(_game.moveCount + 1, 2),
          live: live,
          onPause: openPause,
          perspective: _perspective,
          onTogglePerspective: () => setState(() => _perspective = !_perspective),
        ),
        opponents: [_seat(_bot)],
        you: _seat(_you),
        lastMove: _lastMoveText,
        clockText: _clock.text,
        clockUrgent: _clock.urgent,
        board: CheckersBoardView(
          game: _game,
          moves: moves,
          onMove: _onPlayerMove,
          flipped: _you == CheckerSide.light,
          perspective: _perspective,
        ),
        actionBar: BoardActionBar(
          statusLabel: _isOver ? l.gameOver : (_myTurn ? l.yourMove : l.computerThinking),
          active: _myTurn,
          onResign: live ? forfeit : null,
        ),
      ),
    ),
    );
  }
}

/// Bot search entry point for [compute] (top-level, background isolate).
CheckerMove? _searchCheckers((CheckersState, int) args) => CheckersBot(depth: args.$2).chooseMove(args.$1);
