// Verifies the real profile service calls through ApiClient → Dio, with a
// stand-in HTTP adapter that records each request and answers like the API.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/user.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/auth_service.dart';

class _Req {
  _Req(this.method, this.path, this.auth, this.body);
  final String method;
  final String path;
  final String? auth;
  final dynamic body;
}

/// Answers by "METHOD path"; records every request.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.routes);
  final Map<String, (int, Object?) Function(_Req)> routes;
  final List<_Req> log = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final req = _Req(o.method, o.uri.path, o.headers['Authorization'] as String?, o.data);
    log.add(req);
    final handler = routes['${o.method} ${o.uri.path}'];
    final (status, json) = handler == null ? (404, {'error': 'NOT_FOUND', 'message': 'no route'}) : handler(req);
    return ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _me = {
  'id': '418532b7-5c14-4e0e-8803-00ad6fb350ef',
  'username': 'chaitu01',
  'email': 'chaitu01@gmail.com',
  'role': 'user',
  'created_at': '2026-10-08T16:25:55.915673Z',
};

Map<String, dynamic> _profile({String? name, String? bio, String? country}) => {
      'user_id': _me['id'],
      'display_name': name ?? 'chaitu01',
      'avatar_id': null,
      'avatar_url': null,
      'bio': bio,
      'country': country,
      'date_of_birth': null,
      'preferred_language': null,
    };

ApiClient _client(_FakeAdapter a) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test/api/v1/', contentType: 'application/json'));
  dio.httpClientAdapter = a;
  return ApiClient(dio: dio);
}

void main() {
  test('fetchMe = GET /users/me then GET /users/{id}/profile, bearer attached', () async {
    final a = _FakeAdapter({
      'GET /api/v1/users/me': (_) => (200, _me),
      'GET /api/v1/users/${_me['id']}/profile': (_) => (200, _profile(bio: 'hi')),
    });
    final api = _client(a)..authToken = 'tok';
    final u = await RemoteAuthService(api).fetchMe();
    expect(a.log.map((r) => '${r.method} ${r.path}'), [
      'GET /api/v1/users/me',
      'GET /api/v1/users/${_me['id']}/profile',
    ]);
    expect(a.log.every((r) => r.auth == 'Bearer tok'), isTrue);
    expect(u.username, 'chaitu01');
    expect(u.bio, 'hi');
  });

  test('updateProfile = PATCH /users/me/profile with only changed snake_case fields', () async {
    final a = _FakeAdapter({
      'PATCH /api/v1/users/me/profile': (r) {
        final b = r.body as Map;
        return (200, _profile(name: b['display_name'] as String?, bio: b['bio'] as String?, country: b['country'] as String?));
      },
    });
    final api = _client(a)..authToken = 'tok';
    final current = User.fromApi(_me, _profile());
    final u = await RemoteAuthService(api).updateProfile(current, bio: 'Chess fan', country: 'IN');

    final req = a.log.single;
    expect(req.method, 'PATCH');
    expect(req.path, '/api/v1/users/me/profile');
    expect(req.auth, 'Bearer tok');
    expect(req.body, {'bio': 'Chess fan', 'country': 'IN'}); // display_name unchanged → not sent
    expect(u.bio, 'Chess fan');
    expect(u.country, 'IN');
    expect(u.displayName, 'chaitu01');
  });

  test('language + date of birth go out as preferred_language / date_of_birth', () async {
    final a = _FakeAdapter({
      'PATCH /api/v1/users/me/profile': (r) {
        final b = r.body as Map;
        return (200, {..._profile(), 'preferred_language': b['preferred_language'], 'date_of_birth': b['date_of_birth']});
      },
    });
    final api = _client(a)..authToken = 'tok';
    final current = User.fromApi(_me, _profile());
    final u = await RemoteAuthService(api).updateProfile(current, preferredLanguage: 'es', dateOfBirth: '1998-03-12');
    expect(a.log.single.body, {'preferred_language': 'es', 'date_of_birth': '1998-03-12'});
    expect(u.preferredLanguage, 'es');
    expect(u.dateOfBirth, '1998-03-12');
  });

  test('changePassword = POST /auth/change-password {current_password, new_password}', () async {
    final a = _FakeAdapter({'POST /api/v1/auth/change-password': (_) => (204, null)});
    final api = _client(a)..authToken = 'tok';
    await RemoteAuthService(api).changePassword(currentPassword: 'Old12345', newPassword: 'New12345');
    expect(a.log.single.body, {'current_password': 'Old12345', 'new_password': 'New12345'});
    expect(a.log.single.auth, 'Bearer tok');
  });

  test('wrong current password (401) is an error, not a sign-out', () async {
    final a = _FakeAdapter({
      'POST /api/v1/auth/change-password': (_) => (401, {'error': 'INVALID_CREDENTIALS', 'message': 'invalid credentials'}),
    });
    var signedOut = false;
    final api = _client(a)
      ..authToken = 'tok'
      ..onUnauthorized = () => signedOut = true;
    await expectLater(
      RemoteAuthService(api).changePassword(currentPassword: 'bad', newPassword: 'New12345'),
      throwsA(isA<AppException>().having((e) => e.statusCode, 'status', 401)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(signedOut, isFalse);
  });

  test('expired token: 401 → refresh → PATCH retried once with the new token', () async {
    var token = 'old';
    final a = _FakeAdapter({
      'PATCH /api/v1/users/me/profile': (r) =>
          r.auth == 'Bearer new' ? (200, _profile(bio: 'after refresh')) : (401, {'error': 'TOKEN_EXPIRED', 'message': 'token expired'}),
    });
    final api = _client(a)..authToken = token;
    var refreshed = 0;
    var signedOut = false;
    api.onRefreshToken = () async {
      refreshed++;
      token = 'new';
      api.authToken = token;
      return true;
    };
    api.onUnauthorized = () => signedOut = true;

    final u = await RemoteAuthService(api).updateProfile(User.fromApi(_me, _profile()), bio: 'after refresh');
    expect(refreshed, 1);
    expect(a.log.map((r) => r.auth), ['Bearer old', 'Bearer new']);
    expect(u.bio, 'after refresh');
    await Future<void>.delayed(Duration.zero);
    expect(signedOut, isFalse);
  });

  test('403 on PATCH is an error message, not a sign-out', () async {
    final a = _FakeAdapter({
      'PATCH /api/v1/users/me/profile': (_) => (403, {'error': 'FORBIDDEN', 'message': 'guests cannot edit profiles'}),
    });
    final api = _client(a)..authToken = 'tok';
    var signedOut = false;
    api.onUnauthorized = () => signedOut = true;
    await expectLater(
      RemoteAuthService(api).updateProfile(User.fromApi(_me, _profile()), bio: 'x'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('guests cannot edit profiles'))),
    );
    await Future<void>.delayed(Duration.zero);
    expect(signedOut, isFalse);
  });
}
