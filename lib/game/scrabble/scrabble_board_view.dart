import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../common/board_frame.dart';
import 'scrabble_engine.dart';

Color _premiumColor(Premium p) => switch (p) {
  Premium.tw => const Color(0xFFE11D48),
  Premium.dw => const Color(0xFFF472B6),
  Premium.tl => const Color(0xFF2563EB),
  Premium.dl => const Color(0xFF38BDF8),
  Premium.none => const Color(0xFF2A2346),
};

String _premiumLabel(Premium p) => switch (p) {
  Premium.tw => 'TW',
  Premium.dw => 'DW',
  Premium.tl => 'TL',
  Premium.dl => 'DL',
  Premium.none => '',
};

/// The Scrabble board: 15×15 in the shared chess frame with coloured
/// premium squares, placed tiles, this turn's [pending] tiles (glowing; tap
/// one to take it back) and the last play outlined. Taps on a square go to
/// [onTapSquare]. [perspective] tilts the board (3D) inside the frame.
class ScrabbleBoardView extends StatelessWidget {
  const ScrabbleBoardView({
    super.key,
    required this.board,
    required this.pending,
    required this.lastPlay,
    required this.onTapSquare,
    this.perspective = false,
    this.tilt = 0.4,
  });

  final List<Tile?> board;
  final Map<int, Tile> pending;
  final Set<int> lastPlay;
  final ValueChanged<int> onTapSquare;
  final bool perspective;
  final double tilt;

  Matrix4 _perspectiveMatrix() => Matrix4.identity()
    ..setEntry(3, 2, 0.0014)
    ..rotateX(-tilt)
    ..scaleByDouble(0.92, 0.92, 0.92, 1);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const frame = GameBoardFrame.padding * 2 + 5;
        final outer = math.min(c.maxWidth, c.maxHeight);
        final side = outer - frame;
        final cell = side / kSize;
        final grid = SizedBox.square(
          dimension: side,
          child: Stack(
            children: [
              const Positioned.fill(
                child: RepaintBoundary(child: CustomPaint(painter: _SquaresPainter())),
              ),
              for (var sq = 0; sq < kSize * kSize; sq++)
                if (board[sq] != null || pending[sq] != null)
                  Positioned(
                    left: (sq % kSize) * cell,
                    top: (sq ~/ kSize) * cell,
                    width: cell,
                    height: cell,
                    child: Padding(
                      padding: EdgeInsets.all(cell * 0.04),
                      child: ScrabbleTileView(
                        tile: (pending[sq] ?? board[sq])!,
                        size: cell * 0.92,
                        glow: pending.containsKey(sq),
                        outlined: lastPlay.contains(sq),
                      ),
                    ),
                  ),
              for (var sq = 0; sq < kSize * kSize; sq++)
                if (board[sq] == null)
                  Positioned(
                    left: (sq % kSize) * cell,
                    top: (sq ~/ kSize) * cell,
                    width: cell,
                    height: cell,
                    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => onTapSquare(sq)),
                  ),
            ],
          ),
        );
        return Center(
          child: SizedBox.square(
            dimension: outer,
            child: GameBoardFrame(
              child: perspective
                  ? Transform(alignment: Alignment.center, transform: _perspectiveMatrix(), child: grid)
                  : grid,
            ),
          ),
        );
      },
    );
  }
}

class _SquaresPainter extends CustomPainter {
  const _SquaresPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / kSize;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF15102A));
    for (var sq = 0; sq < kSize * kSize; sq++) {
      final r = sq ~/ kSize, c = sq % kSize;
      final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell).deflate(cell * 0.05);
      final p = premiums[sq];
      final base = _premiumColor(p);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.14)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: p == Premium.none
                ? const [Color(0xFF312A52), Color(0xFF241D40)]
                : [Color.lerp(base, Colors.white, 0.15)!, Color.lerp(base, Colors.black, 0.2)!],
          ).createShader(rect),
      );
      if (sq == kCenter) {
        _star(canvas, rect.center, cell * 0.32);
      } else if (p != Premium.none) {
        final tp = TextPainter(
          text: TextSpan(
            text: _premiumLabel(p),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: cell * 0.3,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  void _star(Canvas canvas, Offset c, double r) {
    final path = Path();
    for (var k = 0; k < 10; k++) {
      final rad = k.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + k * math.pi / 5;
      final p = c + Offset(math.cos(a), math.sin(a)) * rad;
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SquaresPainter old) => false;
}

/// A letter tile: cream face, letter, points (blanks show their letter in
/// violet with no points).
class ScrabbleTileView extends StatelessWidget {
  const ScrabbleTileView({
    super.key,
    required this.tile,
    required this.size,
    this.glow = false,
    this.outlined = false,
    this.lifted = false,
  });

  final Tile tile;
  final double size;

  /// Placed this turn (not committed yet).
  final bool glow;

  /// Part of the last play.
  final bool outlined;

  /// Selected in the rack.
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final letter = tile.blank && tile.as == null ? '' : tile.letter;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      transform: Matrix4.translationValues(0, lifted ? -size * 0.18 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFDF6E3), Color(0xFFE9D7AE)],
        ),
        border: Border.all(
          color: glow
              ? const Color(0xFFC084FC)
              : outlined
              ? const Color(0xFFFBBF24)
              : Colors.black.withValues(alpha: 0.18),
          width: glow || outlined ? math.max(1.5, size * 0.07) : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: size * 0.08,
            offset: Offset(0, size * 0.06),
          ),
          if (glow) BoxShadow(color: const Color(0xFFC084FC).withValues(alpha: 0.7), blurRadius: size * 0.3),
          if (lifted) BoxShadow(color: const Color(0xFFC084FC).withValues(alpha: 0.6), blurRadius: size * 0.35),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              letter,
              style: TextStyle(
                color: tile.blank ? const Color(0xFF7C3AED) : const Color(0xFF1F1A2E),
                fontSize: size * 0.56,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          if (!tile.blank)
            Positioned(
              right: size * 0.08,
              bottom: size * 0.04,
              child: Text(
                '${tile.value}',
                style: TextStyle(color: const Color(0xFF3B3160), fontSize: size * 0.24, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
