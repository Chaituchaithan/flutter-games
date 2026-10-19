import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The chess board's frame as a shared component for every board game:
/// a polished obsidian bezel with a cyan neon edge, a violet/cyan bloom, an
/// inner lip, and a soft glass sheen over the playing surface. The child is
/// clipped to the inner rounded rect; tilt it (3D) inside, as chess does.
///
/// [turnColor] (dice games): the border and glow take the colour of the
/// player whose turn it is, cross-fading on each change; [pulse] makes it
/// breathe (your turn). Without it the frame keeps the chess neon.
class GameBoardFrame extends StatefulWidget {
  const GameBoardFrame({super.key, required this.child, this.turnColor, this.pulse = false});
  final Widget child;
  final Color? turnColor;
  final bool pulse;

  /// Bezel thickness around the playing surface.
  static const double padding = 8; // same bezel as the chess board

  @override
  State<GameBoardFrame> createState() => _GameBoardFrameState();
}

class _GameBoardFrameState extends State<GameBoardFrame> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(GameBoardFrame old) {
    super.didUpdateWidget(old);
    if (old.pulse != widget.pulse) _sync();
  }

  void _sync() {
    if (widget.pulse && widget.turnColor != null) {
      _breath.repeat();
    } else {
      _breath
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inner = Container(
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
            widget.child,
            // Glass sheen (never tilted, never intercepts taps).
            const IgnorePointer(child: _Sheen()),
          ],
        ),
      ),
    );
    final turn = widget.turnColor;
    if (turn == null) return _frame(inner, null, 0);
    // Cross-fade to the new player's colour; breathe on your turn.
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: turn),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      builder: (_, color, child) => AnimatedBuilder(
        animation: _breath,
        builder: (_, _) => _frame(child!, color, widget.pulse ? 0.5 + 0.5 * math.sin(_breath.value * 2 * math.pi) : 0),
      ),
      child: inner,
    );
  }

  Widget _frame(Widget child, Color? turn, double breath) {
    return Container(
      padding: const EdgeInsets.all(GameBoardFrame.padding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1630), Color(0xFF070510)],
        ),
        border: Border.all(
          color: turn == null ? const Color(0xFF22D3EE).withValues(alpha: 0.30) : turn.withValues(alpha: 0.55 + 0.2 * breath),
          width: turn == null ? 1.5 : 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 40,
            spreadRadius: -8,
            offset: const Offset(0, 20),
          ),
          if (turn == null) ...[
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
          ] else ...[
            // The current player's glow all around the board.
            BoxShadow(color: turn.withValues(alpha: 0.2 + 0.1 * breath), blurRadius: 26 + 6 * breath, spreadRadius: -3 + 2 * breath),
            BoxShadow(color: turn.withValues(alpha: 0.12), blurRadius: 10, spreadRadius: -3),
          ],
        ],
      ),
      // The glow breathes every frame on your turn: keep the board in its own
      // layer so it isn't redrawn with it.
      child: RepaintBoundary(child: child),
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
