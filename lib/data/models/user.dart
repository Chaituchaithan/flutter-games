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
    this.email = '',
    this.role = '',
    this.country,
    this.avatarId,
    this.avatarUrl,
    this.dateOfBirth,
    this.preferredLanguage,
    this.createdAt,
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

  // ── Account (/users/me) + profile (/users/{id}/profile) ──
  final String email;

  /// "user", "admin", "guest", …
  final String role;

  /// ISO country code (e.g. "IN"); null until the player sets one.
  final String? country;
  final String? avatarId;
  final String? avatarUrl;

  /// "YYYY-MM-DD" as the API sends it.
  final String? dateOfBirth;
  final String? preferredLanguage;

  /// Account creation time ("Member since").
  final DateTime? createdAt;

  /// Anonymous guest account (POST /guest/create).
  bool get isGuest => role == 'guest' || username.toLowerCase().startsWith('guest');

  /// Up to two uppercase initials from the display name.
  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  double get xpFraction => xpMax == 0 ? 0 : (xp / xpMax).clamp(0.0, 1.0);

  /// Raw username (no leading `@`) — the server identity used for the realtime
  /// socket's `auth.login`. Derived from [handle], which [fromJson] seeds from
  /// the API's `username` field.
  String get username => handle.startsWith('@') ? handle.substring(1) : handle;

  User copyWith({
    String? displayName,
    String? bio,
    String? country,
    String? avatarId,
    String? preferredLanguage,
    String? dateOfBirth,
  }) =>
      User(
        id: id,
        displayName: displayName ?? this.displayName,
        handle: handle,
        bio: bio ?? this.bio,
        level: level,
        tier: tier,
        xp: xp,
        xpMax: xpMax,
        color: color,
        email: email,
        role: role,
        country: country ?? this.country,
        avatarId: avatarId ?? this.avatarId,
        avatarUrl: avatarUrl,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        preferredLanguage: preferredLanguage ?? this.preferredLanguage,
        createdAt: createdAt,
      );

  /// Builds the player from `GET /users/me` (account: id, username, email,
  /// role, created_at) merged with `GET /users/{id}/profile` (display_name,
  /// bio, country, avatar, …). The profile may be missing (null) — e.g. a
  /// brand-new or guest account — in which case the username is the name.
  /// Progression (level / tier / XP) has no service yet, so it starts at the
  /// new-player defaults.
  factory User.fromApi(Map<String, dynamic> me, [Map<String, dynamic>? profile]) {
    final username = me['username'] as String? ?? '';
    final p = profile ?? const <String, dynamic>{};
    final shown = (p['display_name'] as String?)?.trim();
    final name = (shown == null || shown.isEmpty) ? username : shown;
    return User(
      id: (me['id'] ?? p['user_id'] ?? '').toString(),
      displayName: name,
      handle: '@$username',
      bio: p['bio'] as String? ?? '',
      level: (me['level'] as num?)?.toInt() ?? 1,
      tier: me['tier'] as String? ?? 'Bronze I',
      xp: (me['xp'] as num?)?.toInt() ?? 0,
      xpMax: (me['xp_max'] as num?)?.toInt() ?? 100,
      color: Friend.colorForName(name),
      email: me['email'] as String? ?? '',
      role: me['role'] as String? ?? '',
      country: p['country'] as String?,
      avatarId: p['avatar_id']?.toString(),
      avatarUrl: p['avatar_url'] as String?,
      dateOfBirth: p['date_of_birth'] as String?,
      preferredLanguage: p['preferred_language'] as String?,
      createdAt: DateTime.tryParse(me['created_at'] as String? ?? ''),
    );
  }

  /// Applies a profile payload (e.g. the PATCH /users/me/profile response) on
  /// top of this user, keeping the account fields.
  User withProfile(Map<String, dynamic> profile) {
    final shown = (profile['display_name'] as String?)?.trim();
    final name = (shown == null || shown.isEmpty) ? displayName : shown;
    return User(
      id: id,
      displayName: name,
      handle: handle,
      bio: profile.containsKey('bio') ? (profile['bio'] as String? ?? '') : bio,
      level: level,
      tier: tier,
      xp: xp,
      xpMax: xpMax,
      color: Friend.colorForName(name),
      email: email,
      role: role,
      country: profile.containsKey('country') ? profile['country'] as String? : country,
      avatarId: profile.containsKey('avatar_id') ? profile['avatar_id']?.toString() : avatarId,
      avatarUrl: profile.containsKey('avatar_url') ? profile['avatar_url'] as String? : avatarUrl,
      dateOfBirth: profile['date_of_birth'] as String? ?? dateOfBirth,
      preferredLanguage: profile['preferred_language'] as String? ?? preferredLanguage,
      createdAt: createdAt,
    );
  }

  /// First non-null value among [keys] — tolerates snake_case or camelCase
  /// (the API is Rust/serde snake_case; see docs/SERVICES_AND_REALTIME.md).
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

  /// Display-safe fields for the on-device cache ([TokenStore.saveProfile]).
  /// Leaves out email and date of birth; balances aren't on the user at all.
  Map<String, dynamic> toCache() => {
        'v': 1,
        'id': id,
        'display_name': displayName,
        'handle': handle,
        'bio': bio,
        'level': level,
        'tier': tier,
        'xp': xp,
        'xp_max': xpMax,
        'role': role,
        'country': country,
        'avatar_id': avatarId,
        'avatar_url': avatarUrl,
        'preferred_language': preferredLanguage,
        'created_at': createdAt?.toIso8601String(),
      };

  /// Rebuilds the cached player; null when the cache is missing, from an
  /// older format, or unreadable.
  static User? fromCache(Map<String, dynamic> j) {
    try {
      if (j['v'] != 1) return null;
      final name = j['display_name'] as String? ?? '';
      if ((j['id'] as String? ?? '').isEmpty || name.isEmpty) return null;
      return User(
        id: j['id'] as String,
        displayName: name,
        handle: j['handle'] as String? ?? '',
        bio: j['bio'] as String? ?? '',
        level: (j['level'] as num?)?.toInt() ?? 1,
        tier: j['tier'] as String? ?? 'Bronze I',
        xp: (j['xp'] as num?)?.toInt() ?? 0,
        xpMax: (j['xp_max'] as num?)?.toInt() ?? 100,
        color: Friend.colorForName(name),
        role: j['role'] as String? ?? '',
        country: j['country'] as String?,
        avatarId: j['avatar_id'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        preferredLanguage: j['preferred_language'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
      );
    } on Object catch (_) {
      return null;
    }
  }

  /// The demo player used in the static (pre-API) phase.
  static const demo = User(
    id: 'me',
    // Neutral fallback (signed out / demo build) — never a made-up person.
    displayName: 'Player',
    handle: '@player',
    bio: 'Late-night grinder. Top 5% this season.',
    level: 7,
    tier: 'GOLD III',
    xp: 1300,
    xpMax: 2000,
    color: Color(0xFF8B5CF6), // AuraColors.brandPurple
  );
}
