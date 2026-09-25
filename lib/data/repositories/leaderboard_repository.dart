import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data_config.dart';
import '../models/rank_entry.dart';
import '../sources/leaderboard_source.dart';
import '../../services/api_client.dart';

class LeaderboardRepository {
  const LeaderboardRepository(this._source);
  final LeaderboardSource _source;

  Future<List<RankEntry>> entries(String scope) => _source.entries(scope);
}

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) {
  final remote = ref.watch(useRemoteSourcesProvider);
  final api = ref.watch(apiClientProvider);
  return LeaderboardRepository(
    remote ? RemoteLeaderboardSource(api) : const StaticLeaderboardSource(),
  );
});

/// Scope: 'global' | 'friends' | 'weekly'.
final leaderboardProvider = FutureProvider.autoDispose.family<List<RankEntry>, String>(
  (ref, scope) => ref.watch(leaderboardRepositoryProvider).entries(scope),
);
