// Verifies the real app routing: Splash auto-advances to Language, and
// Language's Continue reaches the intro carousel.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/app/aura_app.dart';
import 'package:snakeladder/services/app_prefs.dart';

/// A fresh install: nothing saved on the device.
class _FirstLaunch implements AppPrefs {
  @override
  Future<bool> onboarded() async => false;
  @override
  Future<void> setOnboarded() async {}
  @override
  Future<int?> language() async => null;
  @override
  Future<void> setLanguage(int index) async {}
}

void main() {
  testWidgets('Splash -> Language -> intro carousel', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(ProviderScope(
      overrides: [appPrefsProvider.overrideWithValue(_FirstLaunch())],
      child: const AuraApp(),
    ));

    // Splash is the entry point.
    expect(find.text('Aura Games'), findsOneWidget); // the app name
    expect(find.text('Play. Win. Repeat.'), findsOneWidget);

    // First launch: the startup work finishes (min ~0.9s), then Language.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Choose your language'), findsOneWidget);

    // Continue -> intro carousel.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Find your people'), findsOneWidget);
  });
}
