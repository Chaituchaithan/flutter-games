import '../../services/api_client.dart';
import '../../widgets/aura.dart' show AuraColors;
import '../models/rank_entry.dart';

/// Leaderboard entries for a scope (global/friends/weekly).
abstract class LeaderboardSource {
  Future<List<RankEntry>> entries(String scope);
}

/// The ranked list that used to live inline in `leaderboard_screen.dart`.
class StaticLeaderboardSource implements LeaderboardSource {
  const StaticLeaderboardSource();

  @override
  Future<List<RankEntry>> entries(String scope) async => const [
        RankEntry(rank: 1, name: 'KaiStorm', pts: '9,840', color: AuraColors.avatarOrange),
        RankEntry(rank: 2, name: 'ZeroCool', pts: '9,210', color: AuraColors.avatarBlue),
        RankEntry(rank: 3, name: 'LunaWolf', pts: '8,730', color: AuraColors.avatarPurple),
        RankEntry(rank: 4, name: 'NovaByte', pts: '8,120', color: AuraColors.avatarGreen, level: 'LV 21'),
        RankEntry(rank: 5, name: 'EchoRay', pts: '7,640', color: AuraColors.avatarPink, level: 'LV 19'),
        RankEntry(rank: 6, name: 'PixelFox', pts: '7,300', color: AuraColors.avatarBlue, level: 'LV 16'),
        RankEntry(rank: 7, name: 'SoloAce', pts: '6,980', color: AuraColors.avatarOrange, level: 'LV 15'),
        RankEntry(rank: 8, name: 'RiftWalker', pts: '6,410', color: AuraColors.avatarPurple, level: 'LV 14'),
      ];
}

/// Live-API implementation (off until remote sources are switched on).
class RemoteLeaderboardSource implements LeaderboardSource {
  const RemoteLeaderboardSource(this._api);
  final ApiClient _api;

  @override
  Future<List<RankEntry>> entries(String scope) async {
    final data = await _api.get('/leaderboard', query: {'scope': scope}) as List<dynamic>;
    return data.map((e) => RankEntry.fromJson(e as Map<String, dynamic>)).toList();
  }
}
