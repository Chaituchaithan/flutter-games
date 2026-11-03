// Renders PNGs of the Snooker screen to build/snooker/: the opening table,
// the break mid-flight and the table after it. Not an assertion test — run with
//   flutter test test/snooker_showcase_render.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/snooker/snooker_screen.dart';
import 'package:snakeladder/l10n/gen/app_localizations.dart';

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  while (tester.takeException() != null) {}
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/snooker/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets('snooker showcase', (tester) async {
    final key = GlobalKey();
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepaintBoundary(key: key, child: const SnookerScreen(seed: 3, clockMs: null)),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _capture(tester, key, 'opening');

    final bar = find.byKey(const ValueKey('snooker-power'));
    final g = await tester.startGesture(tester.getTopLeft(bar) + const Offset(10, 12));
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveBy(const Offset(170, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await _capture(tester, key, 'aim');
    await g.up();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _capture(tester, key, 'break');
    await tester.pumpWidget(const SizedBox());
  });
}
