import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../widgets/aura.dart';

/// Register — "Create account". Standalone screen. See docs/DESIGN_SPEC.md §3.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  bool _obscure = true;
  bool _agreed = false;

  void _goHome() => Navigator.pushReplacementNamed(context, Routes.home);

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: const AuraAppBar(showBack: true),
      glowColor: AuraColors.brandPink,
      glowAlignment: const Alignment(-1.4, -1.1),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text('Create account', style: AuraText.headline.copyWith(fontSize: 32)),
          const SizedBox(height: 8),
          Text(
            'Join the community in under a minute.',
            style: AuraText.body.copyWith(color: AuraColors.textSecondary),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: LightButton(
                  label: 'Apple',
                  leading: const Icon(Icons.apple, size: 20, color: Colors.black),
                  onPressed: _goHome,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LightButton(
                  label: 'Google',
                  dark: true,
                  leading: const _GoogleG(size: 18),
                  onPressed: _goHome,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _OrDivider(label: 'or sign up with email'),
          const SizedBox(height: 20),
          const AuraTextField(
            hint: 'Full name',
            icon: Icons.person_outline,
            keyboardType: TextInputType.name,
          ),
          const SizedBox(height: 14),
          const AuraTextField(
            hint: 'Email address',
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          AuraTextField(
            hint: 'Create password',
            icon: Icons.lock_outline,
            obscure: _obscure,
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
          const SizedBox(height: 18),
          _TermsRow(
            checked: _agreed,
            onToggle: () => setState(() => _agreed = !_agreed),
          ),
          const SizedBox(height: 18),
          GradientButton(
            label: 'Create Account',
            onPressed: () => Navigator.pushNamed(context, Routes.otp),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: AuraColors.textSecondary,
                  fontSize: 14,
                ),
                children: [
                  const TextSpan(text: 'Already have an account? '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: () =>
                          Navigator.pushReplacementNamed(context, Routes.login),
                      child: const Text(
                        'Log in',
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

/// Tappable checkbox + "I agree to the Terms & Privacy Policy" rich text.
class _TermsRow extends StatelessWidget {
  const _TermsRow({required this.checked, required this.onToggle});
  final bool checked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    const linkStyle = TextStyle(
      color: AuraColors.accentGlow,
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onToggle,
          // Plain Container (not AnimatedContainer): a gradient can't be tweened
          // back to null, which would leave the checked gradient stuck when unchecked.
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: checked ? AuraGradients.orb : null,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: checked ? Colors.transparent : Colors.white.withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
            child: checked
                ? const Icon(Icons.check, size: 15, color: Colors.white)
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: AuraColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.4,
                ),
                children: const [
                  TextSpan(text: 'I agree to the '),
                  TextSpan(text: 'Terms', style: linkStyle),
                  TextSpan(text: ' & '),
                  TextSpan(text: 'Privacy Policy', style: linkStyle),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
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
