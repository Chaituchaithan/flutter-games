// The profile-and-sessions contract (docs/services/02-profile-and-sessions.md):
// the Me parser (with the doc's samples), AccountApi requests/replies, each
// error's player-facing text, the "this device" session match, and device
// registration on sign-in and on a new push token. Dio runs against a
// stand-in adapter that answers like the gateway and records each request.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/account.dart';
import 'package:snakeladder/services/account_service.dart';
import 'package:snakeladder/services/account_store.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/auth_service.dart';
import 'package:snakeladder/services/session.dart';

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
  return ApiClient(dio: dio)..authToken = 'tok';
}

(int, Object?) _err(int status, String code, [Map<String, Object?> extra = const {}]) =>
    (status, {'error': code, 'message': 'developer text: $code', ...extra});

/// §1: a player who filled in everything (captured live, 24 Nov 2026).
const _full = {
  'id': '2e173b92-a9bb-4bbc-b5d8-f6213ff3b69c',
  'username': 'w02doc1795513371',
  'email': 'w02doc.1795513371@example.com',
  'phone': '+919876513371',
  'email_verified_at': '2026-11-24T09:43:26.107865Z',
  'phone_verified_at': null,
  'role': 'user',
  'status': 'active',
  'created_at': '2026-11-24T09:42:52.077062Z',
  'updated_at': '2026-11-24T09:43:33.141160Z',
  'profile': {
    'user_id': '2e173b92-a9bb-4bbc-b5d8-f6213ff3b69c',
    'display_name': 'Wren Doc',
    'avatar_id': 3,
    'avatar_url': '/assets/avatars/default/red.svg',
    'bio': '',
    'country': 'IN',
    'date_of_birth': '1998-04-12',
    'preferred_language': 'en',
    'updated_at': '2026-11-24T09:43:34.625821Z',
  },
  'full_name': 'Wren Doc',
  'avatar_glyph': 'W',
  'gender': null,
  'timezone': 'Asia/Kolkata',
  'preferred_channel': 'push',
  'addresses': {
    'home': {
      'line1': '12 MG Road',
      'line2': 'Flat 3B',
      'city': 'Bengaluru',
      'region': 'Karnataka',
      'postal_code': '560001',
      'country': 'IN',
      'updated_at': '2026-11-24T09:43:34.625821Z',
    },
    'billing': null,
    'billing_same_as_home': true,
  },
  'privacy': {
    'profile_visibility': 'friends',
    'show_on_leaderboards': true,
    'allow_friend_requests': true,
    'dm_from': 'friends',
    'login_alerts': true,
    'marketing_email': true,
    'marketing_push': true,
    'marketing_sms': true,
  },
  'preferences': {
    'favourite_game': null,
    'default_stake_currency': 'token',
    'remember_last_stake': false,
    'sound': false,
    'haptics': true,
    'table_chat': true,
    'colour_blind': false,
    'reduce_motion': true,
  },
};

/// A brand-new player (seen live).
const _fresh = {
  'id': '7957c40c-1673-4909-bdc8-79c855a99c5d',
  'username': 'w02f14852481',
  'email': 'w02f.14852481@example.com',
  'phone': null,
  'email_verified_at': null,
  'phone_verified_at': null,
  'role': 'user',
  'status': 'active',
  'created_at': '2026-11-24T09:51:10.909588Z',
  'updated_at': '2026-11-24T09:51:10.924950Z',
  'profile': {
    'user_id': '7957c40c-1673-4909-bdc8-79c855a99c5d',
    'display_name': 'w02f14852481',
    'avatar_id': null,
    'avatar_url': null,
    'bio': null,
    'country': null,
    'date_of_birth': null,
    'preferred_language': null,
    'updated_at': '2026-11-24T09:51:10.909588Z',
  },
  'full_name': null,
  'avatar_glyph': null,
  'gender': null,
  'timezone': null,
  'preferred_channel': 'email',
  'addresses': {'home': null, 'billing': null, 'billing_same_as_home': true},
  'privacy': {
    'profile_visibility': 'public',
    'show_on_leaderboards': true,
    'allow_friend_requests': true,
    'dm_from': 'everyone',
    'login_alerts': true,
    'marketing_email': true,
    'marketing_push': true,
    'marketing_sms': false,
  },
  'preferences': {
    'favourite_game': null,
    'default_stake_currency': 'gold',
    'remember_last_stake': false,
    'sound': true,
    'haptics': true,
    'table_chat': true,
    'colour_blind': false,
    'reduce_motion': false,
  },
};

/// A JWT shaped like the gateway's (payload: sub, session_id, iat, exp, role).
String _jwt(Map<String, Object?> claims) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'typ': 'JWT', 'alg': 'HS256'})}.${part(claims)}.c2ln';
}

AppException _ex(int status, String code, {String? field}) =>
    AppException('generic', statusCode: status, code: code, field: field);

void main() {
  group('Me parser', () {
    test('the full sample', () {
      final me = Me.fromJson(_full);
      expect(me.id, '2e173b92-a9bb-4bbc-b5d8-f6213ff3b69c');
      expect(me.username, 'w02doc1795513371');
      expect(me.phone, '+919876513371');
      expect(me.emailVerifiedAt, DateTime.utc(2026, 11, 24, 9, 43, 26, 107, 865));
      expect(me.phoneVerifiedAt, isNull);
      expect(me.isGuest, isFalse);
      expect(me.displayName, 'Wren Doc');
      expect(me.profile.avatarId, 3);
      expect(me.profile.avatarUrl, '/assets/avatars/default/red.svg');
      expect(me.profile.bio, '');
      expect(me.profile.dateOfBirth, '1998-04-12');
      expect((me.fullName, me.avatarGlyph, me.gender, me.timezone, me.preferredChannel),
          ('Wren Doc', 'W', null, 'Asia/Kolkata', 'push'));
      expect(me.glyph, 'W');
      expect(me.addresses.home!.isFilled, isTrue);
      expect(me.addresses.home!.postalCode, '560001');
      expect(me.addresses.billing, isNull);
      expect(me.addresses.billingSameAsHome, isTrue);
      expect(me.privacy.profileVisibility, 'friends');
      expect(me.privacy.dmFrom, 'friends');
      expect(me.privacy.marketingSms, isTrue);
      expect(me.preferences.defaultStakeCurrency, 'token');
      expect(me.preferences.sound, isFalse);
      expect(me.preferences.reduceMotion, isTrue);
      expect(me.preferences.favouriteGame, isNull);
    });

    test('a new player: nulls and the server defaults', () {
      final me = Me.fromJson(_fresh);
      expect(me.displayName, 'w02f14852481');
      expect(me.glyph, 'W', reason: 'no glyph → first letter of the display name');
      expect(me.preferredChannel, 'email');
      expect(me.addresses.home, isNull);
      expect(me.privacy.toJson(), const PrivacySettings().toJson());
      expect(me.preferences.toJson(), const GamePreferences().toJson());
    });

    test('profile: null → all null, the username as display name; a guest has email null', () {
      final me = Me.fromJson({'id': 'u1', 'username': 'guest_ab12cd34', 'email': null, 'profile': null});
      expect(me.displayName, 'guest_ab12cd34');
      expect(me.profile.avatarId, isNull);
      expect(me.isGuest, isTrue);
    });

    test('unknown fields are ignored; numeric strings parse', () {
      final me = Me.fromJson({..._fresh, 'brand_new_field': {'x': 1}, 'profile': {...(_fresh['profile'] as Map), 'avatar_id': '7'}});
      expect(me.profile.avatarId, 7);
    });

    test('a country-only home address is "not filled in"', () {
      final a = Address.fromJson({'line1': null, 'line2': null, 'city': null, 'region': null, 'postal_code': null, 'country': 'IN'});
      expect(a.isFilled, isFalse);
      expect(a.country, 'IN');
    });

    test('PATCH /users/me/profile reply: nine fields to profile, five to Me; country also sets home', () {
      final me = Me.fromJson(_fresh).withProfileReply({
        'user_id': _fresh['id'],
        'display_name': 'Wren Doc',
        'avatar_id': 2,
        'avatar_url': '/assets/avatars/default/green.svg',
        'bio': 'Ludo on Sundays.',
        'country': 'IN',
        'date_of_birth': '1998-04-12',
        'preferred_language': 'en',
        'updated_at': '2026-11-24T09:42:58.204876Z',
        'full_name': 'Wren Doc',
        'avatar_glyph': 'W',
        'gender': 'female',
        'timezone': 'Asia/Kolkata',
        'preferred_channel': 'push',
      });
      expect(me.profile.avatarId, 2);
      expect(me.profile.bio, 'Ludo on Sundays.');
      expect((me.gender, me.timezone, me.preferredChannel), ('female', 'Asia/Kolkata', 'push'));
      expect(me.addresses.home?.country, 'IN');
      expect(me.addresses.home?.isFilled, isFalse);
    });

    test('preferences: "tokens" on input reads back as "token"', () {
      expect(GamePreferences.fromJson({'default_stake_currency': 'tokens'}).defaultStakeCurrency, 'token');
    });

    test('sessions: epoch SECONDS and a readable device name', () {
      final s = SignedInSession.fromJson({
        'session_id': '10a121c5-d359-42db-9649-a6c5d5035a6b',
        'user_id': 'u',
        'ip_address': '127.0.0.1',
        'user_agent': 'RoyaleArcade/1.0.0 (iOS 18.1)',
        'created_at': 1795513375,
        'last_active_at': 1795513375,
      });
      expect(s.createdAt, DateTime.fromMillisecondsSinceEpoch(1795513375000, isUtc: true));
      expect(s.deviceLabel, 'iOS 18.1');
      expect(SignedInSession.fromJson({'session_id': 'x', 'user_agent': 'curl/8'}).deviceLabel, 'curl/8');
      expect(SignedInSession.fromJson({'session_id': 'x'}).deviceLabel, 'Unknown device');
    });

    test('avatar catalogue: free = not premium, not for sale, no level', () {
      final free = AvatarItem.fromJson({'id': 1, 'code': 'default_blue', 'is_premium': false, 'is_purchasable': false, 'required_level': null});
      final paid = AvatarItem.fromJson({
        'id': 10,
        'code': 'snl_golden_ladder',
        'is_premium': true,
        'is_purchasable': true,
        'required_level': 5,
        'price_currency': 'token',
        'price_amount': '500',
      });
      expect(free.isFree, isTrue);
      expect(paid.isFree, isFalse);
      expect(paid.priceAmount, 500);
      final inv = Inventory.fromJson({
        'power_ups': [{'power_up_id': 4, 'code': 'shield', 'quantity': 2}],
        'avatars': [{'avatar_id': 15, 'code': 'ludo_golden_crown', 'source': 'purchase'}],
      });
      expect(inv.avatarIds, {15});
      expect(inv.powerUps.single['code'], 'shield');
    });
  });

  group('This device (§11a)', () {
    test('reads the session_id claim of the access token', () {
      final t = _jwt({'sub': 'u', 'session_id': '8396a79c-d619-45b0-8970-53970c420281', 'iat': 1, 'exp': 2, 'role': 'user'});
      expect(sessionIdFromAccessToken(t), '8396a79c-d619-45b0-8970-53970c420281');
    });

    test('anything undecodable marks no row', () {
      expect(sessionIdFromAccessToken(null), isNull);
      expect(sessionIdFromAccessToken('opaque'), isNull);
      expect(sessionIdFromAccessToken('a.!!!.c'), isNull);
      expect(sessionIdFromAccessToken(_jwt({'sub': 'u'})), isNull);
    });
  });

  group('AccountApi requests', () {
    test('GET /users/me with the bearer', () async {
      final g = _Gateway({'GET /users/me': (_) => (200, _full)});
      final me = await RemoteAccountApi(_client(g)).me();
      expect(g.log.single.auth, 'Bearer tok');
      expect(me.displayName, 'Wren Doc');
    });

    test('PATCH /users/me/profile sends only the changed fields; gender can be cleared with null', () async {
      final g = _Gateway({'PATCH /users/me/profile': (r) => (200, {'user_id': 'u', 'display_name': 'x', ...(r.body as Map)})});
      final api = RemoteAccountApi(_client(g));
      await api.updateProfile(const ProfilePatch(bio: '', timezone: 'Asia/Kolkata', preferredChannel: 'sms'));
      expect(g.log.last.body, {'bio': '', 'timezone': 'Asia/Kolkata', 'preferred_channel': 'sms'});
      await api.updateProfile(const ProfilePatch(clearGender: true));
      expect(g.log.last.body, {'gender': null});
      expect(const ProfilePatch().isEmpty, isTrue);
    });

    test('PATCH /users/me: current_password only with email or phone', () async {
      final g = _Gateway({'PATCH /users/me': (r) => (200, {'id': 'u', ...(Map.of(r.body as Map)..remove('current_password'))})});
      final api = RemoteAccountApi(_client(g));
      await api.updateAccount(username: 'wren_doc', currentPassword: 'ignored');
      expect(g.log.last.body, {'username': 'wren_doc'});
      final r = await api.updateAccount(phone: '+919876543210', currentPassword: 'pw');
      expect(g.log.last.body, {'phone': '+919876543210', 'current_password': 'pw'});
      expect(Me.fromJson(_fresh).withAccountReply(r).phone, '+919876543210');
    });

    test('a wrong current password (401 INVALID_CREDENTIALS) is not a session end', () async {
      final g = _Gateway({'PATCH /users/me': (_) => _err(401, 'INVALID_CREDENTIALS')});
      final client = _client(g);
      var signedOut = false;
      var refreshed = false;
      client.onUnauthorized = (_) => signedOut = true;
      client.onRefreshToken = () async => refreshed = true;
      try {
        await RemoteAccountApi(client).updateAccount(email: 'n@example.com', currentPassword: 'bad');
        fail('expected an error');
      } on AppException catch (e) {
        expect(accountErrorText(e, AccountOp.email), 'Your password is incorrect.');
      }
      await Future<void>.delayed(Duration.zero);
      expect((signedOut, refreshed), (false, false));
      expect(client.authToken, 'tok');
    });

    test('DELETE /users/me carries {password} as its body', () async {
      final g = _Gateway({'DELETE /users/me': (_) => (204, null)});
      await RemoteAccountApi(_client(g)).deleteAccount('pw');
      expect(g.log.single.body, {'password': 'pw'});
    });

    test('addresses: PUT the whole address; GET 404 → none; DELETE 404 → already gone', () async {
      final g = _Gateway({
        'PUT /users/me/addresses/home': (r) => (200, {...(r.body as Map), 'line2': null, 'region': null, 'updated_at': '2026-11-24T09:43:37.624810Z'}),
        'GET /users/me/addresses/billing': (_) => _err(404, 'NOT_FOUND'),
        'DELETE /users/me/addresses/billing': (_) => _err(404, 'NOT_FOUND'),
      });
      final api = RemoteAccountApi(_client(g));
      final a = await api.saveAddress(
          AddressKind.home, const Address(line1: '1 Main St', line2: '', city: 'Pune', postalCode: '411001', country: 'IN'));
      expect(g.log.first.method, 'PUT');
      expect(g.log.first.body, {'line1': '1 Main St', 'city': 'Pune', 'postal_code': '411001', 'country': 'IN'});
      expect(a.city, 'Pune');
      expect(await api.address(AddressKind.billing), isNull);
      await api.removeAddress(AddressKind.billing);
    });

    test('privacy and preferences: PATCH only the change, read all eight back', () async {
      final g = _Gateway({
        'PATCH /users/me/privacy': (r) => (200, {...(_full['privacy'] as Map), ...(r.body as Map)}),
        'PATCH /users/me/preferences': (r) => (200, {...(_full['preferences'] as Map), 'default_stake_currency': 'token'}),
      });
      final api = RemoteAccountApi(_client(g));
      final p = await api.updatePrivacy({'profile_visibility': 'private'});
      expect(g.log.first.body, {'profile_visibility': 'private'});
      expect(p.profileVisibility, 'private');
      final prefs = await api.updatePreferences({'default_stake_currency': 'tokens'});
      expect(prefs.defaultStakeCurrency, 'token');
    });

    test('another player, trimmed by privacy: missing fields are just null', () async {
      final g = _Gateway({
        'GET /users/f72cb92d/profile': (_) => (200, {
              'user_id': 'f72cb92d',
              'display_name': 'w02docb1795513371',
              'avatar_id': null,
              'avatar_url': null,
              'bio': null,
              'country': null,
              'date_of_birth': null,
              'preferred_language': null,
            }),
        'GET /users/gone/profile': (_) => (200, {'user_id': 'gone', 'display_name': 'deleted-2e173b92a9bb4bbcb5d8f621', 'avatar_id': null}),
        'GET /users/nobody/profile': (_) => _err(404, 'NOT_FOUND'),
      });
      final api = RemoteAccountApi(_client(g));
      final p = await api.playerProfile('f72cb92d');
      expect((p.bio, p.country, p.isDeleted), (null, null, false));
      expect((await api.playerProfile('gone')).isDeleted, isTrue);
      try {
        await api.playerProfile('nobody');
        fail('expected 404');
      } on AppException catch (e) {
        expect(accountErrorText(e, AccountOp.playerProfile), "This player couldn't be found.");
      }
    });

    test('device register: push_token left out when there is none (it would clear it)', () async {
      final g = _Gateway({
        'POST /devices/register': (r) => (201, {'id': 2, 'user_id': 'u', ...(r.body as Map), 'push_token': (r.body as Map)['push_token']}),
        'PATCH /devices/2/push-token': (r) => (200, {'id': 2, 'device_id': 'd', 'device_name': 'Pixel 8', 'platform': 'android', ...(r.body as Map)}),
      });
      final api = RemoteAccountApi(_client(g));
      final d = await api.registerDevice(deviceId: 'd', deviceName: 'Pixel 8', platform: 'android');
      expect(g.log.first.body, {'device_id': 'd', 'device_name': 'Pixel 8', 'platform': 'android'});
      expect(d.id, 2);
      await api.registerDevice(deviceId: 'd', deviceName: 'Pixel 8', platform: 'android', pushToken: 'fcm1');
      expect((g.log[1].body as Map)['push_token'], 'fcm1');
      final cleared = await api.setPushToken(2, null);
      expect(g.log.last.body, {'push_token': null});
      expect(cleared.pushToken, isNull);
    });

    test('sessions: list, sign out one, sign out everywhere', () async {
      final g = _Gateway({
        'GET /sessions': (_) => (200, [
              {'session_id': 'a', 'user_agent': 'RoyaleArcade/1.0.0 (Android 14)', 'created_at': 1795513374, 'last_active_at': 1795513374},
              {'session_id': 'b', 'user_agent': 'RoyaleArcade/1.0.0 (iOS 18.1)', 'created_at': 1795513372, 'last_active_at': 1795513372},
            ]),
        'DELETE /sessions/b': (_) => (204, null),
        'DELETE /sessions': (_) => (200, {'revoked': 2}),
      });
      final api = RemoteAccountApi(_client(g));
      expect((await api.sessions()).map((s) => s.deviceLabel), ['Android 14', 'iOS 18.1']);
      await api.revokeSession('b');
      expect(await api.revokeAllSessions(), 2);
    });
  });

  group('Error text', () {
    test('409 CONFLICT depends on what was changed', () {
      final c = _ex(409, 'CONFLICT');
      expect(accountErrorText(c, AccountOp.profile), 'That name is taken. Try another.');
      expect(accountErrorText(c, AccountOp.username), 'That username is taken.');
      expect(accountErrorText(c, AccountOp.email), 'That email is already registered.');
      expect(accountErrorText(c, AccountOp.phone), 'That number is already in use.');
      expect(accountErrorText(c, AccountOp.deleteAccount), 'Finish or leave your current game or tournament first.');
    });

    test('403 on an avatar, 401 wrong password, 400 missing password', () {
      expect(accountErrorText(_ex(403, 'FORBIDDEN'), AccountOp.avatar), "That avatar isn't unlocked yet.");
      expect(accountErrorText(_ex(401, 'INVALID_CREDENTIALS'), AccountOp.deleteAccount), 'Your password is incorrect.');
      expect(accountErrorText(_ex(400, 'BAD_REQUEST', field: 'current_password'), AccountOp.phone),
          'Enter your current password to change this.');
      expect(accountErrorText(_ex(400, 'BAD_REQUEST'), AccountOp.profile), 'Something went wrong. Try again.');
    });

    test('VALIDATION_ERROR shows the rule for its field', () {
      expect(accountErrorText(_ex(400, 'VALIDATION_ERROR', field: 'bio'), AccountOp.profile), 'Bio can be at most 140 characters.');
      expect(accountErrorText(_ex(400, 'VALIDATION_ERROR', field: 'postal_code'), AccountOp.address),
          'Postal code must be 3 to 10 letters, digits, spaces or hyphens.');
      expect(accountErrorText(_ex(400, 'VALIDATION_ERROR', field: 'phone'), AccountOp.phone),
          'Enter the number with its country code, e.g. +919876543210.');
      expect(accountErrorText(_ex(400, 'VALIDATION_ERROR', field: 'mystery'), AccountOp.profile),
          'Check the highlighted field and try again.');
    });

    test('the mapped error from the client keeps code and field', () async {
      final g = _Gateway({
        'PATCH /users/me/profile': (_) => _err(400, 'VALIDATION_ERROR', {'field': 'country'}),
      });
      try {
        await RemoteAccountApi(_client(g)).updateProfile(const ProfilePatch(country: 'in'));
        fail('expected 400');
      } on AppException catch (e) {
        expect((e.code, e.field), ('VALIDATION_ERROR', 'country'));
        expect(accountErrorText(e, AccountOp.profile), 'Pick a country from the list.');
      }
    });
  });

  group('Client rules', () {
    test('username: letters, digits and _ only (the server allows more on edit)', () {
      expect(AccountRules.username('wren_doc'), isNull);
      expect(AccountRules.username('w02 doc!'), isNotNull);
      expect(AccountRules.username('ab'), isNotNull);
    });

    test('phone: E.164', () {
      expect(AccountRules.phone('+919876543210'), isNull);
      expect(AccountRules.phone('+0919876543210'), isNotNull);
      expect(AccountRules.phone('+91 98765 43210'), isNotNull);
      expect(AccountRules.phone('919876543210'), isNotNull);
    });

    test('no future birthdays; bio up to 140', () {
      final now = DateTime(2026, 11, 24);
      expect(AccountRules.dateOfBirth(DateTime(2030), now: now), isNotNull);
      expect(AccountRules.dateOfBirth(DateTime(1998, 4, 12), now: now), isNull);
      expect(AccountRules.bio('x' * 140), isNull);
      expect(AccountRules.bio('x' * 141), isNotNull);
    });

    test('address: required fields, postal code, upper-case country', () {
      expect(AccountRules.address(const Address(line1: '1 Main St', city: 'Pune', postalCode: '411001', country: 'IN')), isEmpty);
      expect(AccountRules.address(const Address(line1: '', city: '', postalCode: '1', country: 'in')).keys,
          containsAll(['line1', 'city', 'postal_code', 'country']));
    });
  });

  group('AccountStore', () {
    late _RecordingApi api;
    late ProviderContainer c;

    setUp(() {
      api = _RecordingApi();
      c = ProviderContainer(overrides: [
        authServiceProvider.overrideWithValue(const StaticAuthService()),
        accountApiProvider.overrideWithValue(api),
      ]);
      c.listen(accountStoreProvider, (_, _) {});
    });
    tearDown(() => c.dispose());

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

    test('signing in registers this device; a new push token is sent, a 404 registers again', () async {
      await c.read(sessionProvider.notifier).login(email: 'a@example.com', password: 'x');
      await settle();
      expect(api.calls.where((e) => e.startsWith('register')).length, 1);
      expect(api.calls.first, 'register:android:null');

      await c.read(accountStoreProvider.notifier).onPushToken('fcm-1');
      expect(api.calls.last, 'push:1:fcm-1');

      api.pushNotFound = true;
      await c.read(accountStoreProvider.notifier).onPushToken('fcm-2');
      expect(api.calls.last, 'register:android:fcm-2');
    });

    test('log out clears this device push token first', () async {
      await c.read(sessionProvider.notifier).login(email: 'a@example.com', password: 'x');
      await settle();
      await c.read(accountStoreProvider.notifier).onPushToken('fcm-1');
      api.calls.clear();
      await c.read(accountStoreProvider.notifier).clearPushTokenForLogout();
      expect(api.calls, ['push:1:null']);
    });

    test('marks this device from the token, and signing out this one is a log out', () async {
      await c.read(sessionProvider.notifier).login(email: 'a@example.com', password: 'x');
      await settle();
      c.read(apiClientProvider).authToken = _jwt({'sub': 'me', 'session_id': 'this-one'});
      final store = c.read(accountStoreProvider.notifier);
      expect(store.thisSessionId, 'this-one');
      await store.revokeSession('other');
      expect(c.read(sessionProvider), isNotNull);
      await store.revokeSession('this-one');
      expect(c.read(sessionProvider), isNull);
    });

    test('privacy is optimistic and rolls back on error', () async {
      final store = c.read(accountStoreProvider.notifier);
      await store.load();
      api.failNext = true;
      final pending = store.setPrivacy({'profile_visibility': 'private'});
      expect(c.read(accountStoreProvider)!.privacy.profileVisibility, 'private');
      await expectLater(pending, throwsA(isA<AppException>()));
      expect(c.read(accountStoreProvider)!.privacy.profileVisibility, 'public');
    });

    test('a profile save updates Me and the session player', () async {
      await c.read(sessionProvider.notifier).login(email: 'a@example.com', password: 'x');
      await settle();
      await c.read(accountStoreProvider.notifier).updateProfile(const ProfilePatch(displayName: 'Wren', avatarId: 2));
      expect(c.read(accountStoreProvider)!.profile.avatarId, 2);
      expect(c.read(sessionProvider)!.displayName, 'Wren');
      expect(c.read(sessionProvider)!.avatarId, '2');
    });
  });
}

/// Records calls; built on the demo account so the reads have data.
class _RecordingApi extends DemoAccountApi {
  final List<String> calls = [];
  bool pushNotFound = false;
  bool failNext = false;

  @override
  Future<Device> registerDevice({required String deviceId, required String deviceName, required String platform, String? pushToken}) async {
    calls.add('register:$platform:$pushToken');
    return Device(id: 1, deviceId: deviceId, deviceName: deviceName, platform: platform, pushToken: pushToken);
  }

  @override
  Future<Device> setPushToken(int id, String? pushToken) async {
    if (pushNotFound) {
      pushNotFound = false;
      throw const AppException('Not found.', statusCode: 404, code: 'NOT_FOUND', kind: AppErrorKind.notFound);
    }
    calls.add('push:$id:$pushToken');
    return Device(id: id, deviceId: 'd', deviceName: 'n', platform: 'android', pushToken: pushToken);
  }

  @override
  Future<PrivacySettings> updatePrivacy(Map<String, dynamic> changes) async {
    if (failNext) {
      failNext = false;
      await Future<void>.delayed(Duration.zero);
      throw const AppException('Something went wrong. Try again.', statusCode: 500, code: 'INTERNAL_ERROR');
    }
    return super.updatePrivacy(changes);
  }

  @override
  Future<void> revokeSession(String sessionId) async => calls.add('revoke:$sessionId');
}
