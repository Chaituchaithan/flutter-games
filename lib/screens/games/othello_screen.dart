import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Othello · 2P game board. See docs/DESIGN_SPEC.md (v2 §Games).
///
/// STATIC UI only — discs are placed for show, there is no game logic.
/// Shares its header / player cards / action bar with the other boards via
/// `game_widgets.dart`.
class OthelloScreen extends StatelessWidget {
  const OthelloScreen({super.key});

  // Plausible mid-game position. '.' empty, 'B' black disc, 'W' white disc.
  static const List<String> _position = [
    '........',
    '........',
    '...WB...',
    '..BBBW..',
    '.WWBWW..',
    '..BBWB..',
    '...WB...',
    '........',
  ];

  static const Color _feltA = Color(0xFF2F7D50);
  static const Color _feltB = Color(0xFF2A7048);
  static const Color _gridLine = Color(0x33000000);

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GameHeader(
            title: '⚫ Othello',
            subtitle: 'Move 1 / 12 · 2 players · 30s per move',
            pot: '400',
          ),
          const SizedBox(height: 16),
          const GameOpponentCard(
            name: 'ZeroCool',
            initials: 'ZE',
            stat: '16 discs',
          ),
          const SizedBox(height: 16),
          _lastMove(),
          const SizedBox(height: 16),
          _board(),
          const SizedBox(height: 16),
          _statusRow(),
          const SizedBox(height: 16),
          const GameActionBar(primaryLabel: 'Place disc'),
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
          'ZeroCool flipped 4 discs',
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
                final alt = (row + col) % 2 == 0;
                final code = _position[row][col];
                return Container(
                  decoration: BoxDecoration(
                    color: alt ? _feltA : _feltB,
                    border: Border.all(color: _gridLine, width: 0.5),
                  ),
                  child: code == '.'
                      ? null
                      : Center(child: _Disc(black: code == 'B', size: cell * 0.78)),
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
          Expanded(child: GameYouCard(stat: '14 discs')),
        ],
      ),
    );
  }
}

/// A single Othello disc with a subtle top highlight.
class _Disc extends StatelessWidget {
  const _Disc({required this.black, required this.size});
  final bool black;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 0.9,
          colors: black
              ? const [Color(0xFF3A3A3A), Color(0xFF111111)]
              : const [Colors.white, Color(0xFFF5F5F5)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
    );
  }
}
