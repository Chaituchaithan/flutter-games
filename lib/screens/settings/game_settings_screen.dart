import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/configs.dart';
import '../../services/account_service.dart';
import '../../services/account_store.dart';
import '../../services/api_client.dart';
import '../../services/app_exception.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';
import 'account_widgets.dart';

/// Game codes and names for the favourite-game picker (`GET /games`, a plain
/// array). Signed out / demo: none.
final _gameNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final signedIn = ref.watch(sessionProvider.select((u) => u != null));
  if (!signedIn || !ref.watch(useRemoteAuthProvider)) return const {};
  final res = await ref.watch(apiClientProvider).get(ApiEndpoints.games);
  final list = res is List ? res : const [];
  return {
    for (final g in list)
      if (g is Map && g['code'] is String) g['code'] as String: (g['name'] as String?) ?? g['code'] as String,
  };
});

/// Settings → Game settings (02-profile-and-sessions.md §7). Applied on the
/// device; the server stores them so they follow the player to a new phone.
/// Each change saves at once (optimistic, rolled back on error).
class GameSettingsScreen extends ConsumerStatefulWidget {
  const GameSettingsScreen({super.key});

  @override
  ConsumerState<GameSettingsScreen> createState() => _GameSettingsScreenState();
}

class _GameSettingsScreenState extends ConsumerState<GameSettingsScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(accountStoreProvider.notifier).ensure();
  }

  Future<void> _set(String key, Object? value) async {
    try {
      await ref.read(accountStoreProvider.notifier).setPreferences({key: value});
    } on AppException catch (e) {
      if (mounted) showAuraToast(context, accountErrorText(e, AccountOp.preferences), kind: AuraToastKind.error);
    } on Object catch (_) {
      if (mounted) showAuraToast(context, 'Something went wrong. Try again.', kind: AuraToastKind.error);
    }
  }

  Future<void> _pickFavourite(Map<String, String> games, String? current) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AuraColors.bgRaised,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
          children: [
            for (final e in {'': 'None', ...games}.entries)
              ListTile(
                onTap: () => Navigator.pop(ctx, e.key),
                title: Text(e.value, style: AuraText.body.copyWith(color: AuraColors.textPrimary)),
                trailing: (e.key.isEmpty ? current == null : e.key == current)
                    ? const Icon(Icons.check_circle_rounded, color: AuraColors.accentGlow)
                    : null,
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    // null clears it.
    await _set('favourite_game', picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(accountStoreProvider);
    final p = me?.preferences;
    final games = ref.watch(_gameNamesProvider).value ?? const <String, String>{};
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Game settings'),
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
                SettingsGroup(children: [
                  SettingsRow(
                    label: 'Favourite game',
                    value: p.favouriteGame == null ? 'None' : (games[p.favouriteGame] ?? p.favouriteGame),
                    sub: 'Shown first in the lobby.',
                    onTap: games.isEmpty ? null : () => _pickFavourite(games, p.favouriteGame),
                  ),
                ]),
                const SizedBox(height: 20),
                const SectionHeader('Default stake'),
                SegmentChoice(
                  options: const {'gold': 'Gold', 'token': 'Tokens'},
                  selected: p.defaultStakeCurrency == 'token' ? 'token' : 'gold',
                  onChanged: (v) => _set('default_stake_currency', v),
                ),
                SettingsGroup(children: [
                  SettingsToggle(
                    label: 'Remember my last stake',
                    value: p.rememberLastStake,
                    onChanged: (v) => _set('remember_last_stake', v),
                  ),
                ]),
                const SizedBox(height: 20),
                const SectionHeader('At the table'),
                const SizedBox(height: 10),
                SettingsGroup(children: [
                  SettingsToggle(label: 'Sound', value: p.sound, onChanged: (v) => _set('sound', v)),
                  SettingsToggle(label: 'Vibration', value: p.haptics, onChanged: (v) => _set('haptics', v)),
                  SettingsToggle(label: 'Table chat and emotes', value: p.tableChat, onChanged: (v) => _set('table_chat', v)),
                  SettingsToggle(
                    label: 'Colour-blind palette',
                    note: 'High-contrast colours.',
                    value: p.colourBlind,
                    onChanged: (v) => _set('colour_blind', v),
                  ),
                  SettingsToggle(
                    label: 'Reduce motion',
                    note: 'Shorter animations.',
                    value: p.reduceMotion,
                    onChanged: (v) => _set('reduce_motion', v),
                  ),
                ]),
              ],
            ),
    );
  }
}
