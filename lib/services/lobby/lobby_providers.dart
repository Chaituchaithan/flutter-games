/// Wires the game-agnostic lobby to the app: the shared game socket
/// ([AppSocket]) and the catalogue's modes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/configs.dart';
import '../../configs/games/core/game_codes.dart';
import '../catalogue_service.dart';
import '../socket/app_socket.dart';
import '../socket/socket_client.dart';
import 'game_lobby.dart';
import '../wallet_store.dart';
import 'lobby_controller.dart';
import 'lobby_models.dart';

/// A [GameLobby] on the app's shared socket. Requests go to whichever
/// socket is current (it is replaced on a new sign-in); pushes follow
/// [AppSocket.events] across reconnects.
SocketGameLobby lobbyOnAppSocket(AppSocket socket, String gameCode) => SocketGameLobby(
  gameCode: gameCode,
  request: (event, data) {
    final c = socket.client;
    if (c == null) return Future.error(const SocketError('disconnected', 'Not connected'));
    return c.request(event, data);
  },
  messages: socket.events,
);

/// The lobby of [GameId] on the shared socket (catalogue code from
/// [GameCodes]). The socket must be signed in on that game's server first
/// ([AppSocket.game]; `GameSocketLogin`).
final gameLobbyProvider = Provider.autoDispose.family<SocketGameLobby, GameId>((ref, id) {
  final lobby = lobbyOnAppSocket(ref.watch(appSocketProvider), GameCodes.codeOf(id));
  ref.onDispose(lobby.dispose);
  return lobby;
});

/// A game's modes split into Quick match and Play with friends, from the
/// catalogue (04-game-catalogue.md); stakes are on the same [GameCatalogue].
final modePickerProvider = FutureProvider.autoDispose.family<ModePicker, String>(
  (ref, gameCode) async => ModePicker.of(await ref.watch(gameCatalogueProvider(gameCode).future)),
);

/// A [LobbyController] for [id] wired to the app: an `invalid_mode` refetches
/// the catalogue, a kill switch raises the game's banner, and a staked game's
/// end re-reads the wallet. The caller disposes it.
LobbyController lobbyControllerFor(WidgetRef ref, GameId id, {String? myUserId}) {
  final code = GameCodes.codeOf(id);
  return LobbyController(
    lobby: ref.read(gameLobbyProvider(id)),
    myUserId: myUserId,
    onFailure: (f) {
      final events = ref.read(catalogueEventsProvider);
      switch (f.error) {
        case LobbyError.invalidMode:
          events.invalidMode(code).ignore();
        case LobbyError.killSwitch:
          events.killSwitch(code, f.text);
        default:
      }
    },
    onStakedGameEnded: () => ref.read(walletProvider.notifier).gameEnded().ignore(),
  );
}
