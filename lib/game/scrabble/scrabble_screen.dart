import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:snakeladder/services/session.dart';
import '../../l10n/l10n.dart';
import '../../screens/match/match_result_screen.dart';
import '../../screens/system/loading_skeleton_screen.dart' show Shimmer, SkeletonBox;
import '../../widgets/aura.dart';
import '../common/board_game_setup.dart';
import '../common/local_game_flow.dart';
import '../common/turn_timer.dart';
import 'scrabble_board_view.dart';
import 'scrabble_engine.dart';
import 'scrabble_words.g.dart';

/// Scrabble turns need more time than a chess move.
const scrabbleTimeOptions = <({String label, int? ms})>[
  (label: '1 min', ms: 60 * 1000),
  (label: '2 min', ms: 2 * 60 * 1000),
  (label: '5 min', ms: 5 * 60 * 1000),
  (label: 'Unlimited', ms: null),
];

/// Quick Play setup → [ScrabbleScreen].
class ScrabbleSetupScreen extends StatelessWidget {
  const ScrabbleSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => BoardGameSetupScreen(
    title: 'Scrabble',
    blurb: context.l10n.scrabbleBlurb,
    timeOptions: scrabbleTimeOptions,
    defaultClockMs: 2 * 60 * 1000,
    timeRule: context.l10n.scrabbleTimeRule,
    start: (_, difficulty, clockMs) => ScrabbleScreen(difficulty: difficulty, clockMs: clockMs),
  );
}

/// The word list, built once per app run. It's compiled into Scrabble's code
/// (scrabble_words.g.dart) rather than bundled as an asset, so apps without
/// Scrabble don't carry it.
Future<Lexicon>? _lexicon;
Future<Lexicon> loadLexicon() => _lexicon ??= Future.microtask(
  () => Lexicon([
    for (final w in scrabbleWordList.split('\n'))
      if (w.length >= 2) w,
  ]),
);

/// Scrabble vs the computer: the board, your rack, Shuffle / Recall · Swap ·
/// Pass · Play (with a live score preview), a per-turn clock (time up =
/// pass), the computer playing by difficulty, and the shared result screen.
class ScrabbleScreen extends StatefulWidget {
  const ScrabbleScreen({super.key, this.difficulty = 2, this.clockMs = 2 * 60 * 1000});

  /// 1 easy · 2 medium · 3 hard.
  final int difficulty;
  final int? clockMs;

  @override
  State<ScrabbleScreen> createState() => _ScrabbleScreenState();
}

class _ScrabbleScreenState extends State<ScrabbleScreen> with LocalGameFlow {
  final _rng = math.Random();
  late final ScrabbleGame _game = ScrabbleGame(rng: _rng)..addListener(_onChange);
  Lexicon? _lex;

  /// Your rack in display order (placed tiles are removed until committed).
  List<Tile> _hand = [];
  final Map<int, Tile> _pending = {};
  int? _selected;

  late final TurnTimer _clock = TurnTimer(limitMs: widget.clockMs, onExpire: _onTimeUp)..addListener(_onChange);
  int _clockTurn = -1;
  bool _thinking = false;
  int _botGen = 0;
  bool _perspective = false;

  @override
  void initState() {
    super.initState();
    loadLexicon().then((lex) {
      if (!mounted) return;
      setState(() {
        _lex = lex;
        _hand = List.of(_game.racks[0]);
      });
      _syncClock();
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

  bool get _isOver => _game.over || resigned;
  bool get _myTurn => !_isOver && _game.turn == 0 && _lex != null;
  bool get _canAct => _myTurn && !paused && !_thinking;

  void _syncClock() {
    if (_lex == null) return;
    if (_isOver) {
      if (_clock.running) _clock.stop();
      return;
    }
    if (_clockTurn == _game.log.length) return;
    _clockTurn = _game.log.length;
    _clock.start();
    if (paused) _clock.pause();
  }

  /// Your time ran out: take back the tiles and pass.
  void _onTimeUp() {
    if (!mounted || _isOver || _game.turn != 0) return;
    _recall();
    showAuraToast(context, context.l10n.timeUpPassed, kind: AuraToastKind.info);
    _afterTurn(() => _game.pass());
  }

  // ── Placing tiles ──

  void _tapRack(int i) {
    if (!_canAct) return;
    setState(() => _selected = _selected == i ? null : i);
  }

  Future<void> _tapSquare(int sq) async {
    if (!_canAct) return;
    final mine = _pending[sq];
    if (mine != null) {
      // Take a tile back to the rack.
      setState(() {
        _pending.remove(sq);
        _hand.add(mine.cleared);
      });
      return;
    }
    final i = _selected;
    if (i == null || i >= _hand.length || _game.board[sq] != null) return;
    var tile = _hand[i];
    if (tile.blank) {
      final letter = await _pickLetter();
      if (letter == null || !mounted) return;
      tile = tile.withLetter(letter);
    }
    setState(() {
      _pending[sq] = tile;
      _hand.removeAt(i);
      _selected = _hand.isEmpty ? null : math.min(i, _hand.length - 1);
    });
  }

  Future<String?> _pickLetter() => showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF15102A),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ctx.l10n.pickLetter, style: AuraText.cardTitle),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (var k = 0; k < 26; k++)
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, String.fromCharCode(65 + k)),
                    child: ScrabbleTileView(tile: Tile(String.fromCharCode(65 + k)), size: 40),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  void _recall() {
    setState(() {
      _hand.addAll(_pending.values.map((t) => t.blank ? t.cleared : t));
      _pending.clear();
      _selected = null;
    });
  }

  void _shuffle() => setState(() {
    _hand.shuffle(_rng);
    _selected = null;
  });

  // ── Turn actions ──

  (ScrabblePlay?, PlayError?, String?) get _preview =>
      _lex == null ? (null, PlayError.empty, null) : evaluatePlay(_game.board, _pending, _lex!);

  void _submit() {
    final (play, _, _) = _preview;
    if (!_canAct || play == null) return;
    _pending.clear();
    _selected = null;
    _afterTurn(() => _game.play(play));
  }

  Future<void> _swap() async {
    if (!_canAct) return;
    if (!_game.canExchange) {
      showAuraToast(context, context.l10n.bagTooSmall, kind: AuraToastKind.info);
      return;
    }
    _recall();
    final chosen = await showModalBottomSheet<List<Tile>>(
      context: context,
      backgroundColor: const Color(0xFF15102A),
      builder: (_) => _SwapSheet(hand: List.of(_hand)),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;
    _afterTurn(() => _game.exchange(chosen));
  }

  Future<void> _pass() async {
    if (!_canAct) return;
    final ok = await showAuraDialog(
      context,
      icon: Icons.skip_next_rounded,
      title: context.l10n.passConfirmTitle,
      body: context.l10n.passConfirmBody,
      primaryLabel: context.l10n.pass,
      secondaryLabel: context.l10n.cancel,
    );
    if (ok != true || !mounted) return;
    _recall();
    _afterTurn(() => _game.pass());
  }

  /// Run your turn's action, refresh your rack, then the computer's turn.
  void _afterTurn(VoidCallback action) {
    action();
    setState(() => _hand = List.of(_game.racks[0]));
    if (_game.over) {
      _finish();
    } else {
      _maybeBot();
    }
  }

  void _maybeBot() {
    final lex = _lex;
    if (lex == null || _isOver || paused || _thinking || _game.turn != 1) return;
    setState(() => _thinking = true);
    final gen = ++_botGen;
    final started = DateTime.now();
    final (minMs, spread) = switch (widget.difficulty) {
      <= 1 => (1200, 800),
      2 => (1600, 1000),
      _ => (2000, 1200),
    };
    final think = minMs + _rng.nextInt(spread);
    compute(_scrabbleBot, (
      List<Tile?>.of(_game.board),
      List<Tile>.of(_game.racks[1]),
      lex.words,
      widget.difficulty,
      _rng.nextInt(1 << 30),
    )).then((play) {
      if (!mounted || gen != _botGen) return;
      final wait = think - DateTime.now().difference(started).inMilliseconds;
      scheduleBot(Duration(milliseconds: wait.clamp(0, think)), () {
        _thinking = false;
        if (_game.turn != 1 || _isOver) return;
        if (play != null) {
          _game.play(play);
        } else if (_game.canExchange) {
          // Swap the least useful tiles (the highest-value ones).
          final rack = List.of(_game.racks[1])..sort((a, b) => b.value.compareTo(a.value));
          _game.exchange(rack.take(math.min(4, rack.length)).toList());
        } else {
          _game.pass();
        }
        setState(() => _hand = _merge(_hand, _game.racks[0]));
        if (_game.over) _finish();
      }, stillValid: () => gen == _botGen);
    });
  }

  /// Keep your tile order across turns (your rack only changes on your turn).
  static List<Tile> _merge(List<Tile> order, List<Tile> rack) => rack.length == order.length ? order : List.of(rack);

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
  String get pauseSubtitle => context.l10n.moveOnHold(_game.log.length + 1);

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
    final you = _game.scores[0], them = _game.scores[1];
    final MatchOutcome outcome;
    final String subtitle;
    if (resigned) {
      outcome = MatchOutcome.defeat;
      subtitle = l.youForfeitedMatch;
    } else if (you == them) {
      outcome = MatchOutcome.draw;
      subtitle = l.scrabbleDrawSub(you, them);
    } else if (you > them) {
      outcome = MatchOutcome.victory;
      subtitle = l.scrabbleWinSub(you, them);
    } else {
      outcome = MatchOutcome.defeat;
      subtitle = l.scrabbleLoseSub(you, them);
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchResultScreen(
          outcome: outcome,
          subtitle: subtitle,
          youScore: you,
          oppScore: them,
          oppName: l.computer,
          oppInitials: 'AI',
          // Quick Play vs the computer: nothing to earn.
          practice: true,
          playAgain: (_) => ScrabbleScreen(difficulty: widget.difficulty, clockMs: widget.clockMs),
        ),
      ),
    );
  }

  // ── UI ──

  int get _secs => (_clock.remainingMs / 1000).ceil();

  String _who(int p) => p == 0 ? context.l10n.you : context.l10n.computer;

  String get _lastText {
    final t = _game.lastTurn;
    final l = context.l10n;
    if (t == null) return '—';
    return switch (t.kind) {
      ScrabbleTurnKind.play => l.scrabblePlayed(_who(t.player), t.play!.mainWord, t.score),
      ScrabbleTurnKind.exchange => l.scrabbleExchanged(_who(t.player), t.count),
      ScrabbleTurnKind.pass => l.scrabblePassed(_who(t.player)),
    };
  }

  String _errorText(PlayError e, String? word) {
    final l = context.l10n;
    return switch (e) {
      PlayError.empty => l.errPlaceTiles,
      PlayError.notInLine => l.errInLine,
      PlayError.gap => l.errGap,
      PlayError.notConnected => l.errConnect,
      PlayError.firstMoveCenter => l.errCenter,
      PlayError.tooShort => l.errTooShort,
      PlayError.notAWord => l.errNotWord(word ?? ''),
    };
  }

  Widget _card(int p) {
    final l = context.l10n;
    final active = !_isOver && _game.turn == p;
    return BoardPlayerCard(
      name: _who(p),
      initials: p == 0 ? ProviderScope.containerOf(context).read(currentUserProvider).initials : 'AI',
      sub: l.scoreN(_game.scores[p]),
      color: p == 0 ? AuraColors.brandPurple : AuraColors.avatarBlue,
      color2: p == 0 ? AuraColors.brandPink : const Color(0xFF3B82F6),
      active: active,
      turnText: !active
          ? null
          : p == 0
          ? (_clock.unlimited ? l.yourMove : l.yourMoveSecs(_secs))
          : (_clock.unlimited ? l.thinking : l.thinkingSecs(_secs)),
      progress: active ? _clock.fraction : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final live = !_isOver;
    final lastPlay = _game.lastTurn?.play?.tiles.keys.toSet() ?? const <int>{};
    final (play, err, badWord) = _preview;
    return guardBack(
      AuraScaffold(
      // Slimmer side margins so the board can be as large as possible.
      padding: const EdgeInsets.symmetric(horizontal: 12),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocalGameHeader(
            title: '🔤 Scrabble',
            subtitle: '${l.bagN(_game.bag.length)} · ${l.moveAndPlayers(_game.log.length + 1, 2)}',
            live: live,
            onPause: openPause,
            perspective: _perspective,
            onTogglePerspective: () => setState(() => _perspective = !_perspective),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _card(1)),
                const SizedBox(width: 10),
                Expanded(
                  child: BoardInfoPanel(label: l.lastMove, value: _lastText),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _lex == null
                ? _LoadingBoard(label: l.loadingDictionary)
                : ScrabbleBoardView(
                    board: _game.board,
                    pending: _pending,
                    lastPlay: lastPlay,
                    onTapSquare: _tapSquare,
                    perspective: _perspective,
                  ),
          ),
          const SizedBox(height: 10),
          _Rack(hand: _hand, selected: _selected, enabled: _canAct, onTap: _tapRack),
          const SizedBox(height: 8),
          // Controls: shuffle/recall · swap · pass · play (live score / reason).
          Row(
            children: [
              _ControlButton(
                icon: _pending.isEmpty ? Icons.shuffle_rounded : Icons.undo_rounded,
                label: _pending.isEmpty ? l.shuffle : l.recall,
                onTap: _canAct ? (_pending.isEmpty ? _shuffle : _recall) : null,
              ),
              const SizedBox(width: 8),
              _ControlButton(icon: Icons.swap_horiz_rounded, label: l.swap, onTap: _canAct ? _swap : null),
              const SizedBox(width: 8),
              _ControlButton(icon: Icons.skip_next_rounded, label: l.pass, onTap: _canAct ? _pass : null),
              const SizedBox(width: 8),
              Expanded(
                child: GradientButton(
                  label: play != null ? l.playScore(play.score) : l.play,
                  enabled: _canAct && play != null,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 18,
            child: Center(
              child: Text(
                !_myTurn
                    ? (_isOver ? l.gameOver : l.computerThinking)
                    : (_pending.isNotEmpty && err != null ? _errorText(err, badWord) : l.yourMove),
                style: AuraText.cardSub.copyWith(
                  fontSize: 12,
                  color: _pending.isNotEmpty && err != null ? AuraColors.amber : AuraColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: BoardInfoPanel(label: l.turnClock, value: _clock.text, big: true, urgent: _clock.urgent),
                ),
                const SizedBox(width: 10),
                Expanded(child: _card(0)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
    );
  }
}

/// Your 7-tile rack; the selected tile lifts.
class _Rack extends StatelessWidget {
  const _Rack({required this.hand, required this.selected, required this.enabled, required this.onTap});
  final List<Tile> hand;
  final int? selected;
  final bool enabled;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(colors: [Color(0xFF6B3A22), Color(0xFF4A2716)]),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final size = math.min(44.0, (c.maxWidth - 6 * 6) / 7);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < hand.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => onTap(i),
                  child: Opacity(
                    opacity: enabled ? 1 : 0.7,
                    child: ScrabbleTileView(tile: hand[i], size: size, lifted: selected == i),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: on ? 1 : 0.45,
        child: Container(
          width: 56,
          height: 52,
          decoration: AuraGlass.decoration(radius: 14, shadow: false),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, style: const TextStyle(color: Colors.white70, fontSize: 9.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pick tiles to swap.
class _SwapSheet extends StatefulWidget {
  const _SwapSheet({required this.hand});
  final List<Tile> hand;

  @override
  State<_SwapSheet> createState() => _SwapSheetState();
}

class _SwapSheetState extends State<_SwapSheet> {
  final Set<int> _picked = {};

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.swapTitle, style: AuraText.cardTitle),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < widget.hand.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _picked.contains(i) ? _picked.remove(i) : _picked.add(i)),
                    child: ScrabbleTileView(tile: widget.hand[i], size: 42, lifted: _picked.contains(i)),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            GradientButton(
              label: l.swapN(_picked.length),
              enabled: _picked.isNotEmpty,
              onPressed: () => Navigator.pop(context, [for (final i in _picked) widget.hand[i]]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder while the word list loads.
class _LoadingBoard extends StatelessWidget {
  const _LoadingBoard({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Expanded(
        child: Shimmer(child: AspectRatio(aspectRatio: 1, child: SkeletonBox(radius: 22))),
      ),
      const SizedBox(height: 10),
      Text(label, style: AuraText.cardSub),
    ],
  );
}

/// The computer's move search for [compute] (background isolate).
ScrabblePlay? _scrabbleBot((List<Tile?>, List<Tile>, List<String>, int, int) a) =>
    chooseScrabblePlay(a.$1, a.$2, Lexicon(a.$3), a.$4, a.$5);
