import 'dart:async';

import 'package:snakeladder/app/app_profile.dart';
import 'package:snakeladder/configs/games/games.dart';
import 'package:snakeladder/main.dart' show allGamesApp;

/// Every test runs inside the all-games app (as `lib/main.dart` would set
/// it up). Tests of a single-game app set [AppProfile.current] themselves.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppProfile.current = allGamesApp;
  GameRegistry.setAppGames([for (final m in allGamesApp.modules) m.id]);
  await testMain();
}
