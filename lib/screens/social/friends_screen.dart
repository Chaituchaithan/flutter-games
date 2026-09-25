import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../../data/models/friend.dart';
import '../../data/repositories/friends_repository.dart';
import '../../widgets/aura.dart';
import '../system/loading_skeleton_screen.dart';
import 'player_profile_screen.dart';

/// Friends & social — Friends / Requests / Find tabs.
/// Reads via `friendsRepositoryProvider` (static source today; live API when
/// remote sources are switched on). Mirrors the mockup's `isSocial` screen.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  int _tab = 0;

  void _openProfile(Friend f) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerProfileScreen(
        name: f.name,
        color: f.color,
        level: f.level,
        online: f.online,
      ),
    ));
  }

  void _challenge(Friend f) {
    ref.read(friendsRepositoryProvider).challenge(f.name);
    showAuraToast(context, 'Challenge sent to ${f.name}', kind: AuraToastKind.success);
  }

  void _add(Friend f) {
    ref.read(friendsRepositoryProvider).add(f.name);
    showAuraToast(context, 'Friend request sent to ${f.name}');
  }

  void _accept(Friend f) {
    ref.read(friendsRepositoryProvider).accept(f.name);
    ref.invalidate(friendRequestsProvider);
    showAuraToast(context, "You're now friends with ${f.name}", kind: AuraToastKind.success);
  }

  void _decline(Friend f) {
    ref.read(friendsRepositoryProvider).decline(f.name);
    ref.invalidate(friendRequestsProvider);
    showAuraToast(context, 'Request from ${f.name} declined', kind: AuraToastKind.info);
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsListProvider);
    final onlineCount = friends.maybeWhen(
      data: (list) => list.where((f) => f.online).length,
      orElse: () => 0,
    );

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
            labels: const ['Friends', 'Requests', 'Find'],
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 16),
          switch (_tab) {
            1 => _requestsTab(),
            2 => _findTab(),
            _ => _friendsTab(friends),
          },
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _friendsTab(AsyncValue<List<Friend>> friends) {
    return _AsyncFriends(
      value: friends,
      onRetry: () => ref.invalidate(friendsListProvider),
      rowBuilder: (f) => _FriendRow(
        friend: f,
        onTap: () => _openProfile(f),
        trailing: f.online
            ? _ChallengeButton(onTap: () => _challenge(f))
            : const Icon(Icons.chevron_right, color: AuraColors.textSecondary, size: 22),
      ),
    );
  }

  Widget _requestsTab() {
    return _AsyncFriends(
      value: ref.watch(friendRequestsProvider),
      onRetry: () => ref.invalidate(friendRequestsProvider),
      emptyLabel: 'No pending requests',
      rowBuilder: (f) => _FriendRow(
        friend: f,
        onTap: () => _openProfile(f),
        trailing: _RequestActions(onAccept: () => _accept(f), onDecline: () => _decline(f)),
      ),
    );
  }

  Widget _findTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuraTextField(hint: 'Search by name or code', icon: Icons.search),
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
                    Text('Invite & earn 2,000 Tokens', style: AuraText.cardTitle.copyWith(fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text('Share your code NOVA-7K2Q', style: AuraText.cardSub.copyWith(fontSize: 11.5)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white, size: 20),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionBar('Suggested'),
        const SizedBox(height: 12),
        _AsyncFriends(
          value: ref.watch(suggestedFriendsProvider),
          onRetry: () => ref.invalidate(suggestedFriendsProvider),
          rowBuilder: (f) => _FriendRow(
            friend: f,
            onTap: () => _openProfile(f),
            trailing: _AddButton(onTap: () => _add(f)),
          ),
        ),
      ],
    );
  }
}

/// Maps a friends [AsyncValue] onto the shared skeleton / retry / list states.
class _AsyncFriends extends StatelessWidget {
  const _AsyncFriends({
    required this.value,
    required this.rowBuilder,
    required this.onRetry,
    this.emptyLabel,
  });

  final AsyncValue<List<Friend>> value;
  final Widget Function(Friend) rowBuilder;
  final VoidCallback onRetry;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => Shimmer(
        child: Column(
          children: [
            for (var i = 0; i < 4; i++) ...[
              const _SkeletonFriendRow(),
              const SizedBox(height: 9),
            ],
          ],
        ),
      ),
      error: (_, _) => _ErrorRetry(onRetry: onRetry),
      data: (list) {
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
      },
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

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.friend, required this.trailing, this.onTap});
  final Friend friend;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
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
                LetterAvatar(letter: friend.name[0], color: friend.color, size: 44),
                if (friend.online)
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        friend.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AuraText.cardTitle.copyWith(fontSize: 14.5),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AuraColors.accentGlow.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'LV ${friend.level}',
                        style: const TextStyle(color: AuraColors.accentGlow, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  friend.status,
                  style: TextStyle(
                    color: friend.online ? AuraColors.green : AuraColors.textSecondary,
                    fontSize: 11.5,
                  ),
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

class _ChallengeButton extends StatelessWidget {
  const _ChallengeButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          gradient: AuraGradients.brand,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: const Text(
          'Challenge',
          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: AuraGlass.decoration(radius: 11, shadow: false),
        child: const Text(
          '+ Add',
          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
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
        GestureDetector(
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
        const SizedBox(width: 6),
        GestureDetector(
          onTap: onDecline,
          child: Container(
            width: 36,
            height: 36,
            decoration: AuraGlass.decoration(radius: 11, shadow: false),
            child: Icon(Icons.close, color: AuraColors.textSecondary, size: 15),
          ),
        ),
      ],
    );
  }
}
