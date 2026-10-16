import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:snakeladder/game/chess/chess_pieces.dart';
import 'package:snakeladder/services/app_prefs.dart';

/// How the chess board looks. Chosen on the chess setup screen and used
/// everywhere chess is played (Quick Play, Online, Practice).
enum ChessBoardStyle {
  /// The app's own violet glass board with the neon-lit pieces.
  aura,

  /// Maple and walnut, like a tournament wooden board.
  wood,

  /// Polished white and green marble.
  marble,

  /// Premium: ebony and ivory with a gold inlay round every square.
  ebony,

  /// Premium: black onyx with gold veins and pearl onyx.
  onyx,

  /// Premium: frosted icy glass that catches the light.
  crystal,
}

/// Colours and materials for one style.
@immutable
class ChessBoardLook {
  const ChessBoardLook({
    required this.light,
    required this.dark,
    required this.onLight,
    required this.onDark,
    required this.slab,
    required this.slabSide,
    required this.neonPieces,
    this.premium = false,
  });

  /// One of the premium boards (crown badge in the picker).
  final bool premium;

  /// Square colours (top → bottom of a square).
  final List<Color> light;
  final List<Color> dark;

  /// Coordinate labels on light / dark squares.
  final Color onLight;
  final Color onDark;

  /// Board edge in 3D (front face top → bottom) and the side faces.
  final List<Color> slab;
  final Color slabSide;

  /// Aura's neon rim light on the pieces (off for the real materials).
  final bool neonPieces;
}

extension ChessBoardStyleX on ChessBoardStyle {
  ChessBoardLook get look => switch (this) {
    ChessBoardStyle.aura => const ChessBoardLook(
      light: [Color(0xFFE4DCFA), Color(0xFFD6CBF2)],
      dark: [Color(0xFF2B2452), Color(0xFF221B45)],
      onLight: Color(0xFF3B3160),
      onDark: Color(0xFFEDE7F8),
      slab: [Color(0xFF5B4B9E), Color(0xFF2E2560), Color(0xFF15102E)],
      slabSide: Color(0xFF221A45),
      neonPieces: true,
    ),
    ChessBoardStyle.wood => const ChessBoardLook(
      light: [Color(0xFFF0D9B5), Color(0xFFE6C99C)],
      dark: [Color(0xFFB07A4F), Color(0xFF9A6640)],
      onLight: Color(0xFF8A5A33),
      onDark: Color(0xFFF6E3C6),
      slab: [Color(0xFF8B5A33), Color(0xFF5E3A1F), Color(0xFF3A2312)],
      slabSide: Color(0xFF4A2E18),
      neonPieces: false,
    ),
    ChessBoardStyle.marble => const ChessBoardLook(
      light: [Color(0xFFF4F4F1), Color(0xFFE4E5E1)],
      dark: [Color(0xFF5F7D72), Color(0xFF4B675D)],
      onLight: Color(0xFF55675F),
      onDark: Color(0xFFEFF3F1),
      slab: [Color(0xFFD8DAD5), Color(0xFF9EA39C), Color(0xFF6B706A)],
      slabSide: Color(0xFF7D827B),
      neonPieces: false,
    ),
    ChessBoardStyle.ebony => const ChessBoardLook(
      light: [Color(0xFFF5ECD8), Color(0xFFE8DABC)],
      dark: [Color(0xFF45352B), Color(0xFF33271F)],
      onLight: Color(0xFF8C6A2E),
      onDark: Color(0xFFE2C275),
      slab: [Color(0xFF4A3524), Color(0xFF2A1D13), Color(0xFF140D08)],
      slabSide: Color(0xFF21170F),
      neonPieces: false,
      premium: true,
    ),
    ChessBoardStyle.onyx => const ChessBoardLook(
      light: [Color(0xFFF3F0EA), Color(0xFFE3DED4)],
      dark: [Color(0xFF3A3A40), Color(0xFF2A2A2F)],
      onLight: Color(0xFF6E6656),
      onDark: Color(0xFFD9B95E),
      slab: [Color(0xFF3E3E45), Color(0xFF1F1F24), Color(0xFF0D0D10)],
      slabSide: Color(0xFF18181C),
      neonPieces: false,
      premium: true,
    ),
    ChessBoardStyle.crystal => const ChessBoardLook(
      light: [Color(0xFFEAF7FF), Color(0xFFCFEAF8)],
      dark: [Color(0xFF4B84A8), Color(0xFF346485)],
      onLight: Color(0xFF3E6E8F),
      onDark: Color(0xFFE7F6FF),
      slab: [Color(0xFFCDEFFF), Color(0xFF7FC2E4), Color(0xFF2F6F92)],
      slabSide: Color(0xFF4E8FB3),
      neonPieces: false,
      premium: true,
    ),
  };
}

/// The chosen style, remembered on the device.
final chessBoardStyleProvider = NotifierProvider<ChessBoardStyleNotifier, ChessBoardStyle>(ChessBoardStyleNotifier.new);

class ChessBoardStyleNotifier extends Notifier<ChessBoardStyle> {
  static const _key = 'chess_board_style';

  @override
  ChessBoardStyle build() {
    // Load the saved choice (best effort); Aura until it arrives.
    ref.read(appPrefsProvider).get(_key).then((v) {
      final saved = ChessBoardStyle.values.where((s) => s.name == v).firstOrNull;
      if (saved != null && saved != state) state = saved;
    });
    return ChessBoardStyle.aura;
  }

  void select(ChessBoardStyle s) {
    state = s;
    ref.read(appPrefsProvider).set(_key, s.name);
  }
}

/// The chosen piece set, remembered on the device.
final chessPieceSetProvider = NotifierProvider<ChessPieceSetNotifier, ChessPieceSet>(ChessPieceSetNotifier.new);

class ChessPieceSetNotifier extends Notifier<ChessPieceSet> {
  static const _key = 'chess_piece_set';

  @override
  ChessPieceSet build() {
    ref.read(appPrefsProvider).get(_key).then((v) {
      final saved = ChessPieceSet.values.where((s) => s.name == v).firstOrNull;
      if (saved != null && saved != state) state = saved;
    });
    return ChessPieceSet.classic;
  }

  void select(ChessPieceSet s) {
    state = s;
    ref.read(appPrefsProvider).set(_key, s.name);
  }
}
