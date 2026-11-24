import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../data/models/account.dart';
import '../../services/account_service.dart';
import '../../services/account_store.dart';
import '../../services/app_exception.dart';
import '../../widgets/aura.dart';
import 'account_widgets.dart';
import '../../services/server_clock.dart';

/// Settings → Signed-in devices (02-profile-and-sessions.md §11): every
/// sign-in with a readable device name, "This device" marked from the access
/// token's `session_id` claim, "Sign out" per other row, and "Sign out
/// everywhere" (this phone too).
class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  List<SignedInSession>? _rows;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await ref.read(accountStoreProvider.notifier).sessions();
      if (mounted) setState(() => _rows = rows);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = accountErrorText(e, AccountOp.session));
    } on Object catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    }
  }

  void _toWelcome() => Navigator.pushNamedAndRemoveUntil(context, Routes.login, (r) => false);

  Future<void> _signOut(SignedInSession s) async {
    final ok = await showAuraDialog(
      context,
      icon: Icons.logout_rounded,
      title: 'Sign out ${s.deviceLabel}?',
      body: 'That device goes back to the sign-in screen.',
      primaryLabel: 'Sign out',
      secondaryLabel: 'Cancel',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final store = ref.read(accountStoreProvider.notifier);
    final own = s.sessionId == store.thisSessionId;
    setState(() => _busy = true);
    try {
      await store.revokeSession(s.sessionId);
      if (!mounted) return;
      if (own) {
        _toWelcome();
        return;
      }
      setState(() => _rows = _rows?.where((r) => r.sessionId != s.sessionId).toList());
      showAuraToast(context, 'Signed out ${s.deviceLabel}', kind: AuraToastKind.success);
      await _load();
    } on AppException catch (e) {
      if (mounted) showAuraToast(context, accountErrorText(e, AccountOp.session), kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOutEverywhere() async {
    final ok = await showAuraDialog(
      context,
      icon: Icons.devices_other_rounded,
      title: 'Sign out everywhere?',
      body: 'This signs you out on every device, including this one.',
      primaryLabel: 'Sign out everywhere',
      secondaryLabel: 'Cancel',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(accountStoreProvider.notifier).signOutEverywhere();
      nav.pushNamedAndRemoveUntil(Routes.login, (r) => false);
    } on AppException catch (e) {
      if (mounted) showAuraToast(context, accountErrorText(e, AccountOp.session), kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _ago(DateTime? t) {
    if (t == null) return '';
    final d = ServerClock.now().difference(t.toLocal());
    // last_active_at only moves on sign-in and refresh: up to ~15 min old.
    if (d.inMinutes < 15) return 'Active recently';
    if (d.inHours < 1) return 'Active about ${d.inMinutes} min ago';
    if (d.inDays < 1) return 'Active about ${d.inHours} h ago';
    return 'Active ${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final thisId = ref.read(accountStoreProvider.notifier).thisSessionId;
    return BusyGuard(
      busy: _busy,
      child: AuraScaffold(
        appBar: const AuraAppBar(title: 'Signed-in devices'),
        scroll: true,
        showGlow: false,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            if (_error != null && rows == null) ...[
              Text(_error!, style: AuraText.cardSub),
              const SizedBox(height: 12),
              SecondaryButton(label: 'Retry', onPressed: _load),
            ] else if (rows == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: AuraColors.accentGlow)),
              )
            else ...[
              SettingsGroup(children: [
                for (final s in rows)
                  SettingsRow(
                    label: s.sessionId == thisId ? '${s.deviceLabel} · This device' : s.deviceLabel,
                    sub: [_ago(s.lastActiveAt), if (s.ipAddress != null) s.ipAddress!].where((e) => e.isNotEmpty).join(' · '),
                    // This phone uses Log out, not Sign out.
                    trailing: s.sessionId == thisId
                        ? const Icon(Icons.smartphone_rounded, color: AuraColors.accentGlow, size: 20)
                        : TextButton(
                            onPressed: () => _signOut(s),
                            child: const Text('Sign out', style: TextStyle(color: AuraColors.dangerText)),
                          ),
                  ),
              ]),
              const SizedBox(height: 24),
              SecondaryButton(label: 'Sign out everywhere', onPressed: _signOutEverywhere),
              const SizedBox(height: 8),
              Text(
                'Signs out every device, including this one.',
                textAlign: TextAlign.center,
                style: AuraText.cardSub.copyWith(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
