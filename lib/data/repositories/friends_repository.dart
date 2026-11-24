import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/feature_flags.dart';
import '../../services/session.dart';
import '../../services/social_store.dart';
import '../models/friend.dart';
import '../sources/friends_source.dart';

/// Friend suggestions: demo data offline, none when signed in to the real
/// server (no route). Blocked players are left out (09-social.md §6c).
final friendsSourceProvider = Provider<FriendsSource>((ref) {
  final live = ref.watch(useRemoteAuthProvider) && ref.watch(sessionProvider.select((u) => u != null));
  return live ? const NoFriendsSource() : const StaticFriendsSource();
});

final suggestedFriendsProvider = FutureProvider.autoDispose<List<Friend>>((ref) async {
  final list = await ref.watch(friendsSourceProvider).suggested();
  final blocked = ref.watch(blockListProvider);
  return withoutBlocked(list, blocked, (f) => f.userId ?? '');
});
