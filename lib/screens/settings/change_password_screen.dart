import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../app/routes.dart';
import '../../services/app_exception.dart';
import '../../services/session.dart';
import '../../utils/validators.dart';
import '../../widgets/aura.dart';

/// Settings → Account → Change password: current password + new password
/// twice. Saves via POST /auth/change-password; the server then signs out
/// every session, so a success sends the player to Log in.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  String? _currentError;
  String? _newError;
  String? _confirmError;
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool _validate() {
    final currentError = Validators.currentPassword(_current.text);
    final newError = Validators.changedPassword(_new.text, current: _current.text);
    final confirmError = Validators.confirmPassword(_confirm.text, password: _new.text);
    setState(() {
      _currentError = currentError;
      _newError = newError;
      _confirmError = confirmError;
    });
    return currentError == null && newError == null && confirmError == null;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(sessionProvider.notifier).changePassword(currentPassword: _current.text, newPassword: _new.text);
      if (!mounted) return;
      await showAuraDialog(
        context,
        icon: Icons.lock_reset_rounded,
        title: context.l10n.passwordChanged,
        body: context.l10n.passwordChangedBody,
        primaryLabel: context.l10n.logInLink,
        tone: AuraDialogTone.success,
      );
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, Routes.login, (r) => false);
    } on AppException catch (e) {
      if (!mounted) return;
      switch (e.statusCode) {
        case 401:
          setState(() => _currentError = context.l10n.currentPasswordWrong);
        case 429:
          showAuraToast(context, context.l10n.tooManyAttempts, kind: AuraToastKind.error);
        default:
          showAuraToast(context, e.message, kind: AuraToastKind.error);
      }
    } on Object catch (_) {
      if (mounted) showAuraToast(context, "Couldn't change your password. Try again.", kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _eye(bool visible, VoidCallback toggle) => IconButton(
    splashRadius: 20,
    icon: Icon(
      visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      size: 20,
      color: AuraColors.textSecondary,
    ),
    onPressed: toggle,
  );

  @override
  Widget build(BuildContext context) {
    return BusyGuard(
      busy: _saving,
      child: AuraScaffold(
        appBar: AuraAppBar(title: context.l10n.changePassword),
        scroll: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Text(context.l10n.changePasswordNote, style: AuraText.cardSub),
            const SizedBox(height: 22),
            SectionHeader(context.l10n.currentPassword),
            const SizedBox(height: 8),
            AuraTextField(
              hint: context.l10n.currentPassword,
              icon: Icons.lock_outline,
              obscure: !_showCurrent,
              controller: _current,
              errorText: _currentError,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_currentError != null) setState(() => _currentError = null);
              },
              trailing: _eye(_showCurrent, () => setState(() => _showCurrent = !_showCurrent)),
            ),
            const SizedBox(height: 20),
            SectionHeader(context.l10n.newPassword),
            const SizedBox(height: 8),
            AuraTextField(
              hint: context.l10n.newPassword,
              icon: Icons.lock_reset_rounded,
              obscure: !_showNew,
              controller: _new,
              errorText: _newError,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_newError != null) setState(() => _newError = null);
              },
              trailing: _eye(_showNew, () => setState(() => _showNew = !_showNew)),
            ),
            const SizedBox(height: 12),
            AuraTextField(
              hint: context.l10n.confirmNewPassword,
              icon: Icons.lock_reset_rounded,
              obscure: !_showConfirm,
              controller: _confirm,
              errorText: _confirmError,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_confirmError != null) setState(() => _confirmError = null);
              },
              onSubmitted: (_) => _save(),
              trailing: _eye(_showConfirm, () => setState(() => _showConfirm = !_showConfirm)),
            ),
            const SizedBox(height: 10),
            Text(context.l10n.passwordRuleHint, style: AuraText.cardSub.copyWith(fontSize: 12)),
            const SizedBox(height: 28),
            GradientButton(label: context.l10n.updatePassword, loading: _saving, onPressed: _save),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
