import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/configs.dart';
import '../data/models/user.dart';
import 'account_store.dart';
import 'api_client.dart';
import 'app_exception.dart';

/// Result of a successful auth call: the player + their token pair.
/// The API issues an access token (15 min) plus an opaque, single-use refresh
/// token (7 days, rotated via /auth/refresh). Both are opaque to the app — it
/// never decodes them. Contract: docs/services/01-auth.md.
class AuthResult {
  const AuthResult(this.user, {this.accessToken = '', this.refreshToken, this.expiresIn});
  final User user;
  final String accessToken;
  final String? refreshToken;

  /// `expires_in` of the access token; the expiry is `now + expiresIn`.
  final Duration? expiresIn;
}

/// Optional welcome fields for sign-up and guest create (01-auth.md §1, §7a).
/// Null fields are left out of the body.
class SignUpExtras {
  const SignUpExtras({this.referralCode, this.entryGame, this.entrySource = 'direct', this.deviceId});

  /// A friend's code; a wrong or used-up code never fails the sign-up.
  final String? referralCode;

  /// The game code the player came in through (`ludo`, `snake-and-ladder`).
  final String? entryGame;

  /// `direct` · `deeplink` · `store` · `invite` · `ad` (anything else is a 400).
  final String entrySource;

  /// This install's stable id ([TokenStore.deviceId]).
  final String? deviceId;

  static const sources = {'direct', 'deeplink', 'store', 'invite', 'ad'};

  Map<String, dynamic> toJson({bool includeReferral = true}) => {
        if (includeReferral && referralCode != null && referralCode!.trim().isNotEmpty) 'referral_code': referralCode!.trim(),
        'entry_game': ?entryGame,
        'entry_source': sources.contains(entrySource) ? entrySource : 'direct',
        'device_id': ?deviceId,
      };
}

/// Forgot password step 1 reply (`202`).
class PasswordResetRequest {
  const PasswordResetRequest({required this.expiresIn, this.debugCode});

  /// How long the emailed code is valid (10 min).
  final Duration expiresIn;

  /// Development servers only (no email provider yet): the code itself. May
  /// pre-fill the code field in debug builds; never relied on.
  final String? debugCode;
}

/// Auth endpoints (mockapi phase → real API). Paths per the Portal Gateway API
/// doc: /api/v1/auth/{login,register,refresh,logout}, current user at /users/me.
abstract class AuthService {
  Future<AuthResult> login({required String email, required String password});
  Future<AuthResult> register({required String name, required String email, required String password, SignUpExtras extras});

  /// POST /guest/create — a real account with no email or password.
  Future<AuthResult> loginGuest({SignUpExtras extras});

  /// POST /guest/convert (the guest's token) — same id, now with email +
  /// password; returns a new token pair.
  Future<AuthResult> convertGuest({required String username, required String email, required String password});
  ///
  /// [current]: the signed-in player. If the profile read after the token
  /// rotation fails, the new pair is still returned with [current], because
  /// the old refresh token is already dead.
  Future<AuthResult> refresh(String refreshToken, {User? current});

  /// Log in with an email code 1: POST /otp/login/send. Same reply for an
  /// unknown email. Returns how long the code is valid.
  Future<Duration> sendLoginCode({required String email});

  /// Log in with an email code 2: POST /otp/login/verify → token reply.
  Future<AuthResult> verifyLoginCode({required String email, required String code});

  /// Verify email 1 (signed in): POST /otp/send {purpose: email_verify}.
  Future<Duration> sendEmailVerifyCode();

  /// Verify email 2: POST /otp/verify — true when verified. A wrong code is a
  /// `200 {"verified": false}`, so this returns false rather than throwing.
  Future<bool> verifyEmail({required String code});

  /// Forgot password 1: POST /auth/forgot-password — emails a 6-digit code.
  /// The reply is the same whether or not the email has an account.
  Future<PasswordResetRequest> requestPasswordReset({required String email});

  /// Forgot password 2: POST /auth/forgot-password/verify — returns the reset
  /// token (10 min, single use). Keep it in memory only.
  Future<String> verifyResetCode({required String email, required String code});

  /// Forgot password 3: POST /auth/reset-password. Every session of the
  /// account, on every device, is signed out.
  Future<void> resetPassword({required String resetToken, required String newPassword});

  /// POST /auth/change-password. The server then revokes every session.
  Future<void> changePassword({required String currentPassword, required String newPassword});
  Future<void> logout();

  /// The signed-in player: GET /users/me + GET /users/{id}/profile.
  Future<User> fetchMe();

  /// PATCH /users/me/profile with the changed fields; returns the updated
  /// player. Only non-null arguments are sent.
  Future<User> updateProfile(User current, {String? displayName, String? bio, String? country, String? preferredLanguage, String? dateOfBirth});
}

class StaticAuthService implements AuthService {
  const StaticAuthService();

  @override
  Future<AuthResult> login({required String email, required String password}) async =>
      const AuthResult(User.demo, accessToken: 'demo-access', refreshToken: 'demo-refresh');

  @override
  Future<AuthResult> register({required String name, required String email, required String password, SignUpExtras extras = const SignUpExtras()}) async =>
      AuthResult(User.demo.copyWith(displayName: name.isEmpty ? 'Player' : name),
          accessToken: 'demo-access', refreshToken: 'demo-refresh');

  @override
  Future<AuthResult> loginGuest({SignUpExtras extras = const SignUpExtras()}) async =>
      AuthResult(User.demo.copyWith(displayName: 'Guest'), accessToken: 'demo-access', refreshToken: 'demo-refresh');

  @override
  Future<AuthResult> convertGuest({required String username, required String email, required String password}) async =>
      AuthResult(User.demo.copyWith(displayName: username), accessToken: 'demo-access', refreshToken: 'demo-refresh');

  @override
  Future<Duration> sendLoginCode({required String email}) async => const Duration(minutes: 10);

  @override
  Future<AuthResult> verifyLoginCode({required String email, required String code}) async =>
      const AuthResult(User.demo, accessToken: 'demo-access', refreshToken: 'demo-refresh');

  @override
  Future<Duration> sendEmailVerifyCode() async => const Duration(minutes: 10);

  @override
  Future<bool> verifyEmail({required String code}) async => true;

  @override
  Future<AuthResult> refresh(String refreshToken, {User? current}) async =>
      const AuthResult(User.demo, accessToken: 'demo-access', refreshToken: 'demo-refresh');


  @override
  Future<PasswordResetRequest> requestPasswordReset({required String email}) async =>
      const PasswordResetRequest(expiresIn: Duration(minutes: 10), debugCode: '123456');

  @override
  Future<String> verifyResetCode({required String email, required String code}) async => 'demo-reset';

  @override
  Future<void> resetPassword({required String resetToken, required String newPassword}) async {}

  @override
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<User> fetchMe() async => User.demo;

  @override
  Future<User> updateProfile(User current, {String? displayName, String? bio, String? country, String? preferredLanguage, String? dateOfBirth}) async =>
      current.copyWith(
          displayName: displayName,
          bio: bio,
          country: country,
          preferredLanguage: preferredLanguage,
          dateOfBirth: dateOfBirth);
}

class RemoteAuthService implements AuthService {
  const RemoteAuthService(this._api, {this.onMe});
  final ApiClient _api;

  /// Gets every raw `GET /users/me` this service reads, so the account store
  /// (02-profile-and-sessions.md) is filled without a second read.
  final void Function(Map<String, dynamic> me)? onMe;

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

  /// From a token reply (`access_token`, `refresh_token`, `expires_in`), set
  /// the token and read the player from `GET /users/me` — the only source of
  /// who the user is (the JWT is opaque). If that read fails, the previous
  /// token is put back and the error is rethrown.
  Future<AuthResult> _finish(dynamic body, {User? fallback}) async {
    final resp = (body as Map).cast<String, dynamic>();
    final access = _str(resp, ['access_token', 'accessToken', 'token']) ?? '';
    final refresh = _str(resp, ['refresh_token', 'refreshToken']);
    final rawExpires = resp['expires_in'] ?? (resp['data'] is Map ? (resp['data'] as Map)['expires_in'] : null);
    final expiresIn = rawExpires is num ? Duration(seconds: rawExpires.toInt()) : null;
    final previous = _api.authToken;
    final previousExpiry = _api.accessExpiry;
    if (access.isNotEmpty) {
      _api.authToken = access;
      _api.accessExpiry = expiresIn == null ? null : DateTime.now().add(expiresIn);
    }
    User user;
    try {
      user = await fetchMe();
    } on Object {
      final embedded = resp['user'] ?? (resp['data'] is Map ? (resp['data'] as Map)['user'] : null);
      if (embedded is! Map && fallback != null && access.isNotEmpty) {
        // Refresh: the tokens rotated, so keep the new pair and the player.
        return AuthResult(fallback, accessToken: access, refreshToken: refresh, expiresIn: expiresIn);
      }
      if (embedded is! Map) {
        _api.authToken = previous;
        _api.accessExpiry = previousExpiry;
        rethrow;
      }
      user = User.fromJson(embedded.cast<String, dynamic>());
    }
    return AuthResult(user, accessToken: access, refreshToken: refresh, expiresIn: expiresIn);
  }

  @override
  Future<AuthResult> login({required String email, required String password}) async =>
      _finish(await _api.post(ApiEndpoints.authLogin, body: {'email': email, 'password': password}));

  @override
  Future<AuthResult> register({required String name, required String email, required String password, SignUpExtras extras = const SignUpExtras()}) async =>
      _finish(await _api.post(ApiEndpoints.authRegister,
          body: {'username': name, 'email': email, 'password': password, ...extras.toJson()}));

  @override
  Future<AuthResult> loginGuest({SignUpExtras extras = const SignUpExtras()}) async =>
      _finish(await _api.post(ApiEndpoints.guestCreate, body: extras.toJson(includeReferral: false)));

  @override
  Future<AuthResult> convertGuest({required String username, required String email, required String password}) async =>
      _finish(await _api.post(ApiEndpoints.guestConvert, body: {'username': username, 'email': email, 'password': password}));

  Duration _expires(dynamic res) {
    final secs = res is Map ? res['expires_in'] : null;
    return Duration(seconds: secs is num ? secs.toInt() : 600);
  }

  @override
  Future<Duration> sendLoginCode({required String email}) async =>
      _expires(await _api.post(ApiEndpoints.otpLoginSend, body: {'email': email}));

  @override
  Future<AuthResult> verifyLoginCode({required String email, required String code}) async =>
      _finish(await _api.post(ApiEndpoints.otpLoginVerify, body: {'email': email, 'code': code}));

  @override
  Future<Duration> sendEmailVerifyCode() async =>
      _expires(await _api.post(ApiEndpoints.otpSend, body: {'purpose': 'email_verify'}));

  @override
  Future<bool> verifyEmail({required String code}) async {
    final res = await _api.post(ApiEndpoints.otpVerify, body: {'purpose': 'email_verify', 'code': code});
    return res is Map && res['verified'] == true;
  }

  @override
  Future<AuthResult> refresh(String refreshToken, {User? current}) async =>
      _finish(await _api.post(ApiEndpoints.authRefresh, body: {'refresh_token': refreshToken}), fallback: current);

  @override
  Future<PasswordResetRequest> requestPasswordReset({required String email}) async {
    final res = await _api.post(ApiEndpoints.authForgotPassword, body: {'email': email});
    final m = res is Map ? res : const {};
    final secs = m['expires_in'];
    final debug = m['debug_code'];
    return PasswordResetRequest(
      expiresIn: Duration(seconds: secs is num ? secs.toInt() : 600),
      debugCode: debug is String && debug.isNotEmpty ? debug : null,
    );
  }

  @override
  Future<String> verifyResetCode({required String email, required String code}) async {
    final res = await _api.post(ApiEndpoints.authForgotPasswordVerify, body: {'email': email, 'code': code});
    final token = res is Map ? _str(res, ['reset_token']) : null;
    if (token == null) throw const AppException('Something went wrong. Try again.');
    return token;
  }

  @override
  Future<void> resetPassword({required String resetToken, required String newPassword}) async {
    await _api.post(ApiEndpoints.authResetPassword, body: {'reset_token': resetToken, 'new_password': newPassword});
  }

  @override
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    await _api.post(ApiEndpoints.authChangePassword,
        body: {'current_password': currentPassword, 'new_password': newPassword});
  }

  @override
  Future<void> logout() async {
    await _api.post(ApiEndpoints.authLogout);
  }

  /// Account from /users/me, then its profile. A missing/failed profile is not
  /// fatal (new and guest accounts may not have one yet) — the username then
  /// stands in for the display name.
  @override
  Future<User> fetchMe() async {
    final me = _unwrap(await _api.get(ApiEndpoints.usersMe));
    onMe?.call(me);
    // /users/me embeds the profile; older servers need the separate read.
    if (me['profile'] is Map) return User.fromApi(me, (me['profile'] as Map).cast<String, dynamic>());
    Map<String, dynamic>? profile;
    final id = me['id']?.toString();
    if (id != null && id.isNotEmpty) {
      try {
        profile = _unwrap(await _api.get(ApiEndpoints.userProfile(id)));
      } on Object catch (_) {
        profile = null;
      }
    }
    return User.fromApi(me, profile);
  }

  @override
  Future<User> updateProfile(User current, {String? displayName, String? bio, String? country, String? preferredLanguage, String? dateOfBirth}) async {
    final body = <String, dynamic>{
      'display_name': ?displayName,
      'bio': ?bio,
      'country': ?country,
      'preferred_language': ?preferredLanguage,
      'date_of_birth': ?dateOfBirth,
    };
    final res = await _api.patch(ApiEndpoints.usersMeProfile, body: body);
    // The API returns the updated profile; if it sends no body, apply locally.
    if (res is Map) return current.withProfile(_unwrap(res));
    return current.copyWith(
        displayName: displayName,
        bio: bio,
        country: country,
        preferredLanguage: preferredLanguage,
        dateOfBirth: dateOfBirth);
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  final remote = ref.watch(useRemoteAuthProvider);
  final api = ref.watch(apiClientProvider);
  return remote
      ? RemoteAuthService(api, onMe: (me) => ref.read(accountStoreProvider.notifier).seed(me))
      : const StaticAuthService();
});
