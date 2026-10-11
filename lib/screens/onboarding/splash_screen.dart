import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../app/startup.dart';
import '../../app/app_profile.dart';
import '../../l10n/l10n.dart';
import '../../widgets/aura.dart';

/// Splash — the app's loading screen. Runs the real startup work
/// ([StartupController]: fonts, saved session, game socket, Home data) while
/// showing a breathing orb, a progress bar that follows the actual steps and
/// a status line; then fades into Language (first launch), Home (signed in)
/// or Login. Offline / server problems show a message with Retry.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  bool _navigated = false;
  Timer? _fallback;
  late final AnimationController _orb = AnimationController(vsync: this, duration: const Duration(seconds: 4))
    ..repeat();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(startupProvider.notifier).run();
    });
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _orb.dispose();
    super.dispose();
  }

  void _go(String route) {
    if (_navigated || !mounted) return;
    // Only advance when Splash is actually the visible route — prevents a
    // Splash sitting at the bottom of a deep-linked stack from hijacking nav.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _navigated = true;
    Navigator.pushReplacement(context, Routes.fadeRoute(route));
  }

  @override
  Widget build(BuildContext context) {
    // Done: let the bar fill to 100% (its onEnd navigates); the timer is a
    // fallback in case the animation never reports completion.
    ref.listen<StartupState>(startupProvider, (_, next) {
      final d = next.destination;
      if (d != null) {
        _fallback?.cancel();
        _fallback = Timer(const Duration(milliseconds: 900), () => _go(d));
      }
    });
    final st = ref.watch(startupProvider);
    return AuraScaffold(
      glowColor: AuraColors.accentGlow,
      glowAlignment: Alignment.center,
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Breathing, slowly turning orb.
                  AnimatedBuilder(
                    animation: _orb,
                    builder: (_, child) {
                      final t = _orb.value * 2 * math.pi;
                      return Transform.scale(
                        scale: 1 + 0.035 * math.sin(t * 2),
                        child: Transform.rotate(angle: t / 2, child: child),
                      );
                    },
                    child: const AuraOrb(size: 150),
                  ),
                  const SizedBox(height: 34),
                  Text(
                    AppProfile.current.appName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AuraText.displayFamily,
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 5,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.tagline,
                    style: AuraText.body.copyWith(color: AuraColors.textSecondary, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 44),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: st.error != null ? _error(st) : _progress(st),
            ),
          ),
        ],
      ),
    );
  }

  /// Progress bar that eases to the real progress + the current step.
  Widget _progress(StartupState st) {
    return Column(
      key: const ValueKey('progress'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Container(
              height: 4,
              color: Colors.white.withValues(alpha: 0.12),
              // Done → fill to 100% quickly, then go on (onEnd). While a step
              // runs, creep toward the next checkpoint so the bar never sits
              // still during a slow network call; a finished step jumps it.
              child: TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: 0,
                  end: st.destination != null ? 1.0 : (st.progress + 0.14).clamp(0.0, 0.94),
                ),
                duration: Duration(milliseconds: st.destination != null ? 420 : 2600),
                curve: st.destination != null ? Curves.easeOutCubic : Curves.easeOut,
                onEnd: () {
                  final d = st.destination;
                  if (d != null) Future.delayed(const Duration(milliseconds: 160), () => _go(d));
                },
                builder: (_, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v,
                  child: Container(decoration: const BoxDecoration(gradient: AuraGradients.brand)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 18,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _stepText(context, st.step),
              key: ValueKey(st.step),
              style: AuraText.cardSub.copyWith(fontSize: 12.5),
            ),
          ),
        ),
      ],
    );
  }

  static String _stepText(BuildContext context, StartupStep step) => switch (step) {
    StartupStep.preparing => context.l10n.startupPreparing,
    StartupStep.signingIn => context.l10n.startupSigningIn,
    StartupStep.connecting => context.l10n.startupConnecting,
    StartupStep.loadingProfile => context.l10n.startupLoadingProfile,
    StartupStep.ready => context.l10n.startupReady,
  };

  /// The failure in the player's language (game-server sign-in errors keep
  /// the server's/English text for now).
  static String _failureText(BuildContext context, StartupState st) => switch (st.failure) {
    StartupFailureKind.offline => context.l10n.errOffline,
    StartupFailureKind.slowServer => context.l10n.errSlowServer,
    StartupFailureKind.serverUnreachable => context.l10n.errServerUnreachable,
    StartupFailureKind.slowGameServer => context.l10n.errSlowGameServer,
    _ => st.error ?? '',
  };

  /// Startup stopped: why, plus Retry (and "Log in again" for session issues).
  Widget _error(StartupState st) {
    return Column(
      key: const ValueKey('error'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_rounded, color: AuraColors.amber, size: 30),
        const SizedBox(height: 10),
        Text(
          _failureText(context, st),
          textAlign: TextAlign.center,
          style: AuraText.body.copyWith(color: AuraColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 200,
          child: GradientButton(label: context.l10n.retry, onPressed: () => ref.read(startupProvider.notifier).run()),
        ),
        if (st.canSignOut)
          TextButton(
            onPressed: () => ref.read(startupProvider.notifier).signOutAndContinue(),
            child: Text(
              context.l10n.logInAgain,
              style: const TextStyle(color: AuraColors.accentGlow, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}
