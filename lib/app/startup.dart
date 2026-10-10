import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/languages.dart';
import '../data/repositories/daily_bonus_repository.dart';
import '../data/repositories/store_repository.dart';
import '../services/app_exception.dart';
import '../services/app_prefs.dart';
import '../services/session.dart';
import 'game_socket_login.dart';
import 'routes.dart';

/// The startup step running (the splash shows it in the player's language).
enum StartupStep { preparing, signingIn, connecting, loadingProfile, ready }

/// Why startup stopped (translated by the splash; [StartupState.error] keeps
/// the English text / server message).
enum StartupFailureKind { offline, slowServer, serverUnreachable, slowGameServer, gameServer }

/// What the splash shows while the app starts.
class StartupState {
  const StartupState({
    this.progress = 0,
    this.step = StartupStep.preparing,
    this.failure,
    this.message = 'Starting…',
    this.error,
    this.destination,
    this.canSignOut = false,
  });

  /// 0..1 — real progress through the startup steps.
  final double progress;
  final StartupStep step;
  final StartupFailureKind? failure;

  /// English text of [step] (logs / tests).
  final String message;

  /// Set when startup stopped (offline, server down…): the splash shows it
  /// with Retry.
  final String? error;

  /// Where to go when done (a route name).
  final String? destination;

  /// The failure is tied to the saved session — offer "Log in again".
  final bool canSignOut;

  StartupState copyWith({double? progress, StartupStep? step, String? message}) => StartupState(
        progress: progress ?? this.progress,
        step: step ?? this.step,
        message: message ?? this.message,
      );
}

/// Runs the app's startup work behind the splash:
///
/// 1. fonts + on-device preferences (language, first launch done)
/// 2. first launch → Language / intro
/// 3. restore the saved session (refreshing an expired token)
/// 4. sign the game socket in (same as after Login)
/// 5. warm Home's data (wallet, daily bonus)
///
/// Offline / server errors stop with a message and Retry — never a silent
/// hang, and the saved session is kept.
class StartupController extends Notifier<StartupState> {
  /// The splash never just flickers.
  static const minDuration = Duration(milliseconds: 900);
  static const stepTimeout = Duration(seconds: 12);

  bool _running = false;

  @override
  StartupState build() => const StartupState();

  Future<void> run() async {
    if (_running) return;
    _running = true;
    final started = DateTime.now();
    state = const StartupState(progress: 0.05, message: 'Getting things ready…');
    String destination;
    try {
      destination = await _steps();
    } on _StartupFailure catch (f) {
      _running = false;
      state = StartupState(
        progress: state.progress,
        step: state.step,
        message: '',
        error: f.message,
        failure: f.kind,
        canSignOut: f.canSignOut,
      );
      return;
    }
    final wait = minDuration - DateTime.now().difference(started);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    state = StartupState(progress: 1, step: StartupStep.ready, message: 'Ready', destination: destination);
    _running = false;
  }

  /// After a session-related failure: forget the session and go to Login.
  void signOutAndContinue() {
    ref.read(sessionProvider.notifier).forceSignOut();
    state = const StartupState(progress: 1, step: StartupStep.ready, message: 'Ready', destination: Routes.login);
  }

  Future<String> _steps() async {
    // 1 · fonts + preferences.
    final prefs = ref.read(appPrefsProvider);
    await Future.wait<void>([
      GoogleFonts.pendingFonts()
          .timeout(const Duration(seconds: 3), onTimeout: () => const [])
          .catchError((Object _) => const []),
      prefs.language().then((i) {
        if (i != null) ref.read(languageProvider.notifier).restore(i);
      }),
    ]);
    _step(0.2, StartupStep.preparing, 'Getting things ready…');

    // 2 · first launch → language picker + intro.
    if (!await prefs.onboarded()) return Routes.language;

    // 3 · saved session.
    _step(0.35, StartupStep.signingIn, 'Signing you in…');
    final bool signedIn;
    try {
      signedIn = await ref.read(sessionProvider.notifier).restore().timeout(stepTimeout);
    } on TimeoutException {
      throw const _StartupFailure(
        "The server is taking too long to respond. Check your connection and try again.",
        StartupFailureKind.slowServer,
      );
    } on AppException catch (e) {
      throw _StartupFailure(
        e.isOffline
            ? "You're offline. Check your connection and try again."
            : "We couldn't reach the server. Please try again in a moment.",
        e.isOffline ? StartupFailureKind.offline : StartupFailureKind.serverUnreachable,
      );
    }
    if (!signedIn) return Routes.login;

    // 4 · game socket (same gate as Login: Home only when it signs in).
    final socket = ref.read(gameSocketLoginProvider);
    if (socket.applies) {
      _step(0.6, StartupStep.connecting, 'Connecting to game server…');
      try {
        await socket.connect(username: ref.read(sessionProvider)?.username).timeout(stepTimeout);
      } on Object catch (e) {
        throw _StartupFailure(
          e is TimeoutException
              ? "The game server is taking too long to respond. Please try again."
              : GameSocketLogin.errorText(e),
          e is TimeoutException ? StartupFailureKind.slowGameServer : StartupFailureKind.gameServer,
          canSignOut: true,
        );
      }
    }

    // 5 · warm Home's data so it opens filled in (failures are fine — Home
    //     shows its own placeholders and retries).
    _step(0.82, StartupStep.loadingProfile, 'Loading your profile…');
    final keep = [ref.listen(walletProvider, (_, _) {}), ref.listen(dailyBonusStatusProvider, (_, _) {})];
    await Future.wait<void>([
      ref.read(walletProvider.future).then((_) {}, onError: (Object _) {}),
      ref.read(dailyBonusStatusProvider.future).then((_) {}, onError: (Object _) {}),
    ]).timeout(const Duration(seconds: 5), onTimeout: () => const []);
    // Hold the warmed values until Home has subscribed.
    Timer(const Duration(seconds: 5), () {
      for (final k in keep) {
        k.close();
      }
    });
    return Routes.home;
  }

  void _step(double progress, StartupStep step, String message) =>
      state = state.copyWith(progress: progress, step: step, message: message);
}

class _StartupFailure implements Exception {
  const _StartupFailure(this.message, this.kind, {this.canSignOut = false});
  final String message;
  final StartupFailureKind kind;
  final bool canSignOut;
}

final startupProvider = NotifierProvider<StartupController, StartupState>(StartupController.new);
