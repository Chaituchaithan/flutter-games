import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../services/app_exception.dart';
import '../../services/session.dart';
import '../../services/socket/app_socket.dart';
import '../../services/token_store.dart';
import '../../utils/validators.dart';
import '../../widgets/aura.dart';

/// Login — "Welcome back". Standalone screen (uses AuraScaffold).
/// Signs in via the session/AuthService. See docs/DESIGN_SPEC.md §2.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _obscure = true;
  bool _busy = false;
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
  Future<void> _auth(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The flow is: API login → socket login → Home, and Home is reached ONLY
  /// if the socket authenticates. After auth succeeds we open the realtime
  /// socket with the freshly-issued gateway token and the account's real
  /// username (from /users/me). If the socket can't connect/authenticate
  /// we surface the error and stay on the login screen. (The demo/OAuth path
  /// has no token → no socket → it still proceeds Home.)
  Future<void> _connectSocketThenHome({String? username}) async {
    final token = await ref.read(tokenStoreProvider).readAccess() ?? '';
    // Socket bypassed (kSocketEnabled = false): API login alone reaches Home.
    if (kSocketEnabled && token.isNotEmpty) {
      try {
        await ref.read(appSocketProvider).connect(token: token, username: username);
      } on Object catch (e) {
        if (mounted) showAuraToast(context, "Couldn't reach the game server: $e", kind: AuraToastKind.error);
        return; // strict gating: no Home unless the socket login succeeded
      }
    }
    if (mounted) Navigator.pushReplacementNamed(context, Routes.home);
  }

  void _signIn() {
    if (!_validate()) return;
    _auth(() => ref
        .read(sessionProvider.notifier)
        .login(email: _email.text.trim(), password: _password.text));
  }

  void _guest() => _auth(() => ref.read(sessionProvider.notifier).loginGuest());

  // Real OAuth is stubbed server-side (503). Placeholder: continue into the app
  // (demo session) so the Apple/Google buttons land on Home. When a DEMO_TOKEN
  // is provided at build time, seed a signed-in session so online play works
  // against the local chess relay (no-op otherwise). Swap for a real OAuth
  // sign-in when the backend supports it.
  Future<void> _oauthContinue() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).startDemoSession();
      await _connectSocketThenHome();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
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
                'Chess',
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
          Text(
            'Welcome back',
            style: AuraText.headline.copyWith(fontSize: 32),
          ),
          const SizedBox(height: 8),
          Text(
            'Log in to pick up where you left off.',
            style: AuraText.body.copyWith(color: AuraColors.textSecondary),
          ),
          const SizedBox(height: 24),
          LightButton(
            label: 'Continue with Apple',
            leading: const Icon(Icons.apple, size: 22, color: Colors.black),
            onPressed: _oauthContinue,
          ),
          const SizedBox(height: 12),
          LightButton(
            label: 'Continue with Google',
            dark: true,
            leading: const _GoogleG(size: 20),
            onPressed: _oauthContinue,
          ),
          const SizedBox(height: 20),
          const _OrDivider(label: 'or log in with email'),
          const SizedBox(height: 20),
          AuraTextField(
            hint: 'Email address',
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
            hint: 'Password',
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
              child: const Text(
                'Forgot password?',
                style: TextStyle(
                  color: AuraColors.accentGlow,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          GradientButton(label: 'Log In', onPressed: _signIn, loading: _busy),
          const SizedBox(height: 12),
          SecondaryButton(label: 'Continue as guest', onPressed: _guest),
          const SizedBox(height: 24),
          Center(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: AuraColors.textSecondary,
                  fontSize: 14,
                ),
                children: [
                  const TextSpan(text: 'New to Chess? '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: () => Navigator.pushNamed(context, Routes.register),
                      child: const Text(
                        'Create account',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
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
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: ringRadius),
      -math.pi / 2,
      math.pi * 1.75,
      false,
      ringPaint,
    );

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
          colors: [
            Color(0xFF4285F4),
            Color(0xFF34A853),
            Color(0xFFFBBC05),
            Color(0xFFEA4335),
            Color(0xFF4285F4),
          ],
        ),
      ),
      child: Text(
        'G',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.62,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
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
          child: Text(
            label,
            style: const TextStyle(color: AuraColors.skip, fontSize: 12.5),
          ),
        ),
        const Expanded(child: Divider(color: AuraColors.cardBorder, thickness: 1)),
      ],
    );
  }
}
