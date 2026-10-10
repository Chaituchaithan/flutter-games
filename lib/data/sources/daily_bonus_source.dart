import '../../configs/endpoints/api_endpoints.dart';
import '../../services/api_client.dart';
import '../models/daily_bonus.dart';

/// Daily-bonus status + claim.
abstract class DailyBonusSource {
  Future<DailyBonusStatus> status();

  /// Claim today's reward. Throws [AppException] 409 when already claimed.
  Future<DailyClaim> claim();
}

/// Signed-out demo: day 3 of the cycle, ready to claim.
class StaticDailyBonusSource implements DailyBonusSource {
  StaticDailyBonusSource();
  bool _claimed = false;

  @override
  Future<DailyBonusStatus> status() async => _claimed
      ? DailyBonusStatus(
          currentStreak: 3,
          canClaim: false,
          nextReward: const DailyReward(dayNumber: 4, tokens: 1500),
          nextClaimAt: DateTime.now().add(const Duration(hours: 24)),
        )
      : const DailyBonusStatus(currentStreak: 2, canClaim: true, nextReward: DailyReward(dayNumber: 3, gold: 250));

  @override
  Future<DailyClaim> claim() async {
    _claimed = true;
    return const DailyClaim(gold: 250, newStreak: 3);
  }
}

/// Live gateway (`/sensitive` routes: bearer + the device fingerprint saved
/// at login).
class RemoteDailyBonusSource implements DailyBonusSource {
  const RemoteDailyBonusSource(this._api);
  final ApiClient _api;

  @override
  Future<DailyBonusStatus> status() async {
    final res = await _api.get(ApiEndpoints.dailyBonusStatus);
    final map = (res is Map && res['data'] is Map ? res['data'] : res) as Map;
    return DailyBonusStatus.fromJson(map.cast<String, dynamic>());
  }

  @override
  Future<DailyClaim> claim() async {
    final res = await _api.post(ApiEndpoints.dailyBonusClaim);
    final map = res is Map ? (res['data'] is Map ? res['data'] as Map : res) : const {};
    return DailyClaim.fromJson(map.cast<String, dynamic>());
  }
}
