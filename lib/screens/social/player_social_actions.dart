import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../data/models/social.dart';
import '../../services/app_exception.dart';
import '../../services/social_api.dart';
import '../../services/social_store.dart';
import '../../widgets/aura.dart';
import '../../widgets/send_gift_sheet.dart';
import '../../widgets/send_money_sheet.dart';

/// The social buttons on another player's card (docs/services/09-social.md):
/// Add friend → "Request sent"; Accept / Decline when they asked first;
/// for a friend: Challenge, Send gift, Send money (the wallet transfer sheet)
/// and Remove friend; Unblock when blocked. Never shown on your own card.
class PlayerSocialActions extends ConsumerStatefulWidget {
  const PlayerSocialActions({super.key, required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  ConsumerState<PlayerSocialActions> createState() => _PlayerSocialActionsState();
}

class _PlayerSocialActionsState extends ConsumerState<PlayerSocialActions> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() => _run(() async {
        try {
          final rel = await ref.read(friendsProvider.notifier).add(widget.userId);
          if (!mounted) return;
          showAuraToast(
            context,
            rel == FriendRelation.friend ? "You're now friends with ${widget.name}" : 'Friend request sent to ${widget.name}',
            kind: AuraToastKind.success,
          );
        } on AppException catch (e) {
          if (mounted) showAuraToast(context, socialErrorText(e, SocialOp.friendRequest), kind: AuraToastKind.info);
        }
      });

  Future<void> _answer({required bool accept}) => _run(() async {
        final r = ref.read(friendsProvider).value?.incomingFrom(widget.userId);
        if (r == null) return;
        try {
          final n = ref.read(friendsProvider.notifier);
          accept ? await n.accept(r) : await n.decline(r);
          if (mounted) {
            showAuraToast(context, accept ? "You're now friends with ${widget.name}" : 'Request declined',
                kind: accept ? AuraToastKind.success : AuraToastKind.info);
          }
        } on AppException catch (e) {
          if (mounted) showAuraToast(context, socialErrorText(e, SocialOp.answerRequest), kind: AuraToastKind.error);
        }
      });

  Future<void> _remove() async {
    final ok = await showAuraDialog(
      context,
      icon: Icons.person_remove_rounded,
      title: 'Remove ${widget.name} from friends?',
      body: 'Either of you can send a new request later.',
      primaryLabel: 'Remove',
      secondaryLabel: 'Cancel',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      try {
        await ref.read(friendsProvider.notifier).remove(widget.userId);
        if (mounted) showAuraToast(context, '${widget.name} removed from friends');
      } on AppException catch (e) {
        if (mounted) showAuraToast(context, socialErrorText(e, SocialOp.removeFriend), kind: AuraToastKind.error);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rel = ref.watch(friendRelationProvider(widget.userId));
    switch (rel) {
      case FriendRelation.self:
        return const SizedBox.shrink();
      case FriendRelation.blocked:
        return SecondaryButton(
          label: 'Unblock',
          loading: _busy,
          onPressed: () => confirmBlockToggle(context, ref, userId: widget.userId, name: widget.name),
        );
      case FriendRelation.none:
        return GradientButton(label: 'Add friend', loading: _busy, onPressed: _add);
      case FriendRelation.sent:
        return GradientButton(label: 'Request sent', enabled: false, onPressed: () {});
      case FriendRelation.incoming:
        return Row(
          children: [
            Expanded(child: GradientButton(label: 'Accept', loading: _busy, onPressed: () => _answer(accept: true))),
            const SizedBox(width: 12),
            Expanded(child: SecondaryButton(label: 'Decline', onPressed: () => _answer(accept: false))),
          ],
        );
      case FriendRelation.friend:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: GradientButton(
                    label: 'Challenge',
                    onPressed: () => Navigator.pushNamed(context, Routes.playFriends),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SecondaryButton(
                    label: 'Send gift',
                    onPressed: () => showSendGiftSheet(context, recipientId: widget.userId, recipientName: widget.name),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SecondaryButton(
              label: 'Send money',
              onPressed: () => showSendMoneySheet(context, recipientId: widget.userId, recipientName: widget.name),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: _busy ? null : _remove,
                child: const Text('Remove friend', style: TextStyle(color: AuraColors.dangerText)),
              ),
            ),
          ],
        );
    }
  }
}

/// Block or unblock [userId] after a confirm (09-social.md §6). A block also
/// ends the friendship and declines pending requests; an unblock brings
/// neither back. Already blocked / not blocked count as done.
Future<void> confirmBlockToggle(BuildContext context, WidgetRef ref, {required String userId, required String name}) async {
  final blocked = ref.read(blockListProvider).containsKey(userId);
  final ok = await showAuraDialog(
    context,
    icon: Icons.block_rounded,
    title: blocked ? 'Unblock $name?' : 'Block $name?',
    body: blocked
        ? 'You can add each other as friends again.'
        : "You won't see their messages, and you'll stop being friends.",
    primaryLabel: blocked ? 'Unblock' : 'Block',
    secondaryLabel: 'Cancel',
    destructive: !blocked,
  );
  if (ok != true || !context.mounted) return;
  final list = ref.read(blockListProvider.notifier);
  try {
    if (blocked) {
      await list.unblock(userId);
    } else {
      await list.block(userId, card: ref.read(playerNameCacheProvider)[userId] ?? UserCard(userId: userId, username: name));
    }
    if (context.mounted) {
      showAuraToast(context, blocked ? '$name unblocked' : '$name blocked',
          kind: blocked ? AuraToastKind.success : AuraToastKind.info);
    }
  } on AppException catch (e) {
    if (context.mounted) {
      showAuraToast(context, socialErrorText(e, blocked ? SocialOp.unblock : SocialOp.block), kind: AuraToastKind.error);
    }
  }
}
