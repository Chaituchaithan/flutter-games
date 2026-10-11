import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../screens/match/match_result_screen.dart';
import '../../widgets/aura.dart';
import '../common/board_game_setup.dart';
import '../common/dice_game_kit.dart';
import '../common/local_game_flow.dart';
import '../common/turn_timer.dart';
import 'othello_board_view.dart';
import 'othello_engine.dart';

/// Quick Play setup → [OthelloScreen].
class OthelloSetupScreen extends StatelessWidget {
  const OthelloSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => BoardGameSetupScreen(
    title: 'Othello',
    blurb: context.l10n.othelloBlurb,
    sides: [
      SetupSide(
        label: context.l10n.black,
        icon: const OthelloDisc(disc: Disc.black, size: 28),
      ),
      SetupSide(
        label: context.l10n.white,
        icon: const OthelloDisc(disc: Disc.white, size: 28),
      ),
    ],
    start: (side, difficulty, clockMs) =>
        OthelloScreen(you: side == null ? null : Disc.values[side], difficulty: difficulty, clockMs: clockMs),
  );
}

/// Othello vs the computer, in the chess game-area layout: opponent card +
/// last move · the board (2D / 3D) · turn clock + your card · action bar.
/// Running out of time on a move loses, as in chess.
class OthelloScreen extends StatefulWidget {
  const OthelloScreen({super.key, this.you = Disc.black, this.difficulty = 2, this.clockMs = 30 * 1000});

  /// Your colour (null = random). Black moves first.
  final Disc? you;

  /// 1 easy · 2 medium · 3 hard.
  final int difficulty;
  final int? clockMs;

  @override
  State<OthelloScreen> createState() => _OthelloScreenState();
}

class _OthelloScreenState extends State<OthelloScreen> with LocalGameFlow {
  final _rng = math.Random();
  late final Disc _you = widget.you ?? (_rng.nextBool() ? Disc.black : Disc.white);
  Disc get _bot => _you.other;
  final OthelloGame _game = OthelloGame();

  late final TurnTimer _clock = TurnTimer(limitMs: widget.clockMs, onExpire: _onTimeUp)..addListener(_onChange);
  int _clockMove = -1;
  Disc? _timedOut;
  bool _thinking = false;
  int _botGen = 0;
  bool _perspective = false;

  int get _depth => switch (widget.difficulty) {
    <= 1 => 1,
    2 => 2,
    _ => 4,
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

  /// A fresh move clock for every move.
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

  void _tap(int sq) {
    if (!_myTurn || paused || _thinking) return;
    if (_game.state.flipsFor(sq, _you).isEmpty) return;
    _play(sq);
  }

  void _play(int sq) {
    final who = _game.state.turn;
    _game.play(sq);
    final passed = _game.passed;
    if (passed != null && mounted) {
      showAuraToast(context, context.l10n.mustPass(_name(passed)), kind: AuraToastKind.info);
    }
    if (_game.state.isOver) {
      _finish();
    } else if (who == _you || _game.state.turn == _bot) {
      _maybeBot();
    }
  }

  String _name(Disc d) => d == _you ? context.l10n.you : context.l10n.computer;

  /// The computer's move: searched off the UI thread, landing after a
  /// "thinking" beat that grows with difficulty.
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
    final think = minMs + _rng.nextInt(spread) + OthelloBoardView.animMs;
    compute(_searchOthello, (_game.state, _depth)).then((m) {
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
    final you = _game.state.count(_you), them = _game.state.count(_bot);
    final MatchOutcome outcome;
    final String subtitle;
    if (resigned) {
      outcome = MatchOutcome.defeat;
      subtitle = l.youForfeitedMatch;
    } else if (_timedOut != null) {
      final mine = _timedOut == _you;
      outcome = mine ? MatchOutcome.defeat : MatchOutcome.victory;
      subtitle = mine ? l.youRanOutOfTime : l.computerRanOutOfTime;
    } else if (you == them) {
      outcome = MatchOutcome.draw;
      subtitle = l.othelloDrawSub(you, them);
    } else if (you > them) {
      outcome = MatchOutcome.victory;
      subtitle = l.othelloWinSub(you, them);
    } else {
      outcome = MatchOutcome.defeat;
      subtitle = l.othelloLoseSub(you, them);
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchResultScreen(
          outcome: outcome,
          subtitle: subtitle,
          youScore: you,
          oppScore: them,
          youInitials: 'YOU',
          oppName: l.computer,
          oppInitials: 'AI',
          reward: switch (outcome) {
            MatchOutcome.victory => '+50 XP',
            MatchOutcome.draw => '+30 XP',
            MatchOutcome.defeat => '+20 XP',
          },
          playAgain: (_) => OthelloScreen(you: widget.you, difficulty: widget.difficulty, clockMs: widget.clockMs),
        ),
      ),
    );
  }

  int get _secs => (_clock.remainingMs / 1000).ceil();

  DiceSeatView _seat(Disc d) {
    final active = !_isOver && _game.state.turn == d;
    final l = context.l10n;
    String? turn;
    if (active) {
      turn = d == _you
          ? (_clock.unlimited ? l.yourMove : l.yourMoveSecs(_secs))
          : (_clock.unlimited ? l.thinking : l.thinkingSecs(_secs));
    }
    final player = d == _you
        ? DicePlayer(name: l.you, initials: 'YOU', color: AuraColors.brandPurple, isYou: true)
        : DicePlayer(name: l.computer, initials: 'AI', color: AuraColors.avatarBlue);
    return DiceSeatView(
      player: player,
      sub: '${d == Disc.black ? l.black : l.white} · ${l.discsCount(_game.state.count(d))}',
      active: active,
      turnText: turn,
      progress: active ? _clock.fraction : null,
    );
  }

  String get _lastMoveText {
    final m = _game.lastMove;
    if (m == null) return '—';
    final mover = _game.state.cells[m];
    if (mover == null) return '—';
    return context.l10n.othelloPlayed(_name(mover), othelloSquareName(m), _game.lastFlips.length);
  }

  String get _status {
    final l = context.l10n;
    if (_isOver) return l.gameOver;
    return _myTurn ? l.yourMove : l.computerThinking;
  }

  @override
  Widget build(BuildContext context) {
    final live = !_isOver;
    return AuraScaffold(
      body: DiceBoardLayout(
        header: LocalGameHeader(
          title: '⚫ Othello',
          subtitle: context.l10n.moveAndPlayers(_game.moveCount + 1, 2),
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
        board: OthelloBoardView(
          game: _game,
          onTap: _tap,
          showHints: _myTurn && !_thinking && !paused,
          perspective: _perspective,
        ),
        actionBar: BoardActionBar(statusLabel: _status, active: _myTurn, onResign: live ? forfeit : null),
      ),
    );
  }
}

/// Bot search entry point for [compute] (top-level, background isolate).
int? _searchOthello((OthelloState, int) args) => OthelloBot(depth: args.$2).chooseMove(args.$1);
