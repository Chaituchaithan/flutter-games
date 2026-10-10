/// The game the player is currently in. Switching games = setting this; the
/// socket URL, game area screen and session all follow from it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../build_overrides.dart';
import 'game_config.dart';
import 'game_id.dart';
import 'game_registry.dart';

class ActiveGameController extends Notifier<GameId> {
  /// Starts on `--dart-define=GAME=…` when that game is in this app, else
  /// the app's first game.
  @override
  GameId build() {
    final fromBuild = GameRegistry.parse(BuildOverrides.game);
    if (fromBuild != null && GameRegistry.isAvailable(fromBuild)) return fromBuild;
    return GameRegistry.available.first.id;
  }

  /// Switch games. Ignored for games this app doesn't include.
  void select(GameId id) {
    if (GameRegistry.isAvailable(id)) state = id;
  }
}

final activeGameProvider = NotifierProvider<ActiveGameController, GameId>(ActiveGameController.new);

/// The active game's config.
final activeGameConfigProvider = Provider<GameConfig>((ref) => GameRegistry.of(ref.watch(activeGameProvider)));
