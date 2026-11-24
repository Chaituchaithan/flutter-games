import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../services/account_service.dart';
import '../../services/account_store.dart';
import '../../services/app_exception.dart';
import '../../services/wallet_store.dart';
import '../../widgets/aura.dart';
import 'account_widgets.dart';

/// Settings → Delete account (02-profile-and-sessions.md §12): what is lost
/// (with the current balances), then the password. Guests never reach it
/// (no password). After success: every session is gone, cached data is
/// cleared, and the app is on the Welcome screen.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    FocusScope.of(context).unfocus();
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    final ok = await showAuraDialog(
      context,
      icon: Icons.delete_forever_rounded,
      title: 'Delete your account?',
      body: "This can't be undone.",
      primaryLabel: 'Delete account',
      secondaryLabel: 'Cancel',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(accountStoreProvider.notifier).deleteAccount(_password.text);
      nav.pushNamedAndRemoveUntil(Routes.login, (r) => false);
      final ctx = nav.context;
      if (ctx.mounted) showAuraToast(ctx, 'Your account has been deleted.', kind: AuraToastKind.info);
    } on AppException catch (e) {
      if (!mounted) return;
      final text = accountErrorText(e, AccountOp.deleteAccount);
      if (e.code == ApiErrorCode.invalidCredentials || e.isValidation) {
        setState(() => _error = text);
      } else {
        // 409: finish or leave a game or tournament first.
        showAuraToast(context, text, kind: AuraToastKind.error);
      }
    } on Object catch (_) {
      if (mounted) showAuraToast(context, 'Something went wrong. Try again.', kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.remove_circle_outline, size: 16, color: AuraColors.dangerText),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AuraText.body.copyWith(color: AuraColors.textPrimary))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider).value;
    final balance = wallet == null
        ? 'Your token and gold balance'
        : 'Your balance: ${wallet.gems} tokens and ${wallet.gold} gold';
    return BusyGuard(
      busy: _busy,
      child: AuraScaffold(
        appBar: const AuraAppBar(title: 'Delete account'),
        scroll: true,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            Text('Deleting your account signs you out everywhere. You lose:', style: AuraText.cardSub),
            const SizedBox(height: 14),
            _bullet('$balance. Nothing is refunded or paid out.'),
            _bullet('Your level, progress and match history.'),
            _bullet('Avatars and items you bought.'),
            _bullet('Your profile, addresses and devices.'),
            const SizedBox(height: 4),
            Text(
              'Finish or leave any game or tournament first.',
              style: AuraText.cardSub.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 22),
            const SectionHeader('Confirm with your password'),
            const SizedBox(height: 8),
            PasswordField(
              controller: _password,
              hint: 'Password',
              errorText: _error,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 28),
            SettingsGroup(children: [
              SettingsRow(label: 'Delete my account', danger: true, onTap: _busy ? null : _delete),
            ]),
          ],
        ),
      ),
    );
  }
}
