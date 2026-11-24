import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'rewards.dart' show BonusGameOffer;

/// One day's reward in the daily-bonus cycle (`next_reward`, `rewards[]`).
/// The cycle has 30 days today (07-rewards.md §2); amounts are already
/// multiplied by the plan.
@immutable
class DailyReward {
  const DailyReward({
    required this.dayNumber,
    this.tokens = 0,
    this.gold = 0,
    this.powerUpId,
    this.powerUpQuantity = 0,
    this.rubies = 0,
    this.nextBonusMultiplier,
    this.bonusGameId,
    this.title,
    this.isMilestone = false,
    this.isEnabled = true,
  });

  /// 1-based day of the cycle.
  final int dayNumber;
  final int tokens;
  final int gold;
  final String? powerUpId;
  final int powerUpQuantity;

  /// Shown only; not credited (no ruby balance yet).
  final int rubies;

  /// A multiplier day: the next claim is multiplied by it (decimal string).
  final String? nextBonusMultiplier;

  /// A spin day: the claim unlocks a play of this bonus game.
  final int? bonusGameId;

  /// The server's card label (`label`, e.g. "Week 4 reward").
  final String? title;

  /// Draw a bigger card.
  final bool isMilestone;

  /// false: the day stays in the calendar but pays nothing (grey it out).
  final bool isEnabled;

  bool get isSpinDay => bonusGameId != null;

  /// "150 Gold", "200 Tokens + 50 Gold", "2× power-up".
  String get label {
    final parts = [
      if (tokens > 0) '${formatAmount(tokens)} Tokens',
      if (gold > 0) '${formatAmount(gold)} Gold',
      if (powerUpId != null && powerUpQuantity > 0) '$powerUpQuantity× boost',
    ];
    return parts.isEmpty ? 'Reward' : parts.join(' + ');
  }

  /// Amounts come as strings ("150") or numbers.
  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}'.split('.').first) ?? 0;

  factory DailyReward.fromJson(Map<String, dynamic> j) => DailyReward(
    dayNumber: math.max(1, _int(j['day_number'])),
    tokens: _int(j['reward_tokens']),
    gold: _int(j['reward_gold']),
    powerUpId: j['power_up_id']?.toString(),
    powerUpQuantity: _int(j['power_up_quantity']),
    rubies: _int(j['ruby_amount']),
    nextBonusMultiplier: j['next_bonus_multiplier']?.toString(),
    bonusGameId: j['bonus_game_id'] == null ? null : _int(j['bonus_game_id']),
    title: j['label'] as String?,
    isMilestone: j['is_milestone'] == true,
    isEnabled: j['is_enabled'] != false,
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
    this.granted = true,
    this.multiplierApplied = '1',
    this.rubies = 0,
    this.isMilestone = false,
    this.title,
    this.bonusGame,
  });

  /// false: the day paid nothing (a switched-off day) but the streak moved on.
  final bool granted;

  /// A pending multiplier this claim used up ("2" → show "x2!").
  final String multiplierApplied;
  final int rubies;
  final bool isMilestone;
  final String? title;

  /// A spin day: open this bonus game at once with its trigger and ref.
  final BonusGameOffer? bonusGame;

  /// The multiplier as a number when above 1, else null.
  double? get boost {
    final m = double.tryParse(multiplierApplied);
    return m != null && m > 1 ? m : null;
  }

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
    granted: j['granted'] != false,
    multiplierApplied: j['multiplier_applied']?.toString() ?? '1',
    rubies: DailyReward._int(j['ruby_amount']),
    isMilestone: j['is_milestone'] == true,
    title: j['label'] as String?,
    bonusGame: BonusGameOffer.fromJson(j['bonus_game']),
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
    this.rewards = const [],
    this.tierMultiplier = '1',
  });

  final int currentStreak;

  /// Every day of the cycle, for the calendar (empty if the server sent none).
  final List<DailyReward> rewards;

  /// The plan's multiplier, already applied to [rewards].
  final String tierMultiplier;

  /// Days in the cycle (30 today; 7 when the cycle isn't known).
  int get cycleLength => rewards.isEmpty ? 7 : rewards.map((r) => r.dayNumber).reduce(math.max);

  /// The calendar entry for [day], if the server sent one.
  DailyReward? rewardFor(int day) {
    for (final r in rewards) {
      if (r.dayNumber == day) return r;
    }
    return null;
  }

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
    rewards: [
      for (final r in (j['rewards'] is List ? j['rewards'] as List : const []))
        if (r is Map) DailyReward.fromJson(r.cast<String, dynamic>()),
    ]..sort((a, b) => a.dayNumber.compareTo(b.dayNumber)),
    tierMultiplier: j['tier_multiplier']?.toString() ?? '1',
  );
}

/// 1234567 → "1,234,567".
String formatAmount(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
