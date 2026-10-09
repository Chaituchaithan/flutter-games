// Renders ChessBoardView to PNG files so the flat vs 3D/perspective view can be
// compared visually. Not an assertion test — it writes two images to build/.
// Google-fonts runtime fetching is already disabled in flutter_test_config.dart;
// any residual font error is filtered out the way interaction_test.dart does.

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

/// Lay a single [ChessBoardView] inside a sized dark MaterialApp and write its
/// pixels to [outPath] at 3x. Same controller/position for every call.
Future<void> _render(
  WidgetTester tester,
  ChessController controller, {
  required bool perspective,
  required String outPath,
}) async {
  final boundaryKey = GlobalKey();

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
            key: boundaryKey,
            child: SizedBox(
              width: 430,
              height: 430,
              child: ChessBoardView(
                controller: controller,
                perspective: perspective,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  // Let layout/paint complete (ignore the harmless font-fetch artifact).
  try {
    await tester.pumpAndSettle();
  } catch (e) {
    if (!_isFontError(e)) rethrow;
  }
  Object? err;
  while ((err = tester.takeException()) != null) {
    if (!_isFontError(err!)) fail('Runtime error rendering $outPath: $err');
  }

  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    final file = File(outPath);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    image.dispose();
  });

  expect(File(outPath).lengthSync(), greaterThan(0));
}

void main() {
  testWidgets('render flat + perspective boards to PNG', (tester) async {
    // Same mid-game position for both images (Italian-ish opening) so flat vs
    // 3D is the only difference. Squares are file + rank*8 (see squareOf).
    final controller = ChessController();
    int sq(int file, int rank) => squareOf(file, rank);
    void move(int ff, int fr, int tf, int tr) {
      final ok = controller.applyExternalCoords(sq(ff, fr), sq(tf, tr));
      expect(ok, isTrue, reason: 'illegal setup move');
    }

    move(4, 1, 4, 3); // e2-e4
    move(4, 6, 4, 4); // e7-e5
    move(6, 0, 5, 2); // Ng1-f3
    move(1, 7, 2, 5); // Nb8-c6
    move(5, 0, 2, 3); // Bf1-c4
    move(5, 7, 2, 4); // Bf8-c5

    await _render(
      tester,
      controller,
      perspective: false,
      outPath: '/Applications/Workspace/Flutter/snakeladder/build/board_flat.png',
    );
    await _render(
      tester,
      controller,
      perspective: true,
      outPath:
          '/Applications/Workspace/Flutter/snakeladder/build/board_perspective.png',
    );
  });
}
