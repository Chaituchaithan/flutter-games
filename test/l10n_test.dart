import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/l10n/l10n.dart';

void main() {
  test('picker codes map to a translated locale or fall back to English', () {
    expect(appLocaleFor('hi'), const Locale('hi'));
    expect(appLocaleFor('en'), const Locale('en'));
    expect(appLocaleFor('ja'), const Locale('en'), reason: 'no Japanese translation yet');
  });

  test('Hindi has every English key (no missing texts)', () {
    Map<String, dynamic> keys(String f) => (jsonDecode(File(f).readAsStringSync()) as Map<String, dynamic>)
      ..removeWhere((k, _) => k.startsWith('@'));
    final en = keys('lib/l10n/app_en.arb').keys.toSet();
    final hi = keys('lib/l10n/app_hi.arb').keys.toSet();
    expect(en.difference(hi), isEmpty);
  });

  test('texts resolve per language, with placeholders and plurals', () {
    final hi = lookupAppLocalizations(const Locale('hi'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.welcomeBack, 'Welcome back');
    expect(hi.welcomeBack, isNot(en.welcomeBack));
    expect(en.newToApp('Ludo'), 'New to Ludo? ');
    expect(en.spinsLeft(1), '1 spin left');
    expect(en.spinsLeft(3), '3 spins left');
  });
}
