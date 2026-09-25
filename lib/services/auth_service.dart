import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/data_config.dart';
import '../data/models/user.dart';
import 'api_client.dart';

/// Result of a successful auth call: the player + their session token.
class AuthResult {
  const AuthResult(this.user, this.token);
  final User user;
  final String token;
}

/// Auth endpoints. Static impl (mockapi phase) accepts anything and returns the
/// demo player; remote impl talks to the real API. See docs/INTEGRATION_PLAN.md §5.
abstract class AuthService {
  Future<AuthResult> login({required String email, required String password});
  Future<AuthResult> register({required String name, required String email, required String password});
  Future<AuthResult> verifyOtp({required String code});
  Future<void> resetPassword({required String email, required String code, required String newPassword});
  Future<void> logout();
}

class StaticAuthService implements AuthService {
  const StaticAuthService();

  @override
  Future<AuthResult> login({required String email, required String password}) async =>
      const AuthResult(User.demo, 'demo-token');

  @override
  Future<AuthResult> register({required String name, required String email, required String password}) async =>
      AuthResult(User.demo.copyWith(displayName: name.isEmpty ? 'Nova Rider' : name), 'demo-token');

  @override
  Future<AuthResult> verifyOtp({required String code}) async => const AuthResult(User.demo, 'demo-token');

  @override
  Future<void> resetPassword({required String email, required String code, required String newPassword}) async {}

  @override
  Future<void> logout() async {}
}

class RemoteAuthService implements AuthService {
  const RemoteAuthService(this._api);
  final ApiClient _api;

  AuthResult _parse(dynamic data) {
    final map = data as Map<String, dynamic>;
    return AuthResult(
      User.fromJson(map['user'] as Map<String, dynamic>),
      map['token'] as String? ?? '',
    );
  }

  @override
  Future<AuthResult> login({required String email, required String password}) async =>
      _parse(await _api.post('/auth/login', body: {'email': email, 'password': password}));

  @override
  Future<AuthResult> register({required String name, required String email, required String password}) async =>
      _parse(await _api.post('/auth/register', body: {'name': name, 'email': email, 'password': password}));

  @override
  Future<AuthResult> verifyOtp({required String code}) async =>
      _parse(await _api.post('/auth/verify-otp', body: {'code': code}));

  @override
  Future<void> resetPassword({required String email, required String code, required String newPassword}) async {
    await _api.post('/auth/reset-password', body: {'email': email, 'code': code, 'password': newPassword});
  }

  @override
  Future<void> logout() async {
    await _api.post('/auth/logout');
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  final remote = ref.watch(useRemoteSourcesProvider);
  final api = ref.watch(apiClientProvider);
  return remote ? RemoteAuthService(api) : const StaticAuthService();
});
