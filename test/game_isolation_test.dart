// Guards the "one game per app" structure: games never depend on each other
// or on the shared app, and each single-game entry point pulls in only its
// own game.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/app/app_profile.dart';
import 'package:snakeladder/configs/games/games.dart';
import 'package:snakeladder/game/chess/chess_module.dart';
import 'package:snakeladder/game/ludo/ludo_module.dart';
import 'package:snakeladder/main.dart' show allGamesApp;
import 'package:snakeladder/main_ludo.dart' show ludoApp;

final _import = RegExp(r"""^(?:import|export)\s+'([^']+)'""", multiLine: true);

/// lib-relative paths a file imports (package: and relative).
List<String> _imports(File f) {
  final out = <String>[];
  for (final m in _import.allMatches(f.readAsStringSync())) {
    final spec = m.group(1)!;
    if (spec.startsWith('package:snakeladder/')) {
      out.add(spec.substring('package:snakeladder/'.length));
    } else if (!spec.contains(':')) {
      final abs = File('${f.parent.path}/$spec').absolute.uri.normalizePath().path;
      final lib = Directory('lib').absolute.uri.normalizePath().path;
      if (abs.startsWith(lib)) out.add(abs.substring(lib.length));
    }
  }
  return out;
}

/// The game folder a lib-relative path belongs to ('chess', 'common', …) or null.
String? _gameOf(String path) => path.startsWith('game/') ? path.split('/')[1] : null;

void main() {
  final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  test('shared code never imports a game', () {
    final bad = <String>[];
    for (final f in files) {
      final rel = f.path.substring('lib/'.length);
      if (rel.startsWith('game/') || RegExp(r'^main(_\w+)?\.dart$').hasMatch(rel)) continue;
      for (final i in _imports(f)) {
        if (_gameOf(i) != null) bad.add('$rel → $i');
      }
    }
    expect(bad, isEmpty);
  });

  test('a game imports only itself and the shared dice-game kit', () {
    final bad = <String>[];
    for (final f in files) {
      final rel = f.path.substring('lib/'.length);
      final mine = _gameOf(rel);
      if (mine == null) continue;
      for (final i in _imports(f)) {
        final other = _gameOf(i);
        if (other == null || other == mine || other == 'common') continue;
        bad.add('$rel → $i');
      }
    }
    expect(bad, isEmpty);
  });

  test('each single-game entry point imports only its own game', () {
    for (final (entry, game) in [('main_chess.dart', 'chess'), ('main_ludo.dart', 'ludo'), ('main_snakes.dart', 'snakes'), ('main_othello.dart', 'othello'), ('main_checkers.dart', 'checkers'), ('main_scrabble.dart', 'scrabble')]) {
      final games = {for (final i in _imports(File('lib/$entry'))) ?_gameOf(i)};
      expect(games, {game}, reason: entry);
    }
  });

  test('a Ludo-only app has no chess screens and no game picker', () {
    final saved = AppProfile.current;
    addTearDown(() {
      AppProfile.current = saved;
      GameRegistry.setAppGames([for (final m in allGamesApp.modules) m.id]);
    });
    AppProfile.current = ludoApp;
    GameRegistry.setAppGames([GameId.ludo]);
    expect(ludoApp.singleGame, isTrue);
    expect(ludoApp.buildRoute(ChessRoutes.online, null), isNull);
    expect(ludoApp.buildRoute(LudoRoutes.setup, null), isNotNull);
    expect(GameRegistry.available.map((g) => g.id), [GameId.ludo]);
  });
}
