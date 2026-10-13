import 'package:flutter/foundation.dart';

/// Your invite code (`GET /referrals/my-code`).
@immutable
class ReferralCode {
  const ReferralCode({required this.code, this.uses = 0, this.maxUses, this.expiresAt});

  final String code;

  /// Sign-ups that used it so far, and the limit (null = unlimited).
  final int uses;
  final int? maxUses;

  /// When it stops working (null = never).
  final DateTime? expiresAt;

  bool get expired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get usedUp => maxUses != null && uses >= maxUses!;

  factory ReferralCode.fromJson(Map<String, dynamic> j) => ReferralCode(
    code: j['code']?.toString() ?? '',
    uses: (j['uses'] as num?)?.toInt() ?? 0,
    maxUses: (j['max_uses'] as num?)?.toInt(),
    expiresAt: DateTime.tryParse(j['expires_at']?.toString() ?? '')?.toLocal(),
  );
}

/// How your invites are doing (`GET /referrals/stats`).
@immutable
class ReferralStats {
  const ReferralStats({this.totalReferrals = 0, this.rewardsGranted = 0});

  /// Friends who signed up with your code.
  final int totalReferrals;

  /// Rewards you've received for them.
  final int rewardsGranted;

  factory ReferralStats.fromJson(Map<String, dynamic> j) => ReferralStats(
    totalReferrals: (j['total_referrals'] as num?)?.toInt() ?? 0,
    rewardsGranted: (j['rewards_granted'] as num?)?.toInt() ?? 0,
  );
}
