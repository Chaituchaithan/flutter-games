import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/ludo/ludo_config.dart';
import 'package:snakeladder/game/ludo/ludo_screen.dart';
import 'package:snakeladder/game/ludo/online/ludo_catalogue.dart';
import 'package:snakeladder/game/ludo/online/ludo_online_screen.dart';

/// Ludo route names (owned by this module).
abstract final class LudoRoutes {
  static const board = '/game/ludo';
  static const setup = '/game/ludo-setup';
  static const online = '/game/ludo-online';
}

/// The server's stake tiers for the shared online screens: quick match
/// `casual_2p` / `casual_4p`, friends `friends_room` (docs/services/ludo.md).
/// Empty until the catalogue loads (then only a free game is offered).
List<int>? _stakeTiers(WidgetRef ref, {required int players, required bool tokens, required bool friends}) {
  final cat = ref.watch(ludoCatalogueProvider).value;
  if (cat == null) return const [];
  final mode = cat.mode(friends ? 'friends_room' : (players >= 4 ? 'casual_4p' : 'casual_2p'));
  if (mode == null) return const [];
  return cat.stakesFor(mode, tokens ? 'token' : 'gold');
}

/// Ludo: Quick Play vs computer, and online quick match / friends rooms over
/// the Ludo socket (`ws://<host>:1285/ws`).
final ludoModule = GameModule(
  config: ludoConfig,
  practiceRoute: LudoRoutes.setup,
  onlineRoute: LudoRoutes.online,
  demoBoardRoute: LudoRoutes.board,
  onlinePlayerCounts: const [2, 4],
  friendsPlayerCounts: const [2, 3, 4],
  onlineFreePlay: true,
  onlineStakeTiers: _stakeTiers,
  roomCodeLength: 8,
  routes: {
    LudoRoutes.board: (_) => const LudoScreen(),
    LudoRoutes.setup: (_) => const LudoSetupScreen(),
    LudoRoutes.online: (a) {
      final args = a as Map<String, dynamic>?;
      return LudoOnlineScreen(
        entry: switch (args?['mode'] as String?) {
          'create' => LudoEntry.create,
          'join' => LudoEntry.join,
          'resume' => LudoEntry.resume,
          _ => LudoEntry.match,
        },
        players: args?['players'] as int? ?? 2,
        stake: args?['stake'] as int? ?? 0,
        tokens: args?['tokens'] as bool? ?? true,
        code: args?['code'] as String?,
        tournament: args?['tournament'] as bool? ?? false,
      );
    },
  },
);
