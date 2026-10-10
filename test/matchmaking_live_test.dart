import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/screens/match/matchmaking_screen.dart';

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1170, 2532); // phone
    view.devicePixelRatio = 3;
  });
  Widget host({required bool found, VoidCallback? onTimeout, bool clockRunning = true, VoidCallback? onStartTimeout}) =>
      ProviderScope(
        child: MaterialApp(
          home: MatchmakingScreen(
            label: 'Online',
            opponentName: 'bob',
            searchTimeout: const Duration(seconds: 60),
            found: found,
            onTimeout: onTimeout,
            clockRunning: clockRunning,
            onStartTimeout: onStartTimeout,
          ),
        ),
      );

  testWidgets('live search counts down 60 s, then calls onTimeout', (tester) async {
    var timedOut = 0;
    await tester.pumpWidget(host(found: false, onTimeout: () => timedOut++));
    expect(find.text('1:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:59'), findsOneWidget);
    await tester.pump(const Duration(seconds: 58));
    expect(timedOut, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(timedOut, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(timedOut, 1); // fires once
  });

  testWidgets('an opponent joining stops the clock and reveals them', (tester) async {
    var timedOut = 0;
    await tester.pumpWidget(host(found: false, onTimeout: () => timedOut++));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(host(found: true, onTimeout: () => timedOut++));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Opponent found — get ready!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
    expect(timedOut, 0);
  });

  testWidgets('the clock waits while connecting', (tester) async {
    await tester.pumpWidget(host(found: false, clockRunning: false));
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('1:00'), findsOneWidget);
    await tester.pumpWidget(host(found: false));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:59'), findsOneWidget);
  });

  testWidgets('found but never started: Leave shows, watchdog fires after 20 s', (tester) async {
    var stalled = 0;
    await tester.pumpWidget(host(found: false));
    await tester.pumpWidget(host(found: true, onStartTimeout: () => stalled++));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Leave match'), findsOneWidget);
    await tester.pump(const Duration(seconds: 19));
    expect(stalled, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(stalled, 1);
  });
}
