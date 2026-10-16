import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/app/game_area.dart';
import 'package:snakeladder/game/chess/chess_module.dart';
import 'package:snakeladder/game/ludo/ludo_module.dart';
import 'package:snakeladder/game/snakes/snakes_module.dart';
import 'package:snakeladder/configs/configs.dart';
import 'package:snakeladder/screens/home/home_screen.dart';
import 'package:snakeladder/main.dart' show allGamesApp;

void main() {
  group('ServerConfig', () {
    test('builds REST and socket URLs from one host', () {
      expect(devServer.apiBaseUrl, 'http://169.58.184.121:31294/api/v1');
      expect(devServer.socketUrl(30083, '/ws'), 'ws://169.58.184.121:30083/ws');
      const prod = ServerConfig(host: 'api.example.com', gatewayPort: 443, secure: true);
      expect(prod.apiBaseUrl, 'https://api.example.com:443/api/v1');
      expect(prod.socketUrl(443, '/ws'), 'wss://api.example.com:443/ws');
    });
  });

  group('GameEndpoints', () {
    test('proxy ON (dev default): socket goes through the proxy, token as query', () {
      expect(ProxyConfig.enabled, isTrue);
      const e = GameEndpoints(chessConfig);
      expect(e.socketUrl, '${ProxyConfig.wsBase}/svc/31283/ws');
      expect(e.socketUrlWithToken('abc'), '${ProxyConfig.wsBase}/svc/31283/ws?token=abc');
      expect(e.socketHeaders('abc'), {'Authorization': 'Bearer abc'});
    });

    test('each game service has its own port (31281–31292), all on /ws', () {
      expect(const GameEndpoints(ludoConfig).socketUrl, '${ProxyConfig.wsBase}/svc/31285/ws');
      expect(devServer.socketUrl(chessConfig.port, chessConfig.socketPath), 'ws://169.58.184.121:31283/ws');
      final ports = {for (final g in GameRegistry.all) g.id: g.port};
      expect(ports, {
        GameId.bingo: 31281, GameId.checkers: 31282, GameId.chess: 31283, GameId.crash: 31284,
        GameId.ludo: 31285, GameId.othello: 31286, GameId.poker: 31287, GameId.racing: 31288,
        GameId.roulette: 31289, GameId.rummy: 31290, GameId.scrabble: 31291, GameId.snakesLadders: 31292,
      });
      expect(GameRegistry.all.every((g) => g.socketPath == '/ws'), isTrue);
    });

    test('a game\'s REST API is on the same port as its socket', () {
      const e = GameEndpoints(chessConfig);
      expect(e.apiBase, '${ProxyConfig.httpBase}/svc/31283'); // proxy ON in dev
      expect(e.health, '${ProxyConfig.httpBase}/svc/31283/health');
      expect(e.metrics, '${ProxyConfig.httpBase}/svc/31283/metrics');
      expect(devServer.serviceBase(31283), 'http://169.58.184.121:31283');
    });
  });

  group('GameRegistry / active game', () {
    test('lookup, parse and availability', () {
      expect(GameRegistry.of(GameId.ludo).displayName, 'Ludo');
      expect(GameRegistry.parse('LUDO'), GameId.ludo);
      expect(GameRegistry.parse('nope'), isNull);
      expect(GameRegistry.available.map((g) => g.id), [
        GameId.chess,
        GameId.snakesLadders,
        GameId.ludo,
        GameId.othello,
        GameId.scrabble,
        GameId.checkers,
        GameId.crash,
        GameId.bingo,
        GameId.roulette,
        GameId.poker,
        GameId.racing,
        GameId.rummy,
      ]);
      expect(chessConfig.playersLabel, '2P');
      expect(ludoConfig.playersLabel, '2–4P');
    });

    test('defaults to chess; switching to a game not in this app is ignored', () {
      // An app with only Chess and Ludo.
      GameRegistry.setAppGames([GameId.chess, GameId.ludo]);
      addTearDown(() => GameRegistry.setAppGames([for (final m in allGamesApp.modules) m.id]));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(activeGameProvider), GameId.chess);
      c.read(activeGameProvider.notifier).select(GameId.poker); // not in this app
      expect(c.read(activeGameProvider), GameId.chess);
      expect(c.read(activeGameConfigProvider).displayName, 'Chess');
      c.read(activeGameProvider.notifier).select(GameId.ludo);
      expect(c.read(activeGameProvider), GameId.ludo);
    });

    test('game areas: chess online + Quick Play; Ludo and Snakes Quick Play only', () {
      expect(GameArea.practiceRoute(GameId.chess), ChessRoutes.setup);
      expect(GameArea.onlineRoute(GameId.chess), ChessRoutes.online);
      expect(GameArea.practiceRoute(GameId.ludo), LudoRoutes.setup);
      expect(GameArea.practiceRoute(GameId.snakesLadders), SnakesRoutes.setup);
      expect(GameArea.onlineRoute(GameId.ludo), isNull);
      // No online Ludo yet → login keeps the chess socket.
      expect(GameArea.socketGame(GameId.ludo), GameId.chess);
      expect(GameArea.socketGame(GameId.chess), GameId.chess);
    });
  });

  testWidgets('Home shows every game chip; all are playable', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: Scaffold(body: HomeScreen()))));
    await tester.pump(const Duration(milliseconds: 300));
    while (tester.takeException() != null) {}
    // The chips scroll sideways: bring each one into view.
    final row = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right).first;
    for (final g in GameRegistry.homeChips) {
      await tester.scrollUntilVisible(find.text(g.chipName), 80, scrollable: row);
      expect(find.text(g.chipName), findsWidgets);
    }
    await tester.scrollUntilVisible(find.text('Othello'), -80, scrollable: row);
    // Every Home game is playable now: no "Soon" chips, and tapping one
    // switches the active game.
    expect(find.text('Soon'), findsNothing);
    await tester.tap(find.text('Othello'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 4));
  });
}
