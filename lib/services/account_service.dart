import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/configs.dart';
import '../data/models/account.dart';
import 'api_client.dart';
import 'app_exception.dart';
import 'session.dart';

/// The player's own account routes: profile, account fields, addresses,
/// privacy, game preferences, other players' profiles, avatars, devices,
/// sessions and account deletion. Contract: docs/services/02-profile-and-sessions.md.
///
/// Every method returns a typed result or throws the shared [AppException]
/// (mapped by [ApiClient]); [accountErrorText] turns one into this file's
/// player-facing text.
abstract class AccountApi {
  /// `GET /users/me` — the full user object (§1).
  Future<Me> me();

  /// `PATCH /users/me/profile` — returns the flat reply (profile + the five
  /// private fields), to merge with [Me.withProfileReply].
  Future<Map<String, dynamic>> updateProfile(ProfilePatch patch);

  /// `PATCH /users/me` — username, email, phone. [currentPassword] is
  /// required by the server when email or phone changes. Returns the account
  /// part of the user object.
  Future<Map<String, dynamic>> updateAccount({String? username, String? email, String? phone, String? currentPassword});

  /// `DELETE /users/me` with `{password}` (§12). `204`.
  Future<void> deleteAccount(String password);

  /// `GET /users/me/inventory` (§9).
  Future<Inventory> inventory();

  /// `GET /users/me/addresses/{kind}` — null on `404` (none stored).
  Future<Address?> address(AddressKind kind);

  /// `PUT /users/me/addresses/{kind}` — the whole address.
  Future<Address> saveAddress(AddressKind kind, Address address);

  /// `DELETE /users/me/addresses/{kind}` — `204`; a `404` (already gone) is
  /// treated as success.
  Future<void> removeAddress(AddressKind kind);

  Future<PrivacySettings> privacy();
  Future<PrivacySettings> updatePrivacy(Map<String, dynamic> changes);
  Future<GamePreferences> preferences();
  Future<GamePreferences> updatePreferences(Map<String, dynamic> changes);

  /// `GET /users/{id}/profile` — trimmed by the owner's privacy (§8).
  Future<PublicProfile> playerProfile(String userId);

  /// `GET /cosmetics/avatars`.
  Future<List<AvatarItem>> avatarCatalogue();

  /// `GET /devices` (most recently seen first).
  Future<List<Device>> devices();

  /// `POST /devices/register` — `201`, also when already registered. Leaving
  /// [pushToken] out CLEARS the stored token (§10a).
  Future<Device> registerDevice({required String deviceId, required String deviceName, required String platform, String? pushToken});

  /// `PATCH /devices/{id}/push-token`; null stops pushes to this device.
  Future<Device> setPushToken(int id, String? pushToken);

  /// `DELETE /devices/{id}` — does NOT sign that phone out.
  Future<void> removeDevice(int id);

  /// `GET /sessions` (most recently refreshed first).
  Future<List<SignedInSession>> sessions();

  /// `DELETE /sessions/{id}`.
  Future<void> revokeSession(String sessionId);

  /// `DELETE /sessions` — every session, THIS ONE TOO. Returns how many.
  Future<int> revokeAllSessions();
}

Map<String, dynamic> _map(dynamic body) {
  if (body is Map && body['data'] is Map) return (body['data'] as Map).cast<String, dynamic>();
  if (body is Map) return body.cast<String, dynamic>();
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _list(dynamic body) {
  final raw = body is List ? body : (body is Map && body['data'] is List ? body['data'] as List : const []);
  return [for (final e in raw) if (e is Map) e.cast<String, dynamic>()];
}

class RemoteAccountApi implements AccountApi {
  const RemoteAccountApi(this._api);
  final ApiClient _api;

  @override
  Future<Me> me() async => Me.fromJson(_map(await _api.get(ApiEndpoints.usersMe)));

  @override
  Future<Map<String, dynamic>> updateProfile(ProfilePatch patch) async =>
      _map(await _api.patch(ApiEndpoints.usersMeProfile, body: patch.toJson()));

  @override
  Future<Map<String, dynamic>> updateAccount({String? username, String? email, String? phone, String? currentPassword}) async =>
      _map(await _api.patch(ApiEndpoints.usersMe, body: {
        'username': ?username,
        'email': ?email,
        'phone': ?phone,
        if (email != null || phone != null) 'current_password': ?currentPassword,
      }));

  @override
  Future<void> deleteAccount(String password) async {
    await _api.delete(ApiEndpoints.usersMe, body: {'password': password});
  }

  @override
  Future<Inventory> inventory() async => Inventory.fromJson(_map(await _api.get(ApiEndpoints.usersMeInventory)));

  @override
  Future<Address?> address(AddressKind kind) async {
    try {
      return Address.fromJson(_map(await _api.get(ApiEndpoints.usersMeAddress(kind.name))));
    } on AppException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<Address> saveAddress(AddressKind kind, Address address) async =>
      Address.fromJson(_map(await _api.put(ApiEndpoints.usersMeAddress(kind.name), body: address.toJson())));

  @override
  Future<void> removeAddress(AddressKind kind) async {
    try {
      await _api.delete(ApiEndpoints.usersMeAddress(kind.name));
    } on AppException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
  }

  @override
  Future<PrivacySettings> privacy() async => PrivacySettings.fromJson(_map(await _api.get(ApiEndpoints.usersMePrivacy)));

  @override
  Future<PrivacySettings> updatePrivacy(Map<String, dynamic> changes) async =>
      PrivacySettings.fromJson(_map(await _api.patch(ApiEndpoints.usersMePrivacy, body: changes)));

  @override
  Future<GamePreferences> preferences() async =>
      GamePreferences.fromJson(_map(await _api.get(ApiEndpoints.usersMePreferences)));

  @override
  Future<GamePreferences> updatePreferences(Map<String, dynamic> changes) async =>
      GamePreferences.fromJson(_map(await _api.patch(ApiEndpoints.usersMePreferences, body: changes)));

  @override
  Future<PublicProfile> playerProfile(String userId) async =>
      PublicProfile.fromJson(_map(await _api.get(ApiEndpoints.userProfile(userId))));

  @override
  Future<List<AvatarItem>> avatarCatalogue() async =>
      [for (final j in _list(await _api.get(ApiEndpoints.cosmeticsAvatars))) AvatarItem.fromJson(j)]
        ..sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.id.compareTo(b.id));

  @override
  Future<List<Device>> devices() async => [for (final j in _list(await _api.get(ApiEndpoints.devices))) Device.fromJson(j)];

  @override
  Future<Device> registerDevice({required String deviceId, required String deviceName, required String platform, String? pushToken}) async =>
      Device.fromJson(_map(await _api.post(ApiEndpoints.devicesRegister, body: {
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
        if (pushToken != null && pushToken.isNotEmpty) 'push_token': pushToken,
      })));

  @override
  Future<Device> setPushToken(int id, String? pushToken) async =>
      Device.fromJson(_map(await _api.patch(ApiEndpoints.devicePushToken(id), body: {'push_token': pushToken})));

  @override
  Future<void> removeDevice(int id) async {
    await _api.delete(ApiEndpoints.device(id));
  }

  @override
  Future<List<SignedInSession>> sessions() async =>
      [for (final j in _list(await _api.get(ApiEndpoints.sessions))) SignedInSession.fromJson(j)];

  @override
  Future<void> revokeSession(String sessionId) async {
    await _api.delete(ApiEndpoints.session(sessionId));
  }

  @override
  Future<int> revokeAllSessions() async {
    final r = _map(await _api.delete(ApiEndpoints.sessions));
    final n = r['revoked'];
    return n is num ? n.toInt() : 0;
  }
}

/// Demo build (no server): an in-memory account so every screen works.
class DemoAccountApi implements AccountApi {
  DemoAccountApi();

  Me _me = Me.fromJson(const {
    'id': 'me',
    'username': 'player',
    'email': 'player@example.com',
    'role': 'user',
    'status': 'active',
    'profile': {'user_id': 'me', 'display_name': 'Player', 'bio': 'Late-night grinder. Top 5% this season.'},
    'preferred_channel': 'email',
  });
  final Set<String> _sessions = {'demo-session'};

  @override
  Future<Me> me() async => _me;

  @override
  Future<Map<String, dynamic>> updateProfile(ProfilePatch patch) async {
    final p = _me.profile;
    final j = patch.toJson();
    final avatarId = j['avatar_id'] as int? ?? p.avatarId;
    final reply = <String, dynamic>{
      'user_id': _me.id,
      'display_name': j['display_name'] ?? p.displayName,
      'avatar_id': avatarId,
      'avatar_url': avatarId == null ? null : '/assets/avatars/default/$avatarId.svg',
      'bio': j['bio'] ?? p.bio,
      'country': j['country'] ?? p.country,
      'date_of_birth': j['date_of_birth'] ?? p.dateOfBirth,
      'preferred_language': j['preferred_language'] ?? p.preferredLanguage,
      'full_name': j['full_name'] ?? _me.fullName,
      'avatar_glyph': j['avatar_glyph'] ?? _me.avatarGlyph,
      'gender': j.containsKey('gender') ? j['gender'] : _me.gender,
      'timezone': j['timezone'] ?? _me.timezone,
      'preferred_channel': j['preferred_channel'] ?? _me.preferredChannel,
    };
    _me = _me.withProfileReply(reply);
    return reply;
  }

  @override
  Future<Map<String, dynamic>> updateAccount({String? username, String? email, String? phone, String? currentPassword}) async {
    final r = <String, dynamic>{
      'id': _me.id,
      'username': username ?? _me.username,
      'email': email ?? _me.email,
      'phone': phone ?? _me.phone,
    };
    _me = _me.withAccountReply(r);
    return r;
  }

  @override
  Future<void> deleteAccount(String password) async {}

  @override
  Future<Inventory> inventory() async => const Inventory();

  @override
  Future<Address?> address(AddressKind kind) async => kind == AddressKind.home ? _me.addresses.home : _me.addresses.billing;

  @override
  Future<Address> saveAddress(AddressKind kind, Address address) async {
    _me = _me.copyWith(addresses: _me.addresses.withAddress(kind, address));
    return address;
  }

  @override
  Future<void> removeAddress(AddressKind kind) async {
    _me = _me.copyWith(addresses: _me.addresses.withAddress(kind, null));
  }

  @override
  Future<PrivacySettings> privacy() async => _me.privacy;

  @override
  Future<PrivacySettings> updatePrivacy(Map<String, dynamic> changes) async {
    _me = _me.copyWith(privacy: _me.privacy.merge(changes));
    return _me.privacy;
  }

  @override
  Future<GamePreferences> preferences() async => _me.preferences;

  @override
  Future<GamePreferences> updatePreferences(Map<String, dynamic> changes) async {
    _me = _me.copyWith(preferences: _me.preferences.merge(changes));
    return _me.preferences;
  }

  @override
  Future<PublicProfile> playerProfile(String userId) async =>
      PublicProfile(userId: userId, displayName: 'Player', bio: null, country: null);

  @override
  Future<List<AvatarItem>> avatarCatalogue() async => [
        for (final (i, c) in const ['blue', 'green', 'red', 'purple', 'orange', 'yellow', 'teal', 'pink'].indexed)
          AvatarItem(id: i + 1, code: 'default_$c', name: c, sortOrder: i + 1),
        const AvatarItem(
            id: 10, code: 'snl_golden_ladder', name: 'Golden Ladder', isPremium: true, isPurchasable: true,
            requiredLevel: 5, priceCurrency: 'token', priceAmount: 500, sortOrder: 101),
      ];

  @override
  Future<List<Device>> devices() async => const [];

  @override
  Future<Device> registerDevice({required String deviceId, required String deviceName, required String platform, String? pushToken}) async =>
      Device(id: 1, deviceId: deviceId, deviceName: deviceName, platform: platform, pushToken: pushToken);

  @override
  Future<Device> setPushToken(int id, String? pushToken) async =>
      Device(id: id, deviceId: '', deviceName: '', platform: '', pushToken: pushToken);

  @override
  Future<void> removeDevice(int id) async {}

  @override
  Future<List<SignedInSession>> sessions() async => [
        for (final s in _sessions)
          SignedInSession(sessionId: s, userAgent: 'RoyaleArcade/1.0.0 (This phone)', lastActiveAt: DateTime.now()),
      ];

  @override
  Future<void> revokeSession(String sessionId) async => _sessions.remove(sessionId);

  @override
  Future<int> revokeAllSessions() async {
    final n = _sessions.length;
    _sessions.clear();
    return n;
  }
}

/// The real API while signed in; the in-memory demo account in the demo
/// build and while signed out (screens built directly still have data).
final accountApiProvider = Provider<AccountApi>((ref) {
  final remote = ref.watch(useRemoteAuthProvider);
  final signedIn = ref.watch(sessionProvider.select((u) => u != null));
  return remote && signedIn ? RemoteAccountApi(ref.watch(apiClientProvider)) : DemoAccountApi();
});

/// What the player was doing when an [AppException] came back; the same
/// code means different things on different routes.
enum AccountOp { profile, avatar, username, email, phone, address, privacy, preferences, playerProfile, session, deleteAccount, device }

/// Player-facing text for an account-route error (02-profile-and-sessions.md
/// "Errors" tables). Decides on status + code + field, never on `message`.
String accountErrorText(AppException e, AccountOp op) {
  final code = e.code;
  if (e.isOffline || e.kind == AppErrorKind.timeout) return e.message;
  if (code == ApiErrorCode.validation) return accountFieldRule(e.field);
  switch (code) {
    case ApiErrorCode.conflict:
      return switch (op) {
        AccountOp.profile || AccountOp.avatar => 'That name is taken. Try another.',
        AccountOp.username => 'That username is taken.',
        AccountOp.email => 'That email is already registered.',
        AccountOp.phone => 'That number is already in use.',
        AccountOp.deleteAccount => 'Finish or leave your current game or tournament first.',
        _ => e.message,
      };
    case ApiErrorCode.invalidCredentials:
      // Only on PATCH /users/me and DELETE /users/me: a wrong password.
      return 'Your password is incorrect.';
    case ApiErrorCode.forbidden when op == AccountOp.avatar || op == AccountOp.profile:
      return "That avatar isn't unlocked yet.";
    case ApiErrorCode.badRequest:
      if (e.field == 'current_password') return 'Enter your current password to change this.';
      if (op == AccountOp.deleteAccount) return 'Enter your password to delete your account.';
      if (op == AccountOp.avatar) return "That avatar isn't unlocked yet.";
      return 'Something went wrong. Try again.';
    case ApiErrorCode.notFound:
      return switch (op) {
        AccountOp.playerProfile => "This player couldn't be found.",
        AccountOp.session => 'That device is already signed out.',
        _ => e.message,
      };
    case ApiErrorCode.rateLimited:
      return 'Too many requests. Wait a moment and try again.';
  }
  return e.message;
}

/// The rule to show next to a field after a `400 VALIDATION_ERROR`.
String accountFieldRule(String? field) => switch (field) {
      'display_name' => 'Name must be 1 to 64 characters.',
      'avatar_id' => 'Pick an avatar from the list.',
      'bio' => 'Bio can be at most 140 characters.',
      'country' => 'Pick a country from the list.',
      'preferred_language' => 'Pick a language from the list.',
      'full_name' => 'Full name must be 1 to 100 characters.',
      'avatar_glyph' => 'Use 1 or 2 characters.',
      'timezone' => 'Pick a time zone from the list.',
      'gender' => 'Pick an option from the list.',
      'username' => 'Username must be 3 to 32 characters: letters, numbers and _.',
      'email' => 'Enter a valid email address.',
      'phone' => 'Enter the number with its country code, e.g. +919876543210.',
      'current_password' || 'password' => 'Enter your password.',
      'line1' => 'Address line 1 is required (up to 200 characters).',
      'line2' => 'Address line 2 can be at most 200 characters.',
      'city' => 'City is required (up to 100 characters).',
      'region' => 'State or region can be at most 100 characters.',
      'postal_code' => 'Postal code must be 3 to 10 letters, digits, spaces or hyphens.',
      'favourite_game' => 'Pick a game from the list.',
      'device_name' || 'push_token' => 'Something went wrong. Try again.',
      _ => 'Check the highlighted field and try again.',
    };

/// Client checks that match the server rules (§2, §4, §5), so most players
/// never see a `400`. Each returns the error text, or null when valid.
abstract final class AccountRules {
  static final _username = RegExp(r'^[A-Za-z0-9_]{3,32}$');
  static final _e164 = RegExp(r'^\+[1-9][0-9]{1,14}$');
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _postal = RegExp(r'^[A-Za-z0-9 \-]{3,10}$');
  static final _country = RegExp(r'^[A-Z]{2}$');

  static String? displayName(String v) {
    final t = v.trim();
    if (t.isEmpty || t.length > 64) return accountFieldRule('display_name');
    return null;
  }

  static String? bio(String v) => v.length > 140 ? accountFieldRule('bio') : null;

  static String? fullName(String v) {
    final t = v.trim();
    return t.length > 100 ? accountFieldRule('full_name') : null;
  }

  static String? avatarGlyph(String v) {
    final n = v.trim().runes.length;
    return n > 2 ? accountFieldRule('avatar_glyph') : null;
  }

  /// No future dates (the server accepts them: Known issues 4).
  static String? dateOfBirth(DateTime? d, {DateTime? now}) {
    if (d == null) return null;
    return d.isAfter(now ?? DateTime.now()) ? "Your birthday can't be in the future." : null;
  }

  /// Letters, digits and `_` only, as at sign-up (Known issues 5).
  static String? username(String v) => _username.hasMatch(v.trim()) ? null : accountFieldRule('username');

  static String? email(String v) => _email.hasMatch(v.trim()) ? null : accountFieldRule('email');

  /// E.164: `+`, then 2 to 15 digits, not starting with 0, no spaces.
  static String? phone(String v) => _e164.hasMatch(v.trim()) ? null : accountFieldRule('phone');

  static String? country(String? v) => v != null && _country.hasMatch(v) ? null : accountFieldRule('country');

  /// The PUT body rules (§5): field → error; empty when [a] can be saved.
  static Map<String, String> address(Address a) {
    final errs = <String, String>{};
    final l1 = (a.line1 ?? '').trim();
    if (l1.isEmpty || l1.length > 200) errs['line1'] = accountFieldRule('line1');
    if ((a.line2 ?? '').length > 200) errs['line2'] = accountFieldRule('line2');
    final city = (a.city ?? '').trim();
    if (city.isEmpty || city.length > 100) errs['city'] = accountFieldRule('city');
    if ((a.region ?? '').length > 100) errs['region'] = accountFieldRule('region');
    if (!_postal.hasMatch((a.postalCode ?? '').trim())) errs['postal_code'] = accountFieldRule('postal_code');
    if (country(a.country) != null) errs['country'] = accountFieldRule('country');
    return errs;
  }
}
