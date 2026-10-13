import 'dart:convert';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/app/game_socket_login.dart';
import 'package:snakeladder/app/routes.dart';
import 'package:snakeladder/app/startup.dart';
import 'package:snakeladder/data/models/user.dart';
import 'package:snakeladder/data/repositories/daily_bonus_repository.dart';
import 'package:snakeladder/data/sources/daily_bonus_source.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/app_prefs.dart';
import 'package:snakeladder/services/auth_service.dart';
import 'package:snakeladder/services/session.dart';
import 'package:snakeladder/services/token_store.dart';

class _Prefs implements AppPrefs {
  _Prefs(this.done);
  final bool done;
  @override
  Future<bool> onboarded() async => done;
  @override
  Future<void> setOnboarded() async {}
  @override
  Future<int?> language() async => null;
  @override
  Future<void> setLanguage(int index) async {}
}

class _Tokens implements TokenStore {
  _Tokens(this.access);
  String? access;
  @override
  Future<String?> readAccess() async => access;
  @override
  Future<String?> readRefresh() async => null;
  @override
  Future<void> save({required String access, String? refresh}) async => this.access = access;
  String? profile;
  @override
  Future<String?> readProfile() async => profile;
  @override
  Future<void> saveProfile(String json) async => profile = json;
  @override
  Future<void> clear() async {
    access = null;
    profile = null;
  }
}

/// fetchMe fails offline [offlineTimes] times, then succeeds.
class _Auth extends StaticAuthService {
  _Auth(this.offlineTimes);
  int offlineTimes;
  @override
  Future<User> fetchMe() async {
    if (offlineTimes-- > 0) throw const AppException('offline', kind: AppErrorKind.offline);
    return User.demo;
  }
}

class _NoSocket extends GameSocketLogin {
  _NoSocket(super.ref);
  @override
  Future<void> connect({String? username}) async {}
}

ProviderContainer _app({required bool onboarded, String? token, int offline = 0, String? cachedProfile}) {
  final tokens = _Tokens(token)..profile = cachedProfile;
  final c = ProviderContainer(overrides: [
    appPrefsProvider.overrideWithValue(_Prefs(onboarded)),
    tokenStoreProvider.overrideWithValue(tokens),
    authServiceProvider.overrideWithValue(_Auth(offline)),
    gameSocketLoginProvider.overrideWith(_NoSocket.new),
    dailyBonusSourceProvider.overrideWithValue(StaticDailyBonusSource()),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('first launch → Language', () async {
    final c = _app(onboarded: false);
    await c.read(startupProvider.notifier).run();
    expect(c.read(startupProvider).destination, Routes.language);
  });

  test('onboarded, no saved session → Login', () async {
    final c = _app(onboarded: true);
    await c.read(startupProvider.notifier).run();
    expect(c.read(startupProvider).destination, Routes.login);
  });

  test('saved session → straight to Home, signed in', () async {
    final c = _app(onboarded: true, token: 'jwt');
    await c.read(startupProvider.notifier).run();
    expect(c.read(startupProvider).destination, Routes.home);
    expect(c.read(sessionProvider), isNotNull);
  });

  test('offline keeps the session and offers Retry', () async {
    final c = _app(onboarded: true, token: 'jwt', offline: 1);
    await c.read(startupProvider.notifier).run();
    final s = c.read(startupProvider);
    expect(s.destination, isNull);
    expect(s.error, contains('offline'));
    expect(await c.read(tokenStoreProvider).readAccess(), 'jwt', reason: 'session kept');

    await c.read(startupProvider.notifier).run(); // Retry, now online
    expect(c.read(startupProvider).destination, Routes.home);
  });

  test('saved player → Home at once, even offline; refreshed when back', () async {
    const cached = User(id: 'u1', displayName: 'Asha Rao', handle: '@asha', bio: '', level: 4, tier: 'Bronze I', xp: 10, xpMax: 100, color: Color(0xFF8B5CF6));
    final c = _app(onboarded: true, token: 'jwt', offline: 1, cachedProfile: jsonEncode(cached.toCache()));
    await c.read(startupProvider.notifier).run();
    expect(c.read(startupProvider).destination, Routes.home, reason: 'no wait on /users/me');
    expect(c.read(sessionProvider)?.initials, 'AR');
    expect(await c.read(tokenStoreProvider).readAccess(), 'jwt', reason: 'offline keeps the session');
  });

  test('sign-out wipes the saved player', () async {
    final c = _app(onboarded: true, token: 'jwt');
    await c.read(startupProvider.notifier).run();
    expect(await c.read(tokenStoreProvider).readProfile(), isNotNull);
    c.read(sessionProvider.notifier).forceSignOut();
    await Future<void>.delayed(Duration.zero);
    expect(await c.read(tokenStoreProvider).readProfile(), isNull);
  });
}
