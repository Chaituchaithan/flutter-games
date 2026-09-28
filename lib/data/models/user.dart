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

  /// First non-null value among [keys] — tolerates snake_case or camelCase
  /// (the API is Rust/serde snake_case; see docs/INTEGRATION_PLAN.md §7b).
  static Object? _pick(Map<String, dynamic> j, List<String> keys) {
    for (final k in keys) {
      if (j[k] != null) return j[k];
    }
    return null;
  }

  factory User.fromJson(Map<String, dynamic> json) {
    final name = _pick(json, ['displayName', 'display_name', 'name', 'username']) as String? ?? '';
    final handle = _pick(json, ['handle', 'username', 'tag']) as String?;
    return User(
      id: _pick(json, ['id', 'user_id', 'uuid'])?.toString() ?? '',
      displayName: name,
      handle: handle != null
          ? (handle.startsWith('@') ? handle : '@$handle')
          : (name.isEmpty ? '' : '@${name.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}'),
      bio: _pick(json, ['bio', 'about']) as String? ?? '',
      level: (_pick(json, ['level', 'lvl']) as num?)?.toInt() ?? 1,
      tier: _pick(json, ['tier', 'rank']) as String? ?? 'Bronze I',
      xp: (_pick(json, ['xp', 'xp_current', 'experience']) as num?)?.toInt() ?? 0,
      xpMax: (_pick(json, ['xpMax', 'xp_max', 'xp_to_next', 'xp_next']) as num?)?.toInt() ?? 100,
      color: Friend.colorForName(name),
    );
  }

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
