import 'package:flutter/material.dart';

import 'friend.dart' show Friend;

/// The signed-in player. Identity + progression shown on Profile / HUD.
@immutable
class User {
  const User({
    required this.id,
    required this.displayName,
    required this.handle,
    required this.bio,
    required this.level,
    required this.tier,
    required this.xp,
    required this.xpMax,
    required this.color,
  });

  final String id;
  final String displayName;
  final String handle;
  final String bio;
  final int level;
  final String tier; // e.g. 'GOLD III'
  final int xp;
  final int xpMax;
  final Color color;

  /// Up to two uppercase initials from the display name.
  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  double get xpFraction => xpMax == 0 ? 0 : (xp / xpMax).clamp(0.0, 1.0);

  User copyWith({String? displayName, String? bio}) => User(
        id: id,
        displayName: displayName ?? this.displayName,
        handle: handle,
        bio: bio ?? this.bio,
        level: level,
        tier: tier,
        xp: xp,
        xpMax: xpMax,
        color: color,
      );

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id']?.toString() ?? '',
        displayName: json['displayName'] as String? ?? '',
        handle: json['handle'] as String? ?? '',
        bio: json['bio'] as String? ?? '',
        level: (json['level'] as num?)?.toInt() ?? 1,
        tier: json['tier'] as String? ?? 'Bronze I',
        xp: (json['xp'] as num?)?.toInt() ?? 0,
        xpMax: (json['xpMax'] as num?)?.toInt() ?? 100,
        color: Friend.colorForName(json['displayName'] as String? ?? ''),
      );

  /// The demo player used in the static (pre-API) phase.
  static const demo = User(
    id: 'me',
    displayName: 'Nova Rider',
    handle: '@nova_rider',
    bio: 'Late-night grinder. Top 5% this season.',
    level: 7,
    tier: 'GOLD III',
    xp: 1300,
    xpMax: 2000,
    color: Color(0xFF8B5CF6), // AuraColors.brandPurple
  );
}
