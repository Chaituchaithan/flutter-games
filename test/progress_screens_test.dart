// Progress screens on the demo data (08-progress-and-history.md): Profile
// cards, the leaderboard "You" row when `rank` is null, the match detail and
// its MATCH_NOT_FOUND message, and the level-up overlay's reward button.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/app/routes.dart';
import 'package:snakeladder/data/models/progress.dart';
import 'package:snakeladder/screens/leaderboard/leaderboard_screen.dart';
import 'package:snakeladder/screens/match/match_detail_screen.dart';
import 'package:snakeladder/screens/profile/level_up_screen.dart';
import 'package:snakeladder/screens/profile/progress_ui.dart';
import 'package:snakeladder/services/progress_service.dart';

Future<void> _pump(WidgetTester tester, Widget home, {List overrides = const []}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(ProviderScope(
    overrides: [...overrides],
    child: MaterialApp(onGenerateRoute: Routes.onGenerateRoute, home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Profile cards: level, XP bar text, rating or Unranked', (tester) async {
    await _pump(tester, const Scaffold(body: SingleChildScrollView(child: ProgressCards())));
    expect(find.text('Level 3'), findsOneWidget);
    expect(find.text('120 / 300 XP'), findsOneWidget);
    expect(find.textContaining('Rating 1032'), findsOneWidget);
    expect(find.text('Level 2'), findsOneWidget);
    expect(find.text('Unranked'), findsOneWidget);
  });

  testWidgets('Profile cards: empty list shows a hint, not an error', (tester) async {
    await _pump(
      tester,
      const Scaffold(body: ProgressCards()),
      overrides: [progressApiProvider.overrideWithValue(_EmptyApi())],
    );
    expect(find.text('Finish a match to start levelling up.'), findsOneWidget);
  });

  testWidgets('Leaderboard: You row worded when not on the board', (tester) async {
    await _pump(tester, const LeaderboardScreen(gameCode: 'ludo'));
    expect(find.text('Updated hourly'), findsOneWidget);
    // On the Wins board the player's own row is highlighted in the list.
    expect(find.textContaining('(you)'), findsOneWidget);
    await tester.tap(find.text('Tokens'));
    await tester.pumpAndSettle();
    expect(find.text(LeaderboardMetric.tokensEarned.offBoardText), findsOneWidget);
  });

  testWidgets('Match detail: seats, and the gone match', (tester) async {
    await _pump(tester, const MatchDetailScreen(matchId: 'demo-match'));
    expect(find.text('Players'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    await _pump(tester, const MatchDetailScreen(matchId: 'nope'));
    expect(find.text('This match is no longer available.'), findsOneWidget);
  });

  testWidgets('Level-up overlay offers the level reward', (tester) async {
    var claimed = false;
    await _pump(tester, Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showLevelUp(context, level: 2, gameName: 'Ludo Royale', rewardLabel: 'Pick 3', onReward: () => claimed = true),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Level 2 reached'), findsOneWidget);
    expect(find.text('in Ludo Royale'), findsOneWidget);
    await tester.tap(find.text('Claim your level reward'));
    await tester.pumpAndSettle();
    expect(claimed, isTrue);
    expect(find.text('Level 2 reached'), findsNothing);
  });
}

class _EmptyApi extends DemoProgressApi {
  @override
  Future<List<GameLevel>> levels() async => const [];
  @override
  Future<List<GameRating>> ratings() async => const [];
}
