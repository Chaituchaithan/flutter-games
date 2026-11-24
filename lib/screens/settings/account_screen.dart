import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../data/models/account.dart';
import '../../services/account_service.dart';
import '../../services/account_store.dart';
import '../../services/app_exception.dart';
import '../../widgets/aura.dart';
import 'account_widgets.dart';

/// Settings → Account (02-profile-and-sessions.md §4): username, email and
/// phone. Email and phone ask for the current password. Guests have no
/// password, so they're sent to "Save your progress" instead.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(accountStoreProvider.notifier).ensure();
  }

  Future<void> _edit(AccountField field, Me me) async {
    if (field != AccountField.username && me.isGuest) {
      Navigator.pushNamed(context, Routes.register, arguments: {'saveProgress': true});
      return;
    }
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => EditAccountFieldScreen(field: field, initial: switch (field) {
        AccountField.username => me.username ?? '',
        AccountField.email => me.email ?? '',
        AccountField.phone => me.phone ?? '',
      }),
    ));
    if (changed != true || !mounted) return;
    // A new email keeps the OLD verification time (Known issues 2): offer
    // "Verify email" anyway.
    if (field == AccountField.email) {
      final verify = await showAuraDialog(
        context,
        icon: Icons.mark_email_read_outlined,
        title: 'Email changed',
        body: 'This is now the email you log in with. Verify it so we can reach you.',
        primaryLabel: 'Verify email',
        secondaryLabel: 'Later',
      );
      if (verify == true && mounted) Navigator.pushNamed(context, Routes.otp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(accountStoreProvider);
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Account'),
      scroll: true,
      showGlow: false,
      body: me == null
          ? const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: AuraColors.accentGlow)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),
                SettingsGroup(children: [
                  SettingsRow(
                    label: 'Username',
                    value: me.username == null ? 'Not set' : '@${me.username}',
                    sub: 'Your unique handle. Other players see your display name.',
                    onTap: () => _edit(AccountField.username, me),
                  ),
                  SettingsRow(
                    label: 'Email',
                    value: me.email ?? 'Not set',
                    sub: me.isGuest
                        ? 'Save your progress to add an email.'
                        : (me.emailVerifiedAt == null ? 'Not verified' : 'Verified'),
                    onTap: () => _edit(AccountField.email, me),
                  ),
                  SettingsRow(
                    label: 'Phone',
                    value: me.phone ?? 'Not set',
                    // No phone verification route yet: never offer Verify.
                    sub: me.phone == null ? null : (me.phoneVerifiedAt == null ? 'Not verified' : 'Verified'),
                    onTap: () => _edit(AccountField.phone, me),
                  ),
                ]),
                if (me.createdAt != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Member since ${_date(me.createdAt!)}',
                    textAlign: TextAlign.center,
                    style: AuraText.cardSub.copyWith(fontSize: 12),
                  ),
                ],
              ],
            ),
    );
  }

  static String _date(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final l = d.toLocal();
    return '${l.day} ${m[l.month - 1]} ${l.year}';
  }
}

enum AccountField { username, email, phone }

/// One account field, with the password for email and phone. Pops `true`
/// when saved.
class EditAccountFieldScreen extends ConsumerStatefulWidget {
  const EditAccountFieldScreen({super.key, required this.field, this.initial = ''});
  final AccountField field;
  final String initial;

  @override
  ConsumerState<EditAccountFieldScreen> createState() => _EditAccountFieldScreenState();
}

class _EditAccountFieldScreenState extends ConsumerState<EditAccountFieldScreen> {
  late final _value = TextEditingController(text: widget.initial);
  final _password = TextEditingController();
  String? _valueError;
  String? _passwordError;
  bool _saving = false;

  bool get _needsPassword => widget.field != AccountField.username;

  String get _title => switch (widget.field) {
        AccountField.username => 'Change username',
        AccountField.email => 'Change email',
        AccountField.phone => 'Change phone',
      };

  AccountOp get _op => switch (widget.field) {
        AccountField.username => AccountOp.username,
        AccountField.email => AccountOp.email,
        AccountField.phone => AccountOp.phone,
      };

  @override
  void dispose() {
    _value.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final v = _value.text.trim();
    final err = switch (widget.field) {
      AccountField.username => AccountRules.username(v),
      AccountField.email => AccountRules.email(v),
      AccountField.phone => AccountRules.phone(v),
    };
    final pwErr = _needsPassword && _password.text.isEmpty ? 'Enter your current password to change this.' : null;
    setState(() {
      _valueError = err;
      _passwordError = pwErr;
    });
    if (err != null || pwErr != null) return;
    // Letter case alone is not an email change.
    final same = widget.field == AccountField.email ? v.toLowerCase() == widget.initial.toLowerCase() : v == widget.initial;
    if (same) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(accountStoreProvider.notifier).updateAccount(
            username: widget.field == AccountField.username ? v : null,
            email: widget.field == AccountField.email ? v : null,
            phone: widget.field == AccountField.phone ? v : null,
            currentPassword: _needsPassword ? _password.text : null,
          );
      if (!mounted) return;
      showAuraToast(context, 'Saved', kind: AuraToastKind.success);
      Navigator.pop(context, true);
    } on AppException catch (e) {
      if (!mounted) return;
      final text = accountErrorText(e, _op);
      // 401 INVALID_CREDENTIALS here is a wrong password, not a session end.
      if (e.code == ApiErrorCode.invalidCredentials || e.field == 'current_password') {
        setState(() => _passwordError = text);
      } else if (e.code == ApiErrorCode.conflict || e.isValidation) {
        setState(() => _valueError = text);
      } else {
        showAuraToast(context, text, kind: AuraToastKind.error);
      }
    } on Object catch (_) {
      if (mounted) showAuraToast(context, 'Something went wrong. Try again.', kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (hint, icon, keyboard) = switch (widget.field) {
      AccountField.username => ('Username', Icons.alternate_email_rounded, TextInputType.text),
      AccountField.email => ('Email', Icons.mail_outline, TextInputType.emailAddress),
      AccountField.phone => ('+919876543210', Icons.phone_outlined, TextInputType.phone),
    };
    return BusyGuard(
      busy: _saving,
      child: AuraScaffold(
        appBar: AuraAppBar(title: _title),
        scroll: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Text(
              switch (widget.field) {
                AccountField.username => 'Letters, numbers and _ only, 3 to 32 characters. Your display name stays the same.',
                AccountField.email => 'Your new email becomes your login at once. You stay signed in.',
                AccountField.phone => 'Include the country code, with no spaces.',
              },
              style: AuraText.cardSub,
            ),
            const SizedBox(height: 20),
            AuraTextField(
              hint: hint,
              icon: icon,
              keyboardType: keyboard,
              controller: _value,
              errorText: _valueError,
              onChanged: (_) {
                if (_valueError != null) setState(() => _valueError = null);
              },
            ),
            if (_needsPassword) ...[
              const SizedBox(height: 12),
              PasswordField(
                controller: _password,
                errorText: _passwordError,
                onChanged: (_) {
                  if (_passwordError != null) setState(() => _passwordError = null);
                },
              ),
            ],
            const SizedBox(height: 28),
            GradientButton(label: 'Save', loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
