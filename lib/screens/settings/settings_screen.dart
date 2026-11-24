import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../widgets/aura.dart';
import '../../app/main_shell.dart';
import '../../app/routes.dart';
import '../store/store_screen.dart';
import '../store/restore_purchases.dart';
import '../../configs/configs.dart';
import '../../services/account_store.dart';
import '../../services/app_prefs.dart';
import '../../services/session.dart';
import 'package:snakeladder/screens/profile/level_up_screen.dart';
import '../onboarding/language_screen.dart';
import '../social/blocked_players_screen.dart';

/// Settings — standalone screen. See docs/DESIGN_SPEC.md.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _sound = true;
  bool _music = true;

  Future<void> _setSound(bool v) async {
    setState(() => _sound = v);
    try {
      await ref.read(accountStoreProvider.notifier).setPreferences({'sound': v});
    } on Object catch (_) {
      if (mounted) setState(() => _sound = !v);
    }
  }

  Future<void> _confirmLogout() async {
    // A guest has no email or password: logging out loses the account.
    if (ref.read(currentUserProvider).isGuest) {
      final save = await showAuraDialog(
        context,
        icon: Icons.warning_amber_rounded,
        title: 'Log out of a guest account?',
        body: "You're playing as a guest. Log out and your progress is lost. Save your progress first?",
        primaryLabel: 'Save your progress',
        secondaryLabel: 'Log out anyway',
        destructive: true,
      );
      if (!mounted || save == null) return;
      if (save) {
        Navigator.pushNamed(context, Routes.register, arguments: {'saveProgress': true});
        return;
      }
      await _logOut();
      return;
    }
    final ok = await showAuraDialog(
      context,
      icon: Icons.logout_rounded,
      title: context.l10n.logOutQuestion,
      body: context.l10n.logOutBody,
      primaryLabel: context.l10n.logOut,
      secondaryLabel: context.l10n.stay,
      destructive: true,
    );
    if (ok == true && mounted) await _logOut();
  }

  /// Log out, then the Welcome screen (Log in · Play as guest · Sign up).
  Future<void> _logOut() async {
    // Capture the navigator first: logging out must always end there, even if
    // this screen was closed while the request was running.
    final nav = Navigator.of(context);
    await ref.read(sessionProvider.notifier).signOut();
    nav.pushNamedAndRemoveUntil(Routes.login, (r) => false);
  }

  /// Debug builds only: the dev server's host (00-conventions.md "Servers").
  Future<void> _editServerHost() async {
    final prefs = ref.read(appPrefsProvider);
    final controller = TextEditingController(text: AppConfig.server.host);
    final host = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server host'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: '192.168.0.235'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Use default')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (host == null || !mounted) return;
    await prefs.set(AppConfig.serverHostPrefKey, host);
    if (!mounted) return;
    showAuraToast(context, 'Saved. Restart the app to use ${host.isEmpty ? 'the default server' : host}.',
        kind: AuraToastKind.info);
  }

  // ── Demo-state triggers (mockup's DEMO STATES section) ──

  /// Flash the offline banner at the top of the screen for a few seconds.
  void _demoOfflineBanner() {
    final overlay = Overlay.of(context);
    final topInset = MediaQuery.of(context).padding.top;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: topInset + 8,
        left: 16,
        right: 16,
        child: AuraOfflineBanner(onRetry: () => entry.remove()),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      if (entry.mounted) entry.remove();
    });
  }

  void _demoMatchCancelled() => showAuraDialog(
    context,
    icon: Icons.flag_outlined,
    title: 'Match cancelled',
    body: 'Your opponent left before the match started. Your stake has been refunded.',
    primaryLabel: 'OK',
  );

  Future<void> _demoSessionExpired() async {
    await showAuraDialog(
      context,
      icon: Icons.schedule_rounded,
      title: 'Session expired',
      body:
          'For your security you were signed out after a period of inactivity. '
          'Please log in again.',
      primaryLabel: 'Log in again',
    );
    // "Log in again" returns to the Login screen (mockup behaviour).
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, Routes.login, (r) => false);
  }

  void _demoToast() => showAuraToast(context, 'Daily reward is ready to claim!', kind: AuraToastKind.success);

  void _demoLockScreenNotif() => showAuraToast(context, 'ZeroCool challenged you to a match', kind: AuraToastKind.info);

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: AuraAppBar(title: context.l10n.settings),
      scroll: true,
      showGlow: false, // mockup Settings has no backdrop glow
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          // Mockup shopVip: Store tab → VIP.
          _VipBanner(
            onTap: () {
              ref.read(storeTabProvider.notifier).select(3);
              ref.read(mainTabProvider.notifier).select(2);
              Navigator.popUntil(context, ModalRoute.withName(Routes.home));
            },
          ),
          const SizedBox(height: 20),
          SectionHeader(context.l10n.preferences),
          const SizedBox(height: 10),
          _GroupCard(
            children: [
              // Saved with the game preferences (02-profile-and-sessions.md §7).
              _ToggleRow(
                label: context.l10n.soundEffects,
                value: ref.watch(accountStoreProvider)?.preferences.sound ?? _sound,
                onChanged: _setSound,
              ),
              const _RowDivider(),
              _ToggleRow(label: context.l10n.music, value: _music, onChanged: (v) => setState(() => _music = v)),
              const _RowDivider(),
              // Push switch, the seven toggles and quiet hours (10-inbox-and-notifications.md §3).
              _NavRow(
                label: context.l10n.notifications,
                onTap: () => Navigator.pushNamed(context, Routes.notificationSettings),
              ),
              const _RowDivider(),
              _NavRow(label: 'Game settings', onTap: () => Navigator.pushNamed(context, Routes.gameSettings)),
              const _RowDivider(),
              _NavRow(
                label: context.l10n.languageTitle,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      languageLabel(ref.watch(languageProvider)),
                      style: const TextStyle(color: AuraColors.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, color: AuraColors.textSecondary, size: 22),
                  ],
                ),
                // Settings mode: "← Language" header; Continue returns here.
                onTap: () => Navigator.pushNamed(context, Routes.language, arguments: {'fromSettings': true}),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SectionHeader(context.l10n.account),
          const SizedBox(height: 10),
          _GroupCard(
            children: [
              _NavRow(label: context.l10n.editProfile, onTap: () => Navigator.pushNamed(context, Routes.editProfile)),
              const _RowDivider(),
              _NavRow(label: 'Account', onTap: () => Navigator.pushNamed(context, Routes.account)),
              const _RowDivider(),
              _NavRow(label: 'Privacy', onTap: () => Navigator.pushNamed(context, Routes.privacy)),
              const _RowDivider(),
              _NavRow(label: 'Addresses', onTap: () => Navigator.pushNamed(context, Routes.addresses)),
              const _RowDivider(),
              _NavRow(label: 'Signed-in devices', onTap: () => Navigator.pushNamed(context, Routes.sessions)),
              const _RowDivider(),
              // Guests have no email or password: offer to save the account.
              if (ref.watch(currentUserProvider).isGuest) ...[
                _NavRow(
                  label: 'Save your progress',
                  onTap: () => Navigator.pushNamed(context, Routes.register, arguments: {'saveProgress': true}),
                ),
                const _RowDivider(),
              ] else ...[
                _NavRow(label: context.l10n.changePassword, onTap: () => Navigator.pushNamed(context, Routes.changePassword)),
                const _RowDivider(),
                if (ref.watch(sessionProvider) != null && !ref.watch(currentUserProvider).emailVerified) ...[
                  _NavRow(label: 'Verify email', onTap: () => Navigator.pushNamed(context, Routes.otp)),
                  const _RowDivider(),
                ],
              ],
              _NavRow(label: context.l10n.friendsAndBlocked, onTap: () => Navigator.pushNamed(context, Routes.friends)),
              const _RowDivider(),
              _NavRow(
                label: 'Blocked players',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlockedPlayersScreen())),
              ),
              const _RowDivider(),
              _NavRow(label: context.l10n.transactionsReceipts, onTap: () => Navigator.pushNamed(context, Routes.transactions)),
              const _RowDivider(),
              // 11-store.md §3e: everything is owned on the account.
              _NavRow(label: 'Restore purchases', onTap: () => restorePurchasesWithToast(context, ref)),
              const _RowDivider(),
              _NavRow(
                label: context.l10n.inviteFriends,
                onTap: () => Navigator.pushNamed(context, Routes.referral),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Safety (docs/services/12-safety.md): my reports, limits help.
          const SectionHeader('Safety'),
          const SizedBox(height: 10),
          _GroupCard(
            children: [
              _NavRow(label: 'My reports', onTap: () => Navigator.pushNamed(context, Routes.myReports)),
              const _RowDivider(),
              _NavRow(label: 'Responsible gaming', onTap: () => Navigator.pushNamed(context, Routes.responsibleGaming)),
            ],
          ),
          const SizedBox(height: 20),
          SectionHeader(context.l10n.support),
          const SizedBox(height: 10),
          _GroupCard(
            children: [
              _NavRow(
                label: context.l10n.helpCenter,
                onTap: () => showAuraToast(context, context.l10n.helpCenterSoon, kind: AuraToastKind.info),
              ),
              const _RowDivider(),
              _NavRow(
                label: context.l10n.privacyPolicy,
                onTap: () => showAuraToast(context, context.l10n.privacyPolicySoon, kind: AuraToastKind.info),
              ),
              const _RowDivider(),
              _NavRow(label: context.l10n.appVersion, trailingText: '1.0.0'),
            ],
          ),
          // Prototype-only QA shortcuts (in the mockup): debug builds only —
          // a shipped app doesn't expose them.
          if (kDebugMode) ...[
            const SizedBox(height: 20),
            const SectionHeader('Demo states'),
            const SizedBox(height: 10),
            _GroupCard(
              children: [
                _NavRow(label: 'Toggle offline banner', onTap: _demoOfflineBanner),
                const _RowDivider(),
                _NavRow(label: 'Match cancelled dialog', onTap: _demoMatchCancelled),
                const _RowDivider(),
                _NavRow(label: 'Level-up celebration', onTap: () => showLevelUp(context)),
                const _RowDivider(),
                _NavRow(label: 'Session expired dialog', onTap: _demoSessionExpired),
                const _RowDivider(),
                _NavRow(label: 'Toast / snackbar', onTap: _demoToast),
                const _RowDivider(),
                _NavRow(label: 'Lock-screen notifications', onTap: _demoLockScreenNotif),
                const _RowDivider(),
                _NavRow(label: 'Maintenance screen', onTap: () => Navigator.pushNamed(context, Routes.maintenance)),
                const _RowDivider(),
                _NavRow(label: 'Force-update screen', onTap: () => Navigator.pushNamed(context, Routes.forceUpdate)),
                const _RowDivider(),
                _NavRow(label: 'Server', trailingText: AppConfig.server.host, onTap: _editServerHost),
              ],
            ),
          ],
          const SizedBox(height: 20),
          _LogoutRow(onTap: _confirmLogout),
          const SizedBox(height: 12),
          // Guests have no password, so they can't delete (§12): Log out
          // already ends a guest's account.
          if (!ref.watch(currentUserProvider).isGuest)
            Center(
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, Routes.deleteAccount),
                child: const Text('Delete account', style: TextStyle(color: AuraColors.textSecondary, fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }
}

class _VipBanner extends StatelessWidget {
  const _VipBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AuraColors.amber.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AuraColors.amber.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(gradient: AuraGradients.goldCoin, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.workspace_premium, color: Color(0xFF7C2D12), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.upgradeToVip,
                      style: TextStyle(
                        fontFamily: AuraText.displayFamily,
                        color: AuraColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(context.l10n.vipPerks, style: TextStyle(color: AuraColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AuraColors.amber, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: children),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => const Divider(height: 1, thickness: 1, color: AuraColors.cardBorder);
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AuraColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
          AuraToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.label, this.onTap, this.trailingText, this.trailing});
  final String label;
  final VoidCallback? onTap;
  final String? trailingText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final Widget trailingWidget;
    if (trailing != null) {
      trailingWidget = trailing!;
    } else if (trailingText != null) {
      trailingWidget = Text(trailingText!, style: const TextStyle(color: AuraColors.textSecondary, fontSize: 14));
    } else {
      trailingWidget = const Icon(Icons.chevron_right, color: AuraColors.textSecondary, size: 22);
    }
    final row = SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AuraColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
          trailingWidget,
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

class _LogoutRow extends StatelessWidget {
  const _LogoutRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AuraRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AuraRadii.md),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AuraColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AuraRadii.md),
              border: Border.all(color: AuraColors.dangerText.withValues(alpha: 0.4)),
            ),
            child: Text(
              context.l10n.logOut,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: AuraColors.dangerText,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
