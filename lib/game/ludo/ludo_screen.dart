import 'dart:math' as math;

import 'package:snakeladder/services/session.dart';
import '../../l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:snakeladder/game/common/dice_view.dart';
import 'package:snakeladder/game/common/local_game_flow.dart';
import 'package:snakeladder/game/common/turn_timer.dart';
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
    blurb: context.l10n.ludoBlurb,
    colors: ludoSetupColors,
    start: (players, color, clockMs) => LudoScreen(players: players, color: LudoColor.values[color], clockMs: clockMs),
  );
}

/// Ludo vs the computer: the drawn board (2D or tilted 3D, your base
/// bottom-left), the animated die, tap-a-token moves, pause / forfeit and
/// the shared result screen.
class LudoScreen extends StatefulWidget {
  const LudoScreen({super.key, this.players = 2, this.color = LudoColor.blue, this.clockMs = 30 * 1000});

  /// 2–4 (you + computers).
  final int players;
  final LudoColor color;

  /// Time per turn — rolling and picking a token (null = unlimited).
  final int? clockMs;

  @override
  State<LudoScreen> createState() => _LudoScreenState();
}

class _LudoScreenState extends State<LudoScreen> with LocalGameFlow {
  late final LudoGame _game = LudoGame(colors: _turnOrder())..addListener(_onChange);
  final _rng = math.Random();

  bool _perspective = false;
  bool _rolling = false; // die in the air

  /// Who rolled last (the die's number badge takes their colour).
  LudoColor? _roller;

  /// Turn clock (chess-style); one budget covers the roll and the token pick.
  late final TurnTimer _clock = TurnTimer(limitMs: widget.clockMs, onExpire: _onTimeUp)..addListener(_onChange);
  (LudoColor, int)? _clockTurn;

  /// Your time ran out this turn: the app rolls and picks for you.
  bool _autoplay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncClock());
  }

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
          ? DicePlayer(name: context.l10n.you, initials: ProviderScope.containerOf(context).read(currentUserProvider).initials, color: ludoColor(_me), isYou: true)
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

  /// A new roll (new player, or an extra roll) starts a fresh turn clock;
  /// it stops while a token moves and when the game ends.
  void _syncClock() {
    if (_isOver || _game.pending != null) {
      if (_clock.running) _clock.stop();
      return;
    }
    if (!_game.awaitingRoll) return; // rolled: the same clock covers the pick
    final key = (_game.current, _game.rollId);
    if (key == _clockTurn) return;
    _clockTurn = key;
    _autoplay = false;
    // Your turn: a short buzz so you notice it.
    if (_game.current == _me && !_isOver) HapticFeedback.mediumImpact();
    _clock.start();
    if (paused) _clock.pause();
  }

  /// Your time ran out: roll and/or move for you (computers act in time).
  void _onTimeUp() {
    if (!mounted || _isOver || _game.current != _me) return;
    showAuraToast(context, context.l10n.timeUpPlayed, kind: AuraToastKind.info);
    _autoplay = true;
    if (_game.awaitingRoll && !_rolling) {
      _roll(); // _onRolled continues the autoplay
    } else if (_game.awaitingMove && !_rolling) {
      _game.move(_game.chooseBotMove());
    }
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

  DiceSeatView _seatView(LudoColor c) {
    final active = !_isOver && _game.current == c;
    String? turn;
    if (active && _game.pending == null) {
      if (c == _me) {
        turn = _canPick
            ? (_clock.unlimited ? context.l10n.pickToken : context.l10n.turnPick(_secs))
            : (_clock.unlimited ? context.l10n.turnYourRollNoClock : context.l10n.turnYourRoll(_secs));
      } else {
        turn = _clock.unlimited ? context.l10n.turnRollingNoClock : context.l10n.turnRolling(_secs);
      }
    }
    return DiceSeatView(
      player: _seats[c]!,
      sub: _tokensText(c),
      active: active,
      turnText: turn,
      progress: active ? _clock.fraction : null,
    );
  }

  bool get _isOver => _game.isOver || resigned;
  bool get _myTurn => !_isOver && _game.current == _me;
  bool get _canRoll => _myTurn && _game.awaitingRoll && !_rolling && !paused;
  bool get _canPick => _myTurn && _game.awaitingMove && !_rolling && !paused;

  void _roll() {
    if (!_game.awaitingRoll || _isOver) return;
    _rolling = true;
    _roller = _game.current;
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
    if (_game.current == _me && _autoplay) {
      // Out of time: pick for the player too.
      scheduleBot(
        const Duration(milliseconds: 350),
        () => _game.move(_game.chooseBotMove()),
        stillValid: () => _game.awaitingMove,
      );
    } else if (_game.current != _me) {
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
  String get pauseSubtitle => context.l10n.moveOnHold(_game.moveCount);

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
              ? context.l10n.youForfeitedMatch
              : won
              ? context.l10n.ludoWinSub
              : context.l10n.ludoLoseSub(_name(_game.winner!)),
          youScore: _game.homeCount(_me),
          oppScore: _game.homeCount(bestRival),
          oppName: _name(bestRival),
          oppInitials: _seats[bestRival]!.initials,
          // Quick Play vs the computer: nothing to earn.
          practice: true,
          playAgain: (_) => LudoScreen(players: widget.players, color: widget.color, clockMs: widget.clockMs),
        ),
      ),
    );
  }

  /// The banner over the board: what was rolled, or whose turn it is.
  Widget? _banner() {
    if (_isOver) return null;
    final l = context.l10n;
    final cur = _game.current;
    final color = ludoColor(cur);
    final mine = cur == _me;
    if (_rolling) {
      return TurnBanner(text: mine ? l.youAreRolling : l.playerRolling(_name(cur)), color: color, icon: Icons.casino_rounded);
    }
    if (_canPick) {
      return TurnBanner(text: l.youRolledPick(_game.lastRoll), color: color, emphasis: true, icon: Icons.touch_app_rounded);
    }
    if (_game.awaitingMove || _game.pending != null) {
      return TurnBanner(
        text: mine ? l.youRolledN(_game.lastRoll) : l.playerRolledN(_name(cur), _game.lastRoll),
        color: color,
        icon: Icons.casino_rounded,
      );
    }
    if (_canRoll) {
      return TurnBanner(text: l.yourTurnTapDice, color: color, emphasis: true, icon: Icons.touch_app_rounded);
    }
    return TurnBanner(text: l.playerTurnName(_name(cur)), color: color);
  }

  String get _status {
    if (_isOver) return context.l10n.gameOver;
    if (_game.pending != null) return context.l10n.playerMoving(_name(_game.current));
    if (_rolling) return context.l10n.rolling;
    if (_canPick) return context.l10n.pickToken;
    if (_myTurn) return context.l10n.yourTurnRoll;
    return context.l10n.playerPlaying(_name(_game.current));
  }


  String _tokensText(LudoColor c) {
    final list = _game.tokens[c]!;
    final home = _game.homeCount(c);
    final out = list.where((p) => p != LudoRules.base && p != LudoRules.home).length;
    return context.l10n.tokensHomeOut(home, out);
  }

  @override
  Widget build(BuildContext context) {
    final live = !_isOver;
    final rivals = _game.colors.where((c) => c != _me).toList();
    return guardBack(
      AuraScaffold(
      // Slimmer side margins so the board can be as large as possible.
      padding: const EdgeInsets.symmetric(horizontal: 12),
      body: DiceBoardLayout(
        header: LocalGameHeader(
          title: '🎲 Ludo',
          subtitle: context.l10n.moveAndPlayers(_game.moveCount, widget.players),
          live: live,
          onPause: openPause,
          perspective: _perspective,
          onTogglePerspective: () => setState(() => _perspective = !_perspective),
        ),
        opponents: [for (final c in rivals) _seatView(c)],
        you: _seatView(_me),
        lastMove: _game.lastText,
        clockText: _clock.text,
        clockUrgent: _clock.urgent,
        dice: DiceView(
          value: _game.lastRoll,
          rollId: _game.rollId,
          size: 38,
          enabled: _canRoll,
          onTap: _roll,
          onRolled: _onRolled,
          glow: ludoColor(_game.current),
          resultColor: _roller == null ? null : ludoColor(_roller!),
          prompt: context.l10n.diceTap,
        ),
        board: LudoBoardView(
          game: _game,
          bottomLeft: _me,
          perspective: _perspective,
          canPick: _canPick,
          onPick: _pick,
          onMoveAnimated: _onMoveAnimated,
          // Whose turn / what was rolled, on the board's top edge.
          banner: _banner(),
          // The board glows in the current player's colour (breathing on yours).
          turnColor: _isOver ? null : ludoColor(_game.current),
          yourTurn: _myTurn,
        ),
        actionBar: BoardActionBar(statusLabel: _status, active: _canRoll || _canPick, onResign: live ? forfeit : null),
      ),
    ),
    );
  }
}
