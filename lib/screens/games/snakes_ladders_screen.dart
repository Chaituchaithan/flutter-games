import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Snakes & Ladders · 4P game board. See docs/DESIGN_SPEC.md (v2 §Games).
///
/// STATIC UI only — tokens are placed for show, there is no game logic.
class SnakesLaddersScreen extends StatelessWidget {
  const SnakesLaddersScreen({super.key});

  // Board decoration data (static, for show).
  static const List<int> _ladders = [4, 28, 51, 72];
  static const List<int> _snakes = [17, 54, 62, 87, 95, 99];

  // Player token squares -> colour.
  static const Map<int, Color> _tokens = {
    47: AuraColors.green, // ZeroCool
    12: AuraColors.storeBlueA, // NeonViper
    36: AuraColors.brandPurple, // PixelGhost
    23: AuraColors.brandPink, // You
  };

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1) Header.
          const GameHeader(
            title: '🪜 Snakes & Ladders',
            subtitle: 'Move 1 / 32 · 4 players · 30s per move',
            pot: '2,000',
          ),
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
                    stat: 'Square 47',
                    status: 'Rolling',
                    color: AuraColors.green,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: GamePlayerChip(
                    name: 'NeonViper',
                    initials: 'NV',
                    stat: 'Square 12',
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
            child: _SnakesBoard(
              ladders: _ladders,
              snakes: _snakes,
              tokens: _tokens,
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
                    stat: 'Square 36',
                    status: 'Waiting',
                    color: AuraColors.brandPurple,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: GamePlayerChip(
                    name: 'You',
                    initials: 'NR',
                    stat: 'Square 23',
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
              'ZeroCool rolled 6 · moved to 47',
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

/// The 10×10 boustrophedon board (1 bottom-left … 100 top-left).
class _SnakesBoard extends StatelessWidget {
  const _SnakesBoard({
    required this.ladders,
    required this.snakes,
    required this.tokens,
  });

  final List<int> ladders;
  final List<int> snakes;
  final Map<int, Color> tokens;

  /// Square number for a display position (row from top, col from left).
  int _numberFor(int rowFromTop, int colFromLeft) {
    final squareRow = 9 - rowFromTop; // 0 = bottom
    if (squareRow.isEven) {
      return squareRow * 10 + colFromLeft + 1;
    }
    return squareRow * 10 + (10 - colFromLeft);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = constraints.maxWidth / 10;
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AuraColors.cardBorder),
            ),
            child: Column(
              children: List.generate(10, (rowFromTop) {
                return Expanded(
                  child: Row(
                    children: List.generate(10, (colFromLeft) {
                      final n = _numberFor(rowFromTop, colFromLeft);
                      return Expanded(
                        child: _boardCell(n, rowFromTop, colFromLeft, cell),
                      );
                    }),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  Widget _boardCell(int n, int row, int col, double cell) {
    final isDark = (row + col).isEven;
    final fill = isDark ? const Color(0xFF3A2E52) : const Color(0xFF4A2740);
    final hasLadder = ladders.contains(n);
    final hasSnake = snakes.contains(n);
    final tokenColor = tokens[n];

    return Container(
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: const Color(0x0FFFFFFF), width: 0.5),
      ),
      child: Stack(
        children: [
          // Tiny number label, top-left.
          Positioned(
            left: 3,
            top: 2,
            child: Text(
              '$n',
              style: TextStyle(
                color: AuraColors.textSecondary,
                fontSize: (cell * 0.2).clamp(6.0, 11.0),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Snake / ladder overlay.
          if (hasLadder || hasSnake)
            Center(
              child: Opacity(
                opacity: 0.85,
                child: Text(
                  hasLadder ? '🪜' : '🐍',
                  style: TextStyle(fontSize: cell * 0.5),
                ),
              ),
            ),
          // Player token dot.
          if (tokenColor != null)
            Center(
              child: Container(
                width: cell * 0.4,
                height: cell * 0.4,
                decoration: BoxDecoration(
                  color: tokenColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: tokenColor.withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
