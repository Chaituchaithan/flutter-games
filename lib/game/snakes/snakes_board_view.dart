import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../common/board_frame.dart';
import '../common/pawn_view.dart';
import 'snakes_engine.dart';

/// The Snakes & Ladders board: a drawn 10×10 board (gradient rows, numbered
/// squares, wooden-gold ladders, curved scaled snakes) plus a START pad, with
/// the players' pawns on top.
///
/// When [SnakesGame.pending] is set the moving pawn hops square by square,
/// then climbs the ladder / slides down the snake's body; [onMoveAnimated]
/// fires at the end so the screen can commit the move.
///
/// [perspective] tilts the board into depth (3D) and stands the pawns up.
class SnakesBoardView extends StatefulWidget {
  const SnakesBoardView({
    super.key,
    required this.game,
    required this.colors,
    required this.onMoveAnimated,
    this.perspective = false,
    this.tilt = 0.5,
    this.delay = Duration.zero,
    this.banner,
    this.turnColor,
    this.yourTurn = false,
  });

  /// Shown centred on the board frame's top edge (whose turn / the roll).
  final Widget? banner;

  /// Colour of the player whose turn it is (the frame glows in it) and
  /// whether that's you (the glow breathes).
  final Color? turnColor;
  final bool yourTurn;

  final SnakesGame game;

  /// Pawn colour per player.
  final List<Color> colors;
  final VoidCallback onMoveAnimated;
  final bool perspective;
  final double tilt;

  /// Wait before a move starts (lets the die land first).
  final Duration delay;

  /// Per-step hop and jump timings.
  static const stepMs = 190;
  static const ladderMs = 700;
  static const snakeMs = 950;

  /// How long [move] takes to animate.
  static int durationMs(SnakesMove m) {
    if (m.blocked) return 450;
    final jump = switch (m.jump) {
      SnakesJump.ladder => ladderMs,
      SnakesJump.snake => snakeMs,
      SnakesJump.none => 0,
    };
    return m.steps.length * stepMs + (jump > 0 ? 120 + jump : 0);
  }

  @override
  State<SnakesBoardView> createState() => _SnakesBoardViewState();
}

/// Height of the turn-banner row above the board.
const _bannerRow = 38.0;

class _SnakesBoardViewState extends State<SnakesBoardView> with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && _animating != null) {
        _animating = null;
        widget.onMoveAnimated();
      }
    });

  /// Pulse for the player whose turn it is.
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  SnakesMove? _animating;
  Timer? _start;

  @override
  void initState() {
    super.initState();
    widget.game.addListener(_onGame);
  }

  @override
  void didUpdateWidget(SnakesBoardView old) {
    super.didUpdateWidget(old);
    if (old.game != widget.game) {
      old.game.removeListener(_onGame);
      widget.game.addListener(_onGame);
    }
  }

  @override
  void dispose() {
    widget.game.removeListener(_onGame);
    _start?.cancel();
    _move.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _onGame() {
    final m = widget.game.pending;
    if (m != null && !identical(m, _animating)) {
      _animating = m;
      _move.duration = Duration(milliseconds: SnakesBoardView.durationMs(m));
      _move.value = 0;
      _start?.cancel();
      _start = Timer(widget.delay, () {
        if (mounted) _move.forward(from: 0);
      });
    }
    if (mounted) setState(() {});
  }

  Matrix4 _perspectiveMatrix() => Matrix4.identity()
    ..setEntry(3, 2, 0.0015)
    ..rotateX(-widget.tilt)
    ..scaleByDouble(0.92, 0.92, 0.92, 1);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // The chess frame around the board + the START pad below it
        // (pad = 0.12 × side); the board tilts inside the frame (3D).
        const frame = GameBoardFrame.padding * 2 + 5; // bezel + borders
        // Room for the turn banner above the frame.
        final bannerSpace = widget.banner != null ? _bannerRow : 0.0;
        final outerW = math.min(c.maxWidth, (c.maxHeight - bannerSpace - frame) / 1.12 + frame);
        final side = outerW - frame;
        final cell = side / 10;
        final padH = side * 0.12;
        final geo = _Geometry(cell: cell, padTop: side, padH: padH, players: widget.game.players);

        final board = SizedBox(
          width: side,
          height: side + padH,
          child: AnimatedBuilder(
            animation: Listenable.merge([_move, _pulse]),
            builder: (_, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _BoardPainter(cell: cell, padH: padH),
                    ),
                  ),
                ),
                ..._pawns(geo),
              ],
            ),
          ),
        );

        return Center(
          child: SizedBox(
            width: outerW,
            height: side + padH + frame + bannerSpace,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: bannerSpace,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: GameBoardFrame(
                    turnColor: widget.turnColor,
                    pulse: widget.yourTurn,
                    child: widget.perspective
                        ? Transform(alignment: Alignment.center, transform: _perspectiveMatrix(), child: board)
                        : board,
                  ),
                ),
                // Its own row above the frame — never over the board.
                if (widget.banner != null)
                  Positioned(top: 0, left: 8, right: 8, height: bannerSpace - 6, child: Center(child: widget.banner)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Pawns, back-to-front so nearer ones overlap naturally. Each stands on
  /// the lower part of its square (so it doesn't reach into the row above);
  /// pawns sharing a square get smaller and line up neatly (see
  /// [_Geometry.slot]). The moving pawn is drawn on top.
  List<Widget> _pawns(_Geometry g) {
    final game = widget.game;
    final m = _animating;
    final pulse = 0.5 + 0.5 * math.sin(_pulse.value * 2 * math.pi);
    final items = <(double, Widget)>[];
    for (var p = 0; p < game.players; p++) {
      Offset pos;
      var lift = 0.0;
      final moving = m != null && m.player == p;
      final sharing = moving || game.positions[p] <= 0 ? [p] : _sharing(p);
      final flat = !widget.perspective;
      if (moving) {
        (pos, lift) = _animatedPosition(m, g);
      } else {
        pos = g.slot(game.positions[p], p, sharing, flat: flat);
      }
      // 2D: smaller when sharing, feet near the bottom of the square (not its
      // centre). 3D keeps the original placement (the tilt gives the depth).
      final size = flat ? g.pawnSize(sharing.length) : g.cell * 0.82;
      final feet = flat ? pos + Offset(0, g.cell * (sharing.length > 2 ? 0.2 : 0.3)) : pos;
      final isTurn = !game.isOver && game.turn == p && game.pending == null;
      Widget pawn = PawnView(color: widget.colors[p], size: size, highlight: isTurn ? pulse : 0);
      if (widget.perspective) {
        pawn = Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()..rotateX(widget.tilt),
          child: pawn,
        );
      }
      items.add((
        feet.dy + (moving ? 1000 : 0),
        Positioned(
          left: feet.dx - size * 0.36,
          top: feet.dy - size * (flat ? 0.93 : 0.88) - lift,
          child: IgnorePointer(child: pawn),
        ),
      ));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final i in items) i.$2];
  }

  /// Players standing on the same square as [p] (for spreading them out).
  List<int> _sharing(int p) {
    final game = widget.game;
    final m = _animating;
    final sq = game.positions[p];
    return [
      for (var q = 0; q < game.players; q++)
        if (game.positions[q] == sq && !(m != null && m.player == q)) q,
    ];
  }

  /// Where the moving pawn is now, and how high it's lifted.
  (Offset, double) _animatedPosition(SnakesMove m, _Geometry g) {
    final ms = _move.value * SnakesBoardView.durationMs(m);
    if (m.blocked) {
      // A little "can't move" shake in place.
      final base = g.center(m.from);
      return (base + Offset(math.sin(ms / 450 * math.pi * 6) * g.cell * 0.08, 0), 0);
    }
    final walkMs = m.steps.length * SnakesBoardView.stepMs;
    if (ms < walkMs) {
      final k = (ms / SnakesBoardView.stepMs).floor().clamp(0, m.steps.length - 1);
      final u = (ms - k * SnakesBoardView.stepMs) / SnakesBoardView.stepMs;
      final a = g.center(k == 0 ? m.from : m.steps[k - 1]);
      final b = g.center(m.steps[k]);
      return (Offset.lerp(a, b, Curves.easeInOut.transform(u))!, math.sin(u * math.pi) * g.cell * 0.38);
    }
    final landed = g.center(m.steps.last);
    if (m.jump == SnakesJump.none || ms < walkMs + 120) return (landed, 0);
    final jumpMs = m.jump == SnakesJump.ladder ? SnakesBoardView.ladderMs : SnakesBoardView.snakeMs;
    final u = ((ms - walkMs - 120) / jumpMs).clamp(0.0, 1.0);
    final end = g.center(m.jumpTo!);
    if (m.jump == SnakesJump.ladder) {
      // Climb rung by rung: a small bob per rung.
      final e = Curves.easeInOut.transform(u);
      return (Offset.lerp(landed, end, e)!, (math.sin(e * math.pi * 8)).abs() * g.cell * 0.08);
    }
    // Slide down the snake's body from head to tail.
    final curve = _SnakeCurve.between(landed, end, SnakesRules.snakes.keys.toList().indexOf(m.steps.last), g.cell);
    return (curve.at(Curves.easeIn.transform(u)), 0);
  }
}

/// Board coordinates.
class _Geometry {
  _Geometry({required this.cell, required this.padTop, required this.padH, required this.players});
  final double cell, padTop, padH;
  final int players;

  /// Centre of square 1..100; square 0 = the START pad.
  Offset center(int square) {
    if (square <= 0) return Offset(cell * 1.2, padTop + padH * 0.62);
    final (c, r) = SnakesRules.cellOf(square);
    return Offset((c + 0.5) * cell, (r + 0.5) * cell);
  }

  /// A player's resting spot: spread out when several share a square.
  Offset slot(int square, int player, List<int> sharing, {bool flat = true}) {
    if (square <= 0) {
      // In a row on the START pad.
      return Offset(cell * (2.4 + player * 1.05), padTop + padH * 0.66);
    }
    final base = center(square);
    final n = sharing.length;
    if (n <= 1) return base;
    final i = sharing.indexOf(player).clamp(0, n - 1);
    if (!flat) {
      // 3D: the original four corners.
      const offs3d = [Offset(-0.2, -0.14), Offset(0.2, -0.14), Offset(-0.2, 0.16), Offset(0.2, 0.16)];
      return base + offs3d[i.clamp(0, 3)] * cell;
    }
    // 2: side by side · 3: two behind, one in front · 4: two rows of two.
    final offs = switch (n) {
      2 => const [Offset(-0.24, 0), Offset(0.24, 0)],
      3 => const [Offset(-0.25, -0.12), Offset(0.25, -0.12), Offset(0, 0.14)],
      _ => const [Offset(-0.25, -0.15), Offset(0.25, -0.15), Offset(-0.25, 0.13), Offset(0.25, 0.13)],
    };
    return base + offs[i.clamp(0, offs.length - 1)] * cell;
  }

  /// Pawn height: full size alone, smaller when sharing a square.
  double pawnSize(int n) => cell * switch (n) {
    <= 1 => 0.8,
    2 => 0.7,
    3 => 0.64,
    _ => 0.6,
  };
}

/// The S-curve a snake's body follows from head to tail (shared by the
/// painter and the slide animation so the pawn rides the drawn body).
class _SnakeCurve {
  _SnakeCurve(this.p0, this.p1, this.p2, this.p3);
  final Offset p0, p1, p2, p3;

  factory _SnakeCurve.between(Offset head, Offset tail, int index, double cell) {
    final d = tail - head;
    final len = d.distance;
    final perp = Offset(-d.dy, d.dx) / (len == 0 ? 1 : len);
    final amp = math.min(len * 0.22, cell * 1.4) * (index.isEven ? 1 : -1);
    return _SnakeCurve(head, head + d * 0.3 + perp * amp, head + d * 0.7 - perp * amp, tail);
  }

  Offset at(double t) {
    final u = 1 - t;
    return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t);
  }

  Offset tangent(double t) {
    final u = 1 - t;
    return (p1 - p0) * (3 * u * u) + (p2 - p1) * (6 * u * t) + (p3 - p2) * (3 * t * t);
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({required this.cell, required this.padH});
  final double cell, padH;

  static const _rowColors = [
    Color(0xFF7C3AED),
    Color(0xFF8B5CF6),
    Color(0xFFA855F7),
    Color(0xFFC026D3),
    Color(0xFFDB2777),
    Color(0xFFE11D48),
    Color(0xFFEA580C),
    Color(0xFFD97706),
    Color(0xFF059669),
    Color(0xFF0891B2),
  ];
  static const _snakeColors = [
    (Color(0xFF22C55E), Color(0xFF14532D)),
    (Color(0xFFF97316), Color(0xFF7C2D12)),
    (Color(0xFF06B6D4), Color(0xFF164E63)),
    (Color(0xFFE11D48), Color(0xFF881337)),
    (Color(0xFFA3E635), Color(0xFF3F6212)),
    (Color(0xFFA855F7), Color(0xFF4C1D95)),
  ];

  Offset _center(int square) {
    final (c, r) = SnakesRules.cellOf(square);
    return Offset((c + 0.5) * cell, (r + 0.5) * cell);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Playing surface (shows around the START pad).
    final all = Offset.zero & size;
    canvas.drawRect(
      all,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: BoardPalette.surface,
        ).createShader(all),
    );

    // Squares: row-tinted checkerboard with a soft top light.
    for (var sq = 1; sq <= 100; sq++) {
      final (c, r) = SnakesRules.cellOf(sq);
      final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
      final base = _rowColors[(sq - 1) ~/ 10];
      final light = (c + r).isEven;
      final col = light ? Color.lerp(base, Colors.white, 0.18)! : Color.lerp(base, Colors.black, 0.18)!;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(col, Colors.white, 0.12)!, col],
          ).createShader(rect),
      );
      // Special squares.
      if (SnakesRules.ladders.containsKey(sq)) {
        canvas.drawRect(rect.deflate(cell * 0.06), Paint()..color = const Color(0x5534D399));
      } else if (SnakesRules.snakes.containsKey(sq)) {
        canvas.drawRect(rect.deflate(cell * 0.06), Paint()..color = const Color(0x55000000));
      }
    }
    // Finish square: a gold crown glow.
    final fin = _center(100);
    canvas.drawCircle(
      fin,
      cell * 0.42,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xCCFDE68A), Color(0x00F59E0B)])
            .createShader(Rect.fromCircle(center: fin, radius: cell * 0.42)),
    );
    _star(canvas, fin + Offset(0, cell * 0.06), cell * 0.24, const Color(0xFFFDE68A));

    // Ladders under snakes.
    var i = 0;
    for (final e in SnakesRules.ladders.entries) {
      _ladder(canvas, _center(e.key), _center(e.value), i++);
    }
    i = 0;
    for (final e in SnakesRules.snakes.entries) {
      _snake(canvas, _center(e.key), _center(e.value), i, _snakeColors[i % _snakeColors.length]);
      i++;
    }
    // START pad.
    final side = cell * 10;
    final pad = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, side + padH * 0.22, side, padH * 0.74),
      Radius.circular(padH * 0.3),
    );
    canvas.drawRRect(pad, Paint()..color = Colors.white.withValues(alpha: 0.07));
    canvas.drawRRect(
      pad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.18),
    );
    _text(
      canvas,
      'START',
      Offset(cell * 0.3, side + padH * 0.42),
      cell * 0.26,
      Colors.white.withValues(alpha: 0.7),
      bold: true,
    );
    // Square numbers last, over the snakes and ladders, so they always read.
    for (var sq = 1; sq <= 100; sq++) {
      final (c, r) = SnakesRules.cellOf(sq);
      _number(canvas, '$sq', Offset(c * cell + cell * 0.08, r * cell + cell * 0.06));
    }
  }

  /// A printed square number: bold white with a dark edge and a soft
  /// shadow, readable on every row colour (and over a snake or ladder).
  void _number(Canvas canvas, String s, Offset at) {
    final size = cell * 0.26;
    TextStyle style(Paint? stroke) => TextStyle(
      fontFamily: AuraText.displayFamily,
      fontSize: size,
      fontWeight: FontWeight.w700,
      height: 1,
      letterSpacing: -0.2,
      foreground: stroke,
      color: stroke == null ? Colors.white.withValues(alpha: 0.92) : null,
      shadows: stroke == null ? null : [Shadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: size * 0.2, offset: Offset(0, size * 0.04))],
    );
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.13
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF1A1033).withValues(alpha: 0.55);
    for (final st in [style(edge), style(null)]) {
      (TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr)..layout()).paint(canvas, at);
    }
  }

  void _ladder(Canvas canvas, Offset a, Offset b, int index) {
    final d = b - a;
    final len = d.distance;
    final dir = d / len;
    final perp = Offset(-dir.dy, dir.dx) * cell * 0.17;
    // Trim into the squares a little.
    final s = a + dir * cell * 0.15, e = b - dir * cell * 0.15;
    final rail = Paint()
      ..strokeWidth = cell * 0.08
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(colors: [Color(0xFFFDE68A), Color(0xFFD97706), Color(0xFF92400E)])
          .createShader(Rect.fromPoints(s, e));
    final shadow = Paint()
      ..strokeWidth = cell * 0.09
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.35);
    final sh = Offset(cell * 0.05, cell * 0.07);
    for (final o in [perp, -perp]) {
      canvas.drawLine(s + o + sh, e + o + sh, shadow);
    }
    // Rungs.
    final rungs = (len / (cell * 0.36)).floor();
    final rung = Paint()
      ..strokeWidth = cell * 0.06
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFF59E0B);
    for (var k = 1; k < rungs; k++) {
      final p = Offset.lerp(s, e, k / rungs)!;
      canvas.drawLine(p + perp + sh * 0.6, p - perp + sh * 0.6, shadow..strokeWidth = cell * 0.05);
      canvas.drawLine(p + perp, p - perp, rung);
    }
    for (final o in [perp, -perp]) {
      canvas.drawLine(s + o, e + o, rail);
    }
  }

  void _snake(Canvas canvas, Offset head, Offset tail, int index, (Color, Color) colors) {
    final curve = _SnakeCurve.between(head, tail, index, cell);
    const n = 140;
    final (bright, deep) = colors;
    // Shadow pass, then body: overlapping discs tapering head → tail.
    for (final shadow in [true, false]) {
      for (var k = n; k >= 0; k--) {
        final t = k / n;
        final p = curve.at(t) + (shadow ? Offset(cell * 0.05, cell * 0.08) : Offset.zero);
        final r = cell * (0.2 - 0.14 * t);
        if (shadow) {
          canvas.drawCircle(p, r, Paint()..color = Colors.black.withValues(alpha: 0.3));
        } else {
          final band = (k ~/ 9).isEven;
          canvas.drawCircle(
            p,
            r,
            Paint()
              ..shader = RadialGradient(
                center: const Alignment(-0.3, -0.4),
                colors: [Color.lerp(bright, Colors.white, 0.3)!, band ? bright : Color.lerp(bright, deep, 0.45)!, deep],
                stops: const [0, 0.5, 1],
              ).createShader(Rect.fromCircle(center: p, radius: r)),
          );
        }
      }
    }
    // Belly dots.
    for (var k = 8; k < n; k += 14) {
      final t = k / n;
      canvas.drawCircle(curve.at(t), cell * (0.04 - 0.02 * t), Paint()..color = Colors.white.withValues(alpha: 0.35));
    }
    // Head: an ellipse along the body's direction, eyes and a tongue.
    final dir = curve.tangent(0.0);
    final angle = math.atan2(dir.dy, dir.dx) + math.pi; // facing away from the body
    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.rotate(angle);
    final hr = cell * 0.22;
    canvas.drawPath(
      Path()
        ..moveTo(hr * 1.25, 0)
        ..relativeLineTo(hr * 0.35, -hr * 0.12)
        ..moveTo(hr * 1.25, 0)
        ..relativeLineTo(hr * 0.35, hr * 0.12),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.025
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFF43F5E),
    );
    canvas.drawLine(
      Offset(hr * 0.9, 0),
      Offset(hr * 1.25, 0),
      Paint()
        ..strokeWidth = cell * 0.025
        ..color = const Color(0xFFF43F5E),
    );
    final headRect = Rect.fromCenter(center: Offset.zero, width: hr * 2.1, height: hr * 1.6);
    canvas.drawOval(
      headRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.5),
          colors: [Color.lerp(bright, Colors.white, 0.35)!, bright, deep],
        ).createShader(headRect),
    );
    for (final sy in [-1.0, 1.0]) {
      final eye = Offset(hr * 0.35, sy * hr * 0.38);
      canvas.drawCircle(eye, hr * 0.24, Paint()..color = Colors.white);
      canvas.drawCircle(eye + Offset(hr * 0.06, 0), hr * 0.12, Paint()..color = Colors.black);
    }
    canvas.restore();
  }

  void _star(Canvas canvas, Offset c, double r, Color color) {
    final path = Path();
    for (var k = 0; k < 10; k++) {
      final rad = k.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + k * math.pi / 5;
      final p = c + Offset(math.cos(a), math.sin(a)) * rad;
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  void _text(Canvas canvas, String s, Offset at, double size, Color color, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
          letterSpacing: bold ? 1.5 : 0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_BoardPainter o) => o.cell != cell || o.padH != padH;
}
