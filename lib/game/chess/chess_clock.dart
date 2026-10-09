import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/aura.dart';
import 'chess_controller.dart';
import 'chess_engine.dart';

/// A client-side chess clock: the side to move ticks down. The backend doesn't
/// broadcast clocks yet (SOCKET_HOOKS: "no clocks"), so this is driven locally
/// off the [ChessController]'s turn. [onFlag] fires once when a side hits zero
/// (callers decide the consequence — e.g. resign for the local player online).
///
/// With [perMove] the clock is a per-move limit instead of a game budget: each
/// time the turn passes, the side now to move starts again from [initialMs].
class ChessClock extends ChangeNotifier {
  ChessClock(this.game, {this.initialMs = 30 * 1000, this.onFlag, this.perMove = false, this.handoverMs = 0}) {
    _whiteMs = initialMs;
    _blackMs = initialMs;
    _lastTurn = game.state.turn;
    _lastTick = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  final ChessController game;
  final int initialMs;
  final void Function(PieceColor flagged)? onFlag;

  /// True = [initialMs] is the time allowed for EACH move (resets every turn).
  final bool perMove;
  late PieceColor _lastTurn;

  /// Hand-over buffer: after the turn changes, the new mover's clock holds
  /// for this long (the piece slide + a beat) before it starts counting, so
  /// animation time is never charged to a player.
  final int handoverMs;
  DateTime? _turnChangedAt;

  late int _whiteMs;
  late int _blackMs;
  bool _flagged = false;
  Timer? _timer;
  DateTime? _lastTick;

  int msFor(PieceColor c) => c == PieceColor.white ? _whiteMs : _blackMs;

  bool _paused = false;
  bool get paused => _paused;

  /// Freeze both clocks (pause overlay / forfeit dialog open).
  void pause() => _paused = true;

  /// Unfreeze; time spent paused is not charged to the mover.
  void resume() {
    _paused = false;
    _lastTick = DateTime.now();
  }

  void _tick() {
    if (game.isOver || _paused) {
      _lastTick = DateTime.now();
      return;
    }
    final now = DateTime.now();
    final dt = now.difference(_lastTick ?? now).inMilliseconds;
    _lastTick = now;
    final active = game.state.turn;
    if (active != _lastTurn) {
      _turnChangedAt = now;
      if (perMove) {
        // A move was made: the new mover gets a fresh per-move allowance, and
        // the side that just moved shows full again while it waits.
        _whiteMs = initialMs;
        _blackMs = initialMs;
      }
    }
    _lastTurn = active;
    // Hand-over buffer: hold the new mover's clock until the move has landed.
    final changedAt = _turnChangedAt;
    if (changedAt != null && now.difference(changedAt).inMilliseconds < handoverMs) {
      notifyListeners();
      return;
    }
    if (active == PieceColor.white) {
      _whiteMs = (_whiteMs - dt).clamp(0, initialMs);
    } else {
      _blackMs = (_blackMs - dt).clamp(0, initialMs);
    }
    if (!_flagged && msFor(active) <= 0) {
      _flagged = true;
      onFlag?.call(active);
    }
    notifyListeners();
  }

  /// Restart both clocks (e.g. a new game in the same screen).
  void reset() {
    _whiteMs = initialMs;
    _blackMs = initialMs;
    _flagged = false;
    _lastTurn = game.state.turn;
    _lastTick = DateTime.now();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// A circular countdown ring showing a player's remaining clock (MM:SS in the
/// centre). The arc depletes with time and shifts cyan → gold → red; the active
/// side glows, the idle side is dimmed.
class ClockRing extends StatelessWidget {
  const ClockRing({super.key, required this.ms, required this.totalMs, required this.active, this.size = 46});
  final int ms;
  final int totalMs;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final frac = (ms / totalMs).clamp(0.0, 1.0);
    final secsTotal = (ms / 1000).ceil();
    final mm = secsTotal ~/ 60;
    final ss = secsTotal % 60;
    // Relative thresholds so colour reads the same for any time control.
    final low = ms <= totalMs * 0.2;
    final mid = ms <= totalMs * 0.5;
    final base = low
        ? AuraColors.danger
        : mid
            ? AuraColors.gold
            : AuraColors.accentGlow;
    final ringColor = active ? base : base.withValues(alpha: 0.35);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ClockRingPainter(frac: frac, color: ringColor, active: active),
        child: Center(
          child: Text(
            '$mm:${ss.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.65),
              fontSize: size * 0.27,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClockRingPainter extends CustomPainter {
  _ClockRingPainter({required this.frac, required this.color, required this.active});
  final double frac;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = (Offset.zero & size).center;
    final radius = size.width / 2 - 3;
    // Track.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = Colors.white.withValues(alpha: 0.12),
    );
    // Glow under the active arc.
    if (active) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        frac * 2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
    // Remaining-time arc (starts at 12 o'clock, sweeps clockwise).
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      frac * 2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _ClockRingPainter old) =>
      old.frac != frac || old.color != color || old.active != active;
}
