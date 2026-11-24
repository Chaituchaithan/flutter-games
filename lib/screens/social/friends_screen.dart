import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../data/models/friend.dart';
import '../../data/models/social.dart';
import '../../data/repositories/friends_repository.dart';
import '../../data/repositories/referral_repository.dart';
import '../../services/app_exception.dart';
import '../../services/social_api.dart';
import '../../services/social_store.dart';
import '../../widgets/aura.dart';
import '../../widgets/player_avatar.dart';
import '../system/loading_skeleton_screen.dart';
import 'blocked_players_screen.dart';
import 'gifts_screen.dart';
import 'lobby_chat_screen.dart';
import 'player_profile_screen.dart';

/// Friends & social (docs/services/09-social.md): Friends (online first, then
/// by name, green dot), Requests (incoming, Accept / Decline) and Find (no
/// player search exists on the server: invite code, gifts, lobby chat,
/// blocked players, and demo suggestions offline).
///
/// Re-reads everything on open and on resume; who is online every 30 s while
/// the screen is open and in the foreground. Names come from the
/// [PlayerNameCache] (lists carry ids only).
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  /// Friends-online poll while open (§2b).
  static const onlinePoll = Duration(seconds: 30);

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  int _tab = 0;
  Timer? _poll;
  AppLifecycleListener? _life;

  @override
  void initState() {
    super.initState();
    // Fresh lists on open (the provider may hold an older read).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(friendsProvider).hasValue) ref.read(friendsProvider.notifier).refresh();
    });
    _poll = Timer.periodic(FriendsScreen.onlinePoll, (_) {
      final st = WidgetsBinding.instance.lifecycleState;
      if (mounted && (st == null || st == AppLifecycleState.resumed)) ref.read(friendsProvider.notifier).refreshOnline();
    });
    _life = AppLifecycleListener(onResume: () {
      if (mounted) ref.read(friendsProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _life?.dispose();
    super.dispose();
  }

  String _name(String id) => ref.read(playerNameCacheProvider)[id]?.name ?? 'Player';

  void _openProfile(String userId, {bool online = false}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerProfileScreen(userId: userId, name: _name(userId), online: online),
    ));
  }

  /// Invites go through a private room and its code (Play with Friends).
  void _challenge() => Navigator.pushNamed(context, Routes.playFriends);

  Future<void> _accept(FriendRequest r) async {
    final name = _name(r.fromUserId);
    try {
      await ref.read(friendsProvider.notifier).accept(r);
      if (mounted) showAuraToast(context, "You're now friends with $name", kind: AuraToastKind.success);
    } on AppException catch (e) {
      if (mounted) showAuraToast(context, socialErrorText(e, SocialOp.answerRequest), kind: AuraToastKind.error);
    }
  }

  Future<void> _decline(FriendRequest r) async {
    final name = _name(r.fromUserId);
    try {
      await ref.read(friendsProvider.notifier).decline(r);
      if (mounted) showAuraToast(context, 'Request from $name declined', kind: AuraToastKind.info);
    } on AppException catch (e) {
      if (mounted) showAuraToast(context, socialErrorText(e, SocialOp.answerRequest), kind: AuraToastKind.error);
    }
  }

  Future<void> _addSuggested(Friend f) async {
    final id = f.userId;
    if (id == null) return;
    try {
      await ref.read(friendsProvider.notifier).add(id);
      if (mounted) showAuraToast(context, 'Friend request sent to ${f.name}');
    } on AppException catch (e) {
      if (mounted) showAuraToast(context, socialErrorText(e, SocialOp.friendRequest), kind: AuraToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final names = ref.watch(playerNameCacheProvider);
    final blocked = ref.watch(blockListProvider);
    final s = friends.value;
    final onlineCount = s == null ? 0 : s.friends.where((f) => s.online.contains(f.userId)).length;
    final requests = s?.incomingTotal ?? 0;
    if (s != null) {
      final ids = [for (final f in s.friends) f.userId, for (final r in s.incoming) r.fromUserId];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(playerNameCacheProvider.notifier).ensure(ids);
      });
    }

    return AuraScaffold(
      appBar: AuraAppBar(
        title: 'Friends',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AuraColors.green,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AuraColors.green.withValues(alpha: 0.7), blurRadius: 8)],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$onlineCount online',
              style: const TextStyle(color: AuraColors.green, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          SegmentedTabs(
            labels: ['Friends', requests > 0 ? 'Requests ($requests)' : 'Requests', 'Find'],
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 16),
          switch (_tab) {
            1 => _requestsTab(friends, names, blocked),
            2 => _findTab(),
            _ => _friendsTab(friends, names),
          },
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _friendsTab(AsyncValue<FriendsState> friends, Map<String, UserCard> names) {
    return _AsyncList<FriendLink>(
      value: friends.whenData((s) => s.sorted((id) => names[id]?.name ?? '')),
      onRetry: () => ref.invalidate(friendsProvider),
      emptyLabel: 'No friends yet. Add players from their profile.',
      rowBuilder: (f) {
        final online = friends.value?.online.contains(f.userId) ?? false;
        final card = names[f.userId];
        return _PlayerRow(
          name: card?.name ?? 'Player',
          avatarUrl: card?.avatarUrl,
          online: online,
          status: online ? 'Online' : 'Offline',
          onTap: () => _openProfile(f.userId, online: online),
          trailing: online
              ? _PillButton(label: 'Challenge', primary: true, onTap: _challenge)
              : const Icon(Icons.chevron_right, color: AuraColors.textSecondary, size: 22),
        );
      },
    );
  }

  Widget _requestsTab(AsyncValue<FriendsState> friends, Map<String, UserCard> names, Map<String, BlockedUser> blocked) {
    return _AsyncList<FriendRequest>(
      value: friends.whenData((s) => withoutBlocked(s.incoming, blocked, (r) => r.fromUserId)),
      onRetry: () => ref.invalidate(friendsProvider),
      emptyLabel: 'No pending requests',
      rowBuilder: (r) {
        final card = names[r.fromUserId];
        return _PlayerRow(
          name: card?.name ?? 'Player',
          avatarUrl: card?.avatarUrl,
          online: false,
          status: 'Wants to be friends',
          onTap: () => _openProfile(r.fromUserId),
          trailing: _RequestActions(onAccept: () => _accept(r), onDecline: () => _decline(r)),
        );
      },
    );
  }

  Widget _findTab() {
    final code = ref.watch(referralCodeProvider).value?.code;
    final playersOnline = ref.watch(onlineCountProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Add friends from their profile: tap a player in a game room, a match result or the leaderboard.',
          style: AuraText.cardSub,
        ),
        if (playersOnline != null) ...[
          const SizedBox(height: 6),
          Text('$playersOnline players online', style: AuraText.cardSub.copyWith(color: AuraColors.green)),
        ],
        const SizedBox(height: 12),
        AuraCard(
          onTap: () => Navigator.pushNamed(context, Routes.referral),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AuraColors.brandPurple.withValues(alpha: 0.3),
              AuraColors.brandPink.withValues(alpha: 0.14),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: AuraGradients.orb,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.card_giftcard, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Invite friends', style: AuraText.cardTitle.copyWith(fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(code == null ? 'Share your invite code' : 'Share your code $code',
                        style: AuraText.cardSub.copyWith(fontSize: 11.5)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white, size: 20),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _QuickLink(
                icon: Icons.redeem_rounded,
                label: 'Gifts',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GiftsScreen())),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickLink(
                icon: Icons.forum_rounded,
                label: 'Lobby chat',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LobbyChatScreen())),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickLink(
                icon: Icons.block_rounded,
                label: 'Blocked',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlockedPlayersScreen())),
              ),
            ),
          ],
        ),
        Consumer(builder: (context, ref, _) {
          final suggested = ref.watch(suggestedFriendsProvider);
          if (suggested.value?.isEmpty ?? false) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),
              const SectionBar('Suggested'),
              const SizedBox(height: 12),
              _AsyncList<Friend>(
                value: suggested,
                onRetry: () => ref.invalidate(suggestedFriendsProvider),
                rowBuilder: (f) {
                  final rel = f.userId == null ? FriendRelation.none : ref.watch(friendRelationProvider(f.userId!));
                  return _PlayerRow(
                    name: f.name,
                    online: false,
                    status: f.status,
                    color: f.color,
                    onTap: f.userId == null ? null : () => _openProfile(f.userId!),
                    trailing: switch (rel) {
                      FriendRelation.sent => const _PillButton(label: 'Request sent'),
                      FriendRelation.friend => const _PillButton(label: 'Friends'),
                      FriendRelation.incoming => _PillButton(label: 'Accept', primary: true, onTap: () => _addSuggested(f)),
                      _ => _PillButton(label: '+ Add', onTap: () => _addSuggested(f)),
                    },
                  );
                },
              ),
            ],
          );
        }),
      ],
    );
  }
}

/// Maps an [AsyncValue] list onto the shared skeleton / retry / list states.
class _AsyncList<T> extends StatelessWidget {
  const _AsyncList({required this.value, required this.rowBuilder, required this.onRetry, this.emptyLabel});

  final AsyncValue<List<T>> value;
  final Widget Function(T) rowBuilder;
  final VoidCallback onRetry;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return _list(context, value.value!);
    if (value.hasError) return _ErrorRetry(onRetry: onRetry);
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < 4; i++) ...[
            const _SkeletonFriendRow(),
            const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }

  Widget _list(BuildContext context, List<T> list) {
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Text(
          emptyLabel ?? 'Nothing here yet',
          textAlign: TextAlign.center,
          style: AuraText.body.copyWith(color: AuraColors.textSecondary),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in list) ...[
          rowBuilder(f),
          const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AuraColors.textSecondary, size: 28),
          const SizedBox(height: 10),
          Text("Couldn't load", style: AuraText.body.copyWith(color: AuraColors.textSecondary)),
          const SizedBox(height: 12),
          SecondaryButton(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}

class _SkeletonFriendRow extends StatelessWidget {
  const _SkeletonFriendRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: AuraGlass.decoration(radius: 16),
      child: Row(
        children: [
          const SkeletonBox(height: 44, shape: BoxShape.circle),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              SkeletonBox(width: 120, height: 13),
              SizedBox(height: 8),
              SkeletonBox(width: 80, height: 10),
            ],
          ),
          const Spacer(),
          const SkeletonBox(width: 74, height: 30, radius: 11),
        ],
      ),
    );
  }
}

/// A player row: avatar with a green dot when online, name, status line.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.name,
    required this.online,
    required this.status,
    required this.trailing,
    this.avatarUrl,
    this.color,
    this.onTap,
  });
  final String name;
  final String? avatarUrl;
  final Color? color;
  final bool online;
  final String status;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final glyph = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    return AuraCard(
      onTap: onTap,
      padding: const EdgeInsets.all(11),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                color != null
                    ? LetterAvatar(letter: glyph, color: color!, size: 44)
                    : AvatarDisc(glyph: glyph, avatarUrl: avatarUrl, name: name, size: 44),
                if (online)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: AuraColors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: AuraColors.bgBase, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.cardTitle.copyWith(fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: online ? AuraColors.green : AuraColors.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, this.onTap, this.primary = false});
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: primary && enabled
            ? BoxDecoration(
                gradient: AuraGradients.brand,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              )
            : AuraGlass.decoration(radius: 11, shadow: false),
        child: Text(
          label,
          style: TextStyle(color: enabled ? Colors.white : AuraColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _QuickLink extends StatelessWidget {
  const _QuickLink({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AuraCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: AuraColors.accentGlow, size: 20),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _RequestActions extends StatelessWidget {
  const _RequestActions({required this.onAccept, required this.onDecline});
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'Accept',
          child: GestureDetector(
            onTap: onAccept,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AuraColors.green, Color(0xFF14B8A6)]),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 16),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Semantics(
          button: true,
          label: 'Decline',
          child: GestureDetector(
            onTap: onDecline,
            child: Container(
              width: 36,
              height: 36,
              decoration: AuraGlass.decoration(radius: 11, shadow: false),
              child: Icon(Icons.close, color: AuraColors.textSecondary, size: 15),
            ),
          ),
        ),
      ],
    );
  }
}
