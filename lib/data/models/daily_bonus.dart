import 'package:flutter/foundation.dart';

/// One day's reward in the 7-day daily-bonus cycle (`next_reward`).
@immutable
class DailyReward {
  const DailyReward({
    required this.dayNumber,
    this.tokens = 0,
    this.gold = 0,
    this.powerUpId,
    this.powerUpQuantity = 0,
  });

  /// 1–7, the day of the cycle.
  final int dayNumber;
  final int tokens;
  final int gold;
  final String? powerUpId;
  final int powerUpQuantity;

  /// "150 Gold", "200 Tokens + 50 Gold", "2× power-up".
  String get label {
    final parts = [
      if (tokens > 0) '${formatAmount(tokens)} Tokens',
      if (gold > 0) '${formatAmount(gold)} Gold',
      if (powerUpId != null && powerUpQuantity > 0) '$powerUpQuantity× power-up',
    ];
    return parts.isEmpty ? 'Reward' : parts.join(' + ');
  }

  /// Amounts come as strings ("150") or numbers.
  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}'.split('.').first) ?? 0;

  factory DailyReward.fromJson(Map<String, dynamic> j) => DailyReward(
    dayNumber: _int(j['day_number']).clamp(1, 7),
    tokens: _int(j['reward_tokens']),
    gold: _int(j['reward_gold']),
    powerUpId: j['power_up_id']?.toString(),
    powerUpQuantity: _int(j['power_up_quantity']),
  );
}

/// `POST /sensitive/daily-bonus/claim` — what was actually paid.
@immutable
class DailyClaim {
  const DailyClaim({
    this.tokens = 0,
    this.gold = 0,
    this.powerUpId,
    this.powerUpQuantity = 0,
    this.newStreak = 0,
    this.totalClaims = 0,
  });

  final int tokens;
  final int gold;
  final String? powerUpId;
  final int powerUpQuantity;
  final int newStreak;
  final int totalClaims;

  /// "100 Gold", "200 Tokens + 50 Gold".
  String get label => DailyReward(
    dayNumber: 1,
    tokens: tokens,
    gold: gold,
    powerUpId: powerUpId,
    powerUpQuantity: powerUpQuantity,
  ).label;

  factory DailyClaim.fromJson(Map<String, dynamic> j) => DailyClaim(
    tokens: DailyReward._int(j['tokens_awarded']),
    gold: DailyReward._int(j['gold_awarded']),
    powerUpId: j['power_up_id']?.toString(),
    powerUpQuantity: DailyReward._int(j['power_up_quantity']),
    newStreak: DailyReward._int(j['new_streak']),
    totalClaims: DailyReward._int(j['total_claims']),
  );
}

/// `GET /sensitive/daily-bonus/status`.
@immutable
class DailyBonusStatus {
  const DailyBonusStatus({
    required this.currentStreak,
    required this.canClaim,
    required this.nextReward,
    this.lastClaimedAt,
    this.nextClaimAt,
    this.totalClaims = 0,
  });

  final int currentStreak;

  /// Today's reward ([nextReward]) is ready to claim.
  final bool canClaim;

  /// Today's reward when [canClaim]; otherwise the next one (at [nextClaimAt]).
  final DailyReward nextReward;
  final DateTime? lastClaimedAt;
  final DateTime? nextClaimAt;
  final int totalClaims;

  /// Cycle days already claimed (they come before [nextReward]'s day).
  int get claimedInCycle => nextReward.dayNumber - 1;

  factory DailyBonusStatus.fromJson(Map<String, dynamic> j) => DailyBonusStatus(
    currentStreak: DailyReward._int(j['current_streak']),
    canClaim: j['can_claim'] == true,
    nextReward: DailyReward.fromJson((j['next_reward'] as Map?)?.cast<String, dynamic>() ?? const {}),
    lastClaimedAt: DateTime.tryParse(j['last_claimed_at'] as String? ?? ''),
    nextClaimAt: DateTime.tryParse(j['next_claim_available_at'] as String? ?? ''),
    totalClaims: DailyReward._int(j['total_claims']),
  );
}

/// 1234567 → "1,234,567".
String formatAmount(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
