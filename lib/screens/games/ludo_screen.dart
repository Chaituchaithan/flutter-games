import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Ludo · 4P game board. See docs/DESIGN_SPEC.md (v2 §Games).
///
/// STATIC UI only — tokens are placed for show, there is no game logic.
class LudoScreen extends StatelessWidget {
  const LudoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1) Header.
          const GameHeader(title: '🎲 Ludo', pot: '2,000'),
          const SizedBox(height: 10),
          // 2) Subtitle.
          const GameMetaText('Move 1 / 32 · 4 players · 30s per move'),
          const SizedBox(height: 16),
          // 3) Top players.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                Expanded(
                  child: GamePlayerChip(
                    name: 'ZeroCool',
                    initials: 'ZC',
                    stat: '0 / 4 home',
                    status: 'Rolling',
                    color: AuraColors.green,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: GamePlayerChip(
                    name: 'NeonViper',
                    initials: 'NV',
                    stat: '2 / 4 home',
                    status: 'Waiting',
                    color: AuraColors.storeBlueA,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 4) Board.
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: CustomPaint(
                painter: _LudoBoardPainter(),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 5) Bottom players.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                Expanded(
                  child: GamePlayerChip(
                    name: 'PixelGhost',
                    initials: 'PG',
                    stat: '1 / 4 home',
                    status: 'Waiting',
                    color: AuraColors.brandPurple,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: GamePlayerChip(
                    name: 'You',
                    initials: 'NR',
                    stat: '1 / 4 home',
                    status: 'Your turn',
                    color: AuraColors.brandPink,
                    highlight: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 6) Status line.
          const Center(
            child: Text(
              'NeonViper rolled 4 · 2 tokens home',
              style: TextStyle(color: AuraColors.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          // 7) Action bar.
          const GameActionBar(primaryLabel: '🎲  Roll dice'),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Paints the classic Ludo cross on a 15×15 grid.
class _LudoBoardPainter extends CustomPainter {
  // Quadrant / player colours.
  static const Color pink = Color(0xFFEC4899); // top-left
  static const Color cyan = Color(0xFF22D3EE); // top-right
  static const Color purple = Color(0xFF8B5CF6); // bottom-left
  static const Color gold = Color(0xFFF5B301); // bottom-right

  static const Color trackFill = Color(0xFFF3EFF7);
  static const Color innerFill = Color(0xFFFFFFFF);
  static const Color gridLine = Color(0xFFB8B0C8);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 15;
    final fill = Paint()..style = PaintingStyle.fill;

    // Base (the plus/track area) painted light.
    fill.color = trackFill;
    canvas.drawRect(Offset.zero & size, fill);

    Rect gc(int col, int row, int w, int h) =>
        Rect.fromLTWH(col * cell, row * cell, w * cell, h * cell);
    Offset ctr(double col, double row) => Offset(col * cell, row * cell);

    // Four 6×6 home quadrants.
    _home(canvas, cell, gc(0, 0, 6, 6), pink);
    _home(canvas, cell, gc(9, 0, 6, 6), cyan);
    _home(canvas, cell, gc(0, 9, 6, 6), purple);
    _home(canvas, cell, gc(9, 9, 6, 6), gold);

    // Coloured home lanes leading to the centre.
    fill.color = cyan;
    canvas.drawRect(gc(7, 1, 1, 5), fill); // top lane
    fill.color = gold;
    canvas.drawRect(gc(9, 7, 5, 1), fill); // right lane
    fill.color = purple;
    canvas.drawRect(gc(7, 9, 1, 5), fill); // bottom lane
    fill.color = pink;
    canvas.drawRect(gc(1, 7, 5, 1), fill); // left lane

    // Coloured start cells on the track.
    fill.color = cyan;
    canvas.drawRect(gc(8, 1, 1, 1), fill);
    fill.color = gold;
    canvas.drawRect(gc(13, 6, 1, 1), fill);
    fill.color = purple;
    canvas.drawRect(gc(6, 13, 1, 1), fill);
    fill.color = pink;
    canvas.drawRect(gc(1, 8, 1, 1), fill);

    // Grid lines over the whole plus-shaped track (cols 6-8 or rows 6-8).
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = gridLine;
    for (int row = 0; row < 15; row++) {
      for (int col = 0; col < 15; col++) {
        final inArm = (col >= 6 && col <= 8) || (row >= 6 && row <= 8);
        final inCentre = col >= 6 && col <= 8 && row >= 6 && row <= 8;
        if (inArm && !inCentre) {
          canvas.drawRect(gc(col, row, 1, 1), line);
        }
      }
    }

    // Centre 3×3 goal — four triangles meeting in the middle.
    final centre = ctr(7.5, 7.5);
    final tl = ctr(6, 6), tr = ctr(9, 6), bl = ctr(6, 9), br = ctr(9, 9);
    _triangle(canvas, tl, tr, centre, cyan); // top
    _triangle(canvas, tr, br, centre, gold); // right
    _triangle(canvas, br, bl, centre, purple); // bottom
    _triangle(canvas, bl, tl, centre, pink); // left

    // A few ★ safe-cell markers on the track.
    _star(canvas, ctr(8.5, 1.5), cell);
    _star(canvas, ctr(1.5, 6.5), cell);
    _star(canvas, ctr(6.5, 13.5), cell);
    _star(canvas, ctr(13.5, 8.5), cell);

    // A couple of tokens travelling on the track.
    _token(canvas, ctr(7.5, 3.5), cell, cyan);
    _token(canvas, ctr(11.5, 7.5), cell, gold);
  }

  /// Draws a home quadrant: colour border, white inner 4×4 and 4 base tokens.
  void _home(Canvas canvas, double cell, Rect outer, Color color) {
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    canvas.drawRect(outer, fill);

    // White inner 4×4 (inset by one cell).
    final inner = Rect.fromLTWH(
      outer.left + cell,
      outer.top + cell,
      cell * 4,
      cell * 4,
    );
    fill.color = innerFill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, Radius.circular(cell * 0.35)),
      fill,
    );

    // 4 token circles arranged 2×2 inside the inner square.
    final c0 = outer.left / cell;
    final r0 = outer.top / cell;
    for (final dc in [2.0, 4.0]) {
      for (final dr in [2.0, 4.0]) {
        _token(canvas, Offset((c0 + dc) * cell, (r0 + dr) * cell), cell, color);
      }
    }
  }

  void _triangle(Canvas canvas, Offset a, Offset b, Offset c, Color color) {
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _token(Canvas canvas, Offset center, double cell, Color color) {
    final r = cell * 0.42;
    canvas.drawCircle(center, r, Paint()..color = color);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
    // Small highlight dot.
    canvas.drawCircle(
      center.translate(-r * 0.25, -r * 0.25),
      r * 0.28,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  void _star(Canvas canvas, Offset center, double cell) {
    final tp = TextPainter(
      text: TextSpan(
        text: '★',
        style: TextStyle(
          fontSize: cell * 0.7,
          color: AuraColors.skip.withValues(alpha: 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _LudoBoardPainter oldDelegate) => false;
}
