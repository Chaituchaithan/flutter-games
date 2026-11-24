import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../services/app_exception.dart';
import '../../services/session.dart';
import '../../utils/validators.dart';
import '../../widgets/aura.dart';

/// Forgot password — email → 6-digit code → new password → done. Mirrors the
/// mockup's `isForgot` (fp1..fp4). API: docs/services/01-auth.md §6
/// (`/auth/forgot-password`, `/verify`, `/auth/reset-password`).
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  int _step = 0; // 0 email · 1 code · 2 new password · 3 done
  String _code = '';
  bool _obscure = true;
  bool _busy = false;
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  String? _emailError;
  String? _codeError;
  String? _pwError;

  /// Valid 10 minutes, single use. Memory only — never stored.
  String? _resetToken;
  Duration _codeLife = const Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _pw.addListener(() => setState(() {}));
    _pw2.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
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

  /// Back to step 1 (rate-limited code, dead reset token).
  void _restart(String message) {
    setState(() {
      _step = 0;
      _code = '';
      _resetToken = null;
      _codeError = null;
      _pwError = null;
    });
    showAuraToast(context, message, kind: AuraToastKind.error);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await action();
    } on AppException catch (e) {
      if (mounted) _onError(e);
    } on Object catch (_) {
      if (mounted) showAuraToast(context, 'Something went wrong. Try again.', kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onError(AppException e) {
    switch ((_step, e.code)) {
      case (0, ApiErrorCode.unavailable) || (0, _) when e.statusCode == 503:
        showAuraToast(context, "Password reset isn't available yet. Contact support.", kind: AuraToastKind.error);
      case (0, ApiErrorCode.validation):
        setState(() => _emailError = e.message);
      case (1, ApiErrorCode.badRequest):
        setState(() => _codeError = 'That code is wrong or has expired.');
      case (1, ApiErrorCode.rateLimited):
        _restart('Too many tries. Ask for a new code.');
      case (1, ApiErrorCode.validation):
        setState(() => _codeError = e.message);
      case (2, ApiErrorCode.badRequest):
        _restart('This reset link has expired. Start again.');
      case (2, ApiErrorCode.validation):
        setState(() => _pwError = e.message);
      default:
        showAuraToast(context, e.message, kind: AuraToastKind.error);
    }
  }

  /// Step 1 (also "Resend"): ask for a code.
  Future<void> _sendCode() async {
    final err = Validators.email(_email.text);
    setState(() => _emailError = err);
    if (err != null) return;
    await _run(() async {
      final r = await ref.read(sessionProvider.notifier).requestPasswordReset(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _codeLife = r.expiresIn;
        _codeError = null;
        // Dev servers send the code back (no email provider yet). Debug builds
        // pre-fill it; release builds never use it.
        _code = kDebugMode && r.debugCode != null ? r.debugCode! : '';
        _step = 1;
      });
    });
  }

  /// Step 2: check the code → reset token.
  Future<void> _verifyCode() async {
    final err = Validators.resetCode(_code);
    setState(() => _codeError = err);
    if (err != null) return;
    await _run(() async {
      final token = await ref.read(sessionProvider.notifier).verifyResetCode(email: _email.text.trim(), code: _code);
      if (!mounted) return;
      setState(() {
        _resetToken = token;
        _step = 2;
      });
    });
  }

  /// Step 3: set the new password. Signs out every session (this one too).
  Future<void> _savePassword() async {
    final err = Validators.newPassword(_pw.text) ?? (_pw.text != _pw2.text ? "Passwords don't match" : null);
    setState(() => _pwError = err);
    if (err != null) return;
    final token = _resetToken;
    if (token == null) return _restart('This reset link has expired. Start again.');
    await _run(() async {
      await ref.read(sessionProvider.notifier).resetPassword(resetToken: token, newPassword: _pw.text);
      if (!mounted) return;
      setState(() {
        _resetToken = null;
        _step = 3;
      });
    });
  }

  String get _codeMinutes {
    final m = _codeLife.inMinutes;
    return m == 1 ? '1 minute' : '$m minutes';
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
    return BusyGuard(
      busy: _busy,
      child: AuraScaffold(
        appBar: AuraAppBar(showBack: _step != 3, onBack: _back),
        scroll: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            if (_step < 3) _progress(),
            const SizedBox(height: 24),
            switch (_step) {
              0 => _emailStep(),
              1 => _codeStep(),
              2 => _newPassword(),
              _ => _done(),
            },
            const SizedBox(height: 8),
          ],
        ),
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
          colors: [AuraColors.brandPurple.withValues(alpha: 0.28), AuraColors.brandPink.withValues(alpha: 0.18)],
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
  Widget _emailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _iconTile(Icons.vpn_key_outlined),
        const SizedBox(height: 20),
        _title('Reset password', "Enter the email linked to your account and we'll send a 6-digit code."),
        const SizedBox(height: 24),
        AuraTextField(
          hint: 'Email address',
          icon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          controller: _email,
          errorText: _emailError,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _sendCode(),
        ),
        const SizedBox(height: 20),
        GradientButton(label: 'Send code', loading: _busy, onPressed: _sendCode),
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
                    // Login is underneath: go back to it, not a second copy.
                    onTap: () => Navigator.canPop(context)
                        ? Navigator.pop(context)
                        : Navigator.pushReplacementNamed(context, Routes.login),
                    child: const Text(
                      'Back to login',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
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
        _title(
          'Check your inbox',
          "If an account uses ${_email.text.trim()}, we've sent a 6-digit code. It expires in $_codeMinutes.",
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) {
            final filled = i < _code.length;
            final active = i == _code.length;
            return _CodeBox(digit: filled ? _code[i] : '', active: active);
          }),
        ),
        if (_codeError != null) ...[
          const SizedBox(height: 10),
          Text(_codeError!, style: const TextStyle(color: AuraColors.dangerText, fontSize: 12.5)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Text("Didn't get it? ", style: AuraText.cardSub),
            GestureDetector(
              onTap: _busy ? null : _sendCode,
              child: const Text(
                'Resend code',
                style: TextStyle(color: AuraColors.accentGlow, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _Keypad(
          onDigit: (d) => setState(() {
            if (_code.length < 6) _code += d;
            _codeError = null;
          }),
          onBackspace: () => setState(() {
            if (_code.isNotEmpty) _code = _code.substring(0, _code.length - 1);
            _codeError = null;
          }),
        ),
        const SizedBox(height: 22),
        GradientButton(label: 'Verify code', loading: _busy, onPressed: _verifyCode),
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
            icon: Icon(
              _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 20,
              color: AuraColors.textSecondary,
            ),
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
        if (_mismatch || _pwError != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              _pwError ?? "Passwords don't match",
              style: const TextStyle(color: AuraColors.dangerText, fontSize: 12.5),
            ),
          ),
        ],
        const SizedBox(height: 20),
        GradientButton(label: 'Save new password', loading: _busy, onPressed: _savePassword),
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
        Text('Password changed', style: AuraText.headline.copyWith(fontSize: 30), textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text(
          'Log in with your new password. You were signed out on every device.',
          style: AuraText.body.copyWith(color: AuraColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        GradientButton(
          label: 'Back to login',
          onPressed: () => Navigator.pushNamedAndRemoveUntil(
            context,
            Routes.login,
            (r) => false,
            arguments: {'email': _email.text.trim()},
          ),
        ),
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
                  : Text(
                      k,
                      style: TextStyle(
                        fontFamily: AuraText.displayFamily,
                        color: AuraColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
