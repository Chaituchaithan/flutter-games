import 'package:flutter/foundation.dart';

/// A VIP plan from `GET /sensitive/subscriptions/plans`.
@immutable
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.tier,
    required this.interval,
    required this.priceCents,
    this.durationDays = 30,
    this.features = const {},
    this.isActive = true,
  });

  final int id;
  final String name;

  /// "free" | "silver" | "gold" | "royal" (lower-case), ranked in that order.
  final String tier;

  /// "monthly" | "yearly".
  final String interval;
  final int priceCents;
  final int durationDays;
  final Map<String, dynamic> features;
  final bool isActive;

  bool get yearly => interval == 'yearly';
  bool get free => priceCents == 0;

  /// "$4.99" (USD, as the API prices in cents).
  String get price {
    final dollars = priceCents ~/ 100, cents = priceCents % 100;
    return '\$$dollars.${cents.toString().padLeft(2, '0')}';
  }

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  factory SubscriptionPlan.fromJson(Map<String, dynamic> j) => SubscriptionPlan(
    id: _int(j['id']),
    name: j['name'] as String? ?? '',
    tier: (j['tier'] as String? ?? '').toLowerCase(),
    interval: (j['billing_interval'] as String? ?? 'monthly').toLowerCase(),
    priceCents: _int(j['price_cents']),
    durationDays: _int(j['duration_days']),
    features: (j['features'] as Map?)?.cast<String, dynamic>() ?? const {},
    isActive: j['is_active'] != false,
  );
}

/// The player's subscription (`GET /sensitive/subscriptions/my`,
/// 11-store.md §4b). Two shapes, told apart by `status`:
/// `{"plan_id": 1, "tier": "free", "status": "default"}` (no paid plan) or the
/// paid row (`id`, `plan_id`, `status: "active"`, `started_at`, `expires_at`,
/// `cancelled_at`, `auto_renew`; no `tier`: look it up in the plans). The
/// cancel reply is the same row with `status: "cancelled"`.
@immutable
class MySubscription {
  const MySubscription({
    this.planId,
    this.tier,
    this.status,
    this.endsAt,
    this.autoRenew = false,
    this.id,
    this.startedAt,
    this.cancelledAt,
  });

  final int? planId;
  final String? tier;

  /// `default` (free tier), `active`, `cancelled`.
  final String? status;

  /// `expires_at`: "Renews on" (auto_renew) / "Ends on".
  final DateTime? endsAt;
  final bool autoRenew;

  /// The subscription id (paid shape only).
  final String? id;
  final DateTime? startedAt;
  final DateTime? cancelledAt;

  static const none = MySubscription();

  /// The free tier (`status: "default"`).
  bool get isDefault => status == 'default' || (!active && tier == 'free');

  /// A live paid subscription.
  bool get active {
    final s = status?.toLowerCase();
    if (s != null && s != 'active' && s != 'trialing') return false;
    return (planId != null || tier != null) && tier != 'free';
  }

  /// The tier, from the reply or [plans] by `plan_id`; `free` when none.
  String tierIn(List<SubscriptionPlan> plans) {
    if (!active) return 'free';
    return tier ?? plans.where((p) => p.id == planId).firstOrNull?.tier ?? 'free';
  }

  factory MySubscription.fromJson(Map<String, dynamic> j) {
    final plan = (j['plan'] as Map?)?.cast<String, dynamic>();
    final id = j['plan_id'] ?? plan?['id'];
    DateTime? date(String k) => DateTime.tryParse(j[k] as String? ?? '');
    return MySubscription(
      planId: id is num ? id.toInt() : int.tryParse('${id ?? ''}'),
      tier: ((j['tier'] ?? plan?['tier']) as String?)?.toLowerCase(),
      status: j['status'] as String?,
      endsAt: date('expires_at') ?? date('current_period_end') ?? date('end_date') ?? date('ends_at'),
      autoRenew: j['auto_renew'] == true,
      id: j['id'] is String ? j['id'] as String : (j['subscription_id'] is String ? j['subscription_id'] as String : null),
      startedAt: date('started_at'),
      cancelledAt: date('cancelled_at'),
    );
  }
}

/// `POST /sensitive/subscriptions/subscribe` reply (§4c).
@immutable
class SubscribeResult {
  const SubscribeResult({required this.subscriptionId, required this.planId, this.planName, this.startedAt, this.expiresAt, this.autoRenew = false});
  final String subscriptionId;
  final int planId;
  final String? planName;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final bool autoRenew;

  factory SubscribeResult.fromJson(Map<String, dynamic> j) {
    DateTime? date(String k) => DateTime.tryParse(j[k] as String? ?? '');
    final id = j['plan_id'];
    return SubscribeResult(
      subscriptionId: '${j['subscription_id'] ?? ''}',
      planId: id is num ? id.toInt() : int.tryParse('${id ?? ''}') ?? 0,
      planName: j['plan_name'] as String?,
      startedAt: date('started_at'),
      expiresAt: date('expires_at'),
      autoRenew: j['auto_renew'] == true,
    );
  }
}
