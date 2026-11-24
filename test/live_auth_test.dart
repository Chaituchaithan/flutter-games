// Live check of the auth contract against a running gateway. Skipped unless
// the base URL is given:
//
//   flutter test test/live_auth_test.dart --dart-define=LIVE_API=http://192.168.0.235:1280/api/v1
//
// Creates a throwaway `@example.com` account (as docs/services/01-auth.md
// allows on the development server) and walks sign-up → me → refresh →
// forgot password → login → logout. Needs a dev server (it uses `debug_code`).
// Never prints tokens, passwords or codes.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/socket/socket_client.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/auth_service.dart';

const _base = String.fromEnvironment('LIVE_API');

/// Optional: the Ludo socket, e.g. ws://192.168.0.235:1285/ws.
const _ludoWs = String.fromEnvironment('LIVE_LUDO_WS');

(ApiClient, RemoteAuthService) _live() {
  final api = ApiClient(dio: Dio(BaseOptions(baseUrl: '$_base/', contentType: 'application/json')));
  return (api, RemoteAuthService(api));
}

void main() {
  test('auth flow against the live gateway', () async {
    final dio = Dio(BaseOptions(baseUrl: '$_base/', contentType: 'application/json'));
    final api = ApiClient(dio: dio);
    final auth = RemoteAuthService(api);
    String? refresh;
    api.onRefreshToken = () async {
      final r = await auth.refresh(refresh!);
      refresh = r.refreshToken;
      return true;
    };

    final n = DateTime.now().millisecondsSinceEpoch % 100000000;
    final email = 'flutter.live.$n@example.com';
    const password = 'Passw0rd!x';

    // Sign up (with the welcome fields) → signed in, user from /users/me.
    final reg = await auth.register(
        name: 'live_$n',
        email: email,
        password: password,
        extras: const SignUpExtras(entryGame: 'ludo', deviceId: '3f6c2a9e-8d1b-4c55-9a77-0b2e5d4f1a10'));
    expect(reg.user.isGuest, isFalse);
    expect(reg.user.emailVerified, isFalse);
    expect(reg.user.username, 'live_$n');
    expect(reg.expiresIn, isNotNull);
    refresh = reg.refreshToken;

    // Taken email → CONFLICT.
    await expectLater(auth.register(name: 'live2_$n', email: email, password: password),
        throwsA(isA<AppException>().having((e) => e.code, 'code', ApiErrorCode.conflict)));

    // Wrong password → INVALID_CREDENTIALS.
    await expectLater(auth.login(email: email, password: 'wrong-pass-1'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', ApiErrorCode.invalidCredentials)));

    // Bad access token → the client refreshes once and the call succeeds.
    api.authToken = 'not-a-valid-token';
    final me = await auth.fetchMe();
    expect(me.email, email);

    // Change password with a wrong current password: an error, still signed in.
    await expectLater(auth.changePassword(currentPassword: 'wrong-pass-1', newPassword: 'Other0Pass!'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', ApiErrorCode.invalidCredentials)));
    expect((await auth.fetchMe()).email, email);

    // Verify email: send a code, a wrong code is a 200 with verified: false.
    await auth.sendEmailVerifyCode();
    expect(await auth.verifyEmail(code: '000000'), isFalse);

    // Single-use refresh token: the first one is dead now.
    await expectLater(auth.refresh(reg.refreshToken!),
        throwsA(isA<AppException>().having((e) => e.statusCode, 'status', 401)));

    // Forgot password (dev: debug_code) → verify → reset.
    final req = await auth.requestPasswordReset(email: email);
    expect(req.debugCode, isNotNull, reason: 'dev servers return debug_code');
    await expectLater(auth.verifyResetCode(email: email, code: req.debugCode == '000000' ? '111111' : '000000'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', ApiErrorCode.badRequest)));
    final reset = await auth.verifyResetCode(email: email, code: req.debugCode!);
    await auth.resetPassword(resetToken: reset, newPassword: 'NewPassw0rd!');

    // Reset signed out every session: the old access token is dead.
    await expectLater(auth.logout(), throwsA(isA<AppException>().having((e) => e.statusCode, 'status', 401)));

    // Old password fails, new one works; then log out → token blacklisted.
    await expectLater(auth.login(email: email, password: password), throwsA(isA<AppException>()));
    final login = await auth.login(email: email, password: 'NewPassw0rd!');
    expect(login.user.email, email);
    await auth.logout();
    await expectLater(auth.fetchMe(),
        throwsA(isA<AppException>().having((e) => e.code, 'code', ApiErrorCode.tokenBlacklisted)));
  }, timeout: const Timeout(Duration(minutes: 2)), skip: _base.isEmpty ? 'set --dart-define=LIVE_API=<gateway>/api/v1' : false);

  test('guest play, save progress, email-code login errors', () async {
    final (api, auth) = _live();
    final n = DateTime.now().millisecondsSinceEpoch % 100000000;

    final guest = await auth.loginGuest(extras: const SignUpExtras(entryGame: 'ludo'));
    expect(guest.user.isGuest, isTrue);
    expect(guest.user.username, startsWith('guest_'));

    final saved = await auth.convertGuest(username: 'gsave_$n', email: 'gsave.$n@example.com', password: 'Passw0rd!x');
    expect(saved.user.id, guest.user.id, reason: 'same account');
    expect(saved.user.isGuest, isFalse);
    expect(saved.accessToken, isNot(guest.accessToken));

    // Converting again: already a full account.
    await expectLater(auth.convertGuest(username: 'gsave2_$n', email: 'gsave2.$n@example.com', password: 'Passw0rd!x'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', ApiErrorCode.badRequest)));

    // Email-code login: send works (no debug_code); a wrong code is INVALID_CREDENTIALS.
    expect(await auth.sendLoginCode(email: 'gsave.$n@example.com'), const Duration(minutes: 10));
    api.authToken = null;
    await expectLater(auth.verifyLoginCode(email: 'gsave.$n@example.com', code: '000000'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', ApiErrorCode.invalidCredentials)));

    // The new email + password log in.
    expect((await auth.login(email: 'gsave.$n@example.com', password: 'Passw0rd!x')).user.id, guest.user.id);
  }, timeout: const Timeout(Duration(minutes: 2)), skip: _base.isEmpty ? 'set --dart-define=LIVE_API=<gateway>/api/v1' : false);

  test('Ludo socket: established clock, auth.login {token}, ping/pong, error reply by id', () async {
    final (_, auth) = _live();
    final g = await auth.loginGuest();
    final socket = SocketClient(url: Uri.parse(_ludoWs), requestTimeout: const Duration(seconds: 8));
    await socket.connect();
    expect(socket.serverClockOffset.inMinutes.abs(), lessThan(60));
    final ok = await socket.login(token: g.accessToken);
    expect(ok.event, 'auth.login_success');
    expect(socket.status, SocketStatus.authenticated);
    final pong = await socket.request('connection.ping');
    expect(pong.event, 'connection.pong');
    await expectLater(socket.request('room.dance'), throwsA(isA<SocketError>().having((e) => e.code, 'code', 'unknown_event')));
    await socket.close();
  }, skip: _base.isEmpty || _ludoWs.isEmpty ? 'set LIVE_API and LIVE_LUDO_WS' : false);
}
