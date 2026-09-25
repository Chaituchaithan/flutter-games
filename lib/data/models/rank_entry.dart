import 'package:flutter/material.dart';

import 'friend.dart' show Friend;

/// One row on the leaderboard.
@immutable
class RankEntry {
  const RankEntry({
    required this.rank,
    required this.name,
    required this.pts,
    required this.color,
    this.level,
  });

  final int rank;
  final String name;
  final String pts;
  final Color color;
  final String? level;

  factory RankEntry.fromJson(Map<String, dynamic> json) => RankEntry(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        pts: json['pts']?.toString() ?? '0',
        level: json['level'] as String?,
        color: Friend.colorForName(json['name'] as String? ?? ''),
      );
}
