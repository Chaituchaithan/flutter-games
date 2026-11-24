import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/inbox_message.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../services/app_exception.dart';
import '../../widgets/aura.dart';
import 'inbox_message_screen.dart';
import '../../services/server_clock.dart';

/// Inbox (docs/services/10-inbox-and-notifications.md): messages (some with
/// tokens or gold to claim) and notifications (short announcements) as two
/// tabs. Both lists are re-read when the screen opens and on pull to
/// refresh; "Load more" pages until `page >= total_pages`.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key, this.initialTab = 0});

  /// 0 Messages · 1 Notifications.
  final int initialTab;

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  late int _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(inboxBadgeProvider.notifier).refresh();
      ref.read(inboxStoreProvider.notifier).reload();
      ref.read(notificationsStoreProvider.notifier).reload().then((_) {
        if (mounted && _tab == 1) ref.read(notificationsStoreProvider.notifier).markSeen();
      });
    });
  }

  void _selectTab(int i) {
    setState(() => _tab = i);
    if (i == 1) ref.read(notificationsStoreProvider.notifier).markSeen();
  }

  Future<void> _openMessage(InboxMessage m) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InboxMessageScreen(message: m)));
  }

  Future<void> _markAllRead() async {
    await ref.read(inboxStoreProvider.notifier).markAllRead();
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxStoreProvider);
    final badge = ref.watch(inboxBadgeProvider);
    final unread = inbox.items.where((m) => !m.isRead).length;
    final notesNew = badge.notificationsNew;

    return AuraScaffold(
      appBar: AuraAppBar(
        title: 'Inbox',
        trailing: _tab == 0 && unread > 0
            ? GestureDetector(
                onTap: _markAllRead,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Mark all read',
                    style: TextStyle(color: AuraColors.accentGlow, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              )
            : null,
      ),
      padding: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(kPageGutter, 4, kPageGutter, 12),
            child: SegmentedTabs(
              labels: [
                unread > 0 ? 'Messages ($unread)' : 'Messages',
                notesNew > 0 && _tab != 1 ? 'Notifications (${badge.notificationsLabel})' : 'Notifications',
              ],
              index: _tab,
              onChanged: _selectTab,
            ),
          ),
          Expanded(
            child: _tab == 0
                ? _PagedView<InboxMessage>(
                    list: inbox,
                    empty: 'No messages yet.',
                    onRefresh: () => Future.wait([
                      ref.read(inboxStoreProvider.notifier).reload(),
                      ref.read(inboxBadgeProvider.notifier).refresh(),
                    ]),
                    onMore: () => ref.read(inboxStoreProvider.notifier).loadMore(),
                    itemBuilder: (m) => _MessageRow(message: m, onTap: () => _openMessage(m)),
                  )
                : _PagedView<PlayerNotification>(
                    list: ref.watch(notificationsStoreProvider),
                    empty: 'No notifications yet.',
                    onRefresh: () async {
                      await ref.read(notificationsStoreProvider.notifier).reload();
                      await ref.read(notificationsStoreProvider.notifier).markSeen();
                    },
                    onMore: () => ref.read(notificationsStoreProvider.notifier).loadMore(),
                    itemBuilder: (n) => _NotificationRow(notification: n),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A pull-to-refresh list with "Load more", an empty state and Retry.
class _PagedView<T> extends StatelessWidget {
  const _PagedView({
    required this.list,
    required this.empty,
    required this.onRefresh,
    required this.onMore,
    required this.itemBuilder,
  });

  final PagedList<T> list;
  final String empty;
  final Future<void> Function() onRefresh;
  final VoidCallback onMore;
  final Widget Function(T) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (!list.loaded) {
      if (list.error != null) {
        children.add(_Message(text: list.error!.message, onRetry: onRefresh));
      } else {
        children.add(const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator(color: AuraColors.accentGlow)),
        ));
      }
    } else if (list.items.isEmpty) {
      children.add(_Message(text: empty));
    } else {
      for (final item in list.items) {
        children
          ..add(itemBuilder(item))
          ..add(const SizedBox(height: 10));
      }
      if (list.error != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(list.error!.message, textAlign: TextAlign.center, style: AuraText.cardSub.copyWith(color: AuraColors.danger)),
        ));
      }
      if (list.hasMore) {
        children.add(SecondaryButton(label: 'Load more', loading: list.loadingMore, onPressed: onMore));
      }
    }
    children.add(const SizedBox(height: 24));
    return RefreshIndicator(
      color: AuraColors.accentGlow,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: kPageGutter),
        children: children,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});
  final String text;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            const Icon(Icons.inbox_outlined, color: AuraColors.textSecondary, size: 40),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: AuraText.cardSub),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              SecondaryButton(label: 'Retry', onPressed: () => onRetry!()),
            ],
          ],
        ),
      );
}

/// "2m", "5h", "Yesterday", "3d", or the date.
String inboxWhen(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  final d = (now ?? ServerClock.now()).difference(at);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays == 1) return 'Yesterday';
  if (d.inDays < 7) return '${d.inDays}d';
  final l = at.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

/// "Expires in 3 days" / "Expires in 5 hours" / "Expired"; null = never.
String? expiryText(DateTime? at, {DateTime? now}) {
  if (at == null) return null;
  final d = at.difference(now ?? ServerClock.now());
  if (d <= Duration.zero) return 'Expired';
  if (d.inDays >= 1) return 'Expires in ${d.inDays} ${d.inDays == 1 ? 'day' : 'days'}';
  if (d.inHours >= 1) return 'Expires in ${d.inHours} ${d.inHours == 1 ? 'hour' : 'hours'}';
  final m = d.inMinutes < 1 ? 1 : d.inMinutes;
  return 'Expires in $m ${m == 1 ? 'minute' : 'minutes'}';
}

/// The message icon: `icon_url` when set (never today), else the default.
class InboxIcon extends StatelessWidget {
  const InboxIcon({super.key, required this.message, this.size = 44});
  final InboxMessage message;
  final double size;

  @override
  Widget build(BuildContext context) {
    final reward = message.hasReward;
    final fallback = Icon(reward ? Icons.card_giftcard : Icons.mail_outline_rounded, color: Colors.white, size: size * 0.45);
    final url = message.iconUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: reward
              ? const [Color(0xFF8B5CF6), Color(0xFFEC4899)]
              : const [AuraColors.brandOrange, AuraColors.brandPink],
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null || !(url.startsWith('http://') || url.startsWith('https://'))
          ? fallback
          : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message, required this.onTap});
  final InboxMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final expiry = expiryText(m.expiresAt);
    return AuraCard(
      onTap: onTap,
      padding: const EdgeInsets.all(13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InboxIcon(message: m),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AuraText.cardTitle.copyWith(
                          fontSize: 14,
                          fontWeight: m.isRead ? FontWeight.w500 : FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(inboxWhen(m.createdAt), style: AuraText.cardSub.copyWith(fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(m.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: AuraText.cardSub.copyWith(fontSize: 12.5)),
                if (m.rewardWaiting() || expiry != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (m.rewardWaiting()) RewardChip(text: m.rewardLabel),
                      if (expiry != null && m.claimedAt == null)
                        Text(expiry, style: AuraText.cardSub.copyWith(fontSize: 11, color: AuraColors.brandOrange)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (!m.isRead) ...[
            const SizedBox(width: 8),
            Container(
              key: const ValueKey('inbox-unread-dot'),
              margin: const EdgeInsets.only(top: 6),
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: AuraColors.brandPink,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AuraColors.brandPink.withValues(alpha: 0.7), blurRadius: 8)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "+500 tokens" on a message with a reward waiting.
class RewardChip extends StatelessWidget {
  const RewardChip({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: AuraGradients.goldCoin,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.black, fontSize: 11.5, fontWeight: FontWeight.w800),
        ),
      );
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification});
  final PlayerNotification notification;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    return AuraCard(
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
                colors: n.forMe
                    ? const [Color(0xFF22D3EE), Color(0xFF6366F1)]
                    : const [AuraColors.brandOrange, AuraColors.brandPink],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Icon(n.forMe ? Icons.person_outline : Icons.campaign, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(n.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AuraText.cardTitle.copyWith(fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    Text(inboxWhen(n.sentAt), style: AuraText.cardSub.copyWith(fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(n.label, style: AuraText.cardSub.copyWith(fontSize: 11, color: AuraColors.accentGlow)),
                const SizedBox(height: 4),
                Text(n.body, style: AuraText.cardSub.copyWith(fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Text for an [AppException] on an inbox screen.
String inboxErrorText(Object e) => e is AppException ? e.message : 'Something went wrong. Try again.';
