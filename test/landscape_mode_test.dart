import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snakeladder/app/aura_app.dart';
import 'package:snakeladder/app/screen_orientation.dart';
import 'package:snakeladder/game/snooker/snooker_screen.dart';
import 'package:snakeladder/l10n/gen/app_localizations.dart';

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(children: [
      Text('count $n'),
      TextButton(onPressed: () => setState(() => n++), child: const Text('inc')),
      TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SnookerScreen(seed: 1, clockMs: null))),
        child: const Text('snooker'),
      ),
    ]),
  );
}

void main() {
  testWidgets('opening and closing Snooker keeps the screens under it', (tester) async {
    // A wide window, so the portrait frame is framing before Snooker opens.
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => PortraitFrame(child: child!),
      home: const _Counter(),
    ));
    expect(tester.getSize(find.byType(_Counter)).width, lessThan(600), reason: 'framed at phone width');
    await tester.tap(find.text('inc'));
    await tester.tap(find.text('inc'));
    await tester.pump();
    expect(find.text('count 2'), findsOneWidget);

    await tester.tap(find.text('snooker'));
    for (var i = 0; i < 30; i++) { await tester.pump(const Duration(milliseconds: 20)); }
    expect(LandscapeMode.screens.value, 1);
    expect(tester.getSize(find.byType(SnookerScreen)).width, 1200, reason: 'Snooker uses the whole window');

    nav.currentState!.pop();
    for (var i = 0; i < 30; i++) { await tester.pump(const Duration(milliseconds: 20)); }
    expect(LandscapeMode.screens.value, 0);
    expect(find.text('count 2'), findsOneWidget, reason: 'the screen underneath kept its state');
    expect(tester.getSize(find.byType(_Counter)).width, lessThan(600), reason: 'framed again');
  });
}
