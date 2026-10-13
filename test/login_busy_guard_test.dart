// Regression: tapping "Continue as guest" and then "Create account" before the
// guest sign-in finished opened Register, then Home was pushed over it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/app/routes.dart';
import 'package:snakeladder/data/models/user.dart';
import 'package:snakeladder/screens/auth/login_screen.dart';
import 'package:snakeladder/services/auth_service.dart';
import 'package:snakeladder/services/token_store.dart';

/// Guest sign-in that waits until the test completes it.
class _SlowGuestAuth extends StaticAuthService {
  _SlowGuestAuth(this.done);
  final Completer<void> done;

  @override
  Future<AuthResult> loginGuest() async {
    await done.future;
    return const AuthResult(User.demo);
  }
}

/// In-memory store (no platform channel in widget tests).
class _MemTokens implements TokenStore {
  @override
  Future<String?> readAccess() async => null;
  @override
  Future<String?> readRefresh() async => null;
  @override
  Future<void> save({required String access, String? refresh}) async {}
  @override
  Future<String?> readProfile() async => null;
  @override
  Future<void> saveProfile(String json) async {}
  @override
  Future<void> clear() async {}
}

/// Enough frames for a route push/replace transition to finish.
Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  testWidgets('while guest sign-in runs, Create account is ignored; Home opens once', (t) async {
    t.view.physicalSize = const Size(411, 891);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    final done = Completer<void>();
    await t.pumpWidget(ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(_SlowGuestAuth(done)),
        tokenStoreProvider.overrideWithValue(_MemTokens()),
      ],
      child: MaterialApp(
        home: const LoginScreen(),
        routes: {
          Routes.home: (_) => const Scaffold(body: Text('HOME')),
          Routes.register: (_) => const Scaffold(body: Text('REGISTER')),
        },
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));

    await t.ensureVisible(find.text('Continue as guest'));
    await t.tap(find.text('Continue as guest'));
    await t.pump();
    await t.ensureVisible(find.text('Create account'));
    await t.tap(find.text('Create account'), warnIfMissed: false); // locked → ignored
    await _frames(t);
    expect(find.text('REGISTER', skipOffstage: false), findsNothing);

    done.complete();
    await _frames(t);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('REGISTER', skipOffstage: false), findsNothing);
  });
}
