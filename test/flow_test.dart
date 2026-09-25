// Verifies the real app routing: Splash auto-advances to Language, and
// Language's Continue reaches the intro carousel.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/main.dart';

void main() {
  testWidgets('Splash -> Language -> intro carousel', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ProviderScope(child: AuraApp()));

    // Splash is the entry point.
    expect(find.text('Aura'), findsOneWidget);
    expect(find.text('Play. Win. Repeat.'), findsOneWidget);

    // Splash auto-advances after ~1.4s.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('Choose your language'), findsOneWidget);

    // Continue -> intro carousel.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Find your people'), findsOneWidget);
  });
}
