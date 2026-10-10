import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:snakeladder/game/common/local_game_flow.dart';
import 'package:snakeladder/game/ludo/ludo_board_view.dart';
import 'package:snakeladder/game/ludo/ludo_engine.dart';
import 'package:snakeladder/widgets/aura.dart';
import 'package:snakeladder/screens/match/match_result_screen.dart';
import 'package:snakeladder/game/common/dice_game_kit.dart';

/// Ludo colours offered in setup (index = [LudoColor.index]).
final ludoSetupColors = <(String, Color)>[
  for (final c in LudoColor.values) ('${c.name[0].toUpperCase()}${c.name.substring(1)}', ludoColor(c)),
];

/// Quick Play setup → [LudoScreen].
class LudoSetupScreen extends StatelessWidget {
  const LudoSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => DiceGameSetupScreen(
    title: 'Ludo',
    blurb: 'Roll a 6 to bring a token out, capture rivals, and get all four tokens home first.',
    colors: ludoSetupColors,
    start: (players, color) => LudoScreen(players: players, color: LudoColor.values[color]),
  );
}

/// Ludo vs the computer: the drawn board (2D or tilted 3D, your base
/// bottom-left), the animated die, tap-a-token moves, pause / forfeit and
/// the shared result screen.
class LudoScreen extends StatefulWidget {
  const LudoScreen({super.key, this.players = 2, this.color = LudoColor.blue});

  /// 2–4 (you + computers).
  final int players;
  final LudoColor color;

  @override
  State<LudoScreen> createState() => _LudoScreenState();
}

class _LudoScreenState extends State<LudoScreen> with LocalGameFlow {
  late final LudoGame _game = LudoGame(colors: _turnOrder())..addListener(_onChange);
  final _rng = math.Random();

  bool _perspective = false;
  bool _rolling = false; // die in the air

  LudoColor get _me => widget.color;

  /// Clockwise from you; 2 players sit opposite each other.
  List<LudoColor> _turnOrder() {
    final at = [for (var k = 0; k < 4; k++) LudoColor.values[(widget.color.index + k) % 4]];
    return switch (widget.players) {
      2 => [at[0], at[2]],
      3 => [at[0], at[1], at[2]],
      _ => at,
    };
  }

  late final Map<LudoColor, DicePlayer> _seats = {
    for (var k = 0; k < _game.colors.length; k++)
      _game.colors[k]: k == 0
          ? DicePlayer(name: 'You', initials: 'YOU', color: ludoColor(_me), isYou: true)
          : DicePlayer(
              name: diceBotNames[k - 1].$1,
              initials: diceBotNames[k - 1].$2,
              color: ludoColor(_game.colors[k]),
            ),
  };

  String _name(LudoColor c) => _seats[c]!.name;

  @override
  void dispose() {
    disposeFlow();
    _game.removeListener(_onChange);
    _game.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  bool get _isOver => _game.isOver || resigned;
  bool get _myTurn => !_isOver && _game.current == _me;
  bool get _canRoll => _myTurn && _game.awaitingRoll && !_rolling && !paused;
  bool get _canPick => _myTurn && _game.awaitingMove && !_rolling && !paused;

  void _roll() {
    if (!_game.awaitingRoll || _isOver) return;
    _rolling = true;
    _game.roll();
  }

  /// The die landed: pass when stuck, auto-move a single option, let the
  /// computer choose, or wait for your tap.
  void _onRolled() {
    _rolling = false;
    if (!mounted || _isOver) return;
    if (_game.passIfStuck(nameOf: _name)) {
      scheduleBot(const Duration(milliseconds: 700), _next);
      return;
    }
    final options = _game.movable;
    if (_game.current != _me) {
      scheduleBot(
        Duration(milliseconds: 350 + _rng.nextInt(350)),
        () => _game.move(_game.chooseBotMove()),
        stillValid: () => _game.awaitingMove,
      );
    } else if (options.length == 1) {
      // Only one legal move: play it (like real Ludo apps).
      scheduleBot(
        const Duration(milliseconds: 350),
        () => _game.move(options.first),
        stillValid: () => _game.awaitingMove,
      );
    }
    setState(() {});
  }

  void _pick(int token) {
    if (_canPick && _game.movable.contains(token)) _game.move(token);
  }

  void _onMoveAnimated() {
    _game.finishMove(nameOf: _name);
    if (_game.isOver) {
      endGame();
    } else {
      _next();
    }
  }

  /// Hand over to whoever rolls next (computers roll by themselves).
  void _next() {
    if (!mounted || _isOver || paused || !_game.awaitingRoll || _game.current == _me) {
      if (mounted) setState(() {});
      return;
    }
    scheduleBot(
      Duration(milliseconds: 600 + _rng.nextInt(500)),
      _roll,
      stillValid: () => _game.awaitingRoll && _game.current != _me,
    );
  }

  // ── LocalGameFlow hooks ──

  @override
  String get pauseSubtitle => 'Move ${_game.moveCount} · the game is on hold.';

  /// Re-run whatever step the pause cancelled.
  @override
  void onResumeGame() {
    if (_game.awaitingMove && !_rolling) {
      _onRolled();
    } else {
      _next();
    }
  }

  // ── Result ──

  @override
  void showResult() {
    final won = !resigned && _game.winner == _me;
    final rivals = _game.colors.where((c) => c != _me).toList();
    final bestRival = rivals.reduce((a, b) => _game.homeCount(a) >= _game.homeCount(b) ? a : b);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchResultScreen(
          outcome: won ? MatchOutcome.victory : MatchOutcome.defeat,
          subtitle: resigned
              ? 'You forfeited the match.'
              : won
              ? 'All four tokens home — champion!'
              : '${_name(_game.winner!)} got all four tokens home first.',
          youScore: _game.homeCount(_me),
          oppScore: _game.homeCount(bestRival),
          youInitials: 'YOU',
          oppName: _name(bestRival),
          oppInitials: _seats[bestRival]!.initials,
          reward: won ? '+50 XP' : '+20 XP',
          playAgain: (_) => LudoScreen(players: widget.players, color: widget.color),
        ),
      ),
    );
  }

  String get _status {
    if (_isOver) return 'Game over';
    if (_game.pending != null) return '${_name(_game.current)} moving…';
    if (_rolling) return 'Rolling…';
    if (_canPick) return 'Pick a token to move';
    if (_myTurn) return 'Your turn — roll';
    return '${_name(_game.current)} is playing…';
  }

  String get _prompt {
    if (_canRoll) return 'Tap the dice\nto roll';
    if (_canPick) return 'Tap a glowing\ntoken';
    return _game.pending != null ? 'Moving…' : 'Wait…';
  }

  String _tokensText(LudoColor c) {
    final list = _game.tokens[c]!;
    final home = _game.homeCount(c);
    final out = list.where((p) => p != LudoRules.base && p != LudoRules.home).length;
    return '$home home · $out out';
  }

  @override
  Widget build(BuildContext context) {
    final live = !_isOver;
    final rivals = _game.colors.where((c) => c != _me).toList();
    return AuraScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocalGameHeader(
            title: '🎲 Ludo',
            subtitle: 'Move ${_game.moveCount} · ${widget.players} players',
            live: live,
            onPause: openPause,
            perspective: _perspective,
            onTogglePerspective: () => setState(() => _perspective = !_perspective),
          ),
          const SizedBox(height: 12),
          DicePlayersStrip(
            players: [for (final c in rivals) _seats[c]!],
            active: live && _game.current != _me ? rivals.indexOf(_game.current) : null,
            status: (k) => _tokensText(rivals[k]),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: LudoBoardView(
              game: _game,
              bottomLeft: _me,
              perspective: _perspective,
              canPick: _canPick,
              onPick: _pick,
              onMoveAnimated: _onMoveAnimated,
            ),
          ),
          const SizedBox(height: 10),
          DicePlayersStrip(players: [_seats[_me]!], active: _myTurn ? 0 : null, status: (_) => _tokensText(_me)),
          const SizedBox(height: 10),
          DiceTray(
            value: _game.lastRoll,
            rollId: _game.rollId,
            canRoll: _canRoll,
            onRoll: _roll,
            onRolled: _onRolled,
            lastMove: _game.lastText,
            prompt: _prompt,
            color: ludoColor(_game.current),
          ),
          const SizedBox(height: 10),
          BoardActionBar(statusLabel: _status, active: _canRoll || _canPick, onResign: live ? forfeit : null),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
