import '../../services/api_client.dart';
import '../../widgets/aura.dart' show AuraColors;
import '../models/match_record.dart';

/// Past-match records for the game-history screen.
abstract class HistorySource {
  Future<List<MatchRecord>> matches();
}

/// The list that used to live inline in `game_history_screen.dart`.
class StaticHistorySource implements HistorySource {
  const StaticHistorySource();

  @override
  Future<List<MatchRecord>> matches() async => const [
        MatchRecord(result: 'W', opponent: 'ZeroCool', score: 'Final 3 — 1', amount: '+250', isXp: false, timeAgo: '2m ago', avatarColor: AuraColors.brandPink),
        MatchRecord(result: 'L', opponent: 'NeonViper', score: 'Final 1 — 3', amount: '+20 XP', isXp: true, timeAgo: '18m ago', avatarColor: AuraColors.avatarBlue),
        MatchRecord(result: 'D', opponent: 'PixelGhost', score: 'Final 2 — 2', amount: '+60', isXp: false, timeAgo: '1h ago', avatarColor: AuraColors.avatarGreen),
        MatchRecord(result: 'W', opponent: 'AcePilot', score: 'Final 3 — 0', amount: '+300', isXp: false, timeAgo: '3h ago', avatarColor: AuraColors.brandOrange),
        MatchRecord(result: 'W', opponent: 'LunaWolf', score: 'Final 3 — 2', amount: '+250', isXp: false, timeAgo: '5h ago', avatarColor: AuraColors.avatarPurple),
        MatchRecord(result: 'L', opponent: 'IronByte', score: 'Final 0 — 3', amount: '+15 XP', isXp: true, timeAgo: 'Yesterday', avatarColor: AuraColors.gems),
        MatchRecord(result: 'D', opponent: 'StormFox', score: 'Final 1 — 1', amount: '+60', isXp: false, timeAgo: 'Yesterday', avatarColor: AuraColors.gold),
        MatchRecord(result: 'W', opponent: 'NovaKid', score: 'Final 3 — 2', amount: '+250', isXp: false, timeAgo: '2d ago', avatarColor: AuraColors.brandPurple),
      ];
}

/// Live-API implementation (off until remote sources are switched on).
class RemoteHistorySource implements HistorySource {
  const RemoteHistorySource(this._api);
  final ApiClient _api;

  @override
  Future<List<MatchRecord>> matches() async {
    final data = await _api.get('/matches/history') as List<dynamic>;
    return data.map((e) => MatchRecord.fromJson(e as Map<String, dynamic>)).toList();
  }
}
