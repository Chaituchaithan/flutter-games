import '../../configs/endpoints/api_endpoints.dart';
import '../../services/api_client.dart';
import '../models/referral.dart';

/// Your invite code and its results.
abstract class ReferralSource {
  Future<ReferralCode> myCode();
  Future<ReferralStats> stats();
}

/// Signed-out demo.
class StaticReferralSource implements ReferralSource {
  const StaticReferralSource();

  @override
  Future<ReferralCode> myCode() async => const ReferralCode(code: 'DEMO2026');

  @override
  Future<ReferralStats> stats() async => const ReferralStats();
}

class RemoteReferralSource implements ReferralSource {
  const RemoteReferralSource(this._api);
  final ApiClient _api;

  static Map<String, dynamic> _body(Object? res) =>
      ((res is Map && res['data'] is Map ? res['data'] : res) as Map).cast<String, dynamic>();

  @override
  Future<ReferralCode> myCode() async => ReferralCode.fromJson(_body(await _api.get(ApiEndpoints.referralMyCode)));

  @override
  Future<ReferralStats> stats() async => ReferralStats.fromJson(_body(await _api.get(ApiEndpoints.referralStats)));
}
