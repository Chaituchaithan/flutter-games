import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../common/pawn_view.dart';
import 'ludo_engine.dart';

/// Display colour of each Ludo side.
Color ludoColor(LudoColor c) => switch (c) {
  LudoColor.red => const Color(0xFFF43F5E),
  LudoColor.green => const Color(0xFF22C55E),
  LudoColor.yellow => const Color(0xFFFBBF24),
  LudoColor.blue => const Color(0xFF3B82F6),
};

/// The Ludo board: a drawn classic cross board (four bases, the track with
/// star safe squares, coloured home columns and the centre triangles) with
/// the tokens as pawns on top.
///
/// The board is turned so [bottomLeft] (the player's colour) sits at the
/// bottom-left. A [LudoGame.pending] move is animated hop by hop, captured
/// tokens fly back to base, then [onMoveAnimated] fires. While [canPick],
/// the movable tokens pulse and a tap calls [onPick].
class LudoBoardView extends StatefulWidget {
  const LudoBoardView({
    super.key,
    required this.game,
    required this.bottomLeft,
    required this.onMoveAnimated,
    this.canPick = false,
    this.onPick,
    this.perspective = false,
    this.tilt = 0.5,
  });

  final LudoGame game;
  final LudoColor bottomLeft;
  final VoidCallback onMoveAnimated;
  final bool canPick;
  final ValueChanged<int>? onPick;
  final bool perspective;
  final double tilt;

  static const stepMs = 170;
  static const exitMs = 380;
  static const captureMs = 480;

  static int durationMs(LudoMove m) =>
      (m.leavesBase ? exitMs : m.path.length * stepMs) + (m.captured.isEmpty ? 0 : captureMs);

  @override
  State<LudoBoardView> createState() => _LudoBoardViewState();
}

class _LudoBoardViewState extends State<LudoBoardView> with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && _animating != null) {
        _animating = null;
        widget.onMoveAnimated();
      }
    });
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
    ..repeat();

  LudoMove? _animating;

  @override
  void initState() {
    super.initState();
    widget.game.addListener(_onGame);
  }

  @override
  void didUpdateWidget(LudoBoardView old) {
    super.didUpdateWidget(old);
    if (old.game != widget.game) {
      old.game.removeListener(_onGame);
      widget.game.addListener(_onGame);
    }
  }

  @override
  void dispose() {
    widget.game.removeListener(_onGame);
    _move.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _onGame() {
    final m = widget.game.pending;
    if (m != null && !identical(m, _animating)) {
      _animating = m;
      _move.duration = Duration(milliseconds: LudoBoardView.durationMs(m));
      _move.forward(from: 0);
    }
    if (mounted) setState(() {});
  }

  /// Quarter turns (clockwise) that bring [LudoBoardView.bottomLeft] to the
  /// bottom-left corner (bases: red TL · green TR · yellow BR · blue BL).
  int get _turns => (3 - widget.bottomLeft.index) % 4;

  /// Board point (in cell units, unrotated) → screen point.
  Offset _screen(Offset p, double cell) {
    var q = p;
    for (var i = 0; i < _turns; i++) {
      q = Offset(15 - q.dy, q.dx);
    }
    return q * cell;
  }

  Matrix4 _perspectiveMatrix() => Matrix4.identity()
    ..setEntry(3, 2, 0.0015)
    ..rotateX(-widget.tilt)
    ..scaleByDouble(0.92, 0.92, 0.92, 1);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final side = math.min(c.maxWidth, c.maxHeight);
        final cell = side / 15;
        final board = SizedBox(
          width: side,
          height: side,
          child: AnimatedBuilder(
            animation: Listenable.merge([_move, _pulse]),
            builder: (_, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _LudoBoardPainter(turns: _turns)),
                  ),
                ),
                ..._pawns(cell),
              ],
            ),
          ),
        );
        return Center(
          child: widget.perspective
              ? Transform(alignment: Alignment.center, transform: _perspectiveMatrix(), child: board)
              : board,
        );
      },
    );
  }

  // ── Token positions (cell units, unrotated board) ──

  static const _baseOrigin = {
    LudoColor.red: Offset(0, 0),
    LudoColor.green: Offset(9, 0),
    LudoColor.yellow: Offset(9, 9),
    LudoColor.blue: Offset(0, 9),
  };
  static const _baseSpots = [Offset(1.9, 1.9), Offset(4.1, 1.9), Offset(1.9, 4.1), Offset(4.1, 4.1)];
  static const _homeSpot = {
    LudoColor.red: Offset(6.55, 7.5),
    LudoColor.green: Offset(7.5, 6.55),
    LudoColor.yellow: Offset(8.45, 7.5),
    LudoColor.blue: Offset(7.5, 8.45),
  };

  Offset _restingPoint(LudoColor c, int token, int progress) {
    if (progress == LudoRules.base) return _baseOrigin[c]! + _baseSpots[token];
    if (progress == LudoRules.home) {
      final h = _homeSpot[c]!;
      return h + Offset((token % 2 - 0.5) * 0.36, (token ~/ 2 - 0.5) * 0.36);
    }
    final (col, row) = LudoRules.cellOf(c, progress)!;
    return Offset(col + 0.5, row + 0.5);
  }

  List<Widget> _pawns(double cell) {
    final game = widget.game;
    final m = _animating;
    final ms = m == null ? 0.0 : _move.value * LudoBoardView.durationMs(m);
    final moveMs = m == null ? 0 : (m.leavesBase ? LudoBoardView.exitMs : m.path.length * LudoBoardView.stepMs);
    final pickable = widget.canPick && game.awaitingMove ? game.movable.toSet() : const <int>{};
    final pulse = 0.5 + 0.5 * math.sin(_pulse.value * 2 * math.pi);

    // Group resting tokens by cell to spread stacks.
    final byCell = <(int, int), List<(LudoColor, int)>>{};
    for (final c in game.colors) {
      for (var i = 0; i < 4; i++) {
        final p = game.tokens[c]![i];
        if (m != null && m.color == c && m.token == i) continue;
        if (p == LudoRules.base || p == LudoRules.home) continue;
        byCell.putIfAbsent(LudoRules.cellOf(c, p)!, () => []).add((c, i));
      }
    }

    final items = <(double, Widget)>[];
    for (final c in game.colors) {
      for (var i = 0; i < 4; i++) {
        final progress = game.tokens[c]![i];
        Offset pt;
        var lift = 0.0;
        var scale = 1.0;
        if (m != null && m.color == c && m.token == i) {
          (pt, lift) = _moverPoint(m, ms);
        } else if (m != null && m.captured.contains((c, i)) && ms > moveMs) {
          // Fly back to base after the mover lands.
          final u = Curves.easeInOut.transform(((ms - moveMs) / LudoBoardView.captureMs).clamp(0.0, 1.0));
          final from = _restingPoint(c, i, progress);
          final to = _restingPoint(c, i, LudoRules.base);
          pt = Offset.lerp(from, to, u)!;
          lift = math.sin(u * math.pi) * 2.2;
        } else {
          pt = _restingPoint(c, i, progress);
          if (progress != LudoRules.base && progress != LudoRules.home) {
            final group = byCell[LudoRules.cellOf(c, progress)!]!;
            if (group.length > 1) {
              final k = group.indexOf((c, i));
              const offs = [Offset(-0.18, -0.16), Offset(0.18, -0.16), Offset(-0.18, 0.16), Offset(0.18, 0.16)];
              pt += offs[k % 4];
              scale = 0.78;
            }
          } else if (progress == LudoRules.home) {
            scale = 0.6;
          }
        }
        final screen = _screen(pt, cell);
        final size = cell * 1.05 * scale;
        final pickMe = c == game.current && pickable.contains(i);
        Widget pawn = PawnView(color: ludoColor(c), size: size, highlight: pickMe ? pulse : 0);
        if (widget.perspective) {
          pawn = Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.identity()..rotateX(widget.tilt),
            child: pawn,
          );
        }
        if (pickMe) {
          pawn = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onPick?.call(i),
            child: Padding(padding: EdgeInsets.all(cell * 0.2), child: pawn),
          );
        }
        final pad = pickMe ? cell * 0.2 : 0.0;
        items.add((
          screen.dy - lift * cell + (pickMe ? 1000 : 0), // movable tokens on top for taps
          Positioned(
            left: screen.dx - size * 0.36 - pad,
            top: screen.dy - size * 0.86 - lift * cell - pad,
            child: pawn,
          ),
        ));
      }
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final it in items) it.$2];
  }

  /// The moving token: hop square to square (or arc out of base).
  (Offset, double) _moverPoint(LudoMove m, double ms) {
    if (m.leavesBase) {
      final u = Curves.easeInOut.transform((ms / LudoBoardView.exitMs).clamp(0.0, 1.0));
      final a = _restingPoint(m.color, m.token, LudoRules.base);
      final b = _restingPoint(m.color, m.token, 0);
      return (Offset.lerp(a, b, u)!, math.sin(u * math.pi) * 1.2);
    }
    final path = m.path;
    final total = path.length * LudoBoardView.stepMs;
    if (ms >= total) return (_restingPoint(m.color, m.token, m.to), 0);
    final k = (ms / LudoBoardView.stepMs).floor().clamp(0, path.length - 1);
    final u = (ms - k * LudoBoardView.stepMs) / LudoBoardView.stepMs;
    final a = _restingPoint(m.color, m.token, k == 0 ? m.from : path[k - 1]);
    final b = _restingPoint(m.color, m.token, path[k]);
    return (Offset.lerp(a, b, Curves.easeInOut.transform(u))!, math.sin(u * math.pi) * 0.45);
  }
}

class _LudoBoardPainter extends CustomPainter {
  _LudoBoardPainter({required this.turns});
  final int turns;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 15;
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.6));

    canvas.drawRRect(
      rr.shift(Offset(0, cell * 0.25)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.6),
    );
    canvas.save();
    canvas.clipRRect(rr);
    // Rotate the drawing so the player's base sits bottom-left.
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(turns * math.pi / 2);
    canvas.translate(-size.width / 2, -size.height / 2);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F1840), Color(0xFF15102A)],
        ).createShader(rect),
    );

    Rect cellRect(int c, int r) => Rect.fromLTWH(c * cell, r * cell, cell, cell);

    // Track squares.
    for (var t = 0; t < 52; t++) {
      final (c, r) = LudoRules.track[t];
      final rc = cellRect(c, r).deflate(cell * 0.04);
      final start = LudoColor.values.where((lc) => LudoRules.startIndex(lc) == t).firstOrNull;
      final fill = start != null ? ludoColor(start) : const Color(0xFFF4F1FB);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rc, Radius.circular(cell * 0.18)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(fill, Colors.white, 0.25)!,
              Color.lerp(fill, Colors.black, start != null ? 0.15 : 0.12)!,
            ],
          ).createShader(rc),
      );
      if (LudoRules.safe.contains(t) && start == null) {
        _star(canvas, rc.center, cell * 0.32, const Color(0xFF9CA3AF));
      }
      if (start != null) {
        // Arrow into the track on each start square.
        _star(canvas, rc.center, cell * 0.3, Colors.white.withValues(alpha: 0.9));
      }
    }
    // Home columns.
    for (final e in LudoRules.homeColumn.entries) {
      for (final (c, r) in e.value) {
        final rc = cellRect(c, r).deflate(cell * 0.04);
        final col = ludoColor(e.key);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rc, Radius.circular(cell * 0.18)),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(col, Colors.white, 0.2)!, Color.lerp(col, Colors.black, 0.2)!],
            ).createShader(rc),
        );
      }
    }
    // Bases.
    const origins = {
      LudoColor.red: Offset(0, 0),
      LudoColor.green: Offset(9, 0),
      LudoColor.yellow: Offset(9, 9),
      LudoColor.blue: Offset(0, 9),
    };
    for (final e in origins.entries) {
      final col = ludoColor(e.key);
      final outer = Rect.fromLTWH(e.value.dx * cell, e.value.dy * cell, cell * 6, cell * 6).deflate(cell * 0.12);
      canvas.drawRRect(
        RRect.fromRectAndRadius(outer, Radius.circular(cell * 0.7)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(col, Colors.white, 0.15)!, Color.lerp(col, Colors.black, 0.3)!],
          ).createShader(outer),
      );
      final inner = outer.deflate(cell * 0.85);
      canvas.drawRRect(
        RRect.fromRectAndRadius(inner, Radius.circular(cell * 0.5)),
        Paint()..color = const Color(0xFF15102A).withValues(alpha: 0.85),
      );
      for (final s in const [Offset(1.9, 1.9), Offset(4.1, 1.9), Offset(1.9, 4.1), Offset(4.1, 4.1)]) {
        final p = (e.value + s) * cell;
        canvas.drawCircle(p, cell * 0.62, Paint()..color = col.withValues(alpha: 0.25));
        canvas.drawCircle(
          p,
          cell * 0.62,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.08
            ..color = col.withValues(alpha: 0.9),
        );
      }
    }
    // Centre: four triangles meeting in the middle.
    final c0 = Offset(6 * cell, 6 * cell), c1 = Offset(9 * cell, 6 * cell);
    final c2 = Offset(9 * cell, 9 * cell), c3 = Offset(6 * cell, 9 * cell);
    final mid = Offset(7.5 * cell, 7.5 * cell);
    void tri(Offset a, Offset b, LudoColor lc) {
      final col = ludoColor(lc);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(mid.dx, mid.dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [Color.lerp(col, Colors.white, 0.35)!, col, Color.lerp(col, Colors.black, 0.25)!],
          ).createShader(Rect.fromCircle(center: mid, radius: cell * 2.2)),
      );
    }

    tri(c0, c3, LudoColor.red); // left
    tri(c0, c1, LudoColor.green); // top
    tri(c1, c2, LudoColor.yellow); // right
    tri(c3, c2, LudoColor.blue); // bottom
    canvas.drawCircle(
      mid,
      cell * 0.55,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)])
            .createShader(Rect.fromCircle(center: mid, radius: cell * 0.55)),
    );
    _star(canvas, mid, cell * 0.38, Colors.white);
    canvas.restore();

    // Rim.
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.14
        ..shader = const LinearGradient(colors: [Color(0xFFC084FC), Color(0xFFEC4899), Color(0xFFFB923C)])
            .createShader(rect),
    );
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

  @override
  bool shouldRepaint(_LudoBoardPainter o) => o.turns != turns;
}
