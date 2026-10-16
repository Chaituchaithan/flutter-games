import 'dart:math' as math;

import 'package:snakeladder/services/session.dart';
import '../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:snakeladder/game/common/dice_view.dart';
import 'package:snakeladder/game/common/local_game_flow.dart';
import 'package:snakeladder/game/common/turn_timer.dart';
import 'package:snakeladder/game/snakes/snakes_board_view.dart';
import 'package:snakeladder/game/snakes/snakes_engine.dart';
import 'package:snakeladder/widgets/aura.dart';
import 'package:snakeladder/screens/match/match_result_screen.dart';
import 'package:snakeladder/game/common/dice_game_kit.dart';

/// Pawn colours for Snakes & Ladders (setup order).
const snakesColors = <(String, Color)>[
  ('Red', Color(0xFFF43F5E)),
  ('Green', Color(0xFF22C55E)),
  ('Yellow', Color(0xFFFBBF24)),
  ('Blue', Color(0xFF3B82F6)),
];

/// Quick Play setup → [SnakesLaddersScreen].
class SnakesSetupScreen extends StatelessWidget {
  const SnakesSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => DiceGameSetupScreen(
    title: 'Snakes & Ladders',
    blurb: context.l10n.snakesBlurb,
    colors: snakesColors,
    start: (players, color, clockMs) => SnakesLaddersScreen(players: players, colorIndex: color, clockMs: clockMs),
  );
}

/// Snakes & Ladders vs the computer: the drawn board (2D or tilted 3D), the
/// animated die, pause / forfeit and the shared result screen.
class SnakesLaddersScreen extends StatefulWidget {
  const SnakesLaddersScreen({super.key, this.players = 2, this.colorIndex = 3, this.clockMs = 30 * 1000});

  /// 2–4 (you + computers).
  final int players;

  /// Your pawn colour (index into [snakesColors]).
  final int colorIndex;

  /// Time per turn (null = unlimited) — chess-style turn clock.
  final int? clockMs;

  @override
  State<SnakesLaddersScreen> createState() => _SnakesLaddersScreenState();
}

class _SnakesLaddersScreenState extends State<SnakesLaddersScreen> with LocalGameFlow {
  late final SnakesGame _game = SnakesGame(players: widget.players)..addListener(_onChange);
  late final List<DicePlayer> _seats = _buildSeats();
  final _rng = math.Random();

  bool _perspective = false;

  /// Turn clock (same idea as chess "time per move"); restarts every roll.
  late final TurnTimer _clock = TurnTimer(limitMs: widget.clockMs, onExpire: _onTimeUp)..addListener(_onChange);
  (int, int)? _clockTurn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncClock());
  }

  /// You always roll first (seat 0).
  List<DicePlayer> _buildSeats() {
    final others = [
      for (var i = 0; i < snakesColors.length; i++)
        if (i != widget.colorIndex) i,
    ];
    return [
      DicePlayer(name: context.l10n.you, initials: ProviderScope.containerOf(context).read(currentUserProvider).initials, color: snakesColors[widget.colorIndex].$2, isYou: true),
      for (var k = 0; k < widget.players - 1; k++)
        DicePlayer(name: diceBotNames[k].$1, initials: diceBotNames[k].$2, color: snakesColors[others[k]].$2),
    ];
  }

  @override
  void dispose() {
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

  /// Start the clock for each new roll; stop it while a move animates or
  /// once the game is over.
  void _syncClock() {
    if (_isOver || _game.pending != null) {
      if (_clock.running) _clock.stop();
      return;
    }
    if (!_game.awaitingRoll) return;
    final key = (_game.turn, _game.rollId);
    if (key == _clockTurn) return;
    _clockTurn = key;
    _clock.start();
    if (paused) _clock.pause();
  }

  /// Your time ran out: roll for you (the computer always rolls in time).
  void _onTimeUp() {
    if (!mounted || _isOver || _game.turn != 0 || !_game.awaitingRoll) return;
    showAuraToast(context, context.l10n.timeUpPlayed, kind: AuraToastKind.info);
    _roll();
  }

  @override
  void pauseGame() {
    super.pauseGame();
    _clock.pause();
  }

  @override
  void resumeGame() {
    super.resumeGame();
    _clock.resume();
  }

  int get _secs => (_clock.remainingMs / 1000).ceil();

  DiceSeatView _seatView(int p) {
    final active = !_isOver && _game.turn == p;
    String? turn;
    if (active && _game.pending == null) {
      turn = p == 0
          ? (_clock.unlimited ? context.l10n.turnYourRollNoClock : context.l10n.turnYourRoll(_secs))
          : (_clock.unlimited ? context.l10n.turnRollingNoClock : context.l10n.turnRolling(_secs));
    }
    return DiceSeatView(
      player: _seats[p],
      sub: _square(p),
      active: active,
      turnText: turn,
      progress: active ? _clock.fraction : null,
    );
  }

  bool get _isOver => _game.isOver || resigned;
  bool get _myTurn => !_isOver && _game.turn == 0;
  bool get _canRoll => _myTurn && _game.awaitingRoll && !paused;

  void _roll() {
    if (!_game.awaitingRoll || _isOver) return;
    _game.roll();
  }

  /// The board finished animating: commit and continue.
  void _onMoveAnimated() {
    _game.finishMove(nameOf: (p) => _seats[p].name);
    if (_game.isOver) {
      endGame();
    } else {
      _scheduleBot();
    }
  }

  /// A computer's turn: roll after a natural pause.
  void _scheduleBot() {
    if (_isOver || paused || _game.turn == 0 || !_game.awaitingRoll) return;
    scheduleBot(
      Duration(milliseconds: 650 + _rng.nextInt(500)),
      _roll,
      stillValid: () => _game.turn != 0 && _game.awaitingRoll,
    );
  }

  // ── LocalGameFlow hooks ──

  @override
  String get pauseSubtitle => context.l10n.moveOnHold(_game.moveCount);

  @override
  void onResumeGame() => _scheduleBot();

  // ── Result ──

  @override
  void showResult() {
    final won = !resigned && _game.winner == 0;
    final best = [for (var p = 1; p < _game.players; p++) _game.positions[p]].reduce(math.max);
    final winnerName = _game.winner == null ? null : _seats[_game.winner!].name;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchResultScreen(
          outcome: won ? MatchOutcome.victory : MatchOutcome.defeat,
          subtitle: resigned
              ? context.l10n.youForfeitedRace
              : won
              ? context.l10n.snakesWinSub
              : context.l10n.snakesLoseSub(winnerName ?? ''),
          youScore: _game.positions[0],
          oppScore: best,
          oppName: widget.players == 2 ? _seats[1].name : context.l10n.bestAi,
          oppInitials: widget.players == 2 ? _seats[1].initials : 'AI',
          // Quick Play vs the computer: nothing to earn.
          practice: true,
          playAgain: (_) =>
              SnakesLaddersScreen(players: widget.players, colorIndex: widget.colorIndex, clockMs: widget.clockMs),
        ),
      ),
    );
  }

  String get _status {
    if (_isOver) return context.l10n.gameOver;
    if (_game.pending != null) return context.l10n.playerMoving(_seats[_game.turn].name);
    if (_myTurn) return context.l10n.yourTurnRoll;
    return context.l10n.playerRolling(_seats[_game.turn].name);
  }

  String _square(int p) =>
      _game.positions[p] == 0 ? context.l10n.startSquare : context.l10n.squareN(_game.positions[p]);

  @override
  Widget build(BuildContext context) {
    final live = !_isOver;
    return AuraScaffold(
      // Slimmer side margins so the board can be as large as possible.
      padding: const EdgeInsets.symmetric(horizontal: 12),
      body: DiceBoardLayout(
        header: LocalGameHeader(
          title: '🐍 Snakes & Ladders',
          subtitle: context.l10n.moveAndPlayers(_game.moveCount, widget.players),
          live: live,
          onPause: openPause,
          perspective: _perspective,
          onTogglePerspective: () => setState(() => _perspective = !_perspective),
        ),
        opponents: [for (var p = 1; p < _seats.length; p++) _seatView(p)],
        you: _seatView(0),
        lastMove: _game.lastText,
        // No Turn clock panel here: the timer ring on each player card shows it.
        clockText: null,
        clockUrgent: false,
        dice: DiceView(
          value: _game.lastRoll,
          rollId: _game.rollId,
          size: 38,
          enabled: _canRoll,
          onTap: _roll,
          glow: _seats[_game.turn].color,
        ),
        board: SnakesBoardView(
          game: _game,
          colors: [for (final s in _seats) s.color],
          perspective: _perspective,
          delay: DiceView.rollDuration,
          onMoveAnimated: _onMoveAnimated,
        ),
        actionBar: BoardActionBar(statusLabel: _status, active: _canRoll, onResign: live ? forfeit : null),
      ),
    );
  }
}
