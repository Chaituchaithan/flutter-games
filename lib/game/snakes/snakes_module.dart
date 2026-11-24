import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:snakeladder/app/game_module.dart';
import 'package:snakeladder/configs/games/snakes_ladders/snakes_ladders_config.dart';
import 'package:snakeladder/game/snakes/online/snakes_online_catalogue.dart';
import 'package:snakeladder/game/snakes/online/snakes_online_screen.dart';
import 'package:snakeladder/game/snakes/snakes_ladders_screen.dart';

/// Snakes & Ladders route names (owned by this module).
abstract final class SnakesRoutes {
  static const board = '/game/snakes-ladders';
  static const setup = '/game/snakes-setup';
  static const online = '/game/snakes-online';
}

/// The server's stake tiers for the shared online screens
/// (docs/services/snake-and-ladder.md): quick match plays `quick_50`; a
/// friends room (`casual`) offers the bet ladder's unlocked bets
/// (`wallet.bet_options`), else the catalogue's tiers. Empty until loaded
/// (then only a free game is offered).
List<int>? _stakeTiers(WidgetRef ref, {required int players, required bool tokens, required bool friends}) {
  final currency = tokens ? 'token' : 'gold';
  final cat = ref.watch(snlCatalogueProvider).value;
  final mode = cat?.mode(friends ? snlFriendsMode : snlQuickMode);
  final tiers = cat == null || mode == null ? const <int>[] : cat.stakesFor(mode, currency);
  if (!friends) return tiers;
  final offer = ref.watch(snlBetOptionsProvider(currency)).value;
  if (offer == null || offer.currency != currency) return tiers;
  return offer.unlocked..sort();
}

/// Snakes & Ladders: Quick Play vs computer, and online quick match / friends
/// rooms over the Snake & Ladder socket (`ws://<host>:1292/ws`).
final snakesModule = GameModule(
  config: snakesLaddersConfig,
  practiceRoute: SnakesRoutes.setup,
  onlineRoute: SnakesRoutes.online,
  demoBoardRoute: SnakesRoutes.board,
  onlinePlayerCounts: const [2, 3, 4],
  friendsPlayerCounts: const [2, 3, 4],
  onlineFreePlay: true,
  onlineStakeTiers: _stakeTiers,
  roomCodeLength: 8,
  routes: {
    SnakesRoutes.board: (_) => const SnakesLaddersScreen(),
    SnakesRoutes.setup: (_) => const SnakesSetupScreen(),
    SnakesRoutes.online: (a) {
      final args = a as Map<String, dynamic>?;
      return SnlOnlineScreen(
        entry: switch (args?['mode'] as String?) {
          'create' => SnlEntry.create,
          'join' => SnlEntry.join,
          'resume' => SnlEntry.resume,
          _ => SnlEntry.match,
        },
        players: args?['players'] as int? ?? 2,
        stake: args?['stake'] as int? ?? 0,
        tokens: args?['tokens'] as bool? ?? true,
        code: args?['code'] as String?,
        modeCode: args?['mode_code'] as String?,
        tournament: args?['tournament'] as bool? ?? false,
      );
    },
  },
);
