import 'package:flutter/material.dart';

/// A glossy board-game pawn (base, body, collar, ball head) in [color].
/// Drawn upright; the board views billboard it in 3D mode. [highlight] adds a
/// pulsing ring (a movable token); [label] prints a small number on the base.
class PawnView extends StatelessWidget {
  const PawnView({super.key, required this.color, required this.size, this.highlight = 0, this.dim = false});

  final Color color;

  /// Pawn height in logical pixels (width ≈ 0.72 × size).
  final double size;

  /// 0 = none, 0..1 = selection ring strength (animate for a pulse).
  final double highlight;

  /// Faded (e.g. not this player's turn).
  final bool dim;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size * 0.72, size),
    painter: _PawnPainter(color: color, highlight: highlight, dim: dim),
  );
}

class _PawnPainter extends CustomPainter {
  _PawnPainter({required this.color, required this.highlight, required this.dim});
  final Color color;
  final double highlight;
  final bool dim;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final dark = Color.lerp(color, Colors.black, 0.45)!;
    final light = Color.lerp(color, Colors.white, 0.45)!;
    final a = dim ? 0.6 : 1.0;

    // Selection ring on the ground.
    if (highlight > 0) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(w / 2, h * 0.9), width: w * 1.35, height: h * 0.32),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = Colors.white.withValues(alpha: 0.5 + 0.5 * highlight),
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(w / 2, h * 0.9), width: w * 1.5, height: h * 0.38),
        Paint()
          ..color = color.withValues(alpha: 0.35 * highlight)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    // Shadow.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w / 2, h * 0.93), width: w * 0.95, height: h * 0.16),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4 * a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    final bodyShader = LinearGradient(
      colors: [
        light.withValues(alpha: a),
        color.withValues(alpha: a),
        dark.withValues(alpha: a),
      ],
      stops: const [0, 0.45, 1],
    ).createShader(Rect.fromLTWH(0, 0, w, h));

    // Base disk.
    final base = Rect.fromLTWH(w * 0.06, h * 0.78, w * 0.88, h * 0.16);
    canvas.drawOval(base, Paint()..shader = bodyShader);
    canvas.drawRect(Rect.fromLTWH(w * 0.06, h * 0.82, w * 0.88, h * 0.04), Paint()..shader = bodyShader);
    canvas.drawOval(base.translate(0, -h * 0.04), Paint()..color = light.withValues(alpha: 0.9 * a));

    // Body (flared cone).
    final body = Path()
      ..moveTo(w * 0.16, h * 0.82)
      ..quadraticBezierTo(w * 0.3, h * 0.6, w * 0.37, h * 0.4)
      ..lineTo(w * 0.63, h * 0.4)
      ..quadraticBezierTo(w * 0.7, h * 0.6, w * 0.84, h * 0.82)
      ..close();
    canvas.drawPath(body, Paint()..shader = bodyShader);

    // Collar.
    canvas.drawOval(Rect.fromLTWH(w * 0.24, h * 0.36, w * 0.52, h * 0.09), Paint()..shader = bodyShader);

    // Ball head with a specular highlight.
    final headC = Offset(w / 2, h * 0.24);
    final r = w * 0.27;
    canvas.drawCircle(
      headC,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [
            Colors.white.withValues(alpha: a),
            light.withValues(alpha: a),
            color.withValues(alpha: a),
            dark.withValues(alpha: a),
          ],
          stops: const [0, 0.18, 0.55, 1],
        ).createShader(Rect.fromCircle(center: headC, radius: r)),
    );
    // Rim.
    canvas.drawCircle(
      headC,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.black.withValues(alpha: 0.25 * a),
    );
  }

  @override
  bool shouldRepaint(_PawnPainter o) => o.color != color || o.highlight != highlight || o.dim != dim;
}
