import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../services/session.dart';
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

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).login(
            email: _email.text.trim(),
            password: _password.text,
          );
      if (mounted) Navigator.pushReplacementNamed(context, Routes.home);
    } on Object catch (_) {
      if (mounted) showAuraToast(context, "Couldn't sign in. Try again.", kind: AuraToastKind.error);
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
          // Logo row: gradient ring + dot, then "Aura".
          Row(
            children: [
              const _AuraLogo(size: 28),
              const SizedBox(width: 10),
              Text(
                'Aura',
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
            onPressed: _signIn,
          ),
          const SizedBox(height: 12),
          LightButton(
            label: 'Continue with Google',
            dark: true,
            leading: const _GoogleG(size: 20),
            onPressed: _signIn,
          ),
          const SizedBox(height: 20),
          const _OrDivider(label: 'or log in with email'),
          const SizedBox(height: 20),
          AuraTextField(
            hint: 'Email address',
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            controller: _email,
          ),
          const SizedBox(height: 14),
          AuraTextField(
            hint: 'Password',
            icon: Icons.lock_outline,
            obscure: _obscure,
            controller: _password,
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
          GradientButton(label: 'Log In', onPressed: _signIn),
          const SizedBox(height: 12),
          SecondaryButton(label: 'Continue as guest', onPressed: _signIn),
          const SizedBox(height: 24),
          Center(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: AuraColors.textSecondary,
                  fontSize: 14,
                ),
                children: [
                  const TextSpan(text: 'New to Aura? '),
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
