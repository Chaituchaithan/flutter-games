import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:snakeladder/game/common/board_frame.dart';

import 'chess_board_style.dart';
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
    this.tilt = 0.56,
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

  /// The board style in use (set from the provider in build).
  ChessBoardStyle _style = ChessBoardStyle.aura;
  ChessPieceSet _set = ChessPieceSet.classic;
  ChessBoardLook get _look => _style.look;

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
      // One hop per square (a knight jumps once), Snakes & Ladders pace.
      _moveCtrl.duration = Duration(milliseconds: _moveMs(m));
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
    ..setEntry(3, 2, 0.0018)
    ..rotateX(-widget.tilt)
    ..scaleByDouble(0.84, 0.84, 0.84, 1);

  /// Billboards a piece upright in perspective mode (counter-rotating the
  /// board's backward tilt), with an optional in-flight lift scale.
  Widget _pieceWidget(Piece piece, double cell, {double scale = 1}) {
    // Each piece is its own layer: drawn once (its glow and shading are
    // costly), then only moved / scaled. Without this, starting or landing a
    // move redrew all 32 pieces in one frame — a visible stutter.
    Widget p = RepaintBoundary(
      child: ChessPiece(
        piece: piece,
        size: cell * (widget.perspective ? 0.9 : 0.82),
        rounded: widget.perspective,
        neon: _look.neonPieces,
        set: _set,
      ),
    );
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
      builder: (ctx) => _PromotionPicker(color: color, set: _set),
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

    // The board style (Aura / Wood / Marble) chosen on the setup screen.
    return Consumer(
      builder: (context, ref, _) {
        _style = ref.watch(chessBoardStyleProvider);
        _set = ref.watch(chessPieceSetProvider);
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
                final key = (_version, flying, cell, widget.flipped, widget.perspective, _style, _set);
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
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          // Board thickness + its shadow on the table.
                          IgnorePointer(
                            child: CustomPaint(painter: _SlabPainter(_perspectiveMatrix(), constraints.biggest, _look)),
                          ),
                          Transform(
                            alignment: Alignment.center,
                            transform: _perspectiveMatrix(),
                            child: Stack(
                              children: [
                                board,
                                // Overhead lamp: bright centre, softer corners.
                                const Positioned.fill(child: IgnorePointer(child: _BoardLight())),
                              ],
                            ),
                          ),
                        ],
                      );
                // (The frame draws the glass sheen over the board.)
                return boardWidget;
              },
            ),
      ),
    );
      },
    );
  }

  /// Time for each square a piece steps through (same pace as the Snakes &
  /// Ladders pawn), and for a knight's single jump.
  static const _stepMs = 190;
  static const _knightMs = 460;

  /// How long a move takes: one step per square along its line; a knight
  /// jumps in one go.
  static int _moveMs(Move m) {
    final df = (fileOf(m.to) - fileOf(m.from)).abs(), dr = (rankOf(m.to) - rankOf(m.from)).abs();
    final knight = df != dr && df != 0 && dr != 0;
    return knight ? _knightMs : math.max(df, dr) * _stepMs;
  }

  /// A piece in flight, like the Snakes & Ladders pawn: it hops square by
  /// square along its line (rook, bishop, queen, king, pawn), each hop a
  /// little lift and set-down; a knight makes one higher jump over the
  /// board. Its shadow stays on the squares beneath it.
  Widget _buildFlying(double cell, int from, int to, Piece piece) {
    final (fr, fc) = _visualOf(from);
    final (tr, tc) = _visualOf(to);
    final dr = tr - fr, dc = tc - fc;
    final knight = dr.abs() != dc.abs() && dr != 0 && dc != 0;
    final steps = knight ? 1 : math.max(dr.abs(), dc.abs());
    final hopH = cell * (knight ? 0.55 : 0.24);
    return Positioned(
      left: 0,
      top: 0,
      width: cell,
      height: cell,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _moveCtrl,
          builder: (context, _) {
            // Which hop we're on, and how far through it.
            final x = _moveCtrl.value * steps;
            final k = x.floor().clamp(0, steps - 1);
            final u = (x - k).clamp(0.0, 1.0);
            final e = Curves.easeInOut.transform(u);
            final a = k / steps, b = (k + 1) / steps;
            final t = a + (b - a) * e;
            final pos = Offset((fc + dc * t) * cell, (fr + dr * t) * cell);
            final h = math.sin(u * math.pi);
            final lift = hopH * h;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Shadow on the board, under the piece: smaller and fainter
                // at the top of each hop.
                Transform.translate(
                  offset: pos,
                  child: Align(
                    alignment: const Alignment(0.08, 0.72),
                    child: Container(
                      width: cell * (0.62 - 0.1 * h),
                      height: cell * (0.3 - 0.05 * h),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.elliptical(cell * 0.4, cell * 0.16)),
                        gradient: RadialGradient(
                          colors: [
                            Colors.black.withValues(alpha: widget.perspective ? 0.55 - 0.25 * h : 0.32 - 0.12 * h),
                            Colors.black.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: pos - Offset(0, lift),
                  child: Center(child: _pieceWidget(piece, cell, scale: 1 + 0.06 * h)),
                ),
              ],
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
                  colors: light ? _look.light : _look.dark,
                ),
              ),
              child: const SizedBox.expand(),
            ),
            // Wood grain / marble veins (each square its own pattern).
            if (_style != ChessBoardStyle.aura)
              CustomPaint(size: Size.square(cell), painter: _MaterialPainter(_style, sq, light)),
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
            // 3D: a soft contact shadow where the piece stands.
            if (widget.perspective && piece != null && !hide.contains(sq))
              Align(
                alignment: const Alignment(0.08, 0.72),
                child: Container(
                  width: cell * 0.62,
                  height: cell * 0.3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.elliptical(cell * 0.31, cell * 0.15)),
                    gradient: RadialGradient(
                      colors: [Colors.black.withValues(alpha: 0.55), Colors.black.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
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
    final color = (light ? _look.onLight : _look.onDark).withValues(alpha: 0.75);
    return Align(
      alignment: topLeft ? Alignment.topLeft : Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Text(label, style: TextStyle(color: color, fontSize: cell * 0.16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// The board's thickness in 3D: the front and side edges below the tilted
/// surface (dark violet wood-like gradient with a lit top edge) and its soft
/// shadow on the table. Corners come from the same perspective matrix.
class _SlabPainter extends CustomPainter {
  _SlabPainter(this.m, this.box, this.look);
  final ChessBoardLook look;
  final Matrix4 m;
  final Size box;

  Offset _project(Offset p) {
    final c = box.center(Offset.zero);
    final t = Matrix4.translationValues(c.dx, c.dy, 0)
      ..multiply(m)
      ..multiply(Matrix4.translationValues(-c.dx, -c.dy, 0));
    return MatrixUtils.transformPoint(t, p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = box.width, h = box.height;
    final tl = _project(Offset.zero), tr = _project(Offset(w, 0));
    final br = _project(Offset(w, h)), bl = _project(Offset(0, h));
    final depth = w * 0.06;
    final down = Offset(0, depth);
    // Shadow on the table.
    canvas.drawPath(
      Path()
        ..moveTo(tl.dx + 6, tl.dy + depth)
        ..lineTo(tr.dx - 6, tr.dy + depth)
        ..lineTo(br.dx + 10, br.dy + depth * 2.2)
        ..lineTo(bl.dx - 10, bl.dy + depth * 2.2)
        ..close(),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, depth * 0.9),
    );
    // Side edges (thin, darker).
    final side = Paint()..color = look.slabSide;
    canvas.drawPath(Path()..moveTo(tl.dx, tl.dy)..lineTo(bl.dx, bl.dy)..lineTo(bl.dx, bl.dy + depth)..lineTo(tl.dx, tl.dy + depth * 0.4)..close(), side);
    canvas.drawPath(Path()..moveTo(tr.dx, tr.dy)..lineTo(br.dx, br.dy)..lineTo(br.dx, br.dy + depth)..lineTo(tr.dx, tr.dy + depth * 0.4)..close(), side);
    // Front edge facing you.
    final front = Path()
      ..moveTo(bl.dx, bl.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(br.dx, br.dy + depth)
      ..lineTo(bl.dx, bl.dy + depth)
      ..close();
    canvas.drawPath(
      front,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: look.slab,
        ).createShader(Rect.fromPoints(bl, br + down)),
    );
    // Lit top edge where the surface meets the front.
    canvas.drawLine(
      bl,
      br,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(_SlabPainter old) => old.box != box || old.m != m || old.look != look;
}

/// Real-material texture over a square: wood grain (light maple / dark
/// walnut, grain direction alternating like a real inlaid board) or marble
/// veins. Seeded by the square, so the pattern is stable.
class _MaterialPainter extends CustomPainter {
  _MaterialPainter(this.style, this.square, this.light);
  final ChessBoardStyle style;
  final int square;
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(square * 7919 + (light ? 1 : 0));
    final w = size.width, h = size.height;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (style == ChessBoardStyle.wood) {
      final vertical = square.isEven;
      final grain = Paint()..style = PaintingStyle.stroke;
      final base = light ? const Color(0xFFB98A57) : const Color(0xFF5E3A1F);
      for (var i = 0; i < 9; i++) {
        final t = (i + rng.nextDouble()) / 9;
        final amp = (0.015 + rng.nextDouble() * 0.03) * w;
        final freq = 1 + rng.nextDouble() * 2.5;
        final phase = rng.nextDouble() * math.pi * 2;
        grain
          ..strokeWidth = 0.5 + rng.nextDouble() * 1.4
          ..color = base.withValues(alpha: 0.12 + rng.nextDouble() * 0.18);
        final path = Path();
        for (var k = 0; k <= 20; k++) {
          final u = k / 20;
          final off = math.sin(u * math.pi * freq + phase) * amp;
          final p = vertical ? Offset(t * w + off, u * h) : Offset(u * w, t * h + off);
          k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, grain);
      }
      // Satin varnish sheen.
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: 0.08), Colors.transparent, Colors.black.withValues(alpha: 0.06)],
          ).createShader(Offset.zero & size),
      );
    } else if (style == ChessBoardStyle.ebony) {
      // Fine grain (ebony dark streaks, faint on ivory) + a gold inlay.
      final grain = Paint()..style = PaintingStyle.stroke;
      for (var i = 0; i < 12; i++) {
        final y = (i + rng.nextDouble()) / 12 * h;
        grain
          ..strokeWidth = 0.4 + rng.nextDouble() * 0.8
          ..color = (light ? const Color(0xFFC9B48C) : const Color(0xFF0B0806)).withValues(alpha: light ? 0.2 : 0.45);
        final path = Path()..moveTo(0, y);
        for (var k = 1; k <= 12; k++) {
          path.lineTo(k / 12 * w, y + math.sin(k * 0.9 + i) * h * 0.012);
        }
        canvas.drawPath(path, grain);
      }
      canvas.drawRect(
        (Offset.zero & size).deflate(w * 0.03),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, w * 0.018)
          ..color = const Color(0xFFD4AF37).withValues(alpha: 0.75),
      );
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: light ? 0.1 : 0.06), Colors.transparent],
            stops: const [0, 0.6],
          ).createShader(Offset.zero & size),
      );
    } else if (style == ChessBoardStyle.crystal) {
      // Frosted glass: light streaks, a soft inner glow and a few sparkles.
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.5),
            colors: [Colors.white.withValues(alpha: light ? 0.35 : 0.22), Colors.transparent],
          ).createShader(Offset.zero & size),
      );
      final streak = Paint()..style = PaintingStyle.stroke;
      for (var i = 0; i < 2; i++) {
        final x = rng.nextDouble() * w;
        streak
          ..strokeWidth = w * (0.04 + rng.nextDouble() * 0.06)
          ..color = Colors.white.withValues(alpha: 0.12 + rng.nextDouble() * 0.1)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.03);
        canvas.drawLine(Offset(x - w * 0.4, h), Offset(x + w * 0.2, 0), streak);
      }
      for (var i = 0; i < 3; i++) {
        canvas.drawCircle(
          Offset(rng.nextDouble() * w, rng.nextDouble() * h),
          0.6 + rng.nextDouble() * 0.9,
          Paint()..color = Colors.white.withValues(alpha: 0.5 + rng.nextDouble() * 0.4),
        );
      }
      canvas.drawRect(
        (Offset.zero & size).deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: light ? 0.5 : 0.25),
      );
    } else {
      // Marble / onyx: soft cloudiness and a few thin veins (gold in black
      // onyx).
      for (var i = 0; i < 3; i++) {
        final c = Offset(rng.nextDouble() * w, rng.nextDouble() * h);
        canvas.drawCircle(
          c,
          w * (0.3 + rng.nextDouble() * 0.4),
          Paint()
            ..color = (style == ChessBoardStyle.onyx
                    ? (light ? const Color(0xFFD7D0C3) : const Color(0xFF34343A))
                    : (light ? const Color(0xFFCFD3CC) : const Color(0xFF7FA295)))
                .withValues(alpha: 0.25)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.15),
        );
      }
      final vein = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 1 + rng.nextInt(2); i++) {
        final start = Offset(rng.nextDouble() * w, 0);
        final end = Offset(rng.nextDouble() * w, h);
        final c1 = Offset(rng.nextDouble() * w, h * (0.2 + rng.nextDouble() * 0.3));
        final c2 = Offset(rng.nextDouble() * w, h * (0.5 + rng.nextDouble() * 0.3));
        vein
          ..strokeWidth = 0.4 + rng.nextDouble() * 0.7
          ..color = (style == ChessBoardStyle.onyx
                  ? (light ? const Color(0xFF9C9284) : const Color(0xFFD4AF37))
                  : (light ? const Color(0xFFA7ADA5) : const Color(0xFFC9D8D1)))
              .withValues(alpha: style == ChessBoardStyle.onyx && !light ? 0.45 + rng.nextDouble() * 0.25 : 0.16 + rng.nextDouble() * 0.14);
        canvas.drawPath(Path()..moveTo(start.dx, start.dy)..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy), vein);
      }
      // Polished gloss.
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: 0.16), Colors.transparent],
            stops: const [0, 0.6],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MaterialPainter old) => old.style != style || old.square != square || old.light != light;
}

/// An overhead lamp over the 3D board: a soft bright pool in the middle,
/// gently darker towards the corners.
class _BoardLight extends StatelessWidget {
  const _BoardLight();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: const Alignment(0, -0.1),
        radius: 0.95,
        colors: [Colors.white.withValues(alpha: 0.10), Colors.transparent, Colors.black.withValues(alpha: 0.28)],
        stops: const [0, 0.55, 1],
      ),
    ),
    child: const SizedBox.expand(),
  );
}

/// Promotion picker shown when a pawn reaches the last rank.
class _PromotionPicker extends StatelessWidget {
  const _PromotionPicker({required this.color, this.set = ChessPieceSet.classic});
  final PieceColor color;
  final ChessPieceSet set;

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
                      child: ChessPiece(piece: Piece(color, t), size: 42, set: set, neon: set == ChessPieceSet.classic),
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
