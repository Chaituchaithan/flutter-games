import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../common/board_frame.dart';
import 'othello_engine.dart';

/// The Othello board: a green felt 8×8 in the shared chess frame, glossy
/// discs, your legal moves as soft dots, the last move marked. A new disc
/// drops in and the outflanked discs flip over one after another.
/// [perspective] tilts the board (3D) inside the frame.
class OthelloBoardView extends StatefulWidget {
  const OthelloBoardView({
    super.key,
    required this.game,
    required this.onTap,
    this.showHints = false,
    this.perspective = false,
    this.tilt = 0.46,
  });

  final OthelloGame game;
  final ValueChanged<int> onTap;

  /// Show the player's legal moves.
  final bool showHints;
  final bool perspective;
  final double tilt;

  /// Drop + flips animation length.
  static const animMs = 560;

  @override
  State<OthelloBoardView> createState() => _OthelloBoardViewState();
}

class _OthelloBoardViewState extends State<OthelloBoardView> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: OthelloBoardView.animMs),
  )..value = 1;
  int? _seenMove;
  int _seenCount = 0;

  @override
  void initState() {
    super.initState();
    widget.game.addListener(_onGame);
  }

  @override
  void didUpdateWidget(OthelloBoardView old) {
    super.didUpdateWidget(old);
    if (old.game != widget.game) {
      old.game.removeListener(_onGame);
      widget.game.addListener(_onGame);
    }
  }

  @override
  void dispose() {
    widget.game.removeListener(_onGame);
    _anim.dispose();
    super.dispose();
  }

  void _onGame() {
    final g = widget.game;
    if (g.moveCount != _seenCount) {
      _seenCount = g.moveCount;
      _seenMove = g.lastMove;
      _anim.forward(from: 0);
    }
    if (mounted) setState(() {});
  }

  Matrix4 _perspectiveMatrix() => Matrix4.identity()
    ..setEntry(3, 2, 0.0016)
    ..rotateX(-widget.tilt)
    ..scaleByDouble(0.9, 0.9, 0.9, 1);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const frame = GameBoardFrame.padding * 2 + 5;
        final outer = math.min(c.maxWidth, c.maxHeight);
        final side = outer - frame;
        final cell = side / 8;
        final s = widget.game.state;
        final hints = widget.showHints ? s.legalMoves().toSet() : const <int>{};

        final board = SizedBox.square(
          dimension: side,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, _) => Stack(
              children: [
                const Positioned.fill(
                  child: RepaintBoundary(child: CustomPaint(painter: _FeltPainter())),
                ),
                for (var sq = 0; sq < 64; sq++)
                  Positioned(
                    left: (sq % 8) * cell,
                    top: (sq ~/ 8) * cell,
                    width: cell,
                    height: cell,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onTap(sq),
                      child: _square(sq, s, hints.contains(sq), cell),
                    ),
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

  Widget _square(int sq, OthelloState s, bool hint, double cell) {
    final disc = s.cells[sq];
    final g = widget.game;
    final t = _anim.value;
    Widget? content;
    if (disc != null) {
      var color = disc;
      var flipX = 1.0;
      var scale = 1.0;
      if (sq == _seenMove && t < 1) {
        // The new disc drops in.
        scale = Curves.easeOutBack.transform((t / 0.45).clamp(0.0, 1.0));
      } else if (g.lastFlips.contains(sq) && t < 1) {
        // Flips ripple outward from the placed disc.
        final dist = _distance(sq, _seenMove ?? sq);
        final start = 0.25 + 0.08 * (dist - 1);
        final u = ((t - start) / 0.35).clamp(0.0, 1.0);
        flipX = math.cos(u * math.pi).abs();
        if (u < 0.5) color = disc.other;
      }
      content = Transform.scale(
        scale: scale,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(math.max(flipX, 0.06), 1, 1),
          child: _DiscWidget(disc: color, size: cell * 0.8),
        ),
      );
    } else if (hint) {
      content = Container(
        width: cell * 0.26,
        height: cell * 0.26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1.2),
        ),
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        if (sq == g.lastMove)
          Container(
            margin: EdgeInsets.all(cell * 0.06),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(cell * 0.12),
              color: const Color(0xFFFBBF24).withValues(alpha: 0.16),
            ),
          ),
        ?content,
      ],
    );
  }

  static int _distance(int a, int b) => math.max(((a ~/ 8) - (b ~/ 8)).abs(), ((a % 8) - (b % 8)).abs());
}

/// Green felt squares with fine grid lines and the four star points.
class _FeltPainter extends CustomPainter {
  const _FeltPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 8;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.4),
          radius: 1.2,
          colors: [Color(0xFF15803D), Color(0xFF166534), Color(0xFF0B3D20)],
        ).createShader(rect),
    );
    // Subtle checker tint for depth.
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        if ((r + c).isOdd) {
          canvas.drawRect(
            Rect.fromLTWH(c * cell, r * cell, cell, cell),
            Paint()..color = Colors.black.withValues(alpha: 0.06),
          );
        }
      }
    }
    final line = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..strokeWidth = 1.2;
    for (var i = 1; i < 8; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), line);
      canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), line);
    }
    for (final p in const [Offset(2, 2), Offset(6, 2), Offset(2, 6), Offset(6, 6)]) {
      canvas.drawCircle(p * cell, cell * 0.06, Paint()..color = Colors.black.withValues(alpha: 0.55));
    }
  }

  @override
  bool shouldRepaint(_FeltPainter old) => false;
}

/// A glossy Othello disc (also used in setup and player cards).
class OthelloDisc extends StatelessWidget {
  const OthelloDisc({super.key, required this.disc, required this.size});
  final Disc disc;
  final double size;

  @override
  Widget build(BuildContext context) => _DiscWidget(disc: disc, size: size);
}

class _DiscWidget extends StatelessWidget {
  const _DiscWidget({required this.disc, required this.size});
  final Disc disc;
  final double size;

  @override
  Widget build(BuildContext context) {
    final black = disc == Disc.black;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: black
              ? const [Color(0xFF4B4B57), Color(0xFF16161D), Color(0xFF050507)]
              : const [Colors.white, Color(0xFFE7E5EF), Color(0xFFB9B5C8)],
          stops: const [0, 0.55, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: size * 0.12,
            offset: Offset(0, size * 0.07),
          ),
        ],
      ),
    );
  }
}
