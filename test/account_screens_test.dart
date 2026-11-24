// The profile-and-sessions screens (docs/services/02-profile-and-sessions.md)
// lay out with the demo account (signed out → in-memory AccountApi).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/app/routes.dart';
import 'package:snakeladder/screens/profile/avatars_screen.dart';
import 'package:snakeladder/screens/profile/edit_profile_screen.dart';
import 'package:snakeladder/screens/settings/account_screen.dart';
import 'package:snakeladder/screens/settings/addresses_screen.dart';
import 'package:snakeladder/screens/settings/delete_account_screen.dart';
import 'package:snakeladder/screens/settings/game_settings_screen.dart';
import 'package:snakeladder/screens/settings/privacy_screen.dart';
import 'package:snakeladder/screens/settings/sessions_screen.dart';
import 'package:snakeladder/screens/social/player_profile_screen.dart';

void main() {
  final screens = <String, Widget>{
    'Account': const AccountScreen(),
    'Addresses': const AddressesScreen(),
    'Privacy': const PrivacyScreen(),
    'GameSettings': const GameSettingsScreen(),
    'Sessions': const SessionsScreen(),
    'DeleteAccount': const DeleteAccountScreen(),
    'EditProfile': const EditProfileScreen(),
    'Avatars': const AvatarsScreen(),
    'PlayerCard': const PlayerProfileScreen(userId: 'f72cb92d'),
  };

  for (final e in screens.entries) {
    testWidgets('${e.key} builds with the demo account', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(onGenerateRoute: Routes.onGenerateRoute, home: e.value),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Privacy: a switch saves at once', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: PrivacyScreen())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Show me on leaderboards'), findsOneWidget);
    await tester.tap(find.text('Only me'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
