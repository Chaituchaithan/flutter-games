import 'package:flutter/material.dart';

import 'friend.dart' show Friend;

/// One past match on the game-history screen. [result] is 'W' | 'L' | 'D'.
@immutable
class MatchRecord {
  const MatchRecord({
    required this.result,
    required this.opponent,
    required this.score,
    required this.amount,
    required this.isXp,
    required this.timeAgo,
    required this.avatarColor,
  });

  final String result;
  final String opponent;
  final String score;
  final String amount;
  final bool isXp;
  final String timeAgo;
  final Color avatarColor;

  factory MatchRecord.fromJson(Map<String, dynamic> json) => MatchRecord(
        result: json['result'] as String? ?? 'D',
        opponent: json['opponent'] as String? ?? '',
        score: json['score'] as String? ?? '',
        amount: json['amount'] as String? ?? '',
        isXp: json['isXp'] as bool? ?? false,
        timeAgo: json['timeAgo'] as String? ?? '',
        avatarColor: Friend.colorForName(json['opponent'] as String? ?? ''),
      );
}
