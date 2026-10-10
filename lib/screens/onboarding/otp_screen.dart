import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';

/// OTP — verify email. Verifying establishes the session. See docs/DESIGN_SPEC.md.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const _length = 6;
  String _code = '482'; // Prefilled for show.

  bool _busy = false;

  Future<void> _verify() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).verifyOtp(_code);
    } on Object catch (_) {
      /* static phase never throws */
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (ModalRoute.of(context)?.isCurrent != false) Navigator.pushReplacementNamed(context, Routes.welcomeBonus);
  }

  void _append(String digit) {
    if (_code.length >= _length) return;
    setState(() => _code += digit);
  }

  void _backspace() {
    if (_code.isEmpty) return;
    setState(() => _code = _code.substring(0, _code.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return BusyGuard(
      busy: _busy,
      child: AuraScaffold(
        appBar: const AuraAppBar(showBack: true),
        scroll: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AuraColors.brandPurple.withValues(alpha: 0.28),
                      AuraColors.brandPink.withValues(alpha: 0.18),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AuraColors.accentGlow.withValues(alpha: 0.4)),
                ),
                child: const Icon(Icons.mail_outline, color: AuraColors.accentGlow, size: 30),
              ),
            ),
            const SizedBox(height: 20),
            Text('Verify your email', style: AuraText.headline.copyWith(fontSize: 30)),
            const SizedBox(height: 8),
            Text(
              'Enter the 6-digit code we just sent to your inbox.',
              style: AuraText.body.copyWith(color: AuraColors.textSecondary),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(_length, (i) {
                final filled = i < _code.length;
                final active = i == _code.length;
                return _CodeBox(digit: filled ? _code[i] : '', active: active);
              }),
            ),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(
                style: AuraText.cardSub,
                children: const [
                  TextSpan(text: "Didn't get a code? "),
                  TextSpan(
                    text: 'Resend in 0:24',
                    style: TextStyle(color: AuraColors.accentGlow, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _Keypad(onDigit: _append, onBackspace: _backspace),
            const SizedBox(height: 22),
            GradientButton(label: 'Verify & Continue', onPressed: _verify, loading: _busy),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.digit, required this.active});
  final String digit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bool filled = digit.isNotEmpty;
    return Container(
      width: 46,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? AuraColors.accentGlow.withValues(alpha: 0.08) : AuraColors.field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active
              ? AuraColors.accentGlow
              : (filled ? AuraColors.accentGlow.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.24)),
          width: 1.5,
        ),
        boxShadow: active
            ? [BoxShadow(color: AuraColors.accentGlow.withValues(alpha: 0.18), spreadRadius: 3, blurRadius: 0)]
            : null,
      ),
      child: Text(
        digit,
        style: TextStyle(
          fontFamily: AuraText.displayFamily,
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBackspace});
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    // Keys: 1-9, blank, 0, backspace.
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.9,
      children: keys.map((k) {
        if (k.isEmpty) return const SizedBox.shrink();
        final isBackspace = k == '⌫';
        return _KeypadButton(
          onTap: () => isBackspace ? onBackspace() : onDigit(k),
          child: isBackspace
              ? const Icon(Icons.backspace_outlined, color: AuraColors.textPrimary, size: 22)
              : Text(
                  k,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: AuraColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        );
      }).toList(),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: AuraGlass.decoration(radius: 16, shadow: false),
          child: child,
        ),
      ),
    );
  }
}
