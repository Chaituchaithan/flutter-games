import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:snakeladder/game/common/dice_view.dart';
import 'package:snakeladder/game/common/local_game_flow.dart';
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
    blurb: 'Race to 100 against the computer. Ladders lift you up, snakes slide you down — land on 100 exactly.',
    colors: snakesColors,
    start: (players, color) => SnakesLaddersScreen(players: players, colorIndex: color),
  );
}

/// Snakes & Ladders vs the computer: the drawn board (2D or tilted 3D), the
/// animated die, pause / forfeit and the shared result screen.
class SnakesLaddersScreen extends StatefulWidget {
  const SnakesLaddersScreen({super.key, this.players = 2, this.colorIndex = 3});

  /// 2–4 (you + computers).
  final int players;

  /// Your pawn colour (index into [snakesColors]).
  final int colorIndex;

  @override
  State<SnakesLaddersScreen> createState() => _SnakesLaddersScreenState();
}

class _SnakesLaddersScreenState extends State<SnakesLaddersScreen> with LocalGameFlow {
  late final SnakesGame _game = SnakesGame(players: widget.players)..addListener(_onChange);
  late final List<DicePlayer> _seats = _buildSeats();
  final _rng = math.Random();

  bool _perspective = false;

  /// You always roll first (seat 0).
  List<DicePlayer> _buildSeats() {
    final others = [
      for (var i = 0; i < snakesColors.length; i++)
        if (i != widget.colorIndex) i,
    ];
    return [
      DicePlayer(name: 'You', initials: 'YOU', color: snakesColors[widget.colorIndex].$2, isYou: true),
      for (var k = 0; k < widget.players - 1; k++)
        DicePlayer(name: diceBotNames[k].$1, initials: diceBotNames[k].$2, color: snakesColors[others[k]].$2),
    ];
  }

  @override
  void dispose() {
    disposeFlow();
    _game.removeListener(_onChange);
    _game.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
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
  String get pauseSubtitle => 'Move ${_game.moveCount} · the game is on hold.';

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
              ? 'You forfeited the race.'
              : won
              ? 'First to 100 — what a climb!'
              : '$winnerName reached 100 first.',
          youScore: _game.positions[0],
          oppScore: best,
          youInitials: 'YOU',
          oppName: widget.players == 2 ? _seats[1].name : 'Best AI',
          oppInitials: widget.players == 2 ? _seats[1].initials : 'AI',
          reward: won ? '+50 XP' : '+20 XP',
          playAgain: (_) => SnakesLaddersScreen(players: widget.players, colorIndex: widget.colorIndex),
        ),
      ),
    );
  }

  String get _status {
    if (_isOver) return 'Game over';
    if (_game.pending != null) return '${_seats[_game.turn].name} moving…';
    if (_myTurn) return 'Your turn — roll';
    return '${_seats[_game.turn].name} is rolling…';
  }

  String _square(int p) => _game.positions[p] == 0 ? 'Start' : 'Square ${_game.positions[p]}';

  @override
  Widget build(BuildContext context) {
    final live = !_isOver;
    final opponents = [for (var i = 1; i < _seats.length; i++) i];
    return AuraScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocalGameHeader(
            title: '🐍 Snakes & Ladders',
            subtitle: 'Move ${_game.moveCount} · ${widget.players} players',
            live: live,
            onPause: openPause,
            perspective: _perspective,
            onTogglePerspective: () => setState(() => _perspective = !_perspective),
          ),
          const SizedBox(height: 12),
          // Opponents on top.
          DicePlayersStrip(
            players: [for (final i in opponents) _seats[i]],
            active: live && _game.turn != 0 ? opponents.indexOf(_game.turn) : null,
            status: (k) => _square(opponents[k]),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SnakesBoardView(
              game: _game,
              colors: [for (final s in _seats) s.color],
              perspective: _perspective,
              delay: DiceView.rollDuration,
              onMoveAnimated: _onMoveAnimated,
            ),
          ),
          const SizedBox(height: 10),
          DicePlayersStrip(players: [_seats[0]], active: _myTurn ? 0 : null, status: (_) => _square(0)),
          const SizedBox(height: 10),
          DiceTray(
            value: _game.lastRoll,
            rollId: _game.rollId,
            canRoll: _canRoll,
            onRoll: _roll,
            lastMove: _game.lastText,
            prompt: _canRoll ? 'Tap the dice\nto roll' : (_game.pending != null ? 'Moving…' : 'Wait…'),
            color: _seats[_game.turn].color,
          ),
          const SizedBox(height: 10),
          BoardActionBar(statusLabel: _status, active: _canRoll, onResign: live ? forfeit : null),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
