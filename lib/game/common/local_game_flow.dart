import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Tells a game screen when its page is fully covered by another page (and
/// uncovered again) — e.g. on web, a URL change pushes a new page on top
/// while the game stays mounted underneath, its timers still running.
///
/// Uses [TickerMode]: the navigator switches it off for a route that's
/// hidden behind an opaque page, and leaves it on under dialogs and sheets
/// (the pause menu, a forfeit confirm, a promotion picker), so those don't
/// count as "covered". Call [update] from `didChangeDependencies`; the
/// callbacks run after the frame, never during build.
class CoverWatch {
  bool _covered = false;

  /// The page is hidden behind another page right now.
  bool get covered => _covered;

  void update(State state, {required VoidCallback onCovered, required VoidCallback onUncovered}) {
    final covered = !TickerMode.valuesOf(state.context).enabled;
    if (covered == _covered) return;
    _covered = covered;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Skip if it flipped back before the frame ended, or the screen left.
      if (!state.mounted || _covered != covered) return;
      covered ? onCovered() : onUncovered();
    });
  }
}

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

  final _cover = CoverWatch();

  /// Paused because the page was covered (not by the player).
  bool _pausedWhileCovered = false;

  /// The game ended while covered: show the result once it's visible again.
  bool _resultWaiting = false;

  /// Covered by another page: pause (clocks, computer players, callers),
  /// and hold back the result screen. Uncovered: the pause menu, so the
  /// player picks up deliberately rather than mid-move.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cover.update(
      this,
      onCovered: () {
        if (paused || resigned || _resultShown) return;
        _pausedWhileCovered = true;
        pauseGame();
      },
      onUncovered: () {
        if (_resultWaiting) {
          _resultWaiting = false;
          showResult();
        } else if (_pausedWhileCovered) {
          _pausedWhileCovered = false;
          if (paused && !_resultShown && !resigned) openPause();
        }
      },
    );
  }

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
      if (!mounted) return;
      // Never push the result over a page the player moved on to.
      if (_cover.covered) {
        _resultWaiting = true;
      } else {
        showResult();
      }
    });
  }

  /// Wrap the screen's body: the phone's Back button (or iOS back swipe)
  /// opens the pause menu — Resume or Forfeit — instead of leaving the game.
  Widget guardBack(Widget child) => GameBackGuard(
    active: !_resultShown && !resigned,
    onBack: () {
      if (!paused) openPause();
    },
    child: child,
  );

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

/// While [active], the phone's Back button doesn't leave the screen: it
/// calls [onBack] (games open their pause menu, where Forfeit is the way out).
class GameBackGuard extends StatelessWidget {
  const GameBackGuard({super.key, required this.active, required this.onBack, required this.child});

  final bool active;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !active,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) onBack();
    },
    child: child,
  );
}
