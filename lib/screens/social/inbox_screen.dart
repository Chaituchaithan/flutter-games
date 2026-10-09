import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/main_shell.dart';
import '../../app/routes.dart';
import '../../data/models/inbox_message.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../state/async_view.dart';
import '../../widgets/aura.dart';

/// Inbox — notifications list. Reads via `inboxProvider` (static source today;
/// live API when remote sources are switched on). Read-state (mark read / mark
/// all read) is held locally after load. Mirrors the mockup's `isNotifs`.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  /// Local working copy seeded from the repository; null until first load.
  List<InboxMessage>? _items;

  int get _unread => _items?.where((n) => n.unread).length ?? 0;

  void _markAllRead() {
    if (_items == null) return;
    setState(() => _items = [for (final n in _items!) n.copyWith(unread: false)]);
  }

  void _markRead(int i) {
    setState(() => _items![i] = _items![i].copyWith(unread: false));
  }

  /// Run a notification's call-to-action (Join / Claim / View / Accept / Shop).
  void _runAction(InboxMessage n) {
    switch (n.kind) {
      case InboxKind.invite:
      case InboxKind.friendRequest:
        Navigator.pushNamed(context, Routes.friends);
      case InboxKind.dailyBonus:
        Navigator.pushNamed(context, Routes.dailyRewards);
      case InboxKind.tournament:
        Navigator.pushNamed(context, Routes.tournaments);
      case InboxKind.shop:
        // Store is a shell tab: switch to it, then pop back to the shell.
        ref.read(mainTabProvider.notifier).select(2);
        Navigator.popUntil(context, (r) => r.isFirst);
      case InboxKind.result:
      case InboxKind.announcement:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(inboxProvider);
    // Seed the local working copy once the repository resolves.
    ref.listen(inboxProvider, (_, next) {
      next.whenData((list) {
        if (_items == null) setState(() => _items = List.of(list));
      });
    });
    final items = _items;

    return AuraScaffold(
      appBar: AuraAppBar(
        title: 'Inbox',
        trailing: GestureDetector(
          onTap: _markAllRead,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Mark all read',
              style: TextStyle(color: AuraColors.accentGlow, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
      scroll: true,
      body: items == null
          ? AsyncView<List<InboxMessage>>(
              value: async,
              onRetry: () => ref.invalidate(inboxProvider),
              data: (_) => const SizedBox.shrink(),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),
                if (_unread > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 12),
                    child: Text.rich(
                      TextSpan(
                        style: AuraText.cardSub,
                        children: [
                          TextSpan(
                            text: '$_unread',
                            style: TextStyle(
                              fontFamily: AuraText.displayFamily,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(text: ' unread'),
                        ],
                      ),
                    ),
                  ),
                for (var i = 0; i < items.length; i++) ...[
                  _NotifRow(
                    notif: items[i],
                    onTap: () => _markRead(i),
                    onAction: items[i].action == null
                        ? null
                        : () {
                            _markRead(i);
                            _runAction(items[i]);
                          },
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
              ],
            ),
    );
  }
}

class _NotifRow extends StatelessWidget {
  const _NotifRow({required this.notif, required this.onTap, this.onAction});
  final InboxMessage notif;
  final VoidCallback onTap;

  /// Tapped the CTA pill (Join / Claim / View / Accept / Shop). Null = no CTA.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      onTap: onTap,
      padding: const EdgeInsets.all(13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: notif.gradient,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Icon(notif.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notif.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AuraText.cardTitle.copyWith(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(notif.when, style: AuraText.cardSub.copyWith(fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(notif.body, style: AuraText.cardSub.copyWith(fontSize: 12.5)),
                if (notif.action != null) ...[
                  const SizedBox(height: 9),
                  // Functional CTA pill (mockup style): white-glass chip, tappable.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: onAction,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                          ),
                          child: Text(
                            notif.action!,
                            style: TextStyle(
                              fontFamily: AuraText.displayFamily,
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (notif.unread) ...[
            const SizedBox(width: 8),
            Container(
              margin: const EdgeInsets.only(top: 6),
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: AuraColors.brandPink,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AuraColors.brandPink.withValues(alpha: 0.7), blurRadius: 8),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
