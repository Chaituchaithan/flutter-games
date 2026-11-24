import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/account.dart';
import '../../services/account_service.dart';
import '../../services/account_store.dart';
import '../../services/app_exception.dart';
import '../../widgets/aura.dart';
import 'account_widgets.dart';

/// Settings → Privacy (02-profile-and-sessions.md §6). Each switch saves at
/// once (optimistic, rolled back on error). Rows the server only stores
/// promise no more than "We'll use this setting".
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  static const _storedOnly = "We'll use this setting.";

  @override
  void initState() {
    super.initState();
    ref.read(accountStoreProvider.notifier).ensure();
  }

  Future<void> _set(String key, Object value) async {
    try {
      await ref.read(accountStoreProvider.notifier).setPrivacy({key: value});
    } on AppException catch (e) {
      if (mounted) showAuraToast(context, accountErrorText(e, AccountOp.privacy), kind: AuraToastKind.error);
    } on Object catch (_) {
      if (mounted) showAuraToast(context, 'Something went wrong. Try again.', kind: AuraToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(accountStoreProvider);
    final p = me?.privacy;
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Privacy'),
      scroll: true,
      showGlow: false,
      body: p == null
          ? const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: AuraColors.accentGlow)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),
                const SectionHeader('Who can see my profile'),
                const SizedBox(height: 4),
                Text('Others always see your name and avatar.', style: AuraText.cardSub.copyWith(fontSize: 12)),
                SegmentChoice(
                  options: const {'public': 'Everyone', 'friends': 'Friends', 'private': 'Only me'},
                  selected: p.profileVisibility,
                  onChanged: (v) => _set('profile_visibility', v),
                ),
                const SizedBox(height: 10),
                SettingsGroup(children: [
                  SettingsToggle(
                    label: 'Show me on leaderboards',
                    value: p.showOnLeaderboards,
                    onChanged: (v) => _set('show_on_leaderboards', v),
                  ),
                  SettingsToggle(
                    label: 'Allow friend requests',
                    note: _storedOnly,
                    value: p.allowFriendRequests,
                    onChanged: (v) => _set('allow_friend_requests', v),
                  ),
                  SettingsToggle(
                    label: 'Sign-in alerts',
                    note: _storedOnly,
                    value: p.loginAlerts,
                    onChanged: (v) => _set('login_alerts', v),
                  ),
                ]),
                const SizedBox(height: 20),
                const SectionHeader('Who can message me'),
                const SizedBox(height: 4),
                Text(_storedOnly, style: AuraText.cardSub.copyWith(fontSize: 12)),
                SegmentChoice(
                  options: const {'everyone': 'Everyone', 'friends': 'Friends', 'nobody': 'Nobody'},
                  selected: PrivacySettings.dmOptions.contains(p.dmFrom) ? p.dmFrom : 'everyone',
                  onChanged: (v) => _set('dm_from', v),
                ),
                const SizedBox(height: 20),
                const SectionHeader('News and offers'),
                const SizedBox(height: 10),
                SettingsGroup(children: [
                  SettingsToggle(label: 'Email', value: p.marketingEmail, onChanged: (v) => _set('marketing_email', v)),
                  SettingsToggle(label: 'Push notifications', value: p.marketingPush, onChanged: (v) => _set('marketing_push', v)),
                  SettingsToggle(label: 'SMS', value: p.marketingSms, onChanged: (v) => _set('marketing_sms', v)),
                ]),
              ],
            ),
    );
  }
}
