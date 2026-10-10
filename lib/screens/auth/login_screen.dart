import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/game_socket_login.dart';
import '../../app/routes.dart';
import '../../services/app_exception.dart';
import '../../services/session.dart';
import '../../utils/validators.dart';
import '../../app/app_profile.dart';
import '../../l10n/l10n.dart';
import '../../widgets/aura.dart';

/// Login — "Welcome back". Standalone screen (uses AuraScaffold).
/// Signs in via the session/AuthService. See docs/DESIGN_SPEC.md.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _obscure = true;

  /// The sign-in in flight (null = idle). While set, the whole screen is
  /// locked (BusyGuard) and that button shows the spinner.
  _SignInKind? _pending;
  bool get _busy => _pending != null;
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Validate the email + password fields; returns true when both pass.
  /// The server's /auth/login validates a proper email, so we enforce it here.
  bool _validate() {
    final emailError = Validators.email(_email.text);
    final passwordError = Validators.password(_password.text);
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
    });
    return emailError == null && passwordError == null;
  }

  /// Runs an auth action with a busy guard, surfacing the server's error message.
  /// On success the realtime socket is opened + authenticated (auth.login with
  /// token + username) before landing on Home — see [_connectSocketThenHome].
  Future<void> _auth(_SignInKind kind, Future<void> Function() action) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _pending = kind);
    try {
      await action();
      // Use the signed-in account's real username for the socket identity
      // (fetched via /users/me) instead of a hardcoded one.
      await _connectSocketThenHome(username: ref.read(sessionProvider)?.username);
    } on AppException catch (e) {
      if (mounted) showAuraToast(context, e.message, kind: AuraToastKind.error);
    } on Object catch (_) {
      if (mounted) showAuraToast(context, "Couldn't sign in. Try again.", kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  /// The flow is: API login → socket login → Home, and Home is reached ONLY
  /// if the socket authenticates. After auth succeeds we open the realtime
  /// socket with the freshly-issued gateway token and the account's real
  /// username (from /users/me). If the socket can't connect/authenticate
  /// we surface the error and stay on the login screen. (The demo/OAuth path
  /// has no token → no socket → it still proceeds Home.)
  Future<void> _connectSocketThenHome({String? username}) async {
    try {
      await ref.read(gameSocketLoginProvider).connect(username: username);
    } on Object catch (e) {
      if (mounted) showAuraToast(context, GameSocketLogin.errorText(e), kind: AuraToastKind.error);
      return; // strict gating: no Home unless the socket login succeeded
    }
    if (!mounted) return;
    // Only enter Home from this screen while it is still the one on top —
    // never push Home over a screen the player moved to meanwhile.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    Navigator.pushReplacementNamed(context, Routes.home);
  }

  void _signIn() {
    if (!_validate()) return;
    _auth(
      _SignInKind.email,
      () => ref.read(sessionProvider.notifier).login(email: _email.text.trim(), password: _password.text),
    );
  }

  void _guest() => _auth(_SignInKind.guest, () => ref.read(sessionProvider.notifier).loginGuest());

  // Real OAuth is stubbed server-side (503). Placeholder: the Apple/Google
  // buttons continue into the app signed out. Swap for a real OAuth sign-in
  // when the backend supports it.
  Future<void> _oauthContinue(_SignInKind kind) async {
    if (_busy) return;
    setState(() => _pending = kind);
    try {
      await _connectSocketThenHome();
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BusyGuard(
      busy: _busy,
      child: AuraScaffold(
        appBar: const AuraAppBar(showBack: true),
        glowColor: AuraColors.brandPurple,
        glowAlignment: const Alignment(1.4, -1.1),
        scroll: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            // Logo row: gradient ring + dot, then the app name.
            Row(
              children: [
                const _AuraLogo(size: 28),
                const SizedBox(width: 10),
                Text(
                  AppProfile.current.appName,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: AuraColors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(context.l10n.welcomeBack, style: AuraText.headline.copyWith(fontSize: 32)),
            const SizedBox(height: 8),
            Text(
              context.l10n.loginSubtitle,
              style: AuraText.body.copyWith(color: AuraColors.textSecondary),
            ),
            const SizedBox(height: 24),
            LightButton(
              label: context.l10n.continueWithApple,
              leading: const Icon(Icons.apple, size: 22, color: Colors.black),
              loading: _pending == _SignInKind.apple,
              onPressed: () => _oauthContinue(_SignInKind.apple),
            ),
            const SizedBox(height: 12),
            LightButton(
              label: context.l10n.continueWithGoogle,
              dark: true,
              leading: const _GoogleG(size: 20),
              loading: _pending == _SignInKind.google,
              onPressed: () => _oauthContinue(_SignInKind.google),
            ),
            const SizedBox(height: 20),
            _OrDivider(label: context.l10n.orLogInWithEmail),
            const SizedBox(height: 20),
            AuraTextField(
              hint: context.l10n.emailHint,
              icon: Icons.mail_outline,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              controller: _email,
              errorText: _emailError,
              onChanged: (_) {
                if (_emailError != null) setState(() => _emailError = null);
              },
            ),
            const SizedBox(height: 14),
            AuraTextField(
              hint: context.l10n.passwordHint,
              icon: Icons.lock_outline,
              obscure: _obscure,
              controller: _password,
              errorText: _passwordError,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_passwordError != null) setState(() => _passwordError = null);
              },
              onSubmitted: (_) => _signIn(),
              trailing: IconButton(
                splashRadius: 20,
                icon: Icon(
                  _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                  color: AuraColors.textSecondary,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, Routes.resetPassword),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  context.l10n.forgotPassword,
                  style: const TextStyle(color: AuraColors.accentGlow, fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 14),
            GradientButton(label: context.l10n.logIn, onPressed: _signIn, loading: _pending == _SignInKind.email),
            const SizedBox(height: 12),
            SecondaryButton(label: context.l10n.continueAsGuest, onPressed: _guest, loading: _pending == _SignInKind.guest),
            const SizedBox(height: 24),
            Center(
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(color: AuraColors.textSecondary, fontSize: 14),
                  children: [
                    TextSpan(text: context.l10n.newToApp(AppProfile.current.appName)),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: GestureDetector(
                        onTap: () => Navigator.pushNamed(context, Routes.register),
                        child: Text(
                          context.l10n.createAccount,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Small Aura mark: a brand-gradient ring with a filled centre dot.
class _AuraLogo extends StatelessWidget {
  const _AuraLogo({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _AuraLogoPainter()),
    );
  }
}

class _AuraLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final ringWidth = size.width * 0.16;
    final ringRadius = (size.width - ringWidth) / 2;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round
      ..shader = AuraGradients.brand.createShader(rect);
    // Leave a small gap so the ring reads as an aura arc.
    canvas.drawArc(Rect.fromCircle(center: center, radius: ringRadius), -math.pi / 2, math.pi * 1.75, false, ringPaint);

    final dotPaint = Paint()..shader = AuraGradients.orb.createShader(rect);
    canvas.drawCircle(center, size.width * 0.20, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A simple multicolour "G" mark stand-in for the Google logo.
class _GoogleG extends StatelessWidget {
  const _GoogleG({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335), Color(0xFF4285F4)],
        ),
      ),
      child: Text(
        'G',
        style: TextStyle(color: Colors.white, fontSize: size * 0.62, fontWeight: FontWeight.w800, height: 1),
      ),
    );
  }
}

/// Centered label flanked by thin hairlines.
class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AuraColors.cardBorder, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label, style: const TextStyle(color: AuraColors.skip, fontSize: 12.5)),
        ),
        const Expanded(child: Divider(color: AuraColors.cardBorder, thickness: 1)),
      ],
    );
  }
}

enum _SignInKind { email, guest, apple, google }
