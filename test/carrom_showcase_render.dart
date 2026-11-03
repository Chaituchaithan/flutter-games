// Renders PNGs of the Carrom screen to build/carrom/: the opening rack, the
// player aiming, and a frame mid-break. Not an assertion test — run with
//   flutter test test/carrom_showcase_render.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/carrom/carrom_screen.dart';
import 'package:snakeladder/l10n/gen/app_localizations.dart';

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  while (tester.takeException() != null) {}
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/carrom/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets('carrom showcase', (tester) async {
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
        home: RepaintBoundary(key: key, child: const CarromScreen(seed: 3, clockMs: null)),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _capture(tester, key, 'rack');

    // Aim: press on the striker and pull straight back.
    final board = find.byType(CustomPaint).evaluate().map((e) => e.renderObject! as RenderBox).reduce((a, b) => a.size.width * a.size.height > b.size.width * b.size.height ? a : b);
    final o = board.localToGlobal(Offset.zero);
    final side = board.size.width;
    final f = side * 0.082, s = side - 2 * f;
    final striker = o + Offset(f + 0.5 * s, f + (1 - 0.137) * s);
    final g = await tester.startGesture(striker);
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveBy(const Offset(4, 50));
    await tester.pump(const Duration(milliseconds: 16));
    await _capture(tester, key, 'aim');
    await g.up();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _capture(tester, key, 'break');
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _capture(tester, key, 'scatter');
    await tester.pumpWidget(const SizedBox());
  });
}
