import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'uno_engine.dart';

/// Card face colours.
const unoColors = {
  UnoColor.red: Color(0xFFE53935),
  UnoColor.yellow: Color(0xFFF9B61A),
  UnoColor.green: Color(0xFF2E9E48),
  UnoColor.blue: Color(0xFF1E6FD9),
};

const _wildBlack = Color(0xFF17171C);

/// One card, drawn (our own design — no printed brand): a coloured face
/// in a white border, a tilted white oval with the big symbol, and the
/// small symbol in two corners. Wilds are black with a four-colour oval.
/// [faceUp] false = the back.
class UnoCardView extends StatelessWidget {
  const UnoCardView({super.key, required this.card, this.width = 60, this.faceUp = true, this.dim = false, this.glow});

  final UnoCard? card;
  final double width;
  final bool faceUp;

  /// Greyed (can't be played now).
  final bool dim;

  /// Outline glow (playable / just drawn).
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final w = width;
    final h = w * 1.5;
    final c = card;
    final face = !faceUp || c == null ? _back(w) : _face(c, w);
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.12),
        boxShadow: [
          const BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 3)),
          if (glow != null) BoxShadow(color: glow!.withValues(alpha: 0.75), blurRadius: 12, spreadRadius: 1),
        ],
      ),
      padding: EdgeInsets.all(w * 0.055),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(w * 0.08),
        child: dim
            ? ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  0.45, 0.25, 0.1, 0, 0, //
                  0.2, 0.5, 0.1, 0, 0,
                  0.2, 0.25, 0.35, 0, 0,
                  0, 0, 0, 1, 0,
                ]),
                child: face,
              )
            : face,
      ),
    );
  }

  Widget _face(UnoCard c, double w) {
    final fill = c.color == null ? _wildBlack : unoColors[c.color]!;
    final ink = c.color == null ? Colors.white : fill;
    return CustomPaint(
      painter: _FacePainter(fill: fill, wild: c.isWild),
      child: Stack(
        children: [
          Center(
            child: _Symbol(card: c, size: w * 0.5, color: c.isWild ? Colors.white : ink, outlined: true),
          ),
          Positioned(
            left: w * 0.05,
            top: w * 0.02,
            child: _Symbol(card: c, size: w * 0.2, color: Colors.white),
          ),
          Positioned(
            right: w * 0.05,
            bottom: w * 0.02,
            child: Transform.rotate(
              angle: math.pi,
              child: _Symbol(card: c, size: w * 0.2, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _back(double w) => CustomPaint(
    painter: const _BackPainter(),
    child: Center(
      child: Transform.rotate(
        angle: -0.42,
        child: Text(
          'AURA',
          style: TextStyle(
            color: const Color(0xFFFFD43B),
            fontSize: w * 0.24,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            letterSpacing: -0.5,
            shadows: const [Shadow(color: Colors.black, offset: Offset(1.5, 1.5))],
          ),
        ),
      ),
    ),
  );
}

/// The face colour and the tilted oval (white, or four colours on a wild).
class _FacePainter extends CustomPainter {
  const _FacePainter({required this.fill, required this.wild});
  final Color fill;
  final bool wild;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = fill);
    // Soft sheen down the face.
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: 0.18), Colors.transparent, Colors.black.withValues(alpha: 0.12)],
        ).createShader(r),
    );
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(0.52);
    final oval = Rect.fromCenter(center: Offset.zero, width: size.width * 0.78, height: size.height * 0.84);
    if (wild) {
      canvas.clipPath(Path()..addOval(oval));
      final q = [
        unoColors[UnoColor.red]!,
        unoColors[UnoColor.blue]!,
        unoColors[UnoColor.yellow]!,
        unoColors[UnoColor.green]!,
      ];
      for (var i = 0; i < 4; i++) {
        canvas.drawArc(oval.inflate(4), -math.pi / 2 + i * math.pi / 2, math.pi / 2, true, Paint()..color = q[i]);
      }
      canvas.restore();
      return;
    }
    canvas.drawOval(oval, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.fill != fill || old.wild != wild;
}

class _BackPainter extends CustomPainter {
  const _BackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _wildBlack);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(0.52);
    final oval = Rect.fromCenter(center: Offset.zero, width: size.width * 0.8, height: size.height * 0.84);
    canvas.drawOval(oval, Paint()..color = unoColors[UnoColor.red]!);
    canvas.drawOval(
      oval.deflate(size.width * 0.04),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white24,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BackPainter old) => false;
}

/// The card's symbol: a number, ⊘ (Skip), ⇄ (Reverse), +2 / +4, or a
/// small four-colour mark (Wild).
class _Symbol extends StatelessWidget {
  const _Symbol({required this.card, required this.size, required this.color, this.outlined = false});
  final UnoCard card;
  final double size;
  final Color color;

  /// Big centre symbol: dark outline so it reads on the white oval.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final shadows = outlined ? const [Shadow(color: Colors.black54, offset: Offset(1.5, 1.5))] : const <Shadow>[];
    Widget text(String t, double scale) => Text(
      t,
      style: TextStyle(
        color: color,
        fontSize: size * scale,
        height: 1,
        fontWeight: FontWeight.w900,
        fontStyle: FontStyle.italic,
        shadows: shadows,
      ),
    );
    return switch (card.kind) {
      UnoKind.number => text('${card.number}', 1),
      UnoKind.drawTwo => text('+2', 0.78),
      UnoKind.wildDrawFour => text('+4', 0.78),
      UnoKind.skip => Icon(Icons.block_rounded, size: size, color: color, shadows: shadows),
      UnoKind.reverse => Transform.rotate(
        angle: -0.6,
        child: Icon(Icons.sync_alt_rounded, size: size, color: color, shadows: shadows),
      ),
      UnoKind.wild => outlined ? const SizedBox.shrink() : _WildMark(size: size),
    };
  }
}

class _WildMark extends StatelessWidget {
  const _WildMark({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size * 0.8,
    height: size,
    child: CustomPaint(painter: _FacePainter(fill: Colors.transparent, wild: true)),
  );
}
