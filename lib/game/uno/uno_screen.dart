import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../configs/games/uno/uno_config.dart';
import '../../l10n/l10n.dart';
import '../../screens/match/match_result_screen.dart';
import '../../widgets/aura.dart';
import '../common/dice_game_kit.dart' show SetupTile;
import '../common/local_game_flow.dart';
import '../common/turn_timer.dart';
import 'uno_card_view.dart';
import 'uno_engine.dart';

const _botNames = [('Nova', 'NV'), ('Rex', 'RX'), ('Mia', 'MI')];
const _botColors = [Color(0xFF22D3EE), Color(0xFFF97316), Color(0xFF22C55E)];

/// Quick Play setup → [UnoScreen]: players, difficulty, time per turn.
class UnoSetupScreen extends StatefulWidget {
  const UnoSetupScreen({super.key});

  @override
  State<UnoSetupScreen> createState() => _UnoSetupScreenState();
}

class _UnoSetupScreenState extends State<UnoSetupScreen> {
  int _players = 4;
  int _difficulty = 2;
  int? _clockMs = 30 * 1000;

  Widget _label(String t) => Text(
    t,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
    style: TextStyle(
      fontFamily: AuraText.displayFamily,
      color: Colors.white,
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _row<T>(List<(T, String)> options, T value, ValueChanged<T> onPick) => Row(
    children: [
      for (var i = 0; i < options.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: SetupTile(
            selected: options[i].$1 == value,
            onTap: () => setState(() => onPick(options[i].$1)),
            child: Center(child: _label(options[i].$2)),
          ),
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AuraScaffold(
      appBar: AuraAppBar(title: l.quickPlay),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(unoConfig.displayName, style: AuraText.headline.copyWith(fontSize: 24)),
          const SizedBox(height: 6),
          Text(l.unoBlurb, style: AuraText.cardSub),
          const SizedBox(height: 18),
          // A taste of the deck.
          SizedBox(
            height: 78,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final (i, c) in const [
                  UnoCard(-1, UnoKind.number, color: UnoColor.red, number: 7),
                  UnoCard(-2, UnoKind.skip, color: UnoColor.blue),
                  UnoCard(-3, UnoKind.wild),
                  UnoCard(-4, UnoKind.reverse, color: UnoColor.green),
                  UnoCard(-5, UnoKind.drawTwo, color: UnoColor.yellow),
                ].indexed)
                  Transform.translate(
                    offset: Offset(0, (i - 2).abs() * 5.0),
                    child: Transform.rotate(
                      angle: (i - 2) * 0.16,
                      child: UnoCardView(card: c, width: 48),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionBar(l.players),
          const SizedBox(height: 10),
          _row(
            [
              for (final n in const [2, 3, 4]) (n, l.youPlusAi(n - 1)),
            ],
            _players,
            (v) => _players = v,
          ),
          const SizedBox(height: 22),
          SectionBar(l.difficulty),
          const SizedBox(height: 10),
          _row([(1, l.easy), (2, l.medium), (3, l.hard)], _difficulty, (v) => _difficulty = v),
          const SizedBox(height: 22),
          SectionBar(l.timePerMove),
          const SizedBox(height: 10),
          _row(
            [(15 * 1000, l.timeSec(15)), (30 * 1000, l.timeSec(30)), (null, l.unlimited)],
            _clockMs,
            (v) => _clockMs = v,
          ),
          const SizedBox(height: 28),
          GradientButton(
            label: l.startGame,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => UnoScreen(players: _players, difficulty: _difficulty, clockMs: _clockMs),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// One round vs the computer: opponents on top, the draw pile and the
/// discard pile (ringed in the colour in play) in the middle, your hand
/// fanned at the bottom — playable cards lifted, the rest dimmed.
class UnoScreen extends StatefulWidget {
  const UnoScreen({
    super.key,
    this.players = 4,
    this.difficulty = 2,
    this.clockMs = 30 * 1000,
    @visibleForTesting this.seed,
  });

  final int players;
  final int difficulty;
  final int? clockMs;
  final int? seed;

  @override
  State<UnoScreen> createState() => _UnoScreenState();
}

/// A card moving across the table (dealt, drawn or played).
class _Flight {
  _Flight({required this.from, required this.to, this.card, this.delayMs = 0, this.onLand}) : id = _next++;
  static int _next = 0;
  final int id;
  final Offset from, to;

  /// Face-up card (a play); null = a card back (a deal / draw).
  final UnoCard? card;
  final int delayMs;
  final VoidCallback? onLand;
}

class _UnoScreenState extends State<UnoScreen> with LocalGameFlow, SingleTickerProviderStateMixin {
  late final math.Random _rng = widget.seed == null ? math.Random() : math.Random(widget.seed);
  late final UnoGame _game = UnoGame(players: widget.players, rng: _rng);
  late final TurnTimer _timer = TurnTimer(limitMs: widget.clockMs, onExpire: _timeout);
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 9))
    ..repeat();

  /// You tapped UNO! for your next play.
  bool _unoArmed = false;

  /// Who said "UNO!" last (shown on their seat for a moment).
  int? _shout;
  Timer? _shoutTimer;

  /// The table message for the last action.
  String? _event;

  /// Cards in the air, and played cards not yet landed on the pile.
  final List<_Flight> _flights = [];
  final Set<int> _inAir = {};

  /// The opening deal: cards each seat has received so far (null = done).
  List<int>? _dealt;
  Timer? _dealTimer;
  Size _table = const Size(360, 480);

  @override
  void initState() {
    super.initState();
    _game.addListener(_onChange);
    _timer.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _deal());
  }

  @override
  void dispose() {
    disposeFlow();
    _shoutTimer?.cancel();
    _dealTimer?.cancel();
    _spin.dispose();
    _timer.dispose();
    _game.removeListener(_onChange);
    _game.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  // ── Table geometry (in the table's box) ──

  Offset get _drawPos => Offset(_table.width / 2 - 50, _table.height * 0.56);
  Offset get _discardPos => Offset(_table.width / 2 + 50, _table.height * 0.56);

  /// Where a seat's cards are (yours = into your hand, below the table).
  Offset _seatPos(int seat) {
    final w = _table.width, h = _table.height;
    if (seat == 0) return Offset(w / 2, h + 60);
    final spots = switch (_game.players) {
      2 => const [(0.5, 0.12)],
      3 => const [(0.2, 0.15), (0.8, 0.15)],
      _ => const [(0.13, 0.38), (0.5, 0.12), (0.87, 0.38)],
    };
    final (x, y) = spots[seat - 1];
    return Offset((w * x).clamp(50, w - 50), h * y);
  }

  void _fly(_Flight f) => setState(() => _flights.add(f));

  void _landed(_Flight f) {
    if (!mounted) return;
    setState(() {
      _flights.remove(f);
      if (f.card != null) _inAir.remove(f.card!.id);
    });
    f.onLand?.call();
  }

  /// Deal 7 each, one at a time round the table, then turn up the first card.
  void _deal() {
    if (!mounted) return;
    final n = _game.players;
    _dealt = List.filled(n, 0);
    var k = 0;
    _inAir.add(_game.top.id);
    _dealTimer = Timer.periodic(const Duration(milliseconds: 70), (t) {
      if (!mounted) return t.cancel();
      if (k >= UnoRules.handSize * n) {
        t.cancel();
        _fly(
          _Flight(
            from: _drawPos,
            to: _discardPos,
            card: _game.top,
            delayMs: 250,
            onLand: () {
              setState(() => _dealt = null);
              _advance();
            },
          ),
        );
        return;
      }
      // Dealer gives the player after you first, you last in each round.
      final seat = (k + 1) % n;
      k++;
      _fly(
        _Flight(
          from: _drawPos,
          to: _seatPos(seat),
          onLand: () {
            if (_dealt != null) setState(() => _dealt![seat]++);
          },
        ),
      );
    });
  }

  /// Cards move for what just happened: plays to the pile, draws to hands.
  void _animate() {
    var delay = 0;
    for (final e in _game.events) {
      switch (e) {
        case UnoPlayed(:final card):
          _inAir.add(card.id);
          _fly(_Flight(from: _seatPos(e.seat), to: _discardPos, card: card));
          delay = 260;
        case UnoDrew(:final count):
          for (var i = 0; i < count; i++) {
            _fly(_Flight(from: _drawPos, to: _seatPos(e.seat), delayMs: delay + i * 110));
          }
        case UnoCaught():
          for (var i = 0; i < UnoRules.unoPenalty; i++) {
            _fly(_Flight(from: _drawPos, to: _seatPos(e.seat), delayMs: delay + i * 110));
          }
        case UnoPassed() || UnoSkipped():
          break;
      }
    }
  }

  String _name(int seat) => seat == 0 ? context.l10n.you : _botNames[seat - 1].$1;

  String _colorName(UnoColor c) {
    final l = context.l10n;
    return switch (c) {
      UnoColor.red => l.unoRed,
      UnoColor.yellow => l.unoYellow,
      UnoColor.green => l.unoGreen,
      UnoColor.blue => l.unoBlue,
    };
  }

  String _cardName(UnoCard c) {
    final l = context.l10n;
    final label = switch (c.kind) {
      UnoKind.number => '${c.number}',
      UnoKind.skip => l.unoSkip,
      UnoKind.reverse => l.unoReverse,
      UnoKind.drawTwo => '+2',
      UnoKind.wild => l.unoWild,
      UnoKind.wildDrawFour => l.unoWildFour,
    };
    return c.color == null ? label : '${_colorName(c.color!)} $label';
  }

  /// The last action as one line ("Nova played Blue +2 · +2 for You").
  void _describe() {
    final l = context.l10n;
    final parts = <String>[];
    for (final e in _game.events) {
      final n = _name(e.seat);
      switch (e) {
        case UnoPlayed(:final card, :final chosen, :final saidUno):
          parts.add(
            chosen == null ? l.unoPlayed(n, _cardName(card)) : l.unoPlayedWild(n, _cardName(card), _colorName(chosen)),
          );
          if (saidUno) {
            parts.add(l.unoSaid(n));
            _shoutFor(e.seat);
          }
        case UnoDrew(:final count, :final forced):
          parts.add(forced ? l.unoForcedDraw(count, n) : l.unoDrewOne(n));
        case UnoPassed():
          parts.add(l.unoKept(n));
        case UnoCaught():
          parts.add(l.unoCaughtName(n));
        case UnoSkipped():
          parts.add(l.unoTurnSkipped(n));
      }
    }
    _event = parts.join(' · ');
    _animate();
  }

  void _shoutFor(int seat) {
    _shoutTimer?.cancel();
    _shout = seat;
    _shoutTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _shout = null);
    });
  }

  bool get _myTurn => _dealt == null && !_game.isOver && !resigned && _game.turn == 0;

  /// Next turn: your clock, or a computer.
  void _advance() {
    if (!mounted || paused || resigned) return;
    if (_game.isOver) {
      _timer.stop();
      endGame(delay: const Duration(milliseconds: 1500));
      return;
    }
    if (_game.turn == 0) {
      if (_game.drawn == null) {
        _timer.start();
        HapticFeedback.selectionClick();
      }
      return;
    }
    _timer.stop();
    _unoArmed = false;
    final seat = _game.turn;
    final think = 850 + _rng.nextInt(widget.difficulty >= 3 ? 900 : 650);
    scheduleBot(
      Duration(milliseconds: _game.drawn != null ? 650 : think),
      () => _botStep(seat),
      stillValid: () => _game.turn == seat,
    );
  }

  void _botStep(int seat) {
    final m = unoBotMove(_game, widget.difficulty, _rng);
    if (m.card != null) {
      _game.play(m.card!, chosen: m.color, saidUno: m.sayUno);
    } else if (_game.drawn == null) {
      _game.draw();
    } else {
      _game.pass();
    }
    _describe();
    _advance();
  }

  Future<void> _play(UnoCard c) async {
    if (!_myTurn || paused || !_game.playable().contains(c)) return;
    UnoColor? chosen;
    if (c.isWild) {
      chosen = await _pickColor();
      if (chosen == null || !mounted || !_myTurn) return;
    }
    _timer.stop();
    HapticFeedback.lightImpact();
    _game.play(c, chosen: chosen, saidUno: _unoArmed);
    _unoArmed = false;
    _describe();
    _advance();
  }

  void _drawOrKeep() {
    if (!_myTurn || paused) return;
    if (_game.drawn != null) {
      _timer.stop();
      _game.pass();
    } else {
      _game.draw();
      // Drew something playable: the clock keeps running for that choice.
      if (_game.drawn == null) _timer.stop();
    }
    _describe();
    _advance();
  }

  /// Out of time: draw (and keep it).
  void _timeout() {
    if (!_myTurn) return;
    showAuraToast(context, context.l10n.timeUpPlayed, kind: AuraToastKind.info);
    if (_game.drawn == null) _game.draw();
    if (_game.turn == 0 && _game.drawn != null) _game.pass();
    _timer.stop();
    _describe();
    _advance();
  }

  Future<UnoColor?> _pickColor() => showGeneralDialog<UnoColor>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'colour',
    barrierColor: Colors.black54,
    pageBuilder: (ctx, _, _) => Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: 280,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          decoration: AuraGlass.decoration(radius: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ctx.l10n.unoChooseColor, style: AuraText.cardTitle.copyWith(fontSize: 17)),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final c in UnoColor.values)
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx, c),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: unoColors[c],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [BoxShadow(color: unoColors[c]!.withValues(alpha: 0.5), blurRadius: 12)],
                        ),
                        child: Text(
                          _colorName(c),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            shadows: [Shadow(color: Colors.black45, offset: Offset(1, 1))],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  String get pauseSubtitle => context.l10n.cardsCount(_game.hands[0].length);

  @override
  void pauseGame() {
    super.pauseGame();
    _timer.pause();
  }

  @override
  void onResumeGame() {
    if (_myTurn) {
      _timer.resume();
    } else {
      _advance();
    }
  }

  @override
  void showResult() {
    final l = context.l10n;
    final w = _game.winner;
    final won = !resigned && w == 0;
    final pts = w == null ? 0 : _game.winnerPoints;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchResultScreen(
          outcome: won ? MatchOutcome.victory : MatchOutcome.defeat,
          subtitle: resigned
              ? l.youForfeitedMatch
              : won
              ? l.unoWinSub(pts)
              : l.unoLoseSub(_name(w ?? 1), _game.hands[0].length),
          youScore: won ? pts : 0,
          oppScore: won ? 0 : pts,
          oppName: widget.players == 2 ? _botNames[0].$1 : l.bestAi,
          oppInitials: widget.players == 2 ? _botNames[0].$2 : 'AI',
          // Quick Play vs the computer: nothing to earn.
          practice: true,
          playAgain: (_) => UnoScreen(players: widget.players, difficulty: widget.difficulty, clockMs: widget.clockMs),
        ),
      ),
    );
  }

  String get _hint {
    final l = context.l10n;
    if (!_myTurn) return '';
    if (_game.drawn != null) return l.unoDrawnHint;
    if (_game.playable().isEmpty) return l.unoNoMatchHint;
    if (_game.hands[0].length == 2 && !_unoArmed) return l.unoUnoHint;
    return l.unoPlayHint;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final g = _game;
    final dealt = _dealt;
    final allMine = g.hands[0];
    final mine = dealt == null ? allMine : allMine.take(dealt[0]).toList();
    final playable = _myTurn ? g.playable().toSet() : const <UnoCard>{};
    final canUno = _myTurn && allMine.length == 2 && playable.isNotEmpty;
    final pile = [for (final c in g.discard) if (!_inAir.contains(c.id)) c];
    return guardBack(
      AuraScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LocalGameHeader(
            title: '${unoConfig.icon} ${unoConfig.displayName}',
            subtitle: l.unoSubtitle(g.direction > 0 ? l.unoClockwise : l.unoAnticlockwise, g.drawPileCount),
            live: !g.isOver && !resigned,
            onPause: openPause,
          ),
          const SizedBox(height: 6),
          // The table, seen from above: opponents round it, the piles in the middle.
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                _table = box.biggest;
                Widget at(Offset p, double w, double h, Widget child) =>
                    Positioned(left: p.dx - w / 2, top: p.dy - h / 2, width: w, height: h, child: child);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _spin,
                        builder: (_, _) => CustomPaint(
                          painter: _TablePainter(color: unoColors[g.color]!, direction: g.direction, turn: _spin.value),
                        ),
                      ),
                    ),
                    for (var s = 1; s < g.players; s++)
                      at(
                        _seatPos(s),
                        104,
                        126,
                        _Seat(
                          name: _botNames[s - 1].$1,
                          initials: _botNames[s - 1].$2,
                          color: _botColors[s - 1],
                          cards: dealt == null ? g.hands[s].length : dealt[s],
                          active: dealt == null && !g.isOver && g.turn == s,
                          shout: _shout == s,
                          spin: _spin,
                        ),
                      ),
                    at(
                      _drawPos,
                      84,
                      116,
                      _DrawPile(count: g.drawPileCount, glow: _myTurn && g.drawn == null, onTap: _drawOrKeep),
                    ),
                    at(_discardPos, 116, 136, _DiscardPile(cards: pile, color: g.color, live: dealt == null)),
                    Positioned(
                      left: 16,
                      right: 16,
                      top: _drawPos.dy + 72,
                      height: 34,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          _event ?? '',
                          key: ValueKey(_event),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AuraText.cardSub.copyWith(
                            fontSize: 12.5,
                            color: Colors.white,
                            shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                          ),
                        ),
                      ),
                    ),
                    if (_shout == 0) Positioned(bottom: 6, left: 0, right: 0, child: const Center(child: _UnoShout())),
                    for (final f in _flights) _FlyingCard(key: ValueKey(f.id), flight: f, onDone: () => _landed(f)),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 18,
            child: Center(
              child: Text(_hint, style: AuraText.cardSub.copyWith(fontSize: 12, color: AuraColors.amber)),
            ),
          ),
          // Your hand, fanned.
          SizedBox(
            height: 132,
            child: _Hand(cards: mine, playable: playable, myTurn: _myTurn, drawn: g.drawn, onTap: _play),
          ),
          SizedBox(
            height: 4,
            child: _myTurn && widget.clockMs != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: _timer.fraction ?? 1,
                      minHeight: 4,
                      color: _timer.urgent ? AuraColors.danger : AuraColors.accentGlow,
                      backgroundColor: Colors.white12,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _UnoButton(
                  label: l.unoCall,
                  armed: _unoArmed,
                  enabled: canUno,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    setState(() => _unoArmed = !_unoArmed);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GradientButton(
                  label: g.drawn != null && _myTurn ? l.unoKeep : l.unoDraw,
                  enabled: _myTurn && !paused,
                  onPressed: _drawOrKeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
    );
  }
}

/// The card table from above: wooden rim, baize, and a ring of arrows that
/// turns with the play direction in the colour in play.
class _TablePainter extends CustomPainter {
  _TablePainter({required this.color, required this.direction, required this.turn});
  final Color color;
  final int direction;
  final double turn;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(2);
    final outer = RRect.fromRectAndRadius(r, Radius.circular(size.width * 0.32));
    canvas.drawRRect(
      outer.shift(const Offset(0, 8)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    // Wooden rim.
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6E3A1B), Color(0xFF3A1A09), Color(0xFF5E2F14), Color(0xFF2E1406)],
        ).createShader(r),
    );
    canvas.drawRRect(
      outer.deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.14),
    );
    // Baize.
    final felt = outer.deflate(13);
    canvas.drawRRect(
      felt,
      Paint()
        ..shader = const RadialGradient(
          radius: 0.8,
          colors: [Color(0xFF14785D), Color(0xFF0C5743), Color(0xFF063427)],
        ).createShader(felt.outerRect),
    );
    canvas.save();
    canvas.clipRRect(felt);
    final rng = math.Random(11);
    final dots = [for (var i = 0; i < 900; i++) Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height)];
    canvas.drawPoints(
      PointMode.points,
      dots,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..strokeWidth = 1.3,
    );
    canvas.drawRRect(
      felt,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.restore();
    canvas.drawRRect(
      felt.deflate(7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFE9C46A).withValues(alpha: 0.35),
    );
    // Direction ring round the piles.
    final c = Offset(size.width / 2, size.height * 0.56);
    final rad = math.min(size.width * 0.44, size.height * 0.3);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.35);
    canvas.drawCircle(c, rad, ring);
    final chevron = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: 0.75);
    for (var i = 0; i < 10; i++) {
      final a = turn * 2 * math.pi * direction + i * 2 * math.pi / 10;
      final p = c + Offset(math.cos(a), math.sin(a)) * rad;
      // Tangent, pointing the way play goes.
      final t = Offset(-math.sin(a), math.cos(a)) * direction.toDouble();
      final n = Offset(math.cos(a), math.sin(a));
      const s = 7.0;
      canvas.drawPath(
        Path()
          ..moveTo((p - t * s + n * s).dx, (p - t * s + n * s).dy)
          ..lineTo(p.dx, p.dy)
          ..lineTo((p - t * s - n * s).dx, (p - t * s - n * s).dy),
        chevron,
      );
    }
  }

  @override
  bool shouldRepaint(_TablePainter old) => old.turn != turn || old.color != color || old.direction != direction;
}

/// An opponent's seat: their cards fanned (backs), avatar with a turn ring
/// and card count, and their name.
class _Seat extends StatelessWidget {
  const _Seat({
    required this.name,
    required this.initials,
    required this.color,
    required this.cards,
    required this.active,
    required this.shout,
    required this.spin,
  });
  final String name, initials;
  final Color color;
  final int cards;
  final bool active, shout;
  final Animation<double> spin;

  @override
  Widget build(BuildContext context) {
    final m = math.min(cards, 8);
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 104,
              height: 50,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var k = 0; k < m; k++)
                    Positioned(
                      left: 52 - 15 + (k - (m - 1) / 2) * 8,
                      top: 4 + ((k - (m - 1) / 2).abs() * 1.2),
                      child: Transform.rotate(
                        angle: (k - (m - 1) / 2) * 0.13,
                        alignment: Alignment.bottomCenter,
                        child: const UnoCardView(card: null, width: 30, faceUp: false),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (active)
                    AnimatedBuilder(
                      animation: spin,
                      builder: (_, _) => Transform.rotate(
                        angle: spin.value * 2 * math.pi * 3,
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(colors: [color, color.withValues(alpha: 0), color]),
                          ),
                        ),
                      ),
                    ),
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.45)!]),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 2),
                      boxShadow: [
                        BoxShadow(color: (active ? color : Colors.black).withValues(alpha: 0.6), blurRadius: active ? 14 : 6),
                      ],
                    ),
                    child: Text(
                      initials,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                  Positioned(
                    right: -6,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: cards == 1 ? const Color(0xFFE53935) : const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Colors.white70),
                      ),
                      child: Text(
                        '$cards',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              name,
              maxLines: 1,
              style: TextStyle(
                color: active ? Colors.white : Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
              ),
            ),
          ],
        ),
        if (shout) const Positioned(top: 18, child: _UnoShout()),
      ],
    );
  }
}

/// One card travelling across the table, with a little lift and spin.
class _FlyingCard extends StatelessWidget {
  const _FlyingCard({super.key, required this.flight, required this.onDone});
  final _Flight flight;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final f = flight;
    const travel = 380;
    final total = f.delayMs + travel;
    final face = f.card != null;
    final w = face ? 74.0 : 56.0;
    final spinTo = face ? ((f.card!.id * 37) % 21 - 10) / 60 : 0.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      onEnd: onDone,
      builder: (_, v, child) {
        final t = Curves.easeOutCubic.transform(((v * total - f.delayMs) / travel).clamp(0.0, 1.0));
        if (v * total < f.delayMs) return const SizedBox.shrink();
        final p = Offset.lerp(f.from, f.to, t)!;
        final lift = math.sin(t * math.pi);
        return Positioned(
          left: p.dx - w / 2,
          top: p.dy - w * 0.75 - lift * 10,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: (face ? (1 - t) * 0.9 : (1 - t) * -0.6) + t * spinTo,
              child: Transform.scale(scale: 1 + lift * 0.12, child: child),
            ),
          ),
        );
      },
      child: UnoCardView(card: f.card, width: w, faceUp: face),
    );
  }
}

class _DrawPile extends StatelessWidget {
  const _DrawPile({required this.count, required this.glow, required this.onTap});
  final int count;
  final bool glow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: glow ? AuraColors.amber.withValues(alpha: 0.85) : Colors.transparent, width: 2),
        boxShadow: [BoxShadow(color: AuraColors.amber.withValues(alpha: glow ? 0.4 : 0), blurRadius: 16)],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // A thick deck: edges stepping up.
          for (var k = 0; k < math.min(6, (count / 8).ceil() + 1); k++)
            Positioned(left: 1.0 + k * 1.1, top: 6 - k * 1.1, child: const UnoCardView(card: null, width: 70, faceUp: false)),
          const SizedBox(width: 78, height: 112),
          Positioned(
            right: -2,
            bottom: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
              child: Text(
                '$count',
                style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The played cards, each at its own slight angle, ringed in the colour in
/// play.
class _DiscardPile extends StatelessWidget {
  const _DiscardPile({required this.cards, required this.color, required this.live});
  final List<UnoCard> cards;
  final UnoColor color;
  final bool live;

  static double _tilt(UnoCard c) => ((c.id * 37) % 21 - 10) / 60;

  @override
  Widget build(BuildContext context) {
    final shown = cards.length > 4 ? cards.sublist(cards.length - 4) : cards;
    final ring = unoColors[color]!;
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        width: 112,
        height: 132,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: live ? ring : Colors.white24, width: 3),
          boxShadow: [if (live) BoxShadow(color: ring.withValues(alpha: 0.45), blurRadius: 22, spreadRadius: 2)],
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            for (final c in shown)
              Transform.rotate(angle: _tilt(c), child: UnoCardView(card: c, width: 74)),
          ],
        ),
      ),
    );
  }
}

/// Your cards fanned in an arc, overlapping to fit; playable ones lifted.
class _Hand extends StatelessWidget {
  const _Hand({required this.cards, required this.playable, required this.myTurn, required this.drawn, required this.onTap});
  final List<UnoCard> cards;
  final Set<UnoCard> playable;
  final bool myTurn;
  final UnoCard? drawn;
  final ValueChanged<UnoCard> onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const cardW = 72.0;
      final n = cards.length;
      final step = n <= 1 ? cardW : math.min(cardW * 0.62, (box.maxWidth - cardW - 36) / (n - 1));
      final total = cardW + (n - 1) * step;
      final left0 = (box.maxWidth - total) / 2;
      final spread = n <= 1 ? 0.0 : math.min(0.06, 0.4 / n);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < n; i++)
            AnimatedPositioned(
              key: ValueKey(cards[i].id),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              left: left0 + i * step,
              top: (playable.contains(cards[i]) ? 4 : 20) + math.pow((i - (n - 1) / 2).abs(), 2) * (spread * 9),
              child: Transform.rotate(
                angle: (i - (n - 1) / 2) * spread,
                alignment: const Alignment(0, 1.6),
                child: GestureDetector(
                  onTap: () => onTap(cards[i]),
                  child: UnoCardView(
                    card: cards[i],
                    width: cardW,
                    dim: myTurn && !playable.contains(cards[i]),
                    glow: cards[i] == drawn ? AuraColors.amber : null,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _UnoButton extends StatelessWidget {
  const _UnoButton({required this.label, required this.armed, required this.enabled, required this.onTap});
  final String label;
  final bool armed;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled || armed ? 1 : 0.4,
    child: GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: armed ? const [Color(0xFFFFD43B), Color(0xFFF59E0B)] : const [Color(0xFFE53935), Color(0xFFB71C1C)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: armed ? 0.9 : 0.25), width: 2),
          boxShadow: [if (enabled) BoxShadow(color: const Color(0xFFE53935).withValues(alpha: 0.5), blurRadius: 14)],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: armed ? const Color(0xFF3B1D00) : Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    ),
  );
}

/// A quick "UNO!" burst on whoever called it.
class _UnoShout extends StatelessWidget {
  const _UnoShout();

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.4, end: 1),
    duration: const Duration(milliseconds: 420),
    curve: Curves.elasticOut,
    builder: (_, s, child) => Transform.scale(scale: s, child: child),
    child: Transform.rotate(
      angle: -0.12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD43B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE53935), width: 2),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
        ),
        child: Text(
          context.l10n.unoCall,
          style: const TextStyle(
            color: Color(0xFFB71C1C),
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            fontSize: 15,
          ),
        ),
      ),
    ),
  );
}
