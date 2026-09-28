import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Chess · 2P game board. See docs/DESIGN_SPEC.md (v2 §Games).
///
/// STATIC UI only — pieces are placed for show, there is no game logic.
/// Shares its header / player cards / action bar with the other boards via
/// `game_widgets.dart`.
class ChessScreen extends StatelessWidget {
  const ChessScreen({super.key});

  // Standard chess starting position, top (black) to bottom (white).
  static const List<List<String>> _position = [
    ['♜', '♞', '♝', '♛', '♚', '♝', '♞', '♜'],
    ['♟', '♟', '♟', '♟', '♟', '♟', '♟', '♟'],
    ['', '', '', '', '', '', '', ''],
    ['', '', '', '', '', '', '', ''],
    ['', '', '', '', '', '', '', ''],
    ['', '', '', '', '', '', '', ''],
    ['♙', '♙', '♙', '♙', '♙', '♙', '♙', '♙'],
    ['♖', '♘', '♗', '♕', '♔', '♗', '♘', '♖'],
  ];

  // e2 square — highlighted to suggest a selected / last-move square.
  static const int _selRow = 6;
  static const int _selCol = 4;

  static const Color _lightSquare = Color(0xFFB9AEE0);
  static const Color _darkSquare = Color(0xFF4A3E6B);

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GameHeader(
            title: '♞ Chess',
            subtitle: 'Move 1 / 12 · 2 players · 30s per move',
            pot: '400',
          ),
          const SizedBox(height: 16),
          const GameOpponentCard(
            name: 'ZeroCool',
            initials: 'ZE',
            stat: '3 captures',
          ),
          const SizedBox(height: 16),
          _lastMove(),
          const SizedBox(height: 16),
          _board(),
          const SizedBox(height: 16),
          _statusRow(),
          const SizedBox(height: 16),
          const GameActionBar(primaryLabel: 'Make move'),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _lastMove() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('LAST MOVE'),
        SizedBox(height: 6),
        Text(
          'ZeroCool played Nf3 · capture',
          style: TextStyle(color: AuraColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  Widget _board() {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cell = constraints.maxWidth / 8;
            return GridView.count(
              crossAxisCount: 8,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(64, (i) {
                final row = i ~/ 8;
                final col = i % 8;
                final light = (row + col) % 2 == 0;
                final glyph = _position[row][col];
                final isBlack = row < 2;
                final selected = row == _selRow && col == _selCol;
                return Container(
                  color: light ? _lightSquare : _darkSquare,
                  child: Stack(
                    children: [
                      if (selected)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AuraColors.gold,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      if (glyph.isNotEmpty)
                        Center(
                          child: Text(
                            glyph,
                            style: TextStyle(
                              fontSize: cell * 0.7,
                              height: 1,
                              color: isBlack
                                  ? const Color(0xFF111111)
                                  : Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }

  Widget _statusRow() {
    return const IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: GameTurnClock()),
          SizedBox(width: 12),
          Expanded(child: GameYouCard(stat: '3 captures')),
        ],
      ),
    );
  }
}
