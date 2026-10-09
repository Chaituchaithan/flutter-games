// Regression: clearing a field's validation error used to re-create its
// TextField (different widget shape with/without the error), dropping focus
// and closing the keyboard after the first keystroke.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/app/routes.dart';
import 'package:snakeladder/screens/auth/login_screen.dart';

Future<void> _p(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  while (t.takeException() != null) {}
}

void main() {
  testWidgets('email keeps focus + keyboard while its error clears', (t) async {
    t.view.physicalSize = const Size(411, 891);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(onGenerateRoute: Routes.onGenerateRoute, home: const LoginScreen()),
    ));
    await _p(t);

    final email = find.byType(TextField).at(0);
    await t.enterText(email, 'auratester01'); // not an email → error on submit
    await t.enterText(find.byType(TextField).at(1), 'Secret123!');
    await t.ensureVisible(find.text('Log In'));
    await t.tap(find.text('Log In').last);
    await _p(t);
    expect(find.text('Enter a valid email address'), findsOneWidget);

    await t.ensureVisible(email);
    await t.tap(email);
    await _p(t);
    t.testTextInput.updateEditingValue(
      const TextEditingValue(text: 'auratester01@', selection: TextSelection.collapsed(offset: 13)),
    );
    await _p(t);

    expect(find.text('Enter a valid email address'), findsNothing);
    expect(t.widget<TextField>(find.byType(TextField).at(0)).focusNode?.hasFocus, isTrue);
    expect(t.testTextInput.isVisible, isTrue);
  });
}
