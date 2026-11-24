// Live progress and history (docs/services/08-progress-and-history.md)
// against the running server, with two fresh guests. Skipped unless both
// addresses are given:
//
//   flutter test test/live_progress_test.dart \
//     --dart-define=LIVE_API=http://192.168.0.235:1280/api/v1 \
//     --dart-define=LIVE_LUDO_WS=ws://192.168.0.235:1285/ws
//
// Reads empty progress, plays one free friends-room Ludo game ended by a
// forfeit (A wins), then reads levels, stats, history, the match and the
// wins board for both, and checks the after-game delta (+100 / +10 XP).

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/progress.dart';
import 'package:snakeladder/game/ludo/online/ludo_controller.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/auth_service.dart';
import 'package:snakeladder/services/progress_service.dart';
import 'package:snakeladder/services/socket/socket_client.dart';

const _api = String.fromEnvironment('LIVE_API');
const _ws = String.fromEnvironment('LIVE_LUDO_WS');

Future<(LudoController, SocketClient, RemoteProgressApi, String)> _player() async {
  Dio dio() => Dio(BaseOptions(baseUrl: '$_api/', contentType: 'application/json'));
  final auth = RemoteAuthService(ApiClient(dio: dio()));
  final g = await auth.loginGuest();
  final socket = SocketClient(url: Uri.parse(_ws), requestTimeout: const Duration(seconds: 8));
  await socket.connect();
  await socket.login(token: g.accessToken);
  final c = LudoController(request: socket.request, events: socket.broadcasts, myUserId: g.user.id, serverNow: socket.serverNow);
  return (c, socket, RemoteProgressApi(ApiClient(dio: dio())..authToken = g.accessToken), g.user.id);
}

Future<void> _until(LudoController c, bool Function() ok) async {
  if (ok()) return;
  final done = Completer<void>();
  void check() {
    if (ok() && !done.isCompleted) done.complete();
  }

  c.addListener(check);
  try {
    await done.future.timeout(const Duration(seconds: 15));
  } finally {
    c.removeListener(check);
  }
}

void main() {
  test('a free Ludo game moves levels, history, the match and the wins board', () async {
    final (a, sa, pa, idA) = await _player();
    final (b, sb, pb, idB) = await _player();
    // ignore: avoid_print
    void log(String s) => print('[PROGRESS] $s');

    expect(await pa.levels(), isEmpty);
    expect(await pa.ratings(), isEmpty);
    expect((await pa.history()).total, 0);

    // The store holds the "before" values (no rows yet).
    final store = ProviderContainer(overrides: [progressApiProvider.overrideWithValue(pa)]);
    addTearDown(store.dispose);
    await store.read(progressStoreProvider.notifier).ensureLoaded();

    expect(await a.createRoom(modeCode: 'friends_room', maxPlayers: 2, turnSeconds: 15), isTrue);
    expect(await b.joinRoom(a.room!.roomCode), isTrue);
    await _until(a, () => a.room!.players.length == 2);
    await a.ready();
    await b.ready();
    await _until(a, () => a.phase == LudoPhase.game);
    final matchId = a.state!.matchId;
    log('match $matchId');

    final running = await pa.history();
    expect(running.data.single.chip, MatchChip.playing);

    await b.forfeit();
    await _until(a, () => a.phase == LudoPhase.result);

    final gameId = running.data.single.gameId!;
    final d = (await store.read(progressStoreProvider.notifier).afterGame(gameId))!;
    log('A after game: ${d.summary}, level-up ${d.leveledUp}');
    expect(d.xpGained, 100);
    expect(d.leveledUp, isTrue);
    expect(d.ratingChange, isNull, reason: 'friends room: unranked');

    final levelsB = await pb.levels();
    expect((levelsB.single.level, levelsB.single.xp), (1, 10));
    final stats = await pa.gameStats(gameId);
    expect(stats.level!.level, 2);
    expect(stats.rating, isNull);

    final h = (await pa.history()).data.single;
    expect((h.matchId, h.status, h.result, h.gameCode), (matchId, 'completed', 'win', 'ludo'));
    expect((await pb.history()).data.single.result, 'forfeit');

    final m = await pa.match(matchId);
    log('match: ${m.byPlace.map((p) => '${p.result} #${p.finalRank} ${p.ratingBefore}->${p.ratingAfter}').join(', ')}');
    expect(m.seatOf(idA)!.finalRank, 1);
    expect(m.seatOf(idB)!.chip, MatchChip.forfeit);
    expect(m.ratingMoved, isFalse);

    final rank = await pa.myRank(gameId, LeaderboardMetric.wins);
    log('wins my-rank: ${rank.rank} (${rank.score})');
    expect(rank.score, 1);

    await sa.close();
    await sb.close();
  }, skip: _api.isEmpty || _ws.isEmpty ? 'set LIVE_API and LIVE_LUDO_WS' : false, timeout: const Timeout(Duration(minutes: 2)));
}
