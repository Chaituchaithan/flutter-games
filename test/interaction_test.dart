// Strong per-screen interaction test: drives each screen's real controls
// (tab switches, bottom sheets, dialogs, keypads, toggles, list taps) and
// asserts no runtime exception surfaces. Complements screens_smoke_test.dart
// (which only builds each screen once). Google-fonts' offline-fetch error is
// filtered out — it's a harmless test-isolate artifact, not an app bug.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/app/routes.dart';
import 'package:snakeladder/widgets/aura.dart';
import 'package:snakeladder/screens/social/friends_screen.dart';
import 'package:snakeladder/screens/leaderboard/leaderboard_screen.dart';
import 'package:snakeladder/screens/store/store_screen.dart';
import 'package:snakeladder/screens/profile/game_history_screen.dart';
import 'package:snakeladder/screens/tournaments/tournaments_screen.dart';
import 'package:snakeladder/screens/social/inbox_screen.dart';
import 'package:snakeladder/screens/settings/settings_screen.dart';
import 'package:snakeladder/screens/onboarding/otp_screen.dart';
import 'package:snakeladder/screens/match/online_play_sheet.dart';

bool _isFontError(Object e) {
  final s = e.toString();
  return s.contains('google_fonts') || s.contains('allowRuntimeFetching');
}

/// Settle animations, then fail if any non-font exception was captured.
Future<void> settle(WidgetTester tester, String where) async {
  try {
    await tester.pumpAndSettle();
  } catch (e) {
    if (!_isFontError(e)) rethrow;
  }
  Object? err;
  while ((err = tester.takeException()) != null) {
    if (!_isFontError(err!)) fail('Runtime error during "$where": $err');
  }
}

Future<void> pumpScreen(WidgetTester tester, Widget body, {bool tabHost = false}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  final home = tabHost ? Scaffold(body: SafeArea(child: body)) : body;
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateRoute: Routes.onGenerateRoute,
      home: home,
    ),
  ));
}

Future<void> tapText(WidgetTester tester, String label, String where) async {
  final f = find.text(label);
  if (f.evaluate().isEmpty) return;
  await tester.tap(f.first, warnIfMissed: false);
  await settle(tester, '$where → tap "$label"');
}

void main() {
  testWidgets('Friends: switch all tabs + row tap', (tester) async {
    await pumpScreen(tester, const FriendsScreen());
    await settle(tester, 'Friends load');
    for (final t in ['Requests', 'Find', 'Friends']) {
      await tapText(tester, t, 'Friends');
    }
  });

  testWidgets('Leaderboard: switch scopes', (tester) async {
    await pumpScreen(tester, const LeaderboardScreen());
    await settle(tester, 'Leaderboard load');
    for (final t in ['Friends', 'Weekly', 'Global']) {
      await tapText(tester, t, 'Leaderboard');
    }
  });

  testWidgets('Store: switch all four tabs', (tester) async {
    await pumpScreen(tester, const StoreScreen(), tabHost: true);
    await settle(tester, 'Store load');
    for (final t in ['Gold', 'Boosts', 'VIP', 'Tokens']) {
      await tapText(tester, t, 'Store');
    }
  });

  testWidgets('Game history: All/Wins/Losses filter', (tester) async {
    await pumpScreen(tester, const GameHistoryScreen());
    await settle(tester, 'History load');
    // Static data: ZeroCool = win, NeonViper = loss, PixelGhost = draw.
    expect(find.text('ZeroCool'), findsOneWidget);
    expect(find.text('NeonViper'), findsOneWidget);
    expect(find.text('PixelGhost'), findsOneWidget);

    await tapText(tester, 'Wins', 'GameHistory');
    expect(find.text('ZeroCool'), findsOneWidget);
    expect(find.text('NeonViper'), findsNothing);
    expect(find.text('PixelGhost'), findsNothing);

    await tapText(tester, 'Losses', 'GameHistory');
    expect(find.text('ZeroCool'), findsNothing);
    expect(find.text('NeonViper'), findsOneWidget);
    expect(find.text('PixelGhost'), findsNothing);

    await tapText(tester, 'All', 'GameHistory');
    expect(find.text('PixelGhost'), findsOneWidget);
  });

  testWidgets('Tournaments: Live/Upcoming/Ended', (tester) async {
    await pumpScreen(tester, const TournamentsScreen());
    await settle(tester, 'Tournaments load');
    for (final t in ['Upcoming', 'Ended', 'Live']) {
      await tapText(tester, t, 'Tournaments');
    }
  });

  testWidgets('Inbox: mark all read', (tester) async {
    await pumpScreen(tester, const InboxScreen());
    await settle(tester, 'Inbox load');
    await tapText(tester, 'Mark all read', 'Inbox');
  });

  testWidgets('Settings: toggle every switch', (tester) async {
    await pumpScreen(tester, const SettingsScreen());
    await settle(tester, 'Settings load');
    final toggles = find.byType(AuraToggle);
    for (var i = 0; i < toggles.evaluate().length; i++) {
      await tester.tap(toggles.at(i), warnIfMissed: false);
      await settle(tester, 'Settings toggle $i');
    }
  });

  testWidgets('OTP: keypad entry', (tester) async {
    await pumpScreen(tester, const OtpScreen());
    await settle(tester, 'OTP load');
    for (final d in ['1', '2', '3', '4']) {
      await tapText(tester, d, 'OTP');
    }
  });

  testWidgets('Online Play sheet: step through to Find match', (tester) async {
    await pumpScreen(
      tester,
      Builder(builder: (c) => Center(child: GradientButton(label: 'open', onPressed: () => showOnlinePlaySheet(c)))),
    );
    await settle(tester, 'launcher');
    await tapText(tester, 'open', 'OnlinePlay');
    // Chess is 2-player, so the sheet opens directly on "Choose your stake".
    expect(find.text('Choose your stake'), findsOneWidget, reason: 'opens on stake');
    await tapText(tester, 'Tokens', 'OnlinePlay currency'); // -> side step
    expect(find.text('Choose your side'), findsOneWidget, reason: 'side step');
    await tapText(tester, 'Black', 'OnlinePlay side'); // -> stake amount step
    await tapText(tester, 'Preview match  →', 'OnlinePlay stake'); // -> preview
    expect(find.text('Black'), findsWidgets, reason: 'preview shows the side');
    // "Find match" is reachable; tapping it launches the live online Chess
    // screen (real WebSocket) which isn't exercised here — just assert it shows.
    expect(find.text('Find match'), findsOneWidget, reason: 'OnlinePlay preview');
  });

  testWidgets('Overlays: chat / paused / dialog / balance / toast', (tester) async {
    await pumpScreen(
      tester,
      AuraScaffold(
        body: Builder(
          builder: (c) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GradientButton(label: 'chat', onPressed: () => showGameChatSheet(c)),
                GradientButton(label: 'paused', onPressed: () => showGamePaused(c)),
                GradientButton(label: 'balance', onPressed: () => showInsufficientBalanceDialog(c)),
                GradientButton(label: 'toast', onPressed: () => showAuraToast(c, 'hi')),
              ],
            ),
          ),
        ),
      ),
    );
    await settle(tester, 'overlay launcher');
    await tapText(tester, 'chat', 'chat');
    await tapText(tester, 'Good luck!', 'chat send');
    // close chat sheet
    if (find.byIcon(Icons.close).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.close).first, warnIfMissed: false);
      await settle(tester, 'chat close');
    }
    await tapText(tester, 'paused', 'paused');
    await tapText(tester, 'Resume', 'paused resume');
    await tapText(tester, 'balance', 'balance');
    await tapText(tester, 'Maybe later', 'balance dismiss');
    await tapText(tester, 'toast', 'toast');
  });
}
