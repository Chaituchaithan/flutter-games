import '../../configs/endpoints/api_endpoints.dart';
import '../../services/api_client.dart';
import '../../services/app_exception.dart';
import '../models/subscription.dart';

/// VIP plans and the player's subscription.
abstract class SubscriptionSource {
  Future<List<SubscriptionPlan>> plans();
  Future<MySubscription> my();

  /// Throws [AppException] (503 until store billing is integrated).
  Future<void> subscribe(int planId, {bool autoRenew = true});
  Future<void> cancel();
}

/// Signed-out demo: the live plan list, Free plan.
class StaticSubscriptionSource implements SubscriptionSource {
  StaticSubscriptionSource();
  MySubscription _mine = MySubscription.none;

  static const _plans = [
    SubscriptionPlan(id: 1, name: 'Free Monthly', tier: 'free', interval: 'monthly', priceCents: 0),
    SubscriptionPlan(id: 2, name: 'Silver Monthly', tier: 'silver', interval: 'monthly', priceCents: 499),
    SubscriptionPlan(id: 4, name: 'Gold Monthly', tier: 'gold', interval: 'monthly', priceCents: 999),
    SubscriptionPlan(id: 3, name: 'Silver Yearly', tier: 'silver', interval: 'yearly', priceCents: 4999, durationDays: 365),
    SubscriptionPlan(id: 5, name: 'Gold Yearly', tier: 'gold', interval: 'yearly', priceCents: 9999, durationDays: 365),
  ];

  @override
  Future<List<SubscriptionPlan>> plans() async => _plans;

  @override
  Future<MySubscription> my() async => _mine;

  @override
  Future<void> subscribe(int planId, {bool autoRenew = true}) async {
    final p = _plans.firstWhere((x) => x.id == planId);
    _mine = MySubscription(planId: p.id, tier: p.tier, status: 'active', autoRenew: autoRenew);
  }

  @override
  Future<void> cancel() async => _mine = MySubscription.none;
}

/// Live gateway (`/sensitive` routes).
class RemoteSubscriptionSource implements SubscriptionSource {
  const RemoteSubscriptionSource(this._api);
  final ApiClient _api;

  static Object? _data(Object? res) => res is Map && res['data'] != null ? res['data'] : res;

  @override
  Future<List<SubscriptionPlan>> plans() async {
    final list = _data(await _api.get(ApiEndpoints.subscriptionPlans));
    return [
      for (final e in (list as List? ?? const []))
        if (e is Map) SubscriptionPlan.fromJson(e.cast<String, dynamic>()),
    ];
  }

  @override
  Future<MySubscription> my() async {
    try {
      final res = _data(await _api.get(ApiEndpoints.subscriptionMy));
      if (res is Map) return MySubscription.fromJson(res.cast<String, dynamic>());
      return MySubscription.none; // null / empty → no subscription
    } on AppException catch (e) {
      if (e.statusCode == 404) return MySubscription.none; // "no subscription"
      rethrow;
    }
  }

  @override
  Future<void> subscribe(int planId, {bool autoRenew = true}) async =>
      _api.post(ApiEndpoints.subscriptionSubscribe, body: {'plan_id': planId, 'auto_renew': autoRenew});

  @override
  Future<void> cancel() async => _api.post(ApiEndpoints.subscriptionCancel);
}
