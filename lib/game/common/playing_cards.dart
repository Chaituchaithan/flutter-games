import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// The shared card kit for card games (Poker, Rummy): the card model, decks
/// and a realistic card face / back. Suits are drawn as paths so they look
/// the same on every device (no font glyphs).

enum Suit { spades, hearts, diamonds, clubs }

extension SuitX on Suit {
  bool get red => this == Suit.hearts || this == Suit.diamonds;
  String get symbol => const ['♠', '♥', '♦', '♣'][index];
}

/// One card. [rank] 1–13 (A = 1, J = 11, Q = 12, K = 13); a printed joker
/// has rank 0. [deck] tells apart the copies when several decks are mixed.
@immutable
class PlayingCard {
  const PlayingCard(this.rank, this.suit, {this.deck = 0});
  const PlayingCard.joker({this.deck = 0}) : rank = 0, suit = Suit.spades;

  final int rank;
  final Suit suit;
  final int deck;

  bool get isJoker => rank == 0;

  /// "A", "2" … "10", "J", "Q", "K"; "★" for a joker.
  String get label => isJoker ? '★' : const ['', 'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'][rank];

  @override
  bool operator ==(Object other) =>
      other is PlayingCard && other.rank == rank && other.suit == suit && other.deck == deck;

  @override
  int get hashCode => Object.hash(rank, suit, deck);

  @override
  String toString() => isJoker ? 'JK$deck' : '$label${suit.symbol}';
}

/// [decks] standard 52-card decks plus [jokers] printed jokers, shuffled.
List<PlayingCard> shuffledDeck(math.Random rng, {int decks = 1, int jokers = 0}) => [
  for (var d = 0; d < decks; d++)
    for (final s in Suit.values)
      for (var r = 1; r <= 13; r++) PlayingCard(r, s, deck: d),
  for (var j = 0; j < jokers; j++) PlayingCard.joker(deck: j),
]..shuffle(rng);

const _red = Color(0xFFD7263D);
const _black = Color(0xFF1B1530);

/// A card at [width] (height = 1.4 × width). Face down shows the Aura back.
/// [selected] lifts it with a glow; [dimmed] greys it (e.g. folded);
/// [wild] marks a rummy wild joker with a small star badge.
class PlayingCardView extends StatelessWidget {
  const PlayingCardView({
    super.key,
    required this.card,
    required this.width,
    this.faceUp = true,
    this.selected = false,
    this.dimmed = false,
    this.wild = false,
    this.highlight,
  });

  final PlayingCard? card;
  final double width;
  final bool faceUp;
  final bool selected;
  final bool dimmed;
  final bool wild;

  /// Outline colour (e.g. winning cards).
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final h = width * 1.4;
    final c = card;
    Widget face = CustomPaint(
      size: Size(width, h),
      painter: faceUp && c != null ? _FacePainter(c) : const _BackPainter(),
    );
    if (dimmed) {
      face = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.4, 0.4, 0.2, 0, 0, //
          0.4, 0.4, 0.2, 0, 0,
          0.4, 0.4, 0.2, 0, 0,
          0, 0, 0, 0.75, 0,
        ]),
        child: face,
      );
    }
    final glow = highlight ?? (selected ? AuraColors.accentGlow : null);
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: width * 0.12, offset: Offset(0, width * 0.05)),
          if (glow != null) BoxShadow(color: glow.withValues(alpha: 0.75), blurRadius: width * 0.25, spreadRadius: 1),
        ],
        border: glow != null ? Border.all(color: glow, width: math.max(1.5, width * 0.035)) : null,
      ),
      child: Stack(
        children: [
          face,
          if (wild && faceUp)
            Positioned(
              right: width * 0.05,
              bottom: width * 0.05,
              child: Container(
                padding: EdgeInsets.all(width * 0.03),
                decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle),
                child: Icon(Icons.star_rounded, size: width * 0.16, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  const _FacePainter(this.card);
  final PlayingCard card;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(w * 0.1));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF1EDF7)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x22000000),
    );
    if (card.isJoker) {
      _joker(canvas, size);
      return;
    }
    final color = card.suit.red ? _red : _black;
    // Corner index: rank over a small suit, top-left and (rotated) bottom-right.
    void corner() {
      final tp = TextPainter(
        text: TextSpan(
          text: card.label,
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: color,
            fontSize: w * (card.rank == 10 ? 0.24 : 0.28),
            fontWeight: FontWeight.w800,
            height: 1,
            letterSpacing: card.rank == 10 ? -1 : 0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w * 0.2 - tp.width / 2, w * 0.07));
      drawSuit(canvas, card.suit, Offset(w * 0.2, w * 0.07 + tp.height + w * 0.1), w * 0.16, color);
    }

    corner();
    canvas.save();
    canvas.translate(w, h);
    canvas.rotate(math.pi);
    corner();
    canvas.restore();

    final center = Offset(w / 2, h / 2);
    if (card.rank >= 11) {
      // Court card: a framed panel with the letter and a crown of suits.
      final panel = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: w * 0.5, height: h * 0.56),
        Radius.circular(w * 0.06),
      );
      canvas.drawRRect(panel, Paint()..color = color.withValues(alpha: 0.08));
      canvas.drawRRect(
        panel,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.02
          ..color = color.withValues(alpha: 0.6),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: card.label,
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: color,
            fontSize: w * 0.36,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2 - w * 0.04));
      drawSuit(canvas, card.suit, center - Offset(0, h * 0.18), w * 0.14, color);
    } else {
      // Ace / number: one large suit in the middle.
      drawSuit(canvas, card.suit, center, w * (card.rank == 1 ? 0.5 : 0.38), color);
    }
  }

  void _joker(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Rect.fromLTWH(w * 0.12, h * 0.12, w * 0.76, h * 0.76);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(w * 0.08)),
      Paint()..shader = const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFFB923C)]).createShader(rect),
    );
    final star = Path();
    final c = Offset(w / 2, h * 0.42);
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? w * 0.22 : w * 0.09;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(star..close(), Paint()..color = Colors.white);
    final tp = TextPainter(
      text: TextSpan(
        text: 'JOKER',
        style: TextStyle(color: Colors.white, fontSize: w * 0.15, fontWeight: FontWeight.w900, letterSpacing: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(w / 2 - tp.width / 2, h * 0.66));
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.card != card;
}

/// The card back: deep violet with a diamond lattice and the Aura ring.
class _BackPainter extends CustomPainter {
  const _BackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(w * 0.1));
    canvas.drawRRect(rrect, Paint()..color = Colors.white);
    final inner = rrect.deflate(w * 0.06);
    canvas.drawRRect(
      inner,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4C1D95), Color(0xFF1E1B4B)],
        ).createShader(inner.outerRect),
    );
    canvas.save();
    canvas.clipRRect(inner);
    final lattice = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    final step = w * 0.16;
    for (var x = -h; x < w + h; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + h, h), lattice);
      canvas.drawLine(Offset(x, h), Offset(x + h, 0), lattice);
    }
    canvas.restore();
    final c = Offset(w / 2, h / 2);
    final r = w * 0.2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.3
        ..shader = const SweepGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFFB923C), Color(0xFF8B5CF6)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(c, r * 0.28, Paint()..color = const Color(0xFFEC4899));
  }

  @override
  bool shouldRepaint(_BackPainter old) => false;
}

/// Draws a suit symbol of height [size] centred at [c].
void drawSuit(Canvas canvas, Suit suit, Offset c, double size, Color color) {
  final s = size;
  final paint = Paint()..color = color;
  canvas.save();
  canvas.translate(c.dx, c.dy);
  switch (suit) {
    case Suit.hearts:
      final p = Path()
        ..moveTo(0, s * 0.45)
        ..cubicTo(-s * 0.55, s * 0.05, -s * 0.55, -s * 0.5, 0, -s * 0.2)
        ..cubicTo(s * 0.55, -s * 0.5, s * 0.55, s * 0.05, 0, s * 0.45)
        ..close();
      canvas.drawPath(p, paint);
    case Suit.diamonds:
      final p = Path()
        ..moveTo(0, -s * 0.5)
        ..lineTo(s * 0.38, 0)
        ..lineTo(0, s * 0.5)
        ..lineTo(-s * 0.38, 0)
        ..close();
      canvas.drawPath(p, paint);
    case Suit.spades:
      final p = Path()
        ..moveTo(0, -s * 0.5)
        ..cubicTo(s * 0.55, -s * 0.05, s * 0.55, s * 0.4, 0, s * 0.12)
        ..cubicTo(-s * 0.55, s * 0.4, -s * 0.55, -s * 0.05, 0, -s * 0.5)
        ..close();
      canvas.drawPath(p, paint);
      canvas.drawPath(
        Path()
          ..moveTo(0, s * 0.05)
          ..lineTo(s * 0.14, s * 0.5)
          ..lineTo(-s * 0.14, s * 0.5)
          ..close(),
        paint,
      );
    case Suit.clubs:
      final r = s * 0.2;
      canvas.drawCircle(Offset(0, -s * 0.22), r, paint);
      canvas.drawCircle(Offset(-s * 0.22, s * 0.06), r, paint);
      canvas.drawCircle(Offset(s * 0.22, s * 0.06), r, paint);
      canvas.drawPath(
        Path()
          ..moveTo(0, -s * 0.05)
          ..lineTo(s * 0.13, s * 0.5)
          ..lineTo(-s * 0.13, s * 0.5)
          ..close(),
        paint,
      );
  }
  canvas.restore();
}

/// Practice-chip stack graphic (casino chip): coloured rim with white edge
/// marks and the value on the inlay. Shared by the casino-style games.
class CasinoChip extends StatelessWidget {
  const CasinoChip({super.key, required this.value, required this.size, this.selected = false});
  final int value;
  final double size;
  final bool selected;

  static Color colorFor(int v) => switch (v) {
    >= 1000 => const Color(0xFF111827),
    >= 500 => const Color(0xFF7C3AED),
    >= 100 => const Color(0xFF1D4ED8),
    >= 25 => const Color(0xFF15803D),
    _ => const Color(0xFFDC2626),
  };

  static String labelFor(int v) => v >= 1000 ? '${v ~/ 1000}K' : '$v';

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: selected ? 1.12 : 1,
    duration: const Duration(milliseconds: 150),
    child: CustomPaint(size: Size.square(size), painter: _ChipPainter(value, selected)),
  );
}

class _ChipPainter extends CustomPainter {
  _ChipPainter(this.value, this.selected);
  final int value;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final color = CasinoChip.colorFor(value);
    if (selected) {
      canvas.drawCircle(c, r + 2, Paint()..color = const Color(0xFFFBBF24).withValues(alpha: 0.8)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
    canvas.drawCircle(c + const Offset(0, 1.5), r, Paint()..color = Colors.black45);
    canvas.drawCircle(c, r, Paint()..color = color);
    // Edge spots.
    final spot = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(a);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, -r * 0.82), width: r * 0.32, height: r * 0.2), const Radius.circular(2)),
        spot,
      );
      canvas.restore();
    }
    canvas.drawCircle(
      c,
      r * 0.66,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.6),
    );
    canvas.drawCircle(c, r * 0.58, Paint()..color = Color.lerp(color, Colors.white, 0.12)!);
    final tp = TextPainter(
      text: TextSpan(
        text: CasinoChip.labelFor(value),
        style: TextStyle(
          fontFamily: AuraText.displayFamily,
          color: Colors.white,
          fontSize: r * (value >= 100 && value < 1000 ? 0.5 : 0.6),
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_ChipPainter old) => old.value != value || old.selected != selected;
}
