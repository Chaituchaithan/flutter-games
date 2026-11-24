import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/common/local_game_flow.dart';

/// A minimal local game: records pauses, pause-menu opens and results.
class _Game extends StatefulWidget {
  const _Game();
  @override
  State<_Game> createState() => _GameState();
}

class _GameState extends State<_Game> with LocalGameFlow<_Game> {
  int pauses = 0, menus = 0, results = 0;

  @override
  String get pauseSubtitle => '';
  @override
  void onResumeGame() {}
  @override
  void showResult() => results++;
  @override
  void pauseGame() {
    super.pauseGame();
    pauses++;
  }

  @override
  void openPause() => menus++;

  @override
  void dispose() {
    disposeFlow();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('game'));
}

void main() {
  Future<(_GameState, NavigatorState)> start(WidgetTester tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const _Game()));
    return (tester.state<_GameState>(find.byType(_Game)), nav.currentState!);
  }

  testWidgets('covered by a page: pauses; back in view: the pause menu', (tester) async {
    final (game, nav) = await start(tester);
    nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('other'))));
    await tester.pumpAndSettle();
    expect(game.paused, isTrue);
    expect(game.pauses, 1);
    expect(game.menus, 0);

    nav.pop();
    await tester.pumpAndSettle();
    expect(game.menus, 1, reason: 'the player resumes from the pause menu');
  });

  testWidgets('a dialog over the game is not "covered"', (tester) async {
    final (game, nav) = await start(tester);
    showDialog<void>(context: nav.context, builder: (_) => const AlertDialog(content: Text('hi')));
    await tester.pumpAndSettle();
    expect(game.paused, isFalse);
    expect(game.pauses, 0);
  });

  testWidgets('a game that ends while covered shows its result once visible', (tester) async {
    final (game, nav) = await start(tester);
    game.endGame(delay: const Duration(seconds: 1)); // fires after the page has covered it
    nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('other'))));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 2));
    expect(game.results, 0, reason: 'never pushed over the other page');

    nav.pop();
    await tester.pumpAndSettle();
    expect(game.results, 1);
    expect(game.menus, 0);
  });
}
