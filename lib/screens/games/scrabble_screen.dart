import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Scrabble game board. [players] is 2 or 4. See docs/DESIGN_SPEC.md (v2 §Games).
///
/// STATIC UI only — tiles are placed for show, there is no game logic.
class ScrabbleScreen extends StatelessWidget {
  const ScrabbleScreen({super.key, this.players = 2});

  final int players;

  // ---- Premium-square colours (classic Scrabble layout) ----
  static const Color _twColor = Color(0xFFEF4444); // Triple Word (red)
  static const Color _dwColor = Color(0xFFEC4899); // Double Word (pink, muted)
  static const Color _tlColor = Color(0xFF3B82F6); // Triple Letter (deep blue)
  static const Color _dlColor = Color(0xFF7FE7FF); // Double Letter (light blue)
  static const Color _normal = Color(0xFF241C33); // plain cell

  // Standard symmetric premium map, 0-indexed on a 15x15 board.
  static const Set<int> _tw = {
    0, 7, 14, // top row
    7 * 15 + 0, 7 * 15 + 14, // middle edges
    14 * 15 + 0, 14 * 15 + 7, 14 * 15 + 14, // bottom row
  };
  static const Set<int> _dw = {
    // top-left → bottom-right diagonal
    1 * 15 + 1, 2 * 15 + 2, 3 * 15 + 3, 4 * 15 + 4,
    10 * 15 + 10, 11 * 15 + 11, 12 * 15 + 12, 13 * 15 + 13,
    // top-right → bottom-left diagonal
    1 * 15 + 13, 2 * 15 + 12, 3 * 15 + 11, 4 * 15 + 10,
    13 * 15 + 1, 12 * 15 + 2, 11 * 15 + 3, 10 * 15 + 4,
  };
  static const int _center = 7 * 15 + 7; // star / double-word centre
  static const Set<int> _tl = {
    1 * 15 + 5, 1 * 15 + 9,
    5 * 15 + 1, 5 * 15 + 5, 5 * 15 + 9, 5 * 15 + 13,
    9 * 15 + 1, 9 * 15 + 5, 9 * 15 + 9, 9 * 15 + 13,
    13 * 15 + 5, 13 * 15 + 9,
  };
  static const Set<int> _dl = {
    0 * 15 + 3, 0 * 15 + 11,
    2 * 15 + 6, 2 * 15 + 8,
    3 * 15 + 0, 3 * 15 + 7, 3 * 15 + 14,
    6 * 15 + 2, 6 * 15 + 6, 6 * 15 + 8, 6 * 15 + 12,
    7 * 15 + 3, 7 * 15 + 11,
    8 * 15 + 2, 8 * 15 + 6, 8 * 15 + 8, 8 * 15 + 12,
    11 * 15 + 0, 11 * 15 + 7, 11 * 15 + 14,
    12 * 15 + 6, 12 * 15 + 8,
    14 * 15 + 3, 14 * 15 + 11,
  };

  // Placed tiles: index -> (letter, points).
  // Horizontal A-U-R-A on row 7 crossing vertical W-I-(A)-N-S on col 7,
  // sharing the 'A' at the centre square.
  static const Map<int, (String, int)> _placed = {
    5 * 15 + 7: ('W', 4),
    6 * 15 + 7: ('I', 1),
    7 * 15 + 7: ('A', 1), // shared centre A
    8 * 15 + 7: ('N', 1),
    9 * 15 + 7: ('S', 1),
    7 * 15 + 8: ('U', 1),
    7 * 15 + 9: ('R', 1),
    7 * 15 + 10: ('A', 1),
  };

  // The 7-tile rack.
  static const List<(String, int)> _rack = [
    ('E', 1), ('A', 1), ('T', 1), ('R', 1), ('N', 1), ('L', 1), ('O', 1),
  ];

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GameHeader(
            title: '🔠 Scrabble',
            subtitle: 'Move 1 / 12 · $players players · 30s per move',
            pot: '400',
          ),
          const SizedBox(height: 16),
          _opponents(),
          const SizedBox(height: 16),
          _lastMove(),
          const SizedBox(height: 16),
          _board(),
          const SizedBox(height: 16),
          _rackRow(),
          const SizedBox(height: 16),
          _statusRow(),
          const SizedBox(height: 16),
          const GameActionBar(primaryLabel: 'Play word'),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _opponents() {
    if (players == 4) {
      return const Row(
        children: [
          Expanded(
            child: _CompactOpponent(
              initials: 'ZE',
              color: AuraColors.avatarBlue,
              name: 'ZeroCool',
              points: '49 pts',
              status: 'Waiting',
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: _CompactOpponent(
              initials: 'NV',
              color: AuraColors.avatarGreen,
              name: 'NeonViper',
              points: '31 pts',
              status: 'Playing',
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: _CompactOpponent(
              initials: 'PG',
              color: AuraColors.avatarOrange,
              name: 'PixelGhost',
              points: '44 pts',
              status: 'Waiting',
            ),
          ),
        ],
      );
    }
    return const GameOpponentCard(
      name: 'ZeroCool',
      initials: 'ZE',
      stat: '49 pts',
    );
  }

  Widget _lastMove() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('LAST MOVE'),
        SizedBox(height: 6),
        Text(
          'ZeroCool played a word for 11 pts',
          style: TextStyle(color: AuraColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  Widget _board() {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF120E1C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AuraColors.cardBorder),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cell = constraints.maxWidth / 15;
              return GridView.count(
                crossAxisCount: 15,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: List.generate(225, (i) => _cell(i, cell)),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _cell(int i, double cell) {
    final placed = _placed[i];
    final isCenter = i == _center;

    Color bg;
    if (_tw.contains(i)) {
      bg = _twColor.withValues(alpha: 0.85);
    } else if (i == _center || _dw.contains(i)) {
      bg = _dwColor.withValues(alpha: 0.55);
    } else if (_tl.contains(i)) {
      bg = _tlColor.withValues(alpha: 0.85);
    } else if (_dl.contains(i)) {
      bg = _dlColor.withValues(alpha: 0.7);
    } else {
      bg = _normal;
    }

    return Container(
      margin: const EdgeInsets.all(0.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(2),
      ),
      child: placed != null
          ? _BoardTile(letter: placed.$1, points: placed.$2, cell: cell)
          : isCenter
              ? Center(
                  child: Text(
                    '★',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: cell * 0.55,
                      height: 1,
                    ),
                  ),
                )
              : null,
    );
  }

  Widget _rackRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final t in _rack)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AspectRatio(
                aspectRatio: 1,
                child: _CreamTile(letter: t.$1, points: t.$2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _statusRow() {
    return const IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: GameTurnClock()),
          SizedBox(width: 12),
          Expanded(child: GameYouCard(stat: '42 pts')),
        ],
      ),
    );
  }
}

/// A cream letter tile as it appears placed on the board (fills the cell).
class _BoardTile extends StatelessWidget {
  const _BoardTile({required this.letter, required this.points, required this.cell});
  final String letter;
  final int points;
  final double cell;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF2E6C9),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              letter,
              style: TextStyle(
                color: const Color(0xFF2A2118),
                fontSize: cell * 0.62,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          if (cell > 18)
            Positioned(
              right: 1,
              bottom: 0,
              child: Text(
                '$points',
                style: TextStyle(
                  color: const Color(0xFF6E5B3A),
                  fontSize: cell * 0.28,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A cream letter tile used on the rack (bold letter + subscript point value).
class _CreamTile extends StatelessWidget {
  const _CreamTile({required this.letter, required this.points});
  final String letter;
  final int points;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7EED8), Color(0xFFE9D9B4)],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              letter,
              style: const TextStyle(
                color: Color(0xFF2A2118),
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          Positioned(
            right: 4,
            bottom: 2,
            child: Text(
              '$points',
              style: const TextStyle(
                color: Color(0xFF6E5B3A),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact opponent card used in the 4-player row.
class _CompactOpponent extends StatelessWidget {
  const _CompactOpponent({
    required this.initials,
    required this.color,
    required this.name,
    required this.points,
    required this.status,
  });

  final String initials;
  final Color color;
  final String name;
  final String points;
  final String status;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      radius: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LetterAvatar(letter: initials, color: color, size: 34),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            points,
            style: const TextStyle(color: AuraColors.textSecondary, fontSize: 11.5),
          ),
          const SizedBox(height: 2),
          Text(
            status,
            style: const TextStyle(color: AuraColors.skip, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

