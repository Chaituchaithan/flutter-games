// Renders showcase PNGs of the premium board: (1) a selected piece with the
// glowing legal-move dots + capture ring + pulsing selection, and (2) a frame
// captured mid-move so the slide animation is visible. Not an assertion test —
// it writes images to build/. Uses fixed `pump` durations (never pumpAndSettle)
// because the ambient highlight pulse loops while something is selected.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/chess/chess_board_view.dart';
import 'package:snakeladder/game/chess/chess_controller.dart';
import 'package:snakeladder/game/chess/chess_engine.dart';

bool _isFontError(Object e) {
  final s = e.toString();
  return s.contains('google_fonts') || s.contains('allowRuntimeFetching');
}

int _sq(int file, int rank) => squareOf(file, rank);

Future<void> _capture(WidgetTester tester, GlobalKey key, String outPath) async {
  Object? err;
  while ((err = tester.takeException()) != null) {
    if (!_isFontError(err!)) fail('Runtime error rendering $outPath: $err');
  }
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(outPath)..parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  expect(File(outPath).lengthSync(), greaterThan(0));
}

Future<GlobalKey> _mount(WidgetTester tester, ChessController controller) async {
  final key = GlobalKey();
  tester.view.physicalSize = const Size(430, 430);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF05040C),
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 430, height: 430, child: ChessBoardView(controller: controller)),
          ),
        ),
      ),
    ),
  );
  await tester.pump(); // first frame (listener attached)
  return key;
}

/// Italian Game position; white to move.
ChessController _italian() {
  final c = ChessController();
  void m(int ff, int fr, int tf, int tr) => c.applyExternalCoords(_sq(ff, fr), _sq(tf, tr));
  m(4, 1, 4, 3); // e4
  m(4, 6, 4, 4); // e5
  m(6, 0, 5, 2); // Nf3
  m(1, 7, 2, 5); // Nc6
  m(5, 0, 2, 3); // Bc4
  m(5, 7, 2, 4); // Bc5
  return c;
}

void main() {
  testWidgets('selected piece: glowing targets + capture ring + pulse', (tester) async {
    final c = _italian();
    final key = await _mount(tester, c);

    // Select the f3 knight → dots on empty squares + a capture ring on e5.
    c.onTapSquare(_sq(5, 2));
    await tester.pump(); // apply selection
    await tester.pump(const Duration(milliseconds: 375)); // advance pulse to its peak

    await _capture(tester, key, '/Applications/Workspace/Flutter/snakeladder/build/board_premium_select.png');

    await tester.pumpWidget(const SizedBox()); // unmount → stop the ambient ticker
  });

  testWidgets('mid-move frame shows the piece in flight', (tester) async {
    final c = ChessController();
    final key = await _mount(tester, c);

    // Commit e2-e4; capture partway through the ~280ms slide.
    c.onTapSquare(_sq(4, 1)); // select e2
    await tester.pump();
    c.onTapSquare(_sq(4, 3)); // move to e4 → animation starts
    await tester.pump(); // kick off the controller
    await tester.pump(const Duration(milliseconds: 120)); // ~43% through the flight

    await _capture(tester, key, '/Applications/Workspace/Flutter/snakeladder/build/board_premium_move.png');

    await tester.pumpWidget(const SizedBox());
  });
}
