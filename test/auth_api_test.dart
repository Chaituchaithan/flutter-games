// The auth contract (docs/services/01-auth.md): AuthApi requests/replies,
// typed errors, and the HTTP client's refresh rules. Dio runs against a
// stand-in adapter that answers like the gateway and records each request.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/user.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/auth_service.dart';
import 'package:snakeladder/utils/amount.dart';
import 'package:snakeladder/utils/uuid.dart';

class _Req {
  _Req(this.method, this.path, this.headers, this.body);
  final String method;
  final String path;
  final Map<String, dynamic> headers;
  final dynamic body;
  String? get auth => headers['Authorization'] as String?;
}

typedef _Handler = FutureOr<(int, Object?)> Function(_Req);

class _Gateway implements HttpClientAdapter {
  _Gateway(this.routes);
  final Map<String, _Handler> routes;
  final List<_Req> log = [];

  int count(String route) => log.where((r) => '${r.method} ${r.path}' == route).length;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final req = _Req(o.method, o.uri.path.replaceFirst('/api/v1', ''), Map.of(o.headers), o.data);
    log.add(req);
    final handler = routes['${req.method} ${req.path}'];
    final (status, json) = handler == null ? (404, {'error': 'NOT_FOUND', 'message': 'no route'}) : await handler(req);
    return ResponseBody.fromString(json == null ? '' : jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(_Gateway g) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1/', contentType: 'application/json'))
    ..httpClientAdapter = g;
  return ApiClient(dio: dio);
}

const _me = {
  'id': 'd52bd2c5-635c-45d8-a783-dae10a09c547',
  'username': 'flutterdoc6804',
  'email': 'flutter.doc@example.com',
  'phone': null,
  'role': 'user',
  'status': 'active',
  'created_at': '2026-11-03T11:53:25.097209Z',
  'profile': {
    'user_id': 'd52bd2c5-635c-45d8-a783-dae10a09c547',
    'display_name': 'Doc Player',
    'avatar_url': null,
    'preferred_language': null,
  },
  'full_name': null,
};

(int, Object?) _tokens(String n) => (200, {'access_token': 'acc$n', 'refresh_token': 'ref$n', 'expires_in': 900});

(int, Object?) _err(int status, String code, [Map<String, Object?> extra = const {}]) =>
    (status, {'error': code, 'message': 'developer text: $code', ...extra});

void main() {
  group('AuthApi', () {
    test('register: body, no bearer, 201 token reply, then GET /users/me with the new token', () async {
      final g = _Gateway({
        'POST /auth/register': (_) => (201, {'access_token': 'acc1', 'refresh_token': 'ref1', 'expires_in': 900}),
        'GET /users/me': (_) => (200, _me),
      });
      final api = _client(g)..authToken = 'stale';
      final r = await RemoteAuthService(api).register(name: 'flutterdoc6804', email: 'a@example.com', password: 'Passw0rd!x');

      final reg = g.log.first;
      expect(reg.body, {'username': 'flutterdoc6804', 'email': 'a@example.com', 'password': 'Passw0rd!x', 'entry_source': 'direct'});
      expect(reg.auth, isNull, reason: 'public call: no Authorization header');
      expect(g.log[1].auth, 'Bearer acc1');
      expect(g.count('GET /users/${_me['id']}/profile'), 0, reason: 'profile is embedded in /users/me');
      expect(r.accessToken, 'acc1');
      expect(r.refreshToken, 'ref1');
      expect(r.expiresIn, const Duration(seconds: 900));
      expect(r.user.username, 'flutterdoc6804');
      expect(r.user.displayName, 'Doc Player');
      expect(api.accessExpiry!.difference(DateTime.now()).inSeconds, inInclusiveRange(890, 900));
    });

    test('login is by email; a failed /users/me keeps the previous token', () async {
      final g = _Gateway({
        'POST /auth/login': (_) => _tokens('1'),
        'GET /users/me': (_) => _err(500, 'INTERNAL_ERROR'),
      });
      final api = _client(g);
      await expectLater(RemoteAuthService(api).login(email: 'a@example.com', password: 'x'), throwsA(isA<AppException>()));
      expect(g.log.first.body, {'email': 'a@example.com', 'password': 'x'});
      expect(api.authToken, isNull);
    });

    test('refresh: a failed /users/me still keeps the rotated token pair', () async {
      final g = _Gateway({
        'POST /auth/refresh': (_) => _tokens('2'),
        'GET /users/me': (_) => _err(503, 'SERVICE_UNAVAILABLE'),
      });
      final api = _client(g)..authToken = 'acc1';
      final current = User.fromApi(_me, (_me['profile'] as Map).cast<String, dynamic>());
      final r = await RemoteAuthService(api).refresh('ref1', current: current);
      expect((r.accessToken, r.refreshToken), ('acc2', 'ref2'));
      expect(r.user.username, 'flutterdoc6804');
      expect(api.authToken, 'acc2');
    });

    test('errors are typed and use the app text, never the server message', () async {
      Future<AppException> loginError((int, Object?) reply) async {
        final g = _Gateway({'POST /auth/login': (_) => reply});
        try {
          await RemoteAuthService(_client(g)).login(email: 'a@example.com', password: 'x');
        } on AppException catch (e) {
          return e;
        }
        throw StateError('expected an AppException');
      }

      final bad = await loginError(_err(401, 'INVALID_CREDENTIALS'));
      expect((bad.statusCode, bad.code, bad.message), (401, 'INVALID_CREDENTIALS', 'Email or password is incorrect.'));

      final ban = await loginError(_err(403, 'ACCOUNT_BANNED', {'until': '2026-11-10T08:00:00Z'}));
      expect(ban.isBanned, isTrue);
      expect(ban.until, DateTime.utc(2026, 11, 10, 8));
      expect(ban.message, startsWith('Your account is suspended until '));

      final perm = await loginError(_err(403, 'ACCOUNT_BANNED'));
      expect(perm.message, 'Your account is suspended. Contact support.');

      final field = await loginError(_err(400, 'VALIDATION_ERROR', {'field': 'email'}));
      expect((field.field, field.isValidation), ('email', true));
      expect(field.message, isNot(contains('developer text')));

      expect((await loginError(_err(409, 'CONFLICT'))).message, 'That username or email is already registered.');
      expect((await loginError(_err(429, 'RATE_LIMITED'))).message, 'Too many attempts. Try again in a minute.');
      expect((await loginError(_err(403, 'GEO_BLOCKED'))).message, "Royale Arcade isn't available in your region.");
      expect((await loginError(_err(503, 'UNAVAILABLE'))).message, 'Something went wrong. Try again.');
    });

    test('forgot password: request (debug_code) → verify → reset, all public', () async {
      final g = _Gateway({
        'POST /auth/forgot-password': (_) => (202, {'expires_in': 600, 'debug_code': '123456'}),
        'POST /auth/forgot-password/verify': (_) => (200, {'reset_token': 'rst', 'expires_in': 600}),
        'POST /auth/reset-password': (_) => (204, null),
      });
      final auth = RemoteAuthService(_client(g)..authToken = 'acc');

      final req = await auth.requestPasswordReset(email: 'a@example.com');
      expect(req.expiresIn, const Duration(minutes: 10));
      expect(req.debugCode, '123456');
      final token = await auth.verifyResetCode(email: 'a@example.com', code: '123456');
      expect(token, 'rst');
      await auth.resetPassword(resetToken: token, newPassword: 'NewPassw0rd!');

      expect(g.log.map((r) => r.body), [
        {'email': 'a@example.com'},
        {'email': 'a@example.com', 'code': '123456'},
        {'reset_token': 'rst', 'new_password': 'NewPassw0rd!'},
      ]);
      expect(g.log.map((r) => r.auth), everyElement(isNull));
    });

    test('forgot password: no debug_code on production replies; wrong code is BAD_REQUEST', () async {
      final g = _Gateway({
        'POST /auth/forgot-password': (_) => (202, {'expires_in': 600}),
        'POST /auth/forgot-password/verify': (_) => _err(400, 'BAD_REQUEST'),
      });
      final auth = RemoteAuthService(_client(g));
      expect((await auth.requestPasswordReset(email: 'a@example.com')).debugCode, isNull);
      await expectLater(
        auth.verifyResetCode(email: 'a@example.com', code: '000000'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', ApiErrorCode.badRequest)),
      );
    });

    test('logout sends the bearer token and no body', () async {
      final g = _Gateway({'POST /auth/logout': (_) => (204, null)});
      await RemoteAuthService(_client(g)..authToken = 'acc').logout();
      expect(g.log.single.auth, 'Bearer acc');
      expect(g.log.single.body, isNull);
    });
  });

  group('refresh interceptor', () {
    /// A client whose refresh calls POST /auth/refresh with the current refresh token.
    (ApiClient, List<String>) wired(_Gateway g, {String refresh = 'ref0'}) {
      final api = _client(g)..authToken = 'acc0';
      final used = <String>[];
      var current = refresh;
      api.onRefreshToken = () async {
        used.add(current);
        final r = await RemoteAuthService(api).refresh(current);
        current = r.refreshToken!;
        return true;
      };
      return (api, used);
    }

    test('two requests fail with 401 together: only one refresh, both retried with the new token', () async {
      final refreshGate = Completer<void>();
      final g = _Gateway({
        'GET /wallet/balance': (r) => r.auth == 'Bearer acc1' ? (200, {'coins': 5}) : _err(401, 'UNAUTHORIZED'),
        'GET /friends': (r) => r.auth == 'Bearer acc1' ? (200, <Object>[]) : _err(401, 'UNAUTHORIZED'),
        'POST /auth/refresh': (r) async {
          await refreshGate.future; // hold it so the second 401 arrives meanwhile
          return r.body['refresh_token'] == 'ref0' ? _tokens('1') : _err(401, 'UNAUTHORIZED', {'message': 'refresh token revoked'});
        },
        'GET /users/me': (_) => (200, _me),
      });
      final (api, used) = wired(g);
      var signedOut = false;
      api.onUnauthorized = (_) => signedOut = true;

      final a = api.get('/wallet/balance');
      final b = api.get('/friends');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      refreshGate.complete();
      expect(await a, {'coins': 5});
      expect(await b, isEmpty);

      expect(g.count('POST /auth/refresh'), 1);
      expect(used, ['ref0']);
      expect(g.log.firstWhere((r) => r.path == '/auth/refresh').auth, isNull, reason: 'refresh is public');
      await Future<void>.delayed(Duration.zero);
      expect(signedOut, isFalse);
    });

    test('a 401 that arrives after another request already refreshed just retries', () async {
      final g = _Gateway({
        'GET /friends': (r) => r.auth == 'Bearer acc1' ? (200, <Object>[]) : _err(401, 'UNAUTHORIZED'),
        'POST /auth/refresh': (_) => _tokens('1'),
        'GET /users/me': (_) => (200, _me),
      });
      final (api, _) = wired(g);
      await api.get('/friends');
      // Simulate a late 401 for a request sent with the old token.
      api.authToken = 'acc1';
      await api.get('/friends');
      expect(g.count('POST /auth/refresh'), 1);
    });

    test('retries once only: still 401 after the refresh → signed out', () async {
      final g = _Gateway({
        'GET /friends': (_) => _err(401, 'UNAUTHORIZED'),
        'POST /auth/refresh': (_) => _tokens('1'),
        'GET /users/me': (_) => (200, _me),
      });
      final (api, _) = wired(g);
      AppException? reason;
      api.onUnauthorized = (e) => reason = e;
      await expectLater(api.get('/friends'), throwsA(isA<AppException>()));
      await Future<void>.delayed(Duration.zero);
      expect(g.count('GET /friends'), 2);
      expect(g.count('POST /auth/refresh'), 1);
      expect(reason?.statusCode, 401);
    });

    test('TOKEN_BLACKLISTED: no refresh, signed out', () async {
      final g = _Gateway({'GET /friends': (_) => _err(401, 'TOKEN_BLACKLISTED')});
      final (api, _) = wired(g);
      AppException? reason;
      api.onUnauthorized = (e) => reason = e;
      await expectLater(api.get('/friends'), throwsA(isA<AppException>()));
      await Future<void>.delayed(Duration.zero);
      expect(g.count('POST /auth/refresh'), 0);
      expect(reason?.code, ApiErrorCode.tokenBlacklisted);
    });

    test('refresh rejected with ACCOUNT_BANNED: signed out with the ban as the reason, never refreshed again', () async {
      final g = _Gateway({
        'GET /friends': (_) => _err(401, 'UNAUTHORIZED'),
        'POST /auth/refresh': (_) => _err(403, 'ACCOUNT_BANNED', {'until': '2026-12-01T00:00:00Z'}),
      });
      final (api, _) = wired(g);
      AppException? reason;
      api.onUnauthorized = (e) => reason = e;
      await expectLater(api.get('/friends'), throwsA(isA<AppException>().having((e) => e.isBanned, 'banned', isTrue)));
      await Future<void>.delayed(Duration.zero);
      expect(reason?.isBanned, isTrue);
      await expectLater(api.get('/friends'), throwsA(isA<AppException>()));
      expect(g.count('POST /auth/refresh'), 1);
    });

    test('refresh fails offline: the session is kept', () async {
      final g = _Gateway({
        'GET /friends': (_) => _err(401, 'UNAUTHORIZED'),
        'POST /auth/refresh': (_) => throw DioException.connectionError(
            requestOptions: RequestOptions(path: '/auth/refresh'), reason: 'offline'),
      });
      final (api, _) = wired(g);
      var signedOut = false;
      api.onUnauthorized = (_) => signedOut = true;
      await expectLater(api.get('/friends'), throwsA(isA<AppException>().having((e) => e.isOffline, 'offline', isTrue)));
      await Future<void>.delayed(Duration.zero);
      expect(signedOut, isFalse);
    });

    test('expiry under 60 s: refreshed before the request', () async {
      final g = _Gateway({
        'GET /friends': (r) => r.auth == 'Bearer acc1' ? (200, <Object>[]) : _err(401, 'UNAUTHORIZED'),
        'POST /auth/refresh': (_) => _tokens('1'),
        'GET /users/me': (_) => (200, _me),
      });
      final (api, _) = wired(g);
      api.accessExpiry = DateTime.now().add(const Duration(seconds: 30));
      await api.get('/friends');
      expect(g.log.where((r) => r.path == '/friends').map((r) => r.auth), ['Bearer acc1'], reason: 'no 401 round trip');
    });

    test('never refreshes on a 401 from an auth call (login, logout)', () async {
      final g = _Gateway({
        'POST /auth/login': (_) => _err(401, 'INVALID_CREDENTIALS'),
        'POST /auth/logout': (_) => _err(401, 'TOKEN_BLACKLISTED'),
      });
      final (api, _) = wired(g);
      api.accessExpiry = DateTime.now(); // expired: still no refresh before a logout
      await expectLater(api.post('/auth/login', body: {}), throwsA(isA<AppException>()));
      await expectLater(api.post('/auth/logout'), throwsA(isA<AppException>()));
      expect(g.count('POST /auth/refresh'), 0);
    });
  });

  group('guest, email codes, extras (01-auth.md §1, §7–9)', () {
    test('sign-up extras: referral, entry game/source, device id; bad source falls back to direct', () {
      const x = SignUpExtras(referralCode: ' FRIEND42 ', entryGame: 'ludo', entrySource: 'store', deviceId: 'dev-1');
      expect(x.toJson(), {'referral_code': 'FRIEND42', 'entry_game': 'ludo', 'entry_source': 'store', 'device_id': 'dev-1'});
      expect(x.toJson(includeReferral: false).containsKey('referral_code'), isFalse);
      expect(const SignUpExtras(entrySource: 'tv').toJson(), {'entry_source': 'direct'});
    });

    test('guest create: public, welcome body, user_id reply; /users/me email null = guest', () async {
      final g = _Gateway({
        'POST /guest/create': (_) => (201, {'user_id': 'a116', 'access_token': 'g1', 'refresh_token': 'gr1', 'expires_in': 900}),
        'GET /users/me': (_) => (200, {'id': 'a116', 'username': 'guest_a1164ecb', 'email': null, 'email_verified_at': null}),
      });
      final r = await RemoteAuthService(_client(g))
          .loginGuest(extras: const SignUpExtras(entryGame: 'ludo', deviceId: 'dev-1', referralCode: 'X'));
      expect(g.log.first.auth, isNull);
      expect(g.log.first.body, {'entry_game': 'ludo', 'entry_source': 'direct', 'device_id': 'dev-1'});
      expect(r.user.isGuest, isTrue);
      expect(r.user.displayName, 'guest_a1164ecb');
    });

    test('a full account is not a guest; email_verified_at is read', () {
      final u = User.fromApi({'id': '1', 'username': 'guest_lover', 'email': 'a@example.com', 'email_verified_at': '2026-11-24T08:00:00Z'});
      expect(u.isGuest, isFalse);
      expect(u.emailVerified, isTrue);
      expect(User.fromApi({'id': '1', 'username': 'x', 'email': 'a@example.com', 'email_verified_at': null}).emailVerified, isFalse);
    });

    test('guest convert: guest bearer, new token pair, same id', () async {
      final g = _Gateway({
        'POST /guest/convert': (_) => (200, {'user_id': 'a116', 'access_token': 'f1', 'refresh_token': 'fr1', 'expires_in': 900}),
        'GET /users/me': (_) => (200, {'id': 'a116', 'username': 'saved', 'email': 's@example.com'}),
      });
      final api = _client(g)..authToken = 'g1';
      final r = await RemoteAuthService(api).convertGuest(username: 'saved', email: 's@example.com', password: 'Passw0rd!x');
      expect(g.log.first.auth, 'Bearer g1');
      expect(g.log.first.body, {'username': 'saved', 'email': 's@example.com', 'password': 'Passw0rd!x'});
      expect((r.accessToken, r.refreshToken, r.user.id, r.user.isGuest), ('f1', 'fr1', 'a116', false));
    });

    test('email-code login: both calls public; the verify reply signs in', () async {
      final g = _Gateway({
        'POST /otp/login/send': (_) => (200, {'purpose': 'login', 'expires_in': 600}),
        'POST /otp/login/verify': (r) => r.body['code'] == '123456' ? _tokens('1') : _err(401, 'INVALID_CREDENTIALS'),
        'GET /users/me': (_) => (200, _me),
      });
      final auth = RemoteAuthService(_client(g)..authToken = 'stale');
      expect(await auth.sendLoginCode(email: 'a@example.com'), const Duration(minutes: 10));
      await expectLater(auth.verifyLoginCode(email: 'a@example.com', code: '000000'),
          throwsA(isA<AppException>().having((e) => e.code, 'code', ApiErrorCode.invalidCredentials)));
      final r = await auth.verifyLoginCode(email: 'a@example.com', code: '123456');
      expect(r.accessToken, 'acc1');
      expect(g.log.where((x) => x.path.startsWith('/otp/')).map((x) => x.auth), everyElement(isNull));
      expect(g.log.first.body, {'email': 'a@example.com'});
    });

    test('verify email: purpose email_verify; checks `verified`, not the status', () async {
      final g = _Gateway({
        'POST /otp/send': (_) => (200, {'purpose': 'email_verify', 'expires_in': 600}),
        'POST /otp/verify': (r) => (200, {'verified': r.body['code'] == '123456'}),
      });
      final auth = RemoteAuthService(_client(g)..authToken = 'acc');
      await auth.sendEmailVerifyCode();
      expect(g.log.first.body, {'purpose': 'email_verify'});
      expect(g.log.first.auth, 'Bearer acc');
      expect(await auth.verifyEmail(code: '000000'), isFalse);
      expect(await auth.verifyEmail(code: '123456'), isTrue);
      expect(g.log.last.body, {'purpose': 'email_verify', 'code': '123456'});
    });
  });

  group('conventions (00-conventions.md)', () {
    test('change password: 401 INVALID_CREDENTIALS is an error, never a refresh or sign-out', () async {
      final g = _Gateway({'POST /auth/change-password': (_) => _err(401, 'INVALID_CREDENTIALS')});
      final api = _client(g)..authToken = 'acc';
      var refreshed = false, signedOut = false;
      api.onRefreshToken = () async => refreshed = true;
      api.onUnauthorized = (_) => signedOut = true;
      await expectLater(RemoteAuthService(api).changePassword(currentPassword: 'x', newPassword: 'NewPassw0rd!'),
          throwsA(isA<AppException>().having((e) => e.code, 'code', ApiErrorCode.invalidCredentials)));
      await Future<void>.delayed(Duration.zero);
      expect((refreshed, signedOut), (false, false));
    });

    test('a signed-in auth call (OTP send) still refreshes on UNAUTHORIZED', () async {
      final g = _Gateway({
        'POST /otp/send': (r) => r.auth == 'Bearer acc1' ? (200, {'expires_in': 600}) : _err(401, 'UNAUTHORIZED'),
        'POST /auth/refresh': (_) => _tokens('1'),
        'GET /users/me': (_) => (200, _me),
      });
      final api = _client(g)..authToken = 'acc0';
      api.onRefreshToken = () async {
        await RemoteAuthService(api).refresh('ref0');
        return true;
      };
      await RemoteAuthService(api).sendEmailVerifyCode();
      expect(g.count('POST /auth/refresh'), 1);
    });

    for (final code in ['TOKEN_EXPIRED', 'SESSION_NOT_FOUND', 'FINGERPRINT_MISMATCH']) {
      test('401 $code: log in again — no refresh, signed out', () async {
        final g = _Gateway({'GET /sensitive/daily-bonus/status': (_) => _err(401, code)});
        final api = _client(g)..authToken = 'acc';
        var refreshed = false;
        AppException? reason;
        api.onRefreshToken = () async => refreshed = true;
        api.onUnauthorized = (e) => reason = e;
        await expectLater(api.get('/sensitive/daily-bonus/status'), throwsA(isA<AppException>()));
        await Future<void>.delayed(Duration.zero);
        expect(refreshed, isFalse);
        expect(reason?.code, code);
      });
    }

    test('503 DATABASE_BUSY is retried once after a second', () async {
      var calls = 0;
      final g = _Gateway({'GET /games': (_) => ++calls == 1 ? _err(503, 'DATABASE_BUSY') : (200, <Object>[])});
      final api = _client(g);
      expect(await api.get('/games'), isEmpty);
      expect(calls, 2);
      final g2 = _Gateway({'GET /games': (_) => _err(503, 'DATABASE_BUSY')});
      await expectLater(_client(g2).get('/games'), throwsA(isA<AppException>()));
      expect(g2.count('GET /games'), 2, reason: 'one retry only');
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('503 KILL_SWITCH_ENGAGED shows the operator message; other messages never', () async {
      final g = _Gateway({
        'POST /matchmaking/join': (_) => (503, {'error': 'KILL_SWITCH_ENGAGED', 'message': 'Back at 6 pm'}),
        'GET /nope': (_) => (404, {'error': 'NOT_FOUND', 'message': 'not found: no route for GET /api/v1/nope'}),
      });
      final api = _client(g);
      await expectLater(api.post('/matchmaking/join'),
          throwsA(isA<AppException>().having((e) => e.message, 'message', 'Back at 6 pm').having((e) => e.isKillSwitch, 'kill', true)));
      await expectLater(api.get('/nope'), throwsA(isA<AppException>().having((e) => e.message, 'message', 'Not found.')));
    });

    test('money parses numbers and numeric strings', () {
      expect([parseAmount('0'), parseAmount('1500'), parseAmount(100), parseAmount(2.0), parseAmount(null), parseAmount('x')],
          [0, 1500, 100, 2, 0, 0]);
    });

    test('device id is a v4 UUID', () {
      expect(newUuidV4(), matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });
  });
}
