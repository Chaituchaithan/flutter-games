import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// The game-flow plumbing every local (vs-computer) game screen shares:
/// pause / resume, forfeit with confirmation, and the hand-off to the result
/// screen once the game ends. A game screen mixes this in and implements the
/// hooks; the board, rules and computer moves stay in the game.
mixin LocalGameFlow<T extends StatefulWidget> on State<T> {
  bool paused = false;
  bool resigned = false;
  bool _resultShown = false;
  Timer? _resultTimer;

  /// Pending computer action (cancelled on pause / game over / dispose).
  Timer? botTimer;

  /// "Move 12" etc. for the pause overlay.
  String get pauseSubtitle;

  /// Called when play may continue (after resume): reschedule the computer.
  void onResumeGame();

  /// Navigate to the result screen (game over or forfeit).
  void showResult();

  /// Run [action] after [delay] unless paused, unmounted or [stillValid]
  /// says no. Replaces any pending computer action.
  void scheduleBot(Duration delay, VoidCallback action, {bool Function()? stillValid}) {
    botTimer?.cancel();
    botTimer = Timer(delay, () {
      if (!mounted || paused || resigned || _resultShown) return;
      if (stillValid != null && !stillValid()) return;
      action();
    });
  }

  void pauseGame() {
    paused = true;
    botTimer?.cancel();
  }

  void resumeGame() {
    if (!mounted) return;
    setState(() => paused = false);
    onResumeGame();
  }

  void openPause() =>
      showGamePaused(context, subtitle: pauseSubtitle, onPause: pauseGame, onResume: resumeGame, onForfeit: forfeit);

  /// Confirm, then end as a defeat; "Keep playing" resumes.
  Future<void> forfeit() async {
    pauseGame();
    final ok = await confirmMatchForfeit(context);
    if (!mounted) return;
    if (ok) {
      setState(() => resigned = true);
      endGame(immediate: true);
    } else {
      resumeGame();
    }
  }

  /// Game over: after a beat (let the last move land) show the result once.
  /// [delay] overrides the beat (e.g. a longer win celebration).
  void endGame({bool immediate = false, Duration? delay}) {
    if (_resultShown) return;
    _resultShown = true;
    botTimer?.cancel();
    _resultTimer = Timer(immediate ? Duration.zero : (delay ?? const Duration(milliseconds: 1100)), () {
      if (mounted) showResult();
    });
  }

  /// Call from the screen's dispose.
  void disposeFlow() {
    botTimer?.cancel();
    _resultTimer?.cancel();
  }
}

/// Header for a local game: pause (top-left), title + subtitle, and the
/// 2D/3D board toggle.
class LocalGameHeader extends StatelessWidget {
  const LocalGameHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.live,
    required this.onPause,
    this.perspective = false,
    this.onTogglePerspective,
  });

  final String title;
  final String subtitle;

  /// Game in progress (pause is a no-op once it's over).
  final bool live;
  final VoidCallback onPause;
  final bool perspective;

  /// 2D/3D toggle; null = no toggle (games without a tiltable board).
  final VoidCallback? onTogglePerspective;

  @override
  Widget build(BuildContext context) => GameHeader(
    title: title,
    subtitle: subtitle,
    pot: '0',
    leading: GlassIconButton(icon: Icons.pause_rounded, onTap: live ? onPause : () {}),
    trailing: onTogglePerspective == null
        ? const SizedBox(width: 42) // keeps the title centred; no pot pill
        : GlassIconButton(
            icon: perspective ? Icons.crop_square_rounded : Icons.view_in_ar_outlined,
            iconSize: 18,
            onTap: onTogglePerspective!,
          ),
  );
}
