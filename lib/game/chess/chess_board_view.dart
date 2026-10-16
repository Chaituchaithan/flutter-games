import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:snakeladder/game/common/board_frame.dart';

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
    this.turnColor,
    this.yourTurn = false,
  });

  /// In a match: the colour of the side to move (the frame glows in it) and
  /// whether that's you (the glow breathes). Null = the plain neon frame.
  final Color? turnColor;
  final bool yourTurn;

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

  /// Castling: the rook slides alongside the king (from, to, piece).
  (int, int, Piece)? _animRook;

  /// The piece taken by the move in flight: stays on its square until the
  /// mover arrives, then fades out (square, piece).
  (int, Piece)? _captured;

  /// The position before the latest move (to find what was captured).
  List<Piece?> _before = const [];

  /// The square layer, rebuilt only when the position / view changes — not on
  /// every parent rebuild (the clock ticks 5×/s), so moves animate smoothly.
  Widget? _squares;
  Object? _squaresKey;
  int _version = 0;

  List<Piece?> _snapshot() => [for (var i = 0; i < 64; i++) c.state.pieceAt(i)];

  @override
  void initState() {
    super.initState();
    _moveCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() {
            _animMove = null;
            _animPiece = null;
            _animRook = null;
            _captured = null;
            _version++;
          });
        }
      });
    _ambient = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _seenMove = c.lastMove;
    _before = _snapshot();
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
      _animRook = null;
      _captured = null;
    } else if (!identical(m, _seenMove)) {
      // A fresh move (local or from the server) → slide it in.
      _seenMove = m;
      _animMove = m;
      _animPiece = c.state.pieceAt(m.to);
      // Castling: king to g → rook h→f; king to c → rook a→d (same rank).
      _animRook = null;
      if (m.isCastle) {
        final rank = rankOf(m.to);
        final kingSide = fileOf(m.to) == 6;
        final rf = squareOf(kingSide ? 7 : 0, rank), rt = squareOf(kingSide ? 5 : 3, rank);
        final rook = c.state.pieceAt(rt);
        if (rook != null) _animRook = (rf, rt, rook);
      }
      // What it took: the piece on the target, or the pawn passed en passant.
      final takenSq = m.isEnPassant ? squareOf(fileOf(m.to), rankOf(m.from)) : m.to;
      final taken = _before.length == 64 ? _before[takenSq] : null;
      _captured = taken == null ? null : (takenSq, taken);
      // Longer moves take a little longer, so every slide reads at one pace.
      final dist = math.max((fileOf(m.to) - fileOf(m.from)).abs(), (rankOf(m.to) - rankOf(m.from)).abs());
      _moveCtrl.duration = Duration(milliseconds: (300 + 70 * dist).clamp(380, 760));
      _moveCtrl.forward(from: 0);
    }
    _before = _snapshot();
    _version++;
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
    final flying = _animMove != null && _moveCtrl.isAnimating;
    // Squares whose piece is drawn by a flying overlay instead.
    final hide = <int>{
      if (flying) _animMove!.to,
      if (flying && _animRook != null) _animRook!.$2,
    };

    return AspectRatio(
      aspectRatio: 1,
      // The shared board frame (bezel, inner lip, sheen); in a match it glows
      // in the colour of whoever is to move.
      child: GameBoardFrame(
        turnColor: widget.turnColor,
        pulse: widget.yourTurn,
        child: LayoutBuilder(
              builder: (context, constraints) {
                final cell = constraints.maxWidth / 8;
                final key = (_version, flying, cell, widget.flipped, widget.perspective);
                if (_squaresKey != key || _squares == null) {
                  _squaresKey = key;
                  _squares = RepaintBoundary(
                    child: Stack(
                      children: [
                        for (var row = 0; row < 8; row++)
                          for (var col = 0; col < 8; col++)
                            _buildSquare(row, col, cell, targetSquares, lastFrom, lastTo, checked, hide),
                      ],
                    ),
                  );
                }
                final board = Stack(
                  children: [
                    _squares!,
                    if (flying && _captured != null) _buildCaptured(cell),
                    if (flying && _animRook != null) _buildFlying(cell, _animRook!.$1, _animRook!.$2, _animRook!.$3),
                    if (_animMove != null && _animPiece != null)
                      _buildFlying(cell, _animMove!.from, _animMove!.to, _animPiece!),
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
                // (The frame draws the glass sheen over the board.)
                return boardWidget;
              },
            ),
      ),
    );
  }

  /// A piece in flight: glides origin → destination (ease-in-out), lifting
  /// slightly with a soft shadow beneath, then settles onto the square.
  Widget _buildFlying(double cell, int from, int to, Piece piece) {
    final (fr, fc) = _visualOf(from);
    final (tr, tc) = _visualOf(to);
    return Positioned(
      left: 0,
      top: 0,
      width: cell,
      height: cell,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _moveCtrl,
          builder: (context, _) {
            final v = _moveCtrl.value;
            final t = Curves.easeInOutCubic.transform(v);
            final dx = (fc + (tc - fc) * t) * cell;
            final dy = (fr + (tr - fr) * t) * cell;
            // Lift arc: up to ~8% bigger mid-flight, back to 1 on landing.
            final arc = math.sin(math.pi * v);
            return Transform.translate(
              offset: Offset(dx, dy),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Contact shadow: spreads and fades as the piece lifts.
                  Transform.translate(
                    offset: Offset(0, cell * 0.30),
                    child: Container(
                      width: cell * (0.50 + 0.12 * arc),
                      height: cell * 0.14,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(cell),
                        color: Colors.black.withValues(alpha: 0.35 - 0.15 * arc),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: cell * 0.12)],
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(0, -cell * 0.10 * arc),
                    child: _pieceWidget(piece, cell, scale: 1 + 0.08 * arc),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// The captured piece: held in place, then shrinks and fades as the mover
  /// arrives (instead of vanishing the moment the move starts).
  Widget _buildCaptured(double cell) {
    final (sq, piece) = _captured!;
    final (r, col) = _visualOf(sq);
    return Positioned(
      left: col * cell,
      top: r * cell,
      width: cell,
      height: cell,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _moveCtrl,
          builder: (context, _) {
            final f = ((_moveCtrl.value - 0.55) / 0.45).clamp(0.0, 1.0);
            final out = Curves.easeIn.transform(f);
            return Opacity(
              opacity: 1 - out,
              child: Center(child: _pieceWidget(piece, cell, scale: 1 - 0.35 * out)),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSquare(int row, int col, double cell, Set<int> targets, int? lastFrom, int? lastTo, int? checked, Set<int> hide) {
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
            // Square: clean, evenly coloured (no per-square shine, bevel or
            // grid glow) — light lavender vs deep violet, with only a faint
            // tone shift so it doesn't look printed flat.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: light
                      ? const [Color(0xFFE4DCFA), Color(0xFFD6CBF2)]
                      : const [Color(0xFF2B2452), Color(0xFF221B45)],
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
            if (piece != null && !hide.contains(sq)) _pieceWidget(piece, cell),
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
