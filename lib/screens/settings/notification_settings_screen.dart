import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/inbox_message.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../services/account_store.dart';
import '../../services/app_exception.dart';
import '../../services/inbox_service.dart';
import '../../services/push_service.dart';
import '../../widgets/aura.dart';
import 'account_widgets.dart';

/// Settings → Notifications (10-inbox-and-notifications.md §3, §4): the push
/// switch (this device's push token), the seven toggles, and quiet hours.
/// The server only stores the toggles and quiet hours today, so the screen
/// promises no effect. Each change PATCHes only that field and rolls back on
/// an error.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> with WidgetsBindingObserver {
  static const _storedOnly = "We'll use these settings when notifications are sent.";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(pushControllerProvider.notifier).recheckPermission();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the system settings: the OS permission may have changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.read(pushControllerProvider.notifier).recheckPermission();
  }

  void _error(Object e) {
    if (!mounted) return;
    showAuraToast(context, e is AppException ? preferencesErrorText(e) : inboxGenericText, kind: AuraToastKind.error);
  }

  Future<void> _change(Map<String, Object?> changes) async {
    try {
      await ref.read(notificationPrefsProvider.notifier).change(changes);
    } on Object catch (e) {
      _error(e);
    }
  }

  Future<void> _quietHours(bool on, NotificationPreferences p) async {
    try {
      await ref.read(notificationPrefsProvider.notifier).setQuietHours(
            on: on,
            start: p.quietHoursStart ?? '22:00:00',
            end: p.quietHoursEnd ?? '07:00:00',
            timezone: p.timezone ?? guessTimeZone(profileZone: ref.read(accountStoreProvider)?.timezone),
          );
    } on Object catch (e) {
      _error(e);
    }
  }

  Future<void> _pickTime(String key, String? current) async {
    final (h, m) = parseQuietTime(current) ?? (key == 'quiet_hours_start' ? (22, 0) : (7, 0));
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: h, minute: m));
    if (picked == null || !mounted) return;
    await _change({key: quietTimeWire(picked.hour, picked.minute)});
  }

  Future<void> _pickZone(String? current) async {
    final zones = [
      if (current != null && !commonTimeZones.contains(current)) current,
      ...commonTimeZones,
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AuraColors.bgBase,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final z in zones)
              ListTile(
                title: Text(z, style: const TextStyle(color: AuraColors.textPrimary)),
                trailing: z == current ? const Icon(Icons.check, color: AuraColors.accentGlow) : null,
                onTap: () => Navigator.of(ctx).pop(z),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == current || !mounted) return;
    await _change({'timezone': picked});
  }

  Future<void> _setPush(bool on) async {
    final s = await ref.read(pushControllerProvider.notifier).setWanted(on);
    if (!mounted) return;
    if (on && s.deniedByOs) {
      showAuraToast(context, "Notifications are off in your phone's settings.", kind: AuraToastKind.info);
    }
  }

  static String _clock(String? wire) {
    final t = parseQuietTime(wire);
    if (t == null) return '--:--';
    return '${t.$1.toString().padLeft(2, '0')}:${t.$2.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationPrefsProvider);
    final push = ref.watch(pushControllerProvider);
    final p = async.value;

    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Notifications'),
      scroll: true,
      showGlow: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          SettingsGroup(children: [
            SettingsToggle(
              label: 'Push notifications',
              note: !push.supported
                  ? "Push notifications aren't available in this version yet."
                  : push.deniedByOs
                      ? "Turned off in your phone's settings."
                      : null,
              value: push.on,
              onChanged: !push.supported || push.busy ? null : _setPush,
            ),
            if (push.deniedByOs)
              SettingsRow(
                label: 'Open system settings',
                onTap: () => ref.read(pushControllerProvider.notifier).openSystemSettings(),
              ),
          ]),
          const SizedBox(height: 20),
          if (p == null)
            async.hasError
                ? Column(
                    children: [
                      Text(
                        async.error is AppException ? (async.error! as AppException).message : inboxGenericText,
                        textAlign: TextAlign.center,
                        style: AuraText.cardSub,
                      ),
                      const SizedBox(height: 12),
                      SecondaryButton(label: 'Retry', onPressed: () => ref.invalidate(notificationPrefsProvider)),
                    ],
                  )
                : const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator(color: AuraColors.accentGlow)),
                  )
          else ...[
            const SectionHeader('Tell me about'),
            const SizedBox(height: 4),
            Text(_storedOnly, style: AuraText.cardSub.copyWith(fontSize: 12)),
            const SizedBox(height: 10),
            SettingsGroup(children: [
              for (final e in NotificationPreferences.toggles.entries)
                SettingsToggle(
                  key: ValueKey('pref-${e.key}'),
                  label: e.value,
                  value: p.toggle(e.key),
                  onChanged: (v) => _change({e.key: v}),
                ),
            ]),
            const SizedBox(height: 20),
            const SectionHeader('Quiet hours'),
            const SizedBox(height: 10),
            SettingsGroup(children: [
              SettingsToggle(
                key: const ValueKey('quiet-hours'),
                label: 'Do not disturb',
                value: p.quietHoursOn,
                onChanged: (v) => _quietHours(v, p),
              ),
              if (p.quietHoursOn) ...[
                SettingsRow(
                  label: 'From',
                  value: _clock(p.quietHoursStart),
                  onTap: () => _pickTime('quiet_hours_start', p.quietHoursStart),
                ),
                SettingsRow(
                  label: 'Until',
                  value: _clock(p.quietHoursEnd),
                  onTap: () => _pickTime('quiet_hours_end', p.quietHoursEnd),
                ),
                SettingsRow(
                  label: 'Time zone',
                  value: p.timezone ?? 'Not set',
                  onTap: () => _pickZone(p.timezone),
                ),
              ],
            ]),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}

/// IANA zones offered in the picker.
const commonTimeZones = [
  'Asia/Kolkata',
  'Asia/Dubai',
  'Asia/Singapore',
  'Asia/Tokyo',
  'Australia/Sydney',
  'Europe/London',
  'Europe/Paris',
  'Europe/Berlin',
  'America/New_York',
  'America/Chicago',
  'America/Los_Angeles',
  'America/Sao_Paulo',
  'UTC',
];

/// The device's IANA zone as best Dart can tell without a time-zone plugin:
/// the profile's zone when set, else a zone with the device's UTC offset.
/// (`flutter_timezone` would give the exact name.)
String guessTimeZone({String? profileZone, Duration? offset}) {
  if (profileZone != null && profileZone.isNotEmpty) return profileZone;
  final o = (offset ?? DateTime.now().timeZoneOffset).inMinutes;
  return switch (o) {
    330 => 'Asia/Kolkata',
    240 => 'Asia/Dubai',
    480 => 'Asia/Singapore',
    540 => 'Asia/Tokyo',
    600 || 660 => 'Australia/Sydney',
    60 || 120 => 'Europe/Paris',
    -300 || -240 => 'America/New_York',
    -360 => 'America/Chicago',
    -480 || -420 => 'America/Los_Angeles',
    -180 => 'America/Sao_Paulo',
    _ => 'UTC',
  };
}
