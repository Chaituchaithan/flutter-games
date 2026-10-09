import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chess_controller.dart';
import 'chess_engine.dart';
import 'chess_pieces.dart';

/// Premium 2.5D chess board. Renders the 8×8 grid with beveled squares, piece
/// drop-shadows and 3D-styled glyph pieces, plus selection / legal-move /
/// last-move / check highlights. Tap to select and move.
///
/// Graphics are generated (no external assets): pieces are styled chess glyphs
/// with an outline + metallic gradient fill + shadow, giving a tactile 3D feel.
///
/// Motion: a move slides the piece from its origin to its destination with a
/// subtle "lift" (scale up mid-flight) so it reads as being picked up and set
/// down; selection, check and legal-target markers breathe via a gated ambient
/// pulse (only ticking while something is actually highlighted, so tests that
/// `pumpAndSettle` the board still settle).
class ChessBoardView extends StatefulWidget {
  const ChessBoardView({
    super.key,
    required this.controller,
    this.flipped = false,
    this.perspective = false,
    this.tilt = 0.46,
  });

  final ChessController controller;

  /// When true, render from black's perspective (a1 top-right).
  final bool flipped;

  /// When true, render the board tilted into depth (an over-the-table 3D view)
  /// instead of flat top-down. Taps still resolve to the correct square — see
  /// [_perspectiveMatrix]. Default false keeps the flat board byte-for-byte.
  final bool perspective;

  /// Tilt angle in radians used when [perspective] is true (~26°).
  final double tilt;

  @override
  State<ChessBoardView> createState() => _ChessBoardViewState();
}

class _ChessBoardViewState extends State<ChessBoardView> with TickerProviderStateMixin {
  ChessController get c => widget.controller;

  /// Slides the moving piece from its origin to its destination.
  late final AnimationController _moveCtrl;

  /// Gentle "breathing" pulse for selection / check / target markers. Only runs
  /// while [_shouldPulse] so an idle board (and tests) settle normally.
  late final AnimationController _ambient;

  /// The move currently being animated + the piece in flight (null when idle).
  Move? _animMove;
  Piece? _animPiece;

  /// Identity guard so we only animate each new move once.
  Move? _seenMove;

  @override
  void initState() {
    super.initState();
    _moveCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() {
            _animMove = null;
            _animPiece = null;
          });
        }
      });
    _ambient = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _seenMove = c.lastMove;
    c.addListener(_onChange);
    _syncAmbient();
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _moveCtrl.dispose();
    _ambient.dispose();
    super.dispose();
  }

  void _onChange() {
    final m = c.lastMove;
    if (m == null) {
      // Board was reset.
      _seenMove = null;
      _animMove = null;
      _animPiece = null;
    } else if (!identical(m, _seenMove)) {
      // A fresh move (local or from the server) → slide it in.
      _seenMove = m;
      _animMove = m;
      _animPiece = c.state.pieceAt(m.to);
      _moveCtrl.forward(from: 0);
    }
    _syncAmbient();
    if (mounted) setState(() {});
  }

  bool get _shouldPulse => c.selected != null || c.checkedKing != null;

  void _syncAmbient() {
    if (_shouldPulse) {
      if (!_ambient.isAnimating) _ambient.repeat();
    } else if (_ambient.isAnimating) {
      _ambient.stop();
    }
  }

  /// Visual index (0=top-left) → board square, honouring [flipped].
  int _squareAt(int visualRow, int visualCol) {
    // Row 0 is the top. White's perspective: top = rank 8.
    final rank = widget.flipped ? visualRow : 7 - visualRow;
    final file = widget.flipped ? 7 - visualCol : visualCol;
    return squareOf(file, rank);
  }

  /// Board square → visual (row, col) — the inverse of [_squareAt].
  (int, int) _visualOf(int sq) {
    final file = fileOf(sq);
    final rank = rankOf(sq);
    final row = widget.flipped ? rank : 7 - rank;
    final col = widget.flipped ? 7 - file : file;
    return (row, col);
  }

  /// Perspective transform for the tilted board. A mild perspective divide plus
  /// a backward rotateX about the board centre makes the far rank recede
  /// (smaller/higher) and the near rank enlarge — an over-the-table view. The
  /// uniform down-scale keeps the magnified near edge inside the frame. Applied
  /// via a [Transform] with `transformHitTests`, so its inverse maps taps back
  /// to squares automatically.
  Matrix4 _perspectiveMatrix() => Matrix4.identity()
    ..setEntry(3, 2, 0.0016)
    ..rotateX(-widget.tilt)
    ..scaleByDouble(0.9, 0.9, 0.9, 1);

  /// Billboards a piece upright in perspective mode (counter-rotating the
  /// board's backward tilt), with an optional in-flight lift scale.
  Widget _pieceWidget(Piece piece, double cell, {double scale = 1}) {
    Widget p = ChessPiece(piece: piece, size: cell * 0.82);
    if (scale != 1) p = Transform.scale(scale: scale, child: p);
    if (widget.perspective) {
      p = Transform(
        alignment: Alignment.bottomCenter,
        transform: Matrix4.identity()..rotateX(widget.tilt),
        child: p,
      );
    }
    return p;
  }

  Future<void> _tap(int sq) async {
    final pendingPromotion = c.onTapSquare(sq);
    if (pendingPromotion != null) {
      final type = await _askPromotion(c.state.turn);
      if (type != null) c.promote(pendingPromotion, type);
    }
  }

  Future<PieceType?> _askPromotion(PieceColor color) {
    return showDialog<PieceType>(
      context: context,
      barrierColor: const Color(0xCC05040C),
      builder: (ctx) => _PromotionPicker(color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final targetSquares = {for (final m in c.targets) m.to};
    final lastFrom = c.lastMove?.from;
    final lastTo = c.lastMove?.to;
    final checked = c.checkedKing;
    // While a move is in flight, the destination piece is drawn by the moving
    // overlay instead of popping into place on the square.
    final hideSq = (_animMove != null && _moveCtrl.isAnimating) ? _animMove!.to : null;

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(11),
        // Board frame: polished obsidian bezel with a cyan neon edge + bloom.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1630), Color(0xFF070510)],
          ),
          border: Border.all(color: const Color(0xFF22D3EE).withValues(alpha: 0.30), width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.65), blurRadius: 40, spreadRadius: -8, offset: const Offset(0, 20)),
            // Dual neon bloom — violet below, cyan above — the glass-arena glow.
            BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.34), blurRadius: 40, spreadRadius: -2, offset: const Offset(0, 8)),
            BoxShadow(color: const Color(0xFF22D3EE).withValues(alpha: 0.26), blurRadius: 32, spreadRadius: -6, offset: const Offset(0, -6)),
          ],
        ),
        child: Container(
          // Inner lip: a thin inset frame separating the felt from the bezel.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.black.withValues(alpha: 0.45), width: 1),
            boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.06), blurRadius: 1, spreadRadius: 0.5)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cell = constraints.maxWidth / 8;
                final board = Stack(
                  children: [
                    for (var row = 0; row < 8; row++)
                      for (var col = 0; col < 8; col++)
                        _buildSquare(row, col, cell, targetSquares, lastFrom, lastTo, checked, hideSq),
                    if (_animMove != null && _animPiece != null) _buildMovingPiece(cell),
                  ],
                );
                final boardWidget = !widget.perspective
                    ? board
                    // Tilt the whole board into depth. `transformHitTests`
                    // (default true) maps every pointer event back through this
                    // matrix's INVERSE before hit-testing the square
                    // GestureDetectors, so taps land on the right square.
                    : Transform(
                        alignment: Alignment.center,
                        transform: _perspectiveMatrix(),
                        child: board,
                      );
                // A soft glass sheen over the whole board (never tilted, never
                // intercepts taps) for a lit, premium finish.
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    boardWidget,
                    const IgnorePointer(child: _BoardSheen()),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// The piece in flight: slides origin → destination with an easing curve and
  /// a subtle lift (scale up at the apex) so it feels picked up and set down.
  Widget _buildMovingPiece(double cell) {
    final (fr, fc) = _visualOf(_animMove!.from);
    final (tr, tc) = _visualOf(_animMove!.to);
    return Positioned(
      left: 0,
      top: 0,
      width: cell,
      height: cell,
      child: AnimatedBuilder(
        animation: _moveCtrl,
        builder: (context, _) {
          final t = Curves.easeInOutCubic.transform(_moveCtrl.value);
          final dx = (fc + (tc - fc) * t) * cell;
          final dy = (fr + (tr - fr) * t) * cell;
          // Lift: 1 → ~1.16 → 1 across the flight.
          final lift = 1 + 0.16 * math.sin(math.pi * _moveCtrl.value);
          return Transform.translate(
            offset: Offset(dx, dy),
            child: Center(child: _pieceWidget(_animPiece!, cell, scale: lift)),
          );
        },
      ),
    );
  }

  Widget _buildSquare(int row, int col, double cell, Set<int> targets, int? lastFrom, int? lastTo, int? checked, int? hideSq) {
    final sq = _squareAt(row, col);
    final light = (fileOf(sq) + rankOf(sq)) % 2 == 1;
    final piece = c.state.pieceAt(sq);
    final isSelected = c.selected == sq;
    final isTarget = targets.contains(sq);
    final isLast = sq == lastFrom || sq == lastTo;
    final isChecked = sq == checked;

    return Positioned(
      left: col * cell,
      top: row * cell,
      width: cell,
      height: cell,
      child: GestureDetector(
        onTap: () => _tap(sq),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Square base: bright ice lights vs deep-obsidian darks — the high
            // contrast reads clearly even at small sizes.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: light
                      ? const [Color(0xFFF2EDFF), Color(0xFFCFC2F0), Color(0xFFB4A3E0)]
                      : const [Color(0xFF241D46), Color(0xFF130E29), Color(0xFF070414)],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
              child: const SizedBox.expand(),
            ),
            // Polished-glass reflection: a bright diagonal streak across the tile.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.transparent,
                    Colors.white.withValues(alpha: light ? 0.32 : 0.13),
                    Colors.transparent,
                  ],
                  stops: const [0.30, 0.46, 0.62],
                ),
              ),
              child: const SizedBox.expand(),
            ),
            // Raised-tile bevel: bright top-left edge, dark bottom-right edge,
            // and a lit neon grid hairline (cyan on lights, violet on darks).
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: light ? 0.48 : 0.22),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: light ? 0.16 : 0.42),
                  ],
                  stops: const [0.0, 0.16, 0.84, 1.0],
                ),
                border: Border.all(
                  color: (light ? const Color(0xFF22D3EE) : const Color(0xFF8B7BE8)).withValues(alpha: 0.28),
                  width: 0.6,
                ),
              ),
              child: const SizedBox.expand(),
            ),
            // Last-move highlight (soft inset glow).
            if (isLast)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.22),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.30),
                      blurRadius: cell * 0.22,
                      spreadRadius: -cell * 0.12,
                      offset: Offset(0, cell * 0.02),
                    ),
                  ],
                ),
                child: const SizedBox.expand(),
              ),
            // Check glow (pulsing).
            if (isChecked)
              AnimatedBuilder(
                animation: _ambient,
                builder: (context, _) {
                  final p = _pulse;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFF43F5E).withValues(alpha: 0.45 + 0.35 * p),
                          Colors.transparent,
                        ],
                        stops: const [0.1, 1.0],
                      ),
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            // Selected ring (pulsing glow).
            if (isSelected)
              AnimatedBuilder(
                animation: _ambient,
                builder: (context, _) {
                  final p = _pulse;
                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFC084FC), width: 2.5 + 1.5 * p),
                      color: const Color(0xFFC084FC).withValues(alpha: 0.12 + 0.12 * p),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFC084FC).withValues(alpha: 0.35 * p),
                          blurRadius: cell * 0.3,
                          spreadRadius: -cell * 0.1,
                        ),
                      ],
                    ),
                  );
                },
              ),
            // Rank/file coordinate labels on the edges.
            if (col == 0) _coord(squareName(sq)[1], cell, topLeft: true, light: light),
            if (row == 7) _coord(squareName(sq)[0], cell, topLeft: false, light: light),
            // The piece (hidden on the destination square while it slides in).
            if (piece != null && sq != hideSq) _pieceWidget(piece, cell),
            // Legal-move indicator: glowing dot on empty, ring on a capture.
            if (isTarget) _targetMarker(cell, capture: piece != null),
          ],
        ),
      ),
    );
  }

  /// Breathing value 0..1 driven by the ambient controller (static when idle).
  double get _pulse => 0.5 + 0.5 * math.sin(_ambient.value * 2 * math.pi);

  Widget _targetMarker(double cell, {required bool capture}) {
    return AnimatedBuilder(
      animation: _ambient,
      builder: (context, _) {
        final p = _pulse;
        if (capture) {
          // Ring around a capturable piece.
          return Container(
            margin: EdgeInsets.all(cell * 0.05),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF34D399).withValues(alpha: 0.65 + 0.25 * p),
                width: cell * 0.07,
              ),
            ),
          );
        }
        // Glowing dot on an empty square.
        final d = cell * (0.26 + 0.05 * p);
        return Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF34D399).withValues(alpha: 0.9),
                const Color(0xFF34D399).withValues(alpha: 0.35),
              ],
            ),
            boxShadow: [
              BoxShadow(color: const Color(0xFF34D399).withValues(alpha: 0.4 * p), blurRadius: cell * 0.15),
            ],
          ),
        );
      },
    );
  }

  Widget _coord(String label, double cell, {required bool topLeft, required bool light}) {
    final color = (light ? const Color(0xFF3B3160) : const Color(0xFFEDE7F8)).withValues(alpha: 0.75);
    return Align(
      alignment: topLeft ? Alignment.topLeft : Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Text(label, style: TextStyle(color: color, fontSize: cell * 0.16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// A soft diagonal glass sheen painted over the whole board for a lit finish.
class _BoardSheen extends StatelessWidget {
  const _BoardSheen();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.07),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.10),
          ],
          stops: const [0.0, 0.28, 0.72, 1.0],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// Promotion picker shown when a pawn reaches the last rank.
class _PromotionPicker extends StatelessWidget {
  const _PromotionPicker({required this.color});
  final PieceColor color;

  @override
  Widget build(BuildContext context) {
    const choices = [PieceType.queen, PieceType.rook, PieceType.bishop, PieceType.knight];
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1A1330), Color(0xFF0C0A18)]),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Promote to', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final t in choices)
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(t),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 60,
                      height: 60,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: ChessPiece(piece: Piece(color, t), size: 42),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
