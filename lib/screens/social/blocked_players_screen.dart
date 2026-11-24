import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/app_exception.dart';
import '../../services/social_api.dart';
import '../../services/social_store.dart';
import '../../widgets/aura.dart';
import '../../widgets/player_avatar.dart';

/// Blocked players (docs/services/09-social.md §6c), with Unblock. An
/// unblock doesn't bring back the friendship; either player may send a new
/// request.
class BlockedPlayersScreen extends ConsumerStatefulWidget {
  const BlockedPlayersScreen({super.key});

  @override
  ConsumerState<BlockedPlayersScreen> createState() => _BlockedPlayersScreenState();
}

class _BlockedPlayersScreenState extends ConsumerState<BlockedPlayersScreen> {
  bool _loading = true;
  AppException? _error;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(blockListProvider.notifier).load();
    } on AppException catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(String id, String name) async {
    setState(() => _busy.add(id));
    try {
      await ref.read(blockListProvider.notifier).unblock(id);
      if (mounted) showAuraToast(context, '$name unblocked', kind: AuraToastKind.success);
    } on AppException catch (e) {
      if (mounted) showAuraToast(context, socialErrorText(e, SocialOp.unblock), kind: AuraToastKind.error);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(blockListProvider).values.toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Blocked players'),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text("Blocked players can't send you friend requests, and their messages and gifts are hidden.",
              style: AuraText.cardSub),
          const SizedBox(height: 16),
          if (_loading && list.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else if (_error != null && list.isEmpty)
            Column(
              children: [
                Text(socialErrorText(_error!, SocialOp.load), style: AuraText.cardSub),
                const SizedBox(height: 10),
                SecondaryButton(label: 'Retry', onPressed: _load),
              ],
            )
          else if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Text("You haven't blocked anyone.",
                  textAlign: TextAlign.center, style: AuraText.body.copyWith(color: AuraColors.textSecondary)),
            )
          else
            for (final b in list) ...[
              AuraCard(
                padding: const EdgeInsets.all(11),
                child: Row(
                  children: [
                    AvatarDisc(
                        glyph: b.card.name.substring(0, 1).toUpperCase(), avatarUrl: b.avatarUrl, name: b.card.name, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(b.card.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.cardTitle.copyWith(fontSize: 14.5)),
                    ),
                    TextButton(
                      onPressed: _busy.contains(b.userId) ? null : () => _unblock(b.userId, b.card.name),
                      child: Text(_busy.contains(b.userId) ? '…' : 'Unblock'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
            ],
        ],
      ),
    );
  }
}
