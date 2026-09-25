// Widget tests for the Aura onboarding flow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/onboarding/onboarding_screen.dart';

void main() {
  testWidgets('shows first slide and advances through onboarding',
      (WidgetTester tester) async {
    // Use a realistic phone-portrait surface for the mobile UI.
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The intro carousel (reached from Splash → Language in the real flow).
    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));

    // First slide is visible with the "Continue" button.
    expect(find.text('Find your people'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Get Started'), findsNothing);

    // Tap Continue -> second slide.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Share your moment'), findsOneWidget);

    // Tap Continue -> third (last) slide; button becomes "Get Started".
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Always in sync'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Skip'), findsNothing); // hidden on last slide
  });
}
