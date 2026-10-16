import 'package:flutter/material.dart';

import 'chess_engine.dart';

/// Draws a chess piece as a faux-3D vector figurine — no font or image assets,
/// so it renders identically on every device and in tests. Each piece is a
/// clean silhouette (union of primitives) given real depth: a soft ground
/// contact shadow, an extruded base (stacked darker copies) for height, a
/// multi-stop metallic fill, ambient occlusion at the foot, a glossy top
/// specular, a crisp outline, and a neon rim light tying it to the Aura theme.
/// Piece sets: one shape, different materials. [classic] is the Aura set;
/// the rest are premium.
enum ChessPieceSet { classic, goldSilver, ivoryEbony, crystal, roseGunmetal, jadeOnyx }

/// What one side of a set is made of.
@immutable
class PieceMaterial {
  const PieceMaterial({
    required this.fill,
    required this.edgeLight,
    required this.edgeDark,
    required this.outline,
    this.gloss = 0.5,
    this.metallic = false,
    this.glass = false,
  });

  /// Body colours, top → bottom.
  final List<Color> fill;

  /// Extruded base (height), top → bottom of the stack.
  final Color edgeLight, edgeDark;
  final Color outline;

  /// Top specular strength (0..1).
  final double gloss;

  /// Polished metal: sharp mirror bands down the body.
  final bool metallic;

  /// Glass: see-through body with bright inner edges.
  final bool glass;
}

extension ChessPieceSetX on ChessPieceSet {
  bool get premium => this != ChessPieceSet.classic;

  String get label => switch (this) {
    ChessPieceSet.classic => 'Classic',
    ChessPieceSet.goldSilver => 'Gold & Silver',
    ChessPieceSet.ivoryEbony => 'Ivory & Ebony',
    ChessPieceSet.crystal => 'Crystal',
    ChessPieceSet.roseGunmetal => 'Rose Gold',
    ChessPieceSet.jadeOnyx => 'Jade & Onyx',
  };

  PieceMaterial material(PieceColor c) {
    final w = c == PieceColor.white;
    return switch (this) {
      ChessPieceSet.classic => w
          ? const PieceMaterial(
              fill: [Color(0xFFFFFFFF), Color(0xFFF2E8CF), Color(0xFFD5C7A4)],
              edgeLight: Color(0xFFCBBFA0),
              edgeDark: Color(0xFF7E7252),
              outline: Color(0xFF6B6350),
              gloss: 0.75,
            )
          : const PieceMaterial(
              fill: [Color(0xFF9A9AA8), Color(0xFF55555F), Color(0xFF2E2E38)],
              edgeLight: Color(0xFF3A3A46),
              edgeDark: Color(0xFF17171E),
              outline: Color(0xFF04040A),
              gloss: 0.3,
            ),
      ChessPieceSet.goldSilver => w
          ? const PieceMaterial(
              fill: [Color(0xFFFFF4C2), Color(0xFFE9B949), Color(0xFF9A6A12)],
              edgeLight: Color(0xFFB8860B),
              edgeDark: Color(0xFF5C3D05),
              outline: Color(0xFF5C3D05),
              gloss: 0.8,
              metallic: true,
            )
          : const PieceMaterial(
              fill: [Color(0xFFF4F6F8), Color(0xFFA9B0B8), Color(0xFF4E555D)],
              edgeLight: Color(0xFF7D848C),
              edgeDark: Color(0xFF2E3338),
              outline: Color(0xFF262A2E),
              gloss: 0.8,
              metallic: true,
            ),
      ChessPieceSet.ivoryEbony => w
          ? const PieceMaterial(
              fill: [Color(0xFFFFFBF0), Color(0xFFF1E3C4), Color(0xFFD9C29A)],
              edgeLight: Color(0xFFC9AF85),
              edgeDark: Color(0xFF8A7149),
              outline: Color(0xFF7A6340),
              gloss: 0.55,
            )
          : const PieceMaterial(
              fill: [Color(0xFF5A4636), Color(0xFF2E231B), Color(0xFF15100C)],
              edgeLight: Color(0xFF2A1F17),
              edgeDark: Color(0xFF0C0806),
              outline: Color(0xFF070504),
              gloss: 0.4,
            ),
      ChessPieceSet.crystal => w
          ? const PieceMaterial(
              fill: [Color(0xFFFFFFFF), Color(0xFFDDF3FF), Color(0xFFA9D9F2)],
              edgeLight: Color(0xFFBFE6F8),
              edgeDark: Color(0xFF6FA9C6),
              outline: Color(0xFF5E93AE),
              gloss: 0.9,
              glass: true,
            )
          : const PieceMaterial(
              fill: [Color(0xFF8E97A6), Color(0xFF4B5361), Color(0xFF222832)],
              edgeLight: Color(0xFF3D4452),
              edgeDark: Color(0xFF151A22),
              outline: Color(0xFF0E1218),
              gloss: 0.7,
              glass: true,
            ),
      ChessPieceSet.roseGunmetal => w
          ? const PieceMaterial(
              fill: [Color(0xFFFFE3DA), Color(0xFFE8A997), Color(0xFFA9614F)],
              edgeLight: Color(0xFFC07E6B),
              edgeDark: Color(0xFF6E3829),
              outline: Color(0xFF6E3829),
              gloss: 0.75,
              metallic: true,
            )
          : const PieceMaterial(
              fill: [Color(0xFF8A9099), Color(0xFF4A4F57), Color(0xFF23262B)],
              edgeLight: Color(0xFF3B3F46),
              edgeDark: Color(0xFF15171A),
              outline: Color(0xFF0F1113),
              gloss: 0.6,
              metallic: true,
            ),
      ChessPieceSet.jadeOnyx => w
          ? const PieceMaterial(
              fill: [Color(0xFFC9F2DA), Color(0xFF5FBF8B), Color(0xFF2B7A50)],
              edgeLight: Color(0xFF3E8F62),
              edgeDark: Color(0xFF1B4D31),
              outline: Color(0xFF17452B),
              gloss: 0.7,
            )
          : const PieceMaterial(
              fill: [Color(0xFF55555C), Color(0xFF222226), Color(0xFF0B0B0D)],
              edgeLight: Color(0xFF1E1E22),
              edgeDark: Color(0xFF060607),
              outline: Color(0xFF000000),
              gloss: 0.55,
            ),
    };
  }
}

class ChessPiece extends StatelessWidget {
  const ChessPiece({
    super.key,
    required this.piece,
    required this.size,
    this.rounded = false,
    this.neon = true,
    this.set = ChessPieceSet.classic,
  });

  /// The piece set (material) to draw with.
  final ChessPieceSet set;
  final Piece piece;
  final double size;

  /// 3D view: cylindrical side shading so the piece reads as solid and round.
  final bool rounded;

  /// The Aura neon rim light and halo (off on the wood / marble boards).
  final bool neon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PiecePainter(piece, rounded: rounded, neon: neon && set == ChessPieceSet.classic, set: set)),
    );
  }
}

class _PiecePainter extends CustomPainter {
  _PiecePainter(this.piece, {this.rounded = false, this.neon = true, this.set = ChessPieceSet.classic});
  final Piece piece;
  final ChessPieceSet set;
  final bool rounded;
  final bool neon;

  @override
  void paint(Canvas canvas, Size size) {
    // Author in a 100×100 box, then scale to fit.
    final s = size.width / 100.0;
    canvas.save();
    canvas.scale(s, s);

    final path = _pathFor(piece.type);
    final isWhite = piece.color == PieceColor.white;
    final mat = set.material(piece.color);
    // Neon accent that lights the piece: cyan for pearl, violet for obsidian.
    final rim = isWhite ? const Color(0xFF7DE3FF) : const Color(0xFFB98BFF);

    // 1. Soft elliptical ground contact shadow (grounds the piece on the tile).
    canvas.drawPath(
      _ellipse(50, 93, 60, 17),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.42)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // 1b. Neon bloom halo behind the piece — the "lit" glass-arena glow.
    if (neon) {
      canvas.drawPath(
      path,
      Paint()
        ..color = rim.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    }

    // 2. Extruded body: stack darker copies downward to fake height/thickness.
    const depth = 6.0;
    final edgeLight = mat.edgeLight;
    final edgeDark = mat.edgeDark;
    for (var dy = depth; dy >= 1; dy -= 1) {
      final f = dy / depth;
      canvas.drawPath(
        path.shift(Offset(0, dy)),
        Paint()..color = Color.lerp(edgeLight, edgeDark, f)!,
      );
    }

    // 3. Main metallic fill (multi-stop for a rounded, lit body).
    final fill = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: mat.glass ? [for (final c in mat.fill) c.withValues(alpha: 0.72)] : mat.fill,
      stops: const [0.0, 0.52, 1.0],
    );
    canvas.drawPath(path, Paint()..shader = fill.createShader(const Rect.fromLTWH(0, 0, 100, 100)));

    // 3a. Polished metal: sharp mirror bands down the body.
    if (mat.metallic) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 100, 100),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.55),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.22),
              Colors.white.withValues(alpha: 0.35),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.18),
            ],
            stops: const [0.1, 0.24, 0.42, 0.55, 0.7, 0.92],
          ).createShader(const Rect.fromLTWH(0, 0, 100, 100)),
      );
      canvas.restore();
    }
    // 3c. Glass: bright refracted inner edge and a light caustic band.
    if (mat.glass) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..color = Colors.white.withValues(alpha: isWhite ? 0.55 : 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawRect(
        const Rect.fromLTWH(56, 0, 9, 100),
        Paint()
          ..color = Colors.white.withValues(alpha: isWhite ? 0.3 : 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.restore();
    }

    // 3b. 3D: turned-wood / lacquer roundness — light from the left, shadow
    // falling off to the right, and a narrow gloss streak down the lit side.
    if (rounded) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 100, 100),
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: isWhite ? 0.22 : 0.14),
              Colors.transparent,
              Colors.black.withValues(alpha: isWhite ? 0.28 : 0.45),
            ],
            stops: const [0.0, 0.42, 1.0],
          ).createShader(const Rect.fromLTWH(18, 0, 64, 100)),
      );
      canvas.drawRect(
        const Rect.fromLTWH(33, 0, 7, 100),
        Paint()
          ..color = Colors.white.withValues(alpha: isWhite ? 0.38 : 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
      canvas.restore();
    }

    // 4. Ambient occlusion at the foot — darkens the base for weight.
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.center,
          colors: [Colors.black.withValues(alpha: 0.30), Colors.transparent],
        ).createShader(const Rect.fromLTWH(0, 45, 100, 55)),
    );

    // 5. Glossy top specular highlight.
    final highlight = Colors.white.withValues(alpha: mat.gloss);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [highlight, Colors.transparent],
        ).createShader(const Rect.fromLTWH(0, 0, 100, 58)),
    );

    // 6. Crisp outline.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeJoin = StrokeJoin.round
        ..color = mat.outline,
    );

    // 7. Neon rim light — the signature Aura accent that makes the piece pop
    // and feel lit by the board's glow. A soft blurred pass + a crisp edge.
    if (neon) {
      canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5)
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [rim.withValues(alpha: 0.85), Colors.transparent],
          stops: const [0.0, 0.5],
        ).createShader(const Rect.fromLTWH(0, 0, 100, 100)),
    );
    }
    if (neon) {
      canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [rim, rim.withValues(alpha: 0.0)],
          stops: const [0.0, 0.5],
        ).createShader(const Rect.fromLTWH(0, 0, 100, 100)),
    );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PiecePainter old) =>
      old.piece != piece || old.rounded != rounded || old.neon != neon || old.set != set;
}

// ── Piece silhouettes (unioned primitives in a 100×100 box, base at bottom) ──

Path _pathFor(PieceType type) => switch (type) {
      PieceType.pawn => _pawn(),
      PieceType.rook => _rook(),
      PieceType.bishop => _bishop(),
      PieceType.queen => _queen(),
      PieceType.king => _king(),
      PieceType.knight => _knight(),
    };

Path _union(List<Path> parts) {
  var p = parts.first;
  for (var i = 1; i < parts.length; i++) {
    p = Path.combine(PathOperation.union, p, parts[i]);
  }
  return p;
}

Path _ellipse(double cx, double cy, double w, double h) =>
    Path()..addOval(Rect.fromCenter(center: Offset(cx, cy), width: w, height: h));

Path _rrect(double l, double t, double r, double b, [double radius = 3]) =>
    Path()..addRRect(RRect.fromLTRBR(l, t, r, b, Radius.circular(radius)));

Path _poly(List<Offset> pts) {
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final o in pts.skip(1)) {
    p.lineTo(o.dx, o.dy);
  }
  p.close();
  return p;
}

Path _pawn() => _union([
      _ellipse(50, 86, 44, 14), // base
      _poly([const Offset(40, 82), Offset(60, 82), Offset(55, 52), Offset(45, 52)]), // stem
      _ellipse(50, 52, 30, 9), // collar
      _ellipse(50, 34, 26, 26), // head
    ]);

Path _rook() => _union([
      _ellipse(50, 87, 50, 14), // base
      _rrect(28, 74, 72, 88, 4), // base block
      _poly([const Offset(34, 76), Offset(66, 76), Offset(62, 40), Offset(38, 40)]), // body
      _rrect(28, 30, 72, 44, 2), // top band
      // Crenellations.
      _rrect(28, 20, 40, 34, 1),
      _rrect(44, 20, 56, 34, 1),
      _rrect(60, 20, 72, 34, 1),
    ]);

Path _bishop() => _union([
      _ellipse(50, 88, 48, 14), // base
      _rrect(32, 76, 68, 90, 4), // base block
      _poly([const Offset(40, 78), Offset(60, 78), Offset(56, 48), Offset(44, 48)]), // body
      _ellipse(50, 48, 28, 8), // collar
      _ellipse(50, 32, 26, 38), // mitre
      _ellipse(50, 12, 11, 11), // finial
    ]);

Path _queen() => _union([
      _ellipse(50, 89, 52, 14), // base
      _rrect(34, 78, 66, 92, 4), // base block
      _poly([const Offset(40, 80), Offset(60, 80), Offset(58, 46), Offset(42, 46)]), // body
      _ellipse(50, 46, 32, 9), // collar
      _poly([const Offset(36, 46), Offset(64, 46), Offset(68, 28), Offset(32, 28)]), // crown band
      // Crown orbs.
      _ellipse(28, 22, 13, 13),
      _ellipse(39, 18, 12, 12),
      _ellipse(50, 15, 13, 13),
      _ellipse(61, 18, 12, 12),
      _ellipse(72, 22, 13, 13),
    ]);

Path _king() => _union([
      _ellipse(50, 89, 52, 14), // base
      _rrect(34, 78, 66, 92, 4), // base block
      _poly([const Offset(40, 80), Offset(60, 80), Offset(58, 44), Offset(42, 44)]), // body
      _ellipse(50, 44, 32, 9), // collar
      _poly([const Offset(36, 44), Offset(64, 44), Offset(68, 28), Offset(32, 28)]), // crown band
      _rrect(45, 4, 55, 30, 2), // cross vertical
      _rrect(38, 11, 62, 20, 2), // cross horizontal
    ]);

Path _knight() => _union([
      _ellipse(50, 89, 48, 14), // base
      _rrect(34, 78, 66, 92, 4), // base block
      // Stylised horse head facing left.
      _poly([
        const Offset(60, 80), // neck base right
        const Offset(63, 58),
        const Offset(60, 42),
        const Offset(56, 30),
        const Offset(54, 20), // right ear base
        const Offset(49, 12), // ear tip
        const Offset(45, 22),
        const Offset(38, 18), // forehead
        const Offset(31, 26),
        const Offset(28, 36),
        const Offset(20, 42), // nose top
        const Offset(16, 50), // muzzle
        const Offset(22, 54),
        const Offset(30, 54), // chin / mouth
        const Offset(34, 62),
        const Offset(38, 72),
        const Offset(40, 80), // neck base left
      ]),
    ]);
