import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';
import '../../configs/feature_flags.dart';
import '../models/friend.dart';
import '../sources/friends_source.dart';

/// Friends domain: reads via a [FriendsSource], write actions are fire-and-forget
/// for the static phase (the screen shows optimistic toast feedback).
class FriendsRepository {
  const FriendsRepository(this._source, {this.api});

  final FriendsSource _source;
  final ApiClient? api;

  Future<List<Friend>> friends() => _source.friends();
  Future<List<Friend>> requests() => _source.requests();
  Future<List<Friend>> suggested() => _source.suggested();

  // Write actions. No-ops against the static source; real calls once remote is on.
  Future<void> add(String name) => _post('/friends/requests', {'name': name});
  Future<void> accept(String name) => _post('/friends/accept', {'name': name});
  Future<void> decline(String name) => _post('/friends/decline', {'name': name});
  Future<void> challenge(String name) => _post('/friends/challenge', {'name': name});

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final client = api;
    if (client == null) return; // static phase: nothing to persist
    await client.post(path, body: body);
  }
}

final friendsRepositoryProvider = Provider<FriendsRepository>((ref) {
  final remote = ref.watch(useRemoteSourcesProvider);
  final api = ref.watch(apiClientProvider);
  return remote
      ? FriendsRepository(RemoteFriendsSource(api), api: api)
      : const FriendsRepository(StaticFriendsSource());
});

final friendsListProvider =
    FutureProvider.autoDispose<List<Friend>>((ref) => ref.watch(friendsRepositoryProvider).friends());

final friendRequestsProvider =
    FutureProvider.autoDispose<List<Friend>>((ref) => ref.watch(friendsRepositoryProvider).requests());

final suggestedFriendsProvider =
    FutureProvider.autoDispose<List<Friend>>((ref) => ref.watch(friendsRepositoryProvider).suggested());
