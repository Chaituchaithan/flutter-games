import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/session_guard.dart';
import '../../services/app_exception.dart';
import '../../services/session.dart';
import '../../utils/validators.dart';
import '../../widgets/aura.dart';

/// Which code this screen checks (01-auth.md §8, §9).
enum OtpMode {
  /// Log in with an email code: POST /otp/login/verify. Pops `true` when
  /// signed in (the caller then opens the socket and Home).
  login,

  /// Verify the signed-in account's email: POST /otp/verify. Pops `true`
  /// when verified.
  verifyEmail,
}

/// 6-digit code entry. The code was already sent by the caller (login) or is
/// sent when this screen opens (verify email).
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, this.mode = OtpMode.verifyEmail, this.email, this.minutes = 10});

  final OtpMode mode;

  /// Login mode: the email the code was sent to.
  final String? email;

  /// How long the code is valid (from the send reply).
  final int minutes;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const _length = 6;
  String _code = '';
  String? _error;
  bool _busy = false;
  late int _minutes = widget.minutes;

  bool get _login => widget.mode == OtpMode.login;

  @override
  void initState() {
    super.initState();
    // Verify email needs a signed-in account: the code goes to its email.
    if (!_login && ref.read(sessionProvider) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send());
    }
  }

  /// Send (or resend) a code. Sending again replaces the earlier code.
  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(sessionProvider.notifier);
      final life = _login ? await session.sendLoginCode(widget.email!) : await session.sendEmailVerifyCode();
      if (mounted) setState(() => _minutes = life.inMinutes);
    } on AppException catch (e) {
      if (mounted) _show(e);
    } on Object catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy) return;
    final invalid = Validators.resetCode(_code);
    if (invalid != null) return setState(() => _error = invalid);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(sessionProvider.notifier);
      if (_login) {
        await session.loginWithCode(email: widget.email!, code: _code);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      // A wrong code is still a 200 ({"verified": false}).
      if (await session.verifyEmail(_code)) {
        if (!mounted) return;
        showAuraToast(context, 'Email verified.', kind: AuraToastKind.success);
        Navigator.of(context).pop(true);
        return;
      }
      if (mounted) setState(() => _error = 'That code is wrong.');
    } on AppException catch (e) {
      if (mounted) _show(e);
    } on Object catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(AppException e) {
    if (_login && handleSignInBlock(e)) return; // ban / region: full screen
    setState(() {
      _error = switch (e.code) {
        ApiErrorCode.invalidCredentials => 'That code is wrong or has expired.',
        ApiErrorCode.notFound => 'That code has expired. Send a new one.',
        ApiErrorCode.rateLimited => _login ? 'Too many tries. Ask for a new code.' : 'Too many tries. Send a new code later.',
        _ when e.statusCode == 503 => _login ? "Code login isn't available yet. Use your password." : "Email codes aren't available yet.",
        _ => e.message,
      };
      if (e.isRateLimited) _code = '';
    });
    // Too many wrong tries deletes the code: back to "send a code".
    if (_login && e.isRateLimited) Navigator.of(context).pop(false);
  }

  void _append(String digit) {
    if (_code.length >= _length) return;
    setState(() {
      _code += digit;
      _error = null;
    });
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
            Text(_login ? 'Check your inbox' : 'Verify your email', style: AuraText.headline.copyWith(fontSize: 30)),
            const SizedBox(height: 8),
            Text(
              _login
                  ? "If an account uses ${widget.email}, we've sent a 6-digit code. It expires in $_minutes minutes."
                  : "We've sent a 6-digit code to your account's email. It expires in $_minutes minutes.",
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
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: AuraColors.dangerText, fontSize: 12.5)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Text("Didn't get a code? ", style: AuraText.cardSub),
                GestureDetector(
                  onTap: _busy ? null : _send,
                  child: const Text('Send again', style: TextStyle(color: AuraColors.accentGlow, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _Keypad(onDigit: _append, onBackspace: _backspace),
            const SizedBox(height: 22),
            GradientButton(label: _login ? 'Log in' : 'Verify email', onPressed: _verify, loading: _busy),
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
