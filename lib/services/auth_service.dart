import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/data_config.dart';
import '../data/models/user.dart';
import 'api_client.dart';

/// Result of a successful auth call: the player + their token pair.
/// The API issues an HS256 JWT access token (15 min) plus an opaque refresh
/// token (7 days, rotated via /auth/refresh). See docs/INTEGRATION_PLAN.md §7b.
class AuthResult {
  const AuthResult(this.user, {this.accessToken = '', this.refreshToken});
  final User user;
  final String accessToken;
  final String? refreshToken;
}

/// Auth endpoints (mockapi phase → real API). Paths per the Portal Gateway API
/// doc: /api/v1/auth/{login,register,refresh,logout}, current user at /users/me.
abstract class AuthService {
  Future<AuthResult> login({required String email, required String password});
  Future<AuthResult> register({required String name, required String email, required String password});
  Future<AuthResult> loginGuest();
  Future<AuthResult> refresh(String refreshToken);
  Future<AuthResult> verifyOtp({required String code});
  Future<void> resetPassword({required String email, required String code, required String newPassword});
  Future<void> logout();

  /// The signed-in player: GET /users/me + GET /users/{id}/profile.
  Future<User> fetchMe();

  /// PATCH /users/me/profile with the changed fields; returns the updated
  /// player. Only non-null arguments are sent.
  Future<User> updateProfile(User current, {String? displayName, String? bio, String? country});
}

class StaticAuthService implements AuthService {
  const StaticAuthService();

  @override
  Future<AuthResult> login({required String email, required String password}) async =>
      const AuthResult(User.demo, accessToken: 'demo-access', refreshToken: 'demo-refresh');

  @override
  Future<AuthResult> register({required String name, required String email, required String password}) async =>
      AuthResult(User.demo.copyWith(displayName: name.isEmpty ? 'Nova Rider' : name),
          accessToken: 'demo-access', refreshToken: 'demo-refresh');

  @override
  Future<AuthResult> loginGuest() async =>
      AuthResult(User.demo.copyWith(displayName: 'Guest'), accessToken: 'demo-access', refreshToken: 'demo-refresh');

  @override
  Future<AuthResult> refresh(String refreshToken) async =>
      const AuthResult(User.demo, accessToken: 'demo-access', refreshToken: 'demo-refresh');

  @override
  Future<AuthResult> verifyOtp({required String code}) async => const AuthResult(User.demo);

  @override
  Future<void> resetPassword({required String email, required String code, required String newPassword}) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<User> fetchMe() async => User.demo;

  @override
  Future<User> updateProfile(User current, {String? displayName, String? bio, String? country}) async =>
      current.copyWith(displayName: displayName, bio: bio, country: country);
}

class RemoteAuthService implements AuthService {
  const RemoteAuthService(this._api);
  final ApiClient _api;

  /// First non-empty string among [keys], checking a `data` envelope too.
  String? _str(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.isNotEmpty) return v;
    }
    if (m['data'] is Map) return _str(m['data'] as Map, keys);
    return null;
  }

  Map<String, dynamic> _unwrap(dynamic body) {
    if (body is Map && body['data'] is Map) return (body['data'] as Map).cast<String, dynamic>();
    return (body as Map).cast<String, dynamic>();
  }

  /// From an auth response, extract the token pair and the user. Now that the
  /// backend serves it, fetch the authoritative profile from `/users/me`
  /// (so the real username is available for the socket identity). Falls back to
  /// an embedded user, then to JWT claims, if that call is unavailable.
  Future<AuthResult> _finish(dynamic body) async {
    final resp = (body as Map).cast<String, dynamic>();
    final access = _str(resp, ['access_token', 'accessToken', 'token', 'jwt']) ?? '';
    final refresh = _str(resp, ['refresh_token', 'refreshToken']);
    if (access.isNotEmpty) _api.authToken = access;
    User user;
    try {
      user = await fetchMe();
    } on Object {
      final embedded = resp['user'] ?? (resp['data'] is Map ? (resp['data'] as Map)['user'] : null);
      user = embedded is Map ? User.fromJson(embedded.cast<String, dynamic>()) : _userFromJwt(access);
    }
    return AuthResult(user, accessToken: access, refreshToken: refresh);
  }

  /// Minimal [User] derived from the access-token JWT claims, used when
  /// /users/me is unavailable. `sub` is the user id; username/email seed a name.
  User _userFromJwt(String jwt) {
    final sub = _jwtClaim(jwt, 'sub') ?? '';
    final username = _jwtClaim(jwt, 'username');
    final name = username ?? _jwtClaim(jwt, 'email') ?? 'Player';
    // Carry the real account username through as the handle — it's the socket
    // `auth.login` identity, so it must not be a guess derived from the email.
    return User.fromJson({'id': sub, 'display_name': name.split('@').first, 'username': ?username});
  }

  /// Reads a single claim from a JWT payload (base64url middle segment).
  String? _jwtClaim(String jwt, String key) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return null;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final map = (jsonDecode(utf8.decode(base64.decode(payload))) as Map).cast<String, dynamic>();
      return map[key]?.toString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AuthResult> login({required String email, required String password}) async =>
      _finish(await _api.post('/auth/login', body: {'email': email, 'password': password}));

  @override
  Future<AuthResult> register({required String name, required String email, required String password}) async =>
      _finish(await _api.post('/auth/register', body: {'username': name, 'email': email, 'password': password}));

  @override
  Future<AuthResult> loginGuest() async => _finish(await _api.post('/guest/create'));

  @override
  Future<AuthResult> refresh(String refreshToken) async =>
      _finish(await _api.post('/auth/refresh', body: {'refresh_token': refreshToken}));

  @override
  Future<AuthResult> verifyOtp({required String code}) async {
    // OTP is bearer-scoped (post-auth) and stubbed (503 outside debug); verifying
    // just re-reads the current account. No token change.
    await _api.post('/otp/verify', body: {'code': code, 'purpose': 'email_verification'});
    return AuthResult(await fetchMe());
  }

  @override
  Future<void> resetPassword({required String email, required String code, required String newPassword}) async {
    // Note: the API exposes bearer /auth/change-password (needs the current
    // password); there is no public forgot-password endpoint. Left as a no-op
    // until that flow exists server-side.
  }

  @override
  Future<void> logout() async {
    await _api.post('/auth/logout');
  }

  /// Account from /users/me, then its profile. A missing/failed profile is not
  /// fatal (new and guest accounts may not have one yet) — the username then
  /// stands in for the display name.
  @override
  Future<User> fetchMe() async {
    final me = _unwrap(await _api.get('/users/me'));
    Map<String, dynamic>? profile;
    final id = me['id']?.toString();
    if (id != null && id.isNotEmpty) {
      try {
        profile = _unwrap(await _api.get('/users/$id/profile'));
      } on Object catch (_) {
        profile = null;
      }
    }
    return User.fromApi(me, profile);
  }

  @override
  Future<User> updateProfile(User current, {String? displayName, String? bio, String? country}) async {
    final body = <String, dynamic>{
      'display_name': ?displayName,
      'bio': ?bio,
      'country': ?country,
    };
    final res = await _api.patch('/users/me/profile', body: body);
    // The API returns the updated profile; if it sends no body, apply locally.
    if (res is Map) return current.withProfile(_unwrap(res));
    return current.copyWith(displayName: displayName, bio: bio, country: country);
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  final remote = ref.watch(useRemoteAuthProvider);
  final api = ref.watch(apiClientProvider);
  return remote ? RemoteAuthService(api) : const StaticAuthService();
});
