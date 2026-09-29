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

  /// From an auth response, extract the token pair and the user (embedded if
  /// present, otherwise fetched from /users/me with the new access token).
  Future<AuthResult> _finish(dynamic body) async {
    final resp = (body as Map).cast<String, dynamic>();
    final access = _str(resp, ['access_token', 'accessToken', 'token', 'jwt']) ?? '';
    final refresh = _str(resp, ['refresh_token', 'refreshToken']);
    final embedded = resp['user'] ?? (resp['data'] is Map ? (resp['data'] as Map)['user'] : null);
    User user;
    if (embedded is Map) {
      user = User.fromJson(embedded.cast<String, dynamic>());
    } else {
      if (access.isNotEmpty) _api.authToken = access; // so /users/me is authorized
      user = User.fromJson(_unwrap(await _api.get('/users/me')));
    }
    return AuthResult(user, accessToken: access, refreshToken: refresh);
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
    return AuthResult(User.fromJson(_unwrap(await _api.get('/users/me'))));
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
}

final authServiceProvider = Provider<AuthService>((ref) {
  final remote = ref.watch(useRemoteAuthProvider);
  final api = ref.watch(apiClientProvider);
  return remote ? RemoteAuthService(api) : const StaticAuthService();
});
