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
  @override
  Future<void> clear() async => access = null;
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

ProviderContainer _app({required bool onboarded, String? token, int offline = 0}) {
  final tokens = _Tokens(token);
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
}
