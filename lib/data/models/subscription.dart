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

  /// "free" | "silver" | "gold" (lower-case).
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

/// The player's subscription (`GET /sensitive/subscriptions/my`). The
/// response shape isn't documented yet, so common field names are accepted:
/// `plan_id` / `plan.id`, `tier` / `plan.tier`, `status`, an end date and
/// `auto_renew`.
@immutable
class MySubscription {
  const MySubscription({this.planId, this.tier, this.status, this.endsAt, this.autoRenew = false});

  final int? planId;
  final String? tier;
  final String? status;
  final DateTime? endsAt;
  final bool autoRenew;

  static const none = MySubscription();

  /// A live paid subscription.
  bool get active {
    final s = status?.toLowerCase();
    if (s != null && s != 'active' && s != 'trialing') return false;
    return (planId != null || tier != null) && tier != 'free';
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
    );
  }
}
