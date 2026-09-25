import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../widgets/aura.dart';

/// Reset password — 4-step flow: email → code → new password → done.
/// Mirrors the mockup's `isForgot` (fp1..fp4). See docs/VERIFICATION_AUDIT.md §C.4.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  int _step = 0; // 0 email · 1 code · 2 new password · 3 done
  String _code = '';
  bool _obscure = true;
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pw.addListener(() => setState(() {}));
    _pw2.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  void _back() {
    if (_step > 0 && _step < 3) {
      setState(() => _step--);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  int get _strength {
    final p = _pw.text;
    var s = 0;
    if (p.length >= 8) s++;
    if (p.contains(RegExp(r'[0-9]'))) s++;
    if (p.contains(RegExp(r'[A-Z]')) || p.contains(RegExp(r'[^A-Za-z0-9]'))) s++;
    return s;
  }

  bool get _mismatch => _pw2.text.isNotEmpty && _pw.text != _pw2.text;

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: AuraAppBar(showBack: _step != 3, onBack: _back),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          if (_step < 3) _progress(),
          const SizedBox(height: 24),
          switch (_step) {
            0 => _email(),
            1 => _codeStep(),
            2 => _newPassword(),
            _ => _done(),
          },
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _progress() {
    return Row(
      children: List.generate(3, (i) {
        return Expanded(
          child: Container(
            height: 6,
            margin: EdgeInsets.only(right: i == 2 ? 0 : 8),
            decoration: BoxDecoration(
              gradient: i <= _step ? AuraGradients.brand : null,
              color: i <= _step ? null : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }

  Widget _iconTile(IconData icon) => Align(
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
          child: Icon(icon, color: AuraColors.accentGlow, size: 28),
        ),
      );

  Widget _title(String t, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t, style: AuraText.headline.copyWith(fontSize: 30)),
          const SizedBox(height: 8),
          Text(sub, style: AuraText.body.copyWith(color: AuraColors.textSecondary)),
        ],
      );

  // ── Step 0: email ──
  Widget _email() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _iconTile(Icons.vpn_key_outlined),
        const SizedBox(height: 20),
        _title('Reset password', "Enter the email linked to your account and we'll send a 6-digit code."),
        const SizedBox(height: 24),
        const AuraTextField(hint: 'Email address', icon: Icons.mail_outline, keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 20),
        GradientButton(label: 'Send code', onPressed: () => setState(() => _step = 1)),
        const SizedBox(height: 20),
        Center(
          child: Text.rich(
            TextSpan(
              style: const TextStyle(color: AuraColors.textSecondary, fontSize: 13.5),
              children: [
                const TextSpan(text: 'Remembered it? '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: GestureDetector(
                    onTap: () => Navigator.pushReplacementNamed(context, Routes.login),
                    child: const Text('Back to login', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 1: code ──
  Widget _codeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Check your inbox', 'We sent a code to n•••@gmail.com'),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) {
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
              TextSpan(text: "Didn't get it? "),
              TextSpan(text: 'Resend in 0:24', style: TextStyle(color: AuraColors.accentGlow, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _Keypad(
          onDigit: (d) => setState(() { if (_code.length < 6) _code += d; }),
          onBackspace: () => setState(() { if (_code.isNotEmpty) _code = _code.substring(0, _code.length - 1); }),
        ),
        const SizedBox(height: 22),
        GradientButton(label: 'Verify code', onPressed: () => setState(() => _step = 2)),
      ],
    );
  }

  // ── Step 2: new password ──
  Widget _newPassword() {
    const hints = ['Weak', 'Good', 'Strong'];
    final strength = _strength;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('New password', 'Make it at least 8 characters — mix letters and numbers.'),
        const SizedBox(height: 24),
        AuraTextField(
          hint: 'New password',
          icon: Icons.lock_outline,
          controller: _pw,
          obscure: _obscure,
          trailing: IconButton(
            splashRadius: 20,
            icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: AuraColors.textSecondary),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              Expanded(
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    gradient: i < strength ? AuraGradients.brand : null,
                    color: i < strength ? null : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              if (i < 2) const SizedBox(width: 5),
            ],
            const SizedBox(width: 10),
            Text(
              _pw.text.isEmpty ? '' : hints[(strength - 1).clamp(0, 2)],
              style: const TextStyle(color: AuraColors.textSecondary, fontSize: 11.5),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AuraTextField(hint: 'Confirm password', icon: Icons.lock_outline, controller: _pw2, obscure: _obscure),
        if (_mismatch) ...[
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text("Passwords don't match", style: TextStyle(color: AuraColors.dangerText, fontSize: 12.5)),
          ),
        ],
        const SizedBox(height: 20),
        GradientButton(label: 'Save new password', onPressed: () => setState(() => _step = 3)),
      ],
    );
  }

  // ── Step 3: done ──
  Widget _done() {
    return Column(
      children: [
        const SizedBox(height: 40),
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AuraColors.green, Color(0xFF14B8A6)]),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: AuraColors.green.withValues(alpha: 0.6), blurRadius: 40, spreadRadius: -6)],
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 48),
        ),
        const SizedBox(height: 28),
        Text('Password updated', style: AuraText.headline.copyWith(fontSize: 30), textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text(
          "You're all set. Log in with your new password to keep playing.",
          style: AuraText.body.copyWith(color: AuraColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        GradientButton(label: 'Back to login', onPressed: () => Navigator.pushNamedAndRemoveUntil(context, Routes.login, (r) => false)),
      ],
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.digit, required this.active});
  final String digit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final filled = digit.isNotEmpty;
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
      ),
      child: Text(
        digit,
        style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
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
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.9,
      children: keys.map((k) {
        if (k.isEmpty) return const SizedBox.shrink();
        final back = k == '⌫';
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => back ? onBackspace() : onDigit(k),
            child: Container(
              alignment: Alignment.center,
              decoration: AuraGlass.decoration(radius: 16, shadow: false),
              child: back
                  ? const Icon(Icons.backspace_outlined, color: AuraColors.textPrimary, size: 22)
                  : Text(k, style: TextStyle(fontFamily: AuraText.displayFamily, color: AuraColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w700)),
            ),
          ),
        );
      }).toList(),
    );
  }
}
