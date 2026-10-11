import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../common/board_frame.dart';
import 'checkers_engine.dart';

/// The Checkers board: a wooden 8×8 in the shared chess frame with crimson
/// and ivory pieces (kings crowned). Your side is at the bottom ([flipped]
/// when you play Light).
///
/// On your turn ([moves] non-empty) tap a piece to see its targets, then tap
/// a target; a multi-jump is tapped hop by hop and [onMove] fires with the
/// complete move. The last move glides along its path and the captured
/// pieces fade out. [perspective] tilts the board (3D) inside the frame.
class CheckersBoardView extends StatefulWidget {
  const CheckersBoardView({
    super.key,
    required this.game,
    required this.moves,
    required this.onMove,
    this.flipped = false,
    this.perspective = false,
    this.tilt = 0.46,
  });

  final CheckersGame game;

  /// The player's legal moves (empty when it isn't their turn).
  final List<CheckerMove> moves;
  final ValueChanged<CheckerMove> onMove;
  final bool flipped;
  final bool perspective;
  final double tilt;

  static const hopMs = 230;
  static int durationMs(CheckerMove m) => (m.path.length - 1) * hopMs;

  @override
  State<CheckersBoardView> createState() => _CheckersBoardViewState();
}

class _CheckersBoardViewState extends State<CheckersBoardView> with TickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this)..value = 1;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();
  int _seen = 0;

  /// The path tapped so far (first = the selected piece).
  List<int> _partial = const [];

  @override
  void initState() {
    super.initState();
    widget.game.addListener(_onGame);
  }

  @override
  void didUpdateWidget(CheckersBoardView old) {
    super.didUpdateWidget(old);
    if (old.game != widget.game) {
      old.game.removeListener(_onGame);
      widget.game.addListener(_onGame);
    }
    if (widget.moves.isEmpty) _partial = const [];
  }

  @override
  void dispose() {
    widget.game.removeListener(_onGame);
    _anim.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _onGame() {
    final g = widget.game;
    if (g.moveCount != _seen && g.lastMove != null) {
      _seen = g.moveCount;
      _partial = const [];
      _anim.duration = Duration(milliseconds: CheckersBoardView.durationMs(g.lastMove!));
      _anim.forward(from: 0);
    }
    if (mounted) setState(() {});
  }

  /// Moves continuing the tapped path.
  Iterable<CheckerMove> get _matching =>
      widget.moves.where((m) => m.path.length > _partial.length && _startsWith(m.path, _partial));

  static bool _startsWith(List<int> path, List<int> prefix) {
    for (var i = 0; i < prefix.length; i++) {
      if (path[i] != prefix[i]) return false;
    }
    return true;
  }

  void _tap(int sq) {
    if (widget.moves.isEmpty) return;
    // A target of the current selection → extend the path.
    if (_partial.isNotEmpty) {
      final next = [..._partial, sq];
      final cont = widget.moves.where((m) => m.path.length >= next.length && _startsWith(m.path, next)).toList();
      if (cont.isNotEmpty) {
        final done = cont.where((m) => m.path.length == next.length).toList();
        if (done.length == 1 && cont.length == 1) {
          setState(() => _partial = const []);
          widget.onMove(done.single);
        } else {
          setState(() => _partial = next);
        }
        return;
      }
    }
    // Select one of your movable pieces (or deselect).
    final canMove = widget.moves.any((m) => m.from == sq);
    setState(() => _partial = canMove && !(_partial.length == 1 && _partial.first == sq) ? [sq] : const []);
  }

  Matrix4 _perspectiveMatrix() => Matrix4.identity()
    ..setEntry(3, 2, 0.0016)
    ..rotateX(-widget.tilt)
    ..scaleByDouble(0.9, 0.9, 0.9, 1);

  /// Board square → visual (row, col) honouring [flipped].
  (int, int) _visual(int sq) {
    final r = sq ~/ 8, c = sq % 8;
    return widget.flipped ? (7 - r, 7 - c) : (r, c);
  }

  Offset _centre(int sq, double cell) {
    final (r, c) = _visual(sq);
    return Offset((c + 0.5) * cell, (r + 0.5) * cell);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const frame = GameBoardFrame.padding * 2 + 5;
        final outer = math.min(c.maxWidth, c.maxHeight);
        final side = outer - frame;
        final cell = side / 8;
        final board = SizedBox.square(
          dimension: side,
          child: AnimatedBuilder(
            animation: Listenable.merge([_anim, _pulse]),
            builder: (_, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _WoodPainter(flipped: widget.flipped)),
                  ),
                ),
                ..._markers(cell),
                ..._pieces(cell),
                // Tap targets on top.
                for (var sq = 0; sq < 64; sq++)
                  if ((sq ~/ 8 + sq % 8).isOdd)
                    Positioned(
                      left: _visual(sq).$2 * cell,
                      top: _visual(sq).$1 * cell,
                      width: cell,
                      height: cell,
                      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _tap(sq)),
                    ),
              ],
            ),
          ),
        );
        return Center(
          child: SizedBox.square(
            dimension: outer,
            child: GameBoardFrame(
              child: widget.perspective
                  ? Transform(alignment: Alignment.center, transform: _perspectiveMatrix(), child: board)
                  : board,
            ),
          ),
        );
      },
    );
  }

  /// Last move trail, the selected piece, targets and movable-piece rings.
  List<Widget> _markers(double cell) {
    final out = <Widget>[];
    Widget box(int sq, Color color, {double inset = 0.04, double radius = 0.12}) {
      final (r, c) = _visual(sq);
      return Positioned(
        left: c * cell,
        top: r * cell,
        width: cell,
        height: cell,
        child: Container(
          margin: EdgeInsets.all(cell * inset),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(cell * radius)),
        ),
      );
    }

    final last = widget.game.lastMove;
    if (last != null) {
      for (final sq in last.path) {
        out.add(box(sq, const Color(0xFFFBBF24).withValues(alpha: 0.18)));
      }
    }
    final p = 0.5 + 0.5 * math.sin(_pulse.value * 2 * math.pi);
    if (_partial.isEmpty) {
      // Your movable pieces glow softly (captures are compulsory).
      for (final from in widget.moves.map((m) => m.from).toSet()) {
        out.add(box(from, const Color(0xFF34D399).withValues(alpha: 0.12 + 0.12 * p)));
      }
    } else {
      out.add(box(_partial.last, const Color(0xFFC084FC).withValues(alpha: 0.35)));
      for (final sq in _matching.map((m) => m.path[_partial.length]).toSet()) {
        final (r, c) = _visual(sq);
        out.add(
          Positioned(
            left: c * cell,
            top: r * cell,
            width: cell,
            height: cell,
            child: Center(
              child: Container(
                width: cell * 0.34,
                height: cell * 0.34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF34D399).withValues(alpha: 0.55 + 0.3 * p),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF34D399).withValues(alpha: 0.5 * p),
                      blurRadius: cell * 0.2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }
    return out;
  }

  List<Widget> _pieces(double cell) {
    final g = widget.game;
    final last = g.lastMove;
    final t = _anim.value;
    final animating = last != null && t < 1;
    final out = <Widget>[];
    Widget at(Offset centre, Checker piece, {double opacity = 1, double lift = 0}) => Positioned(
      left: centre.dx - cell * 0.42,
      top: centre.dy - cell * 0.42 - lift,
      width: cell * 0.84,
      height: cell * 0.84,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: CheckerPiece(piece: piece, size: cell * 0.84),
        ),
      ),
    );

    for (var sq = 0; sq < 64; sq++) {
      final piece = g.state.board[sq];
      if (piece == null) continue;
      if (animating && sq == last.to) continue; // drawn in flight below
      out.add(at(_centre(sq, cell), piece));
    }
    if (animating) {
      final hops = last.path.length - 1;
      final pos = t * hops;
      final k = pos.floor().clamp(0, hops - 1);
      final u = Curves.easeInOut.transform(pos - k);
      final a = _centre(last.path[k], cell), b = _centre(last.path[k + 1], cell);
      // Captured pieces fade as the mover passes them.
      for (var i = 0; i < g.lastCaptured.length; i++) {
        final (sq, piece) = g.lastCaptured[i];
        final fade = (1 - (pos - i).clamp(0.0, 1.0)).toDouble();
        if (fade > 0) out.add(at(_centre(sq, cell), piece, opacity: fade));
      }
      out.add(at(Offset.lerp(a, b, u)!, g.state.board[last.to]!, lift: math.sin(u * math.pi) * cell * 0.25));
    }
    return out;
  }
}

/// Wooden squares: warm maple lights, deep walnut darks.
class _WoodPainter extends CustomPainter {
  const _WoodPainter({required this.flipped});
  final bool flipped;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 8;
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
        final dark = (r + c).isOdd;
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xFF6B3A22), Color(0xFF4A2716)]
                  : const [Color(0xFFF3DFB8), Color(0xFFE2C48F)],
            ).createShader(rect),
        );
        // A faint grain line per square.
        canvas.drawLine(
          rect.topLeft + Offset(0, cell * 0.35),
          rect.topRight + Offset(0, cell * 0.42),
          Paint()
            ..color = Colors.black.withValues(alpha: dark ? 0.10 : 0.05)
            ..strokeWidth = 1,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WoodPainter old) => old.flipped != flipped;
}

/// A checkers piece: a ridged disc in its side's colour; kings wear a crown.
class CheckerPiece extends StatelessWidget {
  const CheckerPiece({super.key, required this.piece, required this.size});
  final Checker piece;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _PiecePainter(piece));
}

class _PiecePainter extends CustomPainter {
  _PiecePainter(this.piece);
  final Checker piece;

  @override
  void paint(Canvas canvas, Size s) {
    final dark = piece.side == CheckerSide.dark;
    final c = Offset(s.width / 2, s.height / 2);
    final r = s.width / 2;
    final base = dark ? const Color(0xFFDC2626) : const Color(0xFFF5EEDC);
    final deep = dark ? const Color(0xFF7F1D1D) : const Color(0xFFBFAF8C);
    // Shadow + body edge (a little thickness).
    canvas.drawCircle(
      c + Offset(0, r * 0.14),
      r * 0.96,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12),
    );
    canvas.drawCircle(c + Offset(0, r * 0.08), r * 0.96, Paint()..color = deep);
    // Top face.
    canvas.drawCircle(
      c,
      r * 0.94,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Color.lerp(base, Colors.white, 0.35)!, base, deep],
          stops: const [0, 0.6, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Ridges.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06
      ..color = deep.withValues(alpha: 0.55);
    canvas.drawCircle(c, r * 0.72, ring);
    canvas.drawCircle(c, r * 0.5, ring..strokeWidth = r * 0.04);
    if (piece.king) {
      // Gold crown.
      final w = r * 0.9, h = r * 0.55;
      final o = c + Offset(-w / 2, -h / 2);
      final crown = Path()
        ..moveTo(o.dx, o.dy + h)
        ..lineTo(o.dx, o.dy + h * 0.25)
        ..lineTo(o.dx + w * 0.25, o.dy + h * 0.6)
        ..lineTo(o.dx + w * 0.5, o.dy)
        ..lineTo(o.dx + w * 0.75, o.dy + h * 0.6)
        ..lineTo(o.dx + w, o.dy + h * 0.25)
        ..lineTo(o.dx + w, o.dy + h)
        ..close();
      canvas.drawPath(
        crown,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
          ).createShader(crown.getBounds()),
      );
      canvas.drawPath(
        crown,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF92400E),
      );
    }
  }

  @override
  bool shouldRepaint(_PiecePainter old) => old.piece.side != piece.side || old.piece.king != piece.king;
}
