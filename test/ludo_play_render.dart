// Renders Ludo play to PNG frames (not an assertion suite; writes to
// build/ludo_play/). Drives the real LudoBoardView:
//   offline/  — full offline Quick Play games (4 bots), a frame per hop
//   online/   — the online board: the 52nd square's bend into the lane, the
//               6th lane square, and finishing with a 2
// Run: flutter test test/ludo_play_render.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/game/ludo/ludo_board_view.dart';
import 'package:snakeladder/game/ludo/ludo_engine.dart';

const _out = 'build/ludo_play';
const _size = 360.0;

Future<void> _snap(WidgetTester tester, GlobalKey key, String path) async {
  while (tester.takeException() != null) {}
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
    img.dispose();
  });
}

Future<GlobalKey> _mount(WidgetTester tester, LudoGame g) async {
  final key = GlobalKey();
  tester.view.physicalSize = const Size(_size, _size);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF05040C),
      body: RepaintBoundary(
        key: key,
        child: SizedBox(
          width: _size,
          height: _size,
          child: LudoBoardView(game: g, bottomLeft: LudoColor.blue, onMoveAnimated: () {}),
        ),
      ),
    ),
  ));
  await tester.pump();
  return key;
}

/// Plays [m] on the board, a frame mid-hop and on each square.
Future<int> _animate(WidgetTester tester, GlobalKey key, LudoMove m, String dir, int n) async {
  final steps = m.leavesBase ? 1 : m.path.length;
  final per = m.leavesBase ? LudoBoardView.exitMs : LudoBoardView.stepMs;
  for (var s = 0; s < steps; s++) {
    await tester.pump(Duration(milliseconds: per ~/ 2));
    await _snap(tester, key, '$dir/${(n++).toString().padLeft(5, '0')}.png');
    await tester.pump(Duration(milliseconds: per - per ~/ 2));
    await _snap(tester, key, '$dir/${(n++).toString().padLeft(5, '0')}.png');
  }
  if (m.captured.isNotEmpty) {
    await tester.pump(const Duration(milliseconds: LudoBoardView.captureMs));
    await _snap(tester, key, '$dir/${(n++).toString().padLeft(5, '0')}.png');
  }
  await tester.pump(const Duration(milliseconds: 50));
  return n;
}

void main() {
  for (final seed in [1, 2, 3]) {
    testWidgets('offline game $seed', (tester) async {
      final dir = '$_out/offline_$seed';
      Directory(dir).createSync(recursive: true);
      for (final f in Directory(dir).listSync()) {
        f.deleteSync();
      }
      final g = LudoGame(colors: LudoColor.values, rng: math.Random(seed));
      final key = await _mount(tester, g);
      final log = StringBuffer();
      var n = 0, move = 0;
      while (!g.isOver && move < 2000) {
        final dice = g.roll();
        if (g.passIfStuck()) continue;
        final c = g.current;
        final token = g.chooseBotMove();
        final m = g.move(token);
        move++;
        log.writeln('#$move ${c.name} rolled $dice: pawn $token ${m.from}→${m.to} '
            '(${m.leavesBase ? 'leaves base' : '${m.path.length} hops'})'
            '${m.captured.isNotEmpty ? ' captures ${m.captured.map((x) => x.$1.name).join(',')}' : ''}'
            '${m.reachesHome ? ' HOME' : ''}');
        // Every hop of blue's moves (the player's colour, bottom-left), and
        // every lane entry / finish of any colour.
        final interesting = c == LudoColor.blue ||
            (m.from <= LudoRules.lastTrack && m.to > LudoRules.lastTrack) ||
            m.reachesHome ||
            m.captured.isNotEmpty;
        if (interesting) {
          n = await _animate(tester, key, m, dir, n);
        } else {
          await tester.pump(Duration(milliseconds: LudoBoardView.durationMs(m) + 50));
        }
        g.finishMove();
        await tester.pump();
      }
      await _snap(tester, key, '$dir/${(n++).toString().padLeft(5, '0')}.png');
      log.writeln('winner: ${g.winner?.name} after $move moves');
      File('$dir/moves.txt').writeAsStringSync(log.toString());
    }, timeout: const Timeout(Duration(minutes: 10)));
  }

  testWidgets('online board: lane entry and finishing', (tester) async {
    final dir = '$_out/online';
    Directory(dir).createSync(recursive: true);
    for (final f in Directory(dir).listSync()) {
      f.deleteSync();
    }
    final g = LudoGame(colors: LudoColor.values, layout: LudoLayout.server);
    Map<LudoColor, List<int>> pos(List<int> blue) => {
          LudoColor.red: [-1, -1, -1, -1],
          LudoColor.green: [-1, -1, -1, -1],
          LudoColor.yellow: [-1, -1, -1, -1],
          LudoColor.blue: blue,
        };
    g.applyServer(positions: pos([49, 55, -1, -1]), current: LudoColor.blue);
    final key = await _mount(tester, g);
    var n = 0;
    await _snap(tester, key, '$dir/${(n++).toString().padLeft(5, '0')}.png');
    // Blue rolls 4 at 49: 50, 51 (the 52nd square), bend into the lane, 53.
    var m = const LudoMove(color: LudoColor.blue, token: 0, from: 49, to: 53);
    g.applyServer(positions: pos([53, 55, -1, -1]), current: LudoColor.blue, pending: m);
    n = await _animate(tester, key, m, dir, n);
    g.clearPending();
    await tester.pump();
    // Pawn 1 at 55 rolls 2: the 5th lane square, the 6th (drawn), not home yet.
    m = const LudoMove(color: LudoColor.blue, token: 1, from: 55, to: 57);
    g.applyServer(positions: pos([53, 57, -1, -1]), current: LudoColor.blue, pending: m);
    n = await _animate(tester, key, m, dir, n);
    g.clearPending();
    await tester.pump();
    // …then a 1 finishes it in the middle.
    m = const LudoMove(color: LudoColor.blue, token: 1, from: 57, to: 58);
    g.applyServer(positions: pos([53, 58, -1, -1]), current: LudoColor.blue, pending: m);
    n = await _animate(tester, key, m, dir, n);
    g.clearPending();
    await tester.pump();
    await _snap(tester, key, '$dir/${(n++).toString().padLeft(5, '0')}.png');
  });
}
