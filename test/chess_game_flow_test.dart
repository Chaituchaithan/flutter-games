// Quick Play game-area flows: pause overlay (Resume back to the board) and
// forfeit → Defeat result screen. Uses fixed pumps — the move clock ticks
// every 200ms, so pumpAndSettle would never settle.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/app/routes.dart';
import 'package:snakeladder/game/chess/chess_board_view.dart';
import 'package:snakeladder/game/chess/chess_engine.dart';
import 'package:snakeladder/game/chess/screens/chess_vs_computer_screen.dart';

bool _isFontError(Object e) {
  final s = e.toString();
  return s.contains('google_fonts') || s.contains('allowRuntimeFetching');
}

Future<void> _pump(WidgetTester tester, [int ms = 400]) async {
  await tester.pump(Duration(milliseconds: ms));
  await tester.pump(const Duration(milliseconds: 300));
  Object? err;
  while ((err = tester.takeException()) != null) {
    if (!_isFontError(err!)) fail('Runtime error: $err');
  }
}

Future<void> _start(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      onGenerateRoute: Routes.onGenerateRoute,
      // Unlimited time so the clock can't end the game mid-test.
      home: const ChessVsComputerScreen(clockMs: null, playerColor: PieceColor.white),
    ),
  ));
  await _pump(tester);
}

void main() {
  testWidgets('pause overlay matches mockup and Resume returns to the board', (tester) async {
    await _start(tester);
    await tester.tap(find.byIcon(Icons.pause_rounded).first);
    await _pump(tester);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Sound effects'), findsOneWidget);
    expect(find.text('Forfeit match'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await _pump(tester);
    expect(find.text('Paused'), findsNothing);
    expect(find.text('Your move'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('forfeit → confirm → Defeat result screen', (tester) async {
    await _start(tester);
    await tester.tap(find.byIcon(Icons.flag_outlined));
    await _pump(tester);
    expect(find.text('Forfeit the match?'), findsOneWidget);

    await tester.tap(find.text('Forfeit'));
    await _pump(tester, 600);
    expect(find.text('DEFEAT'), findsOneWidget);
    expect(find.text('You forfeited the match.'), findsOneWidget);
    expect(find.text('Play Again'), findsOneWidget);
    expect(find.text('Back to Home'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('forfeit → Keep playing resumes the game', (tester) async {
    await _start(tester);
    await tester.tap(find.byIcon(Icons.flag_outlined));
    await _pump(tester);
    await tester.tap(find.text('Keep playing'));
    await _pump(tester);
    expect(find.text('Forfeit the match?'), findsNothing);
    expect(find.text('DEFEAT'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Play Again on the result screen starts a new Quick Play game', (tester) async {
    await _start(tester);
    await tester.tap(find.byIcon(Icons.flag_outlined));
    await _pump(tester);
    await tester.tap(find.text('Forfeit'));
    await _pump(tester, 600);
    expect(find.text('DEFEAT'), findsOneWidget);

    await tester.tap(find.text('Play Again'));
    for (var i = 0; i < 4; i++) {
      await _pump(tester, 300);
    }
    expect(find.text('DEFEAT'), findsNothing);
    expect(find.text('♞ Quick Play'), findsOneWidget);
    expect(find.text('Match started · Chess'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('computer replies off the UI thread after a thinking buffer', (tester) async {
    await _start(tester);
    // e2 → e4 by tapping squares (White at the bottom, 8×8 grid).
    final board = tester.getRect(find.byType(ChessBoardView));
    Offset sq(int file, int rank) => Offset(
          board.left + board.width * (file + 0.5) / 8,
          board.top + board.height * (7 - rank + 0.5) / 8,
        );
    await tester.tapAt(sq(4, 1));
    await _pump(tester, 100);
    await tester.tapAt(sq(4, 3));
    await _pump(tester, 100);
    expect(find.text('You played e4'), findsOneWidget);
    // Background search + Medium's 1.0–1.8s buffer: real time must pass.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2200)));
    await _pump(tester, 400);
    expect(find.textContaining('Computer played'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
