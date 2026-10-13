import 'package:flutter/material.dart';

/// The chess board's frame as a shared component for every board game:
/// a polished obsidian bezel with a cyan neon edge, a violet/cyan bloom, an
/// inner lip, and a soft glass sheen over the playing surface. The child is
/// clipped to the inner rounded rect; tilt it (3D) inside, as chess does.
class GameBoardFrame extends StatelessWidget {
  const GameBoardFrame({super.key, required this.child});
  final Widget child;

  /// Bezel thickness around the playing surface.
  static const double padding = 8; // same bezel as the chess board

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(padding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1630), Color(0xFF070510)],
        ),
        border: Border.all(color: const Color(0xFF22D3EE).withValues(alpha: 0.30), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 40,
            spreadRadius: -8,
            offset: const Offset(0, 20),
          ),
          // Dual neon bloom — violet below, cyan above.
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.34),
            blurRadius: 40,
            spreadRadius: -2,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: const Color(0xFF22D3EE).withValues(alpha: 0.26),
            blurRadius: 32,
            spreadRadius: -6,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Container(
        // Inner lip between the playing surface and the bezel.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.black.withValues(alpha: 0.45), width: 1),
          boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.06), blurRadius: 1, spreadRadius: 0.5)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              // Glass sheen (never tilted, never intercepts taps).
              const IgnorePointer(child: _Sheen()),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sheen extends StatelessWidget {
  const _Sheen();

  @override
  Widget build(BuildContext context) => DecoratedBox(
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

/// The chess square palette, shared so every board matches.
abstract final class BoardPalette {
  /// Light squares: lavender glass (top-left → bottom-right).
  static const light = [Color(0xFFF2EDFF), Color(0xFFCFC2F0), Color(0xFFB4A3E0)];

  /// Dark squares: deep violet.
  static const dark = [Color(0xFF241D46), Color(0xFF130E29), Color(0xFF070414)];

  /// Label text on light / dark squares.
  static const onLight = Color(0xFF3B3160);
  static const onDark = Color(0xFFEDE7F8);

  /// Playing-surface background.
  static const surface = [Color(0xFF241D46), Color(0xFF0B0819)];
}
