import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../utils/amount.dart';

/// The player's own account, as `GET /users/me` returns it, plus the pieces
/// the account routes reply with. Contract: docs/services/02-profile-and-sessions.md.
///
/// Every parser is lenient (unknown fields ignored, missing ones defaulted):
/// the gateway adds fields without notice (00-conventions.md).

String? _s(Object? v) => v is String ? v : null;
bool _b(Object? v, bool fallback) => v is bool ? v : fallback;
int? _i(Object? v) => switch (v) {
      int() => v,
      num() => v.toInt(),
      String() => int.tryParse(v),
      _ => null,
    };
DateTime? _t(Object? v) => v is String ? DateTime.tryParse(v) : null;
Map<String, dynamic> _m(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};

/// `GET /users/me` `profile`, and `GET /users/{id}/profile` (another player).
/// Only these fields are ever shown to other players (§8).
@immutable
class PublicProfile {
  const PublicProfile({
    required this.userId,
    required this.displayName,
    this.avatarId,
    this.avatarUrl,
    this.bio,
    this.country,
    this.dateOfBirth,
    this.preferredLanguage,
    this.updatedAt,
  });

  final String userId;
  final String displayName;
  final int? avatarId;
  final String? avatarUrl;

  /// Up to 140 characters. `""` and null draw the same.
  final String? bio;

  /// ISO 3166-1 alpha-2, upper case.
  final String? country;

  /// `YYYY-MM-DD`; always null for another player.
  final String? dateOfBirth;
  final String? preferredLanguage;
  final DateTime? updatedAt;

  /// A deleted account still answers, named `deleted-<hex>` with no avatar.
  bool get isDeleted => displayName.startsWith('deleted-') && avatarId == null;

  factory PublicProfile.fromJson(Map<String, dynamic> j, {String fallbackName = ''}) {
    final name = _s(j['display_name'])?.trim();
    return PublicProfile(
      userId: (j['user_id'] ?? '').toString(),
      displayName: (name == null || name.isEmpty) ? fallbackName : name,
      avatarId: _i(j['avatar_id']),
      avatarUrl: _s(j['avatar_url']),
      bio: _s(j['bio']),
      country: _s(j['country']),
      dateOfBirth: _s(j['date_of_birth']),
      preferredLanguage: _s(j['preferred_language']),
      updatedAt: _t(j['updated_at']),
    );
  }
}

/// One saved address (§5). A home row may hold only a country (set from the
/// profile): [isFilled] is false then.
@immutable
class Address {
  const Address({this.line1, this.line2, this.city, this.region, this.postalCode, this.country, this.updatedAt});

  final String? line1;
  final String? line2;
  final String? city;
  final String? region;
  final String? postalCode;
  final String? country;
  final DateTime? updatedAt;

  /// A home address with `line1: null` is "not filled in".
  bool get isFilled => (line1 ?? '').isNotEmpty;

  factory Address.fromJson(Map<String, dynamic> j) => Address(
        line1: _s(j['line1']),
        line2: _s(j['line2']),
        city: _s(j['city']),
        region: _s(j['region']),
        postalCode: _s(j['postal_code']),
        country: _s(j['country']),
        updatedAt: _t(j['updated_at']),
      );

  /// The PUT body: the whole address; empty optional lines left out.
  Map<String, dynamic> toJson() => {
        'line1': line1,
        if ((line2 ?? '').isNotEmpty) 'line2': line2,
        'city': city,
        if ((region ?? '').isNotEmpty) 'region': region,
        'postal_code': postalCode,
        'country': country,
      };
}

/// The two address kinds in the path (`/users/me/addresses/{kind}`).
enum AddressKind { home, billing }

@immutable
class Addresses {
  const Addresses({this.home, this.billing, this.billingSameAsHome = true});
  final Address? home;
  final Address? billing;
  final bool billingSameAsHome;

  factory Addresses.fromJson(Map<String, dynamic> j) => Addresses(
        home: j['home'] is Map ? Address.fromJson(_m(j['home'])) : null,
        billing: j['billing'] is Map ? Address.fromJson(_m(j['billing'])) : null,
        billingSameAsHome: _b(j['billing_same_as_home'], j['billing'] == null),
      );

  Addresses withAddress(AddressKind kind, Address? a) => kind == AddressKind.home
      ? Addresses(home: a, billing: billing, billingSameAsHome: billing == null)
      : Addresses(home: home, billing: a, billingSameAsHome: a == null);
}

/// §6. Defaults are the server's for a new player.
@immutable
class PrivacySettings {
  const PrivacySettings({
    this.profileVisibility = 'public',
    this.showOnLeaderboards = true,
    this.allowFriendRequests = true,
    this.dmFrom = 'everyone',
    this.loginAlerts = true,
    this.marketingEmail = true,
    this.marketingPush = true,
    this.marketingSms = false,
  });

  static const visibilities = ['public', 'friends', 'private'];
  static const dmOptions = ['everyone', 'friends', 'nobody'];

  final String profileVisibility;
  final bool showOnLeaderboards;
  final bool allowFriendRequests;
  final String dmFrom;
  final bool loginAlerts;
  final bool marketingEmail;
  final bool marketingPush;
  final bool marketingSms;

  factory PrivacySettings.fromJson(Map<String, dynamic> j) {
    const d = PrivacySettings();
    return PrivacySettings(
      profileVisibility: _s(j['profile_visibility']) ?? d.profileVisibility,
      showOnLeaderboards: _b(j['show_on_leaderboards'], d.showOnLeaderboards),
      allowFriendRequests: _b(j['allow_friend_requests'], d.allowFriendRequests),
      dmFrom: _s(j['dm_from']) ?? d.dmFrom,
      loginAlerts: _b(j['login_alerts'], d.loginAlerts),
      marketingEmail: _b(j['marketing_email'], d.marketingEmail),
      marketingPush: _b(j['marketing_push'], d.marketingPush),
      marketingSms: _b(j['marketing_sms'], d.marketingSms),
    );
  }

  Map<String, dynamic> toJson() => {
        'profile_visibility': profileVisibility,
        'show_on_leaderboards': showOnLeaderboards,
        'allow_friend_requests': allowFriendRequests,
        'dm_from': dmFrom,
        'login_alerts': loginAlerts,
        'marketing_email': marketingEmail,
        'marketing_push': marketingPush,
        'marketing_sms': marketingSms,
      };

  /// This object with the PATCH [changes] (snake_case keys) applied — the
  /// optimistic value shown while the request runs.
  PrivacySettings merge(Map<String, dynamic> changes) => PrivacySettings.fromJson({...toJson(), ...changes});
}

/// §7. Applied on the device; the server only stores them.
@immutable
class GamePreferences {
  const GamePreferences({
    this.favouriteGame,
    this.defaultStakeCurrency = 'gold',
    this.rememberLastStake = false,
    this.sound = true,
    this.haptics = true,
    this.tableChat = true,
    this.colourBlind = false,
    this.reduceMotion = false,
  });

  /// A game `code` from `GET /games`, or null.
  final String? favouriteGame;

  /// `gold` or `token` (the reply never says `tokens`).
  final String defaultStakeCurrency;
  final bool rememberLastStake;
  final bool sound;
  final bool haptics;
  final bool tableChat;
  final bool colourBlind;
  final bool reduceMotion;

  factory GamePreferences.fromJson(Map<String, dynamic> j) {
    const d = GamePreferences();
    final cur = _s(j['default_stake_currency']);
    return GamePreferences(
      favouriteGame: _s(j['favourite_game']),
      defaultStakeCurrency: cur == 'tokens' ? 'token' : (cur ?? d.defaultStakeCurrency),
      rememberLastStake: _b(j['remember_last_stake'], d.rememberLastStake),
      sound: _b(j['sound'], d.sound),
      haptics: _b(j['haptics'], d.haptics),
      tableChat: _b(j['table_chat'], d.tableChat),
      colourBlind: _b(j['colour_blind'], d.colourBlind),
      reduceMotion: _b(j['reduce_motion'], d.reduceMotion),
    );
  }

  Map<String, dynamic> toJson() => {
        'favourite_game': favouriteGame,
        'default_stake_currency': defaultStakeCurrency,
        'remember_last_stake': rememberLastStake,
        'sound': sound,
        'haptics': haptics,
        'table_chat': tableChat,
        'colour_blind': colourBlind,
        'reduce_motion': reduceMotion,
      };

  GamePreferences merge(Map<String, dynamic> changes) => GamePreferences.fromJson({...toJson(), ...changes});
}

/// The full `GET /users/me` (§1). Screens in the profile hand-off read this.
@immutable
class Me {
  const Me({
    required this.id,
    required this.profile,
    this.username,
    this.email,
    this.phone,
    this.emailVerifiedAt,
    this.phoneVerifiedAt,
    this.role = 'user',
    this.status = 'active',
    this.createdAt,
    this.updatedAt,
    this.fullName,
    this.avatarGlyph,
    this.gender,
    this.timezone,
    this.preferredChannel = 'email',
    this.addresses = const Addresses(),
    this.privacy = const PrivacySettings(),
    this.preferences = const GamePreferences(),
  });

  static const genders = ['female', 'male', 'non_binary', 'prefer_not_to_say'];
  static const channels = ['email', 'push', 'sms'];

  final String id;
  final String? username;

  /// Null = a guest.
  final String? email;

  /// E.164.
  final String? phone;
  final DateTime? emailVerifiedAt;
  final DateTime? phoneVerifiedAt;
  final String role;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Never null here: a missing `profile` reads as all-null with the
  /// username as the display name.
  final PublicProfile profile;
  final String? fullName;
  final String? avatarGlyph;
  final String? gender;
  final String? timezone;
  final String preferredChannel;
  final Addresses addresses;
  final PrivacySettings privacy;
  final GamePreferences preferences;

  bool get isGuest => email == null;
  String get displayName => profile.displayName;

  /// 1–2 characters for the avatar circle: the glyph, else the name's first letter.
  String get glyph {
    final g = avatarGlyph?.trim();
    if (g != null && g.isNotEmpty) return g;
    final n = displayName.trim();
    return n.isEmpty ? '?' : n.substring(0, 1).toUpperCase();
  }

  factory Me.fromJson(Map<String, dynamic> j) {
    final username = _s(j['username']);
    final id = (j['id'] ?? '').toString();
    final p = j['profile'] is Map ? _m(j['profile']) : <String, dynamic>{'user_id': id};
    return Me(
      id: id,
      username: username,
      email: _s(j['email']),
      phone: _s(j['phone']),
      emailVerifiedAt: _t(j['email_verified_at']),
      phoneVerifiedAt: _t(j['phone_verified_at']),
      role: _s(j['role']) ?? 'user',
      status: _s(j['status']) ?? 'active',
      createdAt: _t(j['created_at']),
      updatedAt: _t(j['updated_at']),
      profile: PublicProfile.fromJson(p, fallbackName: username ?? ''),
      fullName: _s(j['full_name']),
      avatarGlyph: _s(j['avatar_glyph']),
      gender: _s(j['gender']),
      timezone: _s(j['timezone']),
      preferredChannel: _s(j['preferred_channel']) ?? 'email',
      addresses: Addresses.fromJson(_m(j['addresses'])),
      privacy: PrivacySettings.fromJson(_m(j['privacy'])),
      preferences: GamePreferences.fromJson(_m(j['preferences'])),
    );
  }

  Me copyWith({
    PublicProfile? profile,
    Addresses? addresses,
    PrivacySettings? privacy,
    GamePreferences? preferences,
  }) =>
      Me(
        id: id,
        username: username,
        email: email,
        phone: phone,
        emailVerifiedAt: emailVerifiedAt,
        phoneVerifiedAt: phoneVerifiedAt,
        role: role,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        profile: profile ?? this.profile,
        fullName: fullName,
        avatarGlyph: avatarGlyph,
        gender: gender,
        timezone: timezone,
        preferredChannel: preferredChannel,
        addresses: addresses ?? this.addresses,
        privacy: privacy ?? this.privacy,
        preferences: preferences ?? this.preferences,
      );

  /// The `PATCH /users/me/profile` reply: the first nine fields go into
  /// [profile], the five private ones into this object (§2).
  Me withProfileReply(Map<String, dynamic> r) => Me(
        id: id,
        username: username,
        email: email,
        phone: phone,
        emailVerifiedAt: emailVerifiedAt,
        phoneVerifiedAt: phoneVerifiedAt,
        role: role,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
        profile: PublicProfile.fromJson({'user_id': id, ...r}, fallbackName: displayName),
        fullName: r.containsKey('full_name') ? _s(r['full_name']) : fullName,
        avatarGlyph: r.containsKey('avatar_glyph') ? _s(r['avatar_glyph']) : avatarGlyph,
        gender: r.containsKey('gender') ? _s(r['gender']) : gender,
        timezone: r.containsKey('timezone') ? _s(r['timezone']) : timezone,
        preferredChannel: _s(r['preferred_channel']) ?? preferredChannel,
        // Setting the country also sets the home address country (§2).
        addresses: _s(r['country']) != null && _s(r['country']) != addresses.home?.country
            ? addresses.withAddress(
                AddressKind.home,
                Address(
                  line1: addresses.home?.line1,
                  line2: addresses.home?.line2,
                  city: addresses.home?.city,
                  region: addresses.home?.region,
                  postalCode: addresses.home?.postalCode,
                  country: _s(r['country']),
                  updatedAt: addresses.home?.updatedAt,
                ))
            : addresses,
        privacy: privacy,
        preferences: preferences,
      );

  /// The `PATCH /users/me` reply: the account part (§4).
  Me withAccountReply(Map<String, dynamic> r) => Me(
        id: id,
        username: r.containsKey('username') ? _s(r['username']) : username,
        email: r.containsKey('email') ? _s(r['email']) : email,
        phone: r.containsKey('phone') ? _s(r['phone']) : phone,
        emailVerifiedAt: r.containsKey('email_verified_at') ? _t(r['email_verified_at']) : emailVerifiedAt,
        phoneVerifiedAt: r.containsKey('phone_verified_at') ? _t(r['phone_verified_at']) : phoneVerifiedAt,
        role: _s(r['role']) ?? role,
        status: _s(r['status']) ?? status,
        createdAt: _t(r['created_at']) ?? createdAt,
        updatedAt: _t(r['updated_at']) ?? updatedAt,
        profile: profile,
        fullName: fullName,
        avatarGlyph: avatarGlyph,
        gender: gender,
        timezone: timezone,
        preferredChannel: preferredChannel,
        addresses: addresses,
        privacy: privacy,
        preferences: preferences,
      );
}

/// The fields of `PATCH /users/me/profile`. Null = not sent (left as is),
/// except [clearGender], which sends `gender: null` (§2 "Clearing a value").
@immutable
class ProfilePatch {
  const ProfilePatch({
    this.displayName,
    this.avatarId,
    this.bio,
    this.country,
    this.dateOfBirth,
    this.preferredLanguage,
    this.fullName,
    this.avatarGlyph,
    this.timezone,
    this.gender,
    this.clearGender = false,
    this.preferredChannel,
  });

  final String? displayName;
  final int? avatarId;
  final String? bio;
  final String? country;
  final String? dateOfBirth;
  final String? preferredLanguage;
  final String? fullName;
  final String? avatarGlyph;
  final String? timezone;
  final String? gender;
  final bool clearGender;
  final String? preferredChannel;

  bool get isEmpty => toJson().isEmpty;

  Map<String, dynamic> toJson() => {
        'display_name': ?displayName,
        'avatar_id': ?avatarId,
        'bio': ?bio,
        'country': ?country,
        'date_of_birth': ?dateOfBirth,
        'preferred_language': ?preferredLanguage,
        'full_name': ?fullName,
        'avatar_glyph': ?avatarGlyph,
        'timezone': ?timezone,
        if (clearGender) 'gender': null else 'gender': ?gender,
        'preferred_channel': ?preferredChannel,
      };
}

/// `GET /cosmetics/avatars` row (catalogue; buying is in 11-store.md).
@immutable
class AvatarItem {
  const AvatarItem({
    required this.id,
    required this.code,
    required this.name,
    this.imageUrl,
    this.isPremium = false,
    this.isPurchasable = false,
    this.requiredLevel,
    this.priceCurrency,
    this.priceAmount,
    this.sortOrder = 0,
  });

  final int id;
  final String code;
  final String name;
  final String? imageUrl;
  final bool isPremium;
  final bool isPurchasable;
  final int? requiredLevel;
  final String? priceCurrency;
  final int? priceAmount;
  final int sortOrder;

  /// Free to pick without owning it (§3): not premium, not for sale, no level.
  bool get isFree => !isPremium && !isPurchasable && requiredLevel == null;

  factory AvatarItem.fromJson(Map<String, dynamic> j) => AvatarItem(
        id: _i(j['id']) ?? 0,
        code: _s(j['code']) ?? '',
        name: _s(j['name']) ?? '',
        imageUrl: _s(j['image_url']),
        isPremium: _b(j['is_premium'], false),
        isPurchasable: _b(j['is_purchasable'], false),
        requiredLevel: _i(j['required_level']),
        priceCurrency: _s(j['price_currency']),
        priceAmount: j['price_amount'] == null ? null : parseAmount(j['price_amount']),
        sortOrder: _i(j['sort_order']) ?? 0,
      );
}

/// `GET /users/me/inventory` (§9).
@immutable
class Inventory {
  const Inventory({this.avatarIds = const {}, this.powerUps = const []});

  /// Owned avatar ids (newest first in the reply).
  final Set<int> avatarIds;
  final List<Map<String, dynamic>> powerUps;

  factory Inventory.fromJson(Map<String, dynamic> j) => Inventory(
        avatarIds: {
          for (final a in (j['avatars'] is List ? j['avatars'] as List : const []))
            if (a is Map && _i(a['avatar_id']) != null) _i(a['avatar_id'])!,
        },
        powerUps: [
          for (final p in (j['power_ups'] is List ? j['power_ups'] as List : const []))
            if (p is Map) p.cast<String, dynamic>(),
        ],
      );
}

/// A registered install (§10).
@immutable
class Device {
  const Device({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    this.pushToken,
    this.lastActiveAt,
    this.createdAt,
  });

  /// The server's numeric id — used by the push-token and remove routes.
  final int id;
  final String deviceId;
  final String deviceName;
  final String platform;
  final String? pushToken;
  final DateTime? lastActiveAt;
  final DateTime? createdAt;

  factory Device.fromJson(Map<String, dynamic> j) => Device(
        id: _i(j['id']) ?? 0,
        deviceId: _s(j['device_id']) ?? '',
        deviceName: _s(j['device_name']) ?? '',
        platform: _s(j['platform']) ?? '',
        pushToken: _s(j['push_token']),
        lastActiveAt: _t(j['last_active_at']),
        createdAt: _t(j['created_at']),
      );
}

/// A signed-in session (§11). Times are epoch SECONDS here (Known issues 9).
@immutable
class SignedInSession {
  const SignedInSession({
    required this.sessionId,
    this.ipAddress,
    this.userAgent,
    this.createdAt,
    this.lastActiveAt,
  });

  final String sessionId;
  final String? ipAddress;
  final String? userAgent;
  final DateTime? createdAt;
  final DateTime? lastActiveAt;

  /// "Android 14" from `RoyaleArcade/1.0.0 (Android 14)`; else the whole
  /// user agent; else "Unknown device".
  String get deviceLabel {
    final ua = userAgent?.trim() ?? '';
    if (ua.isEmpty) return 'Unknown device';
    final m = RegExp(r'\(([^)]+)\)').firstMatch(ua);
    final inner = m?.group(1)?.trim();
    return (inner == null || inner.isEmpty) ? ua : inner;
  }

  static DateTime? _epoch(Object? v) {
    final n = _i(v);
    if (n != null) return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
    return _t(v);
  }

  factory SignedInSession.fromJson(Map<String, dynamic> j) => SignedInSession(
        sessionId: (j['session_id'] ?? '').toString(),
        ipAddress: _s(j['ip_address']),
        userAgent: _s(j['user_agent']),
        createdAt: _epoch(j['created_at']),
        lastActiveAt: _epoch(j['last_active_at']),
      );
}

/// The `session_id` claim of a JWT access token (§11a) — the one place the
/// app reads the token. Null when it can't be decoded.
String? sessionIdFromAccessToken(String? token) {
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final claims = jsonDecode(payload);
    final sid = claims is Map ? claims['session_id'] : null;
    return sid is String && sid.isNotEmpty ? sid : null;
  } on Object catch (_) {
    return null;
  }
}
