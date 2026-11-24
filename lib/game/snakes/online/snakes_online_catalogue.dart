/// Snake & Ladder's catalogue from the gateway: modes, stake tiers and boosts
/// (snake-and-ladder.md "Server", "Modes"). Read from the server, never
/// hard-coded: an operator can switch modes off.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../configs/games/core/game_id.dart';
import '../../../services/catalogue_service.dart';
import '../../../services/socket/app_socket.dart';
import '../../common/online_room/room_catalogue.dart';
import 'snakes_online_models.dart';

export '../../common/online_room/room_catalogue.dart';

/// Snake & Ladder's code in the catalogue (`25` on the dev server; the id is
/// always looked up by this code).
const snlCode = 'snake-and-ladder';

/// Quick match: `match.find` with no mode plays this one.
const snlQuickMode = 'quick_50';

/// Play with friends: `room.create` with no mode plays this one.
const snlFriendsMode = 'casual';

/// Snake & Ladder's modes and stakes (re-read when invalidated).
final snlCatalogueProvider = FutureProvider<RoomCatalogue>(
  (ref) async => RoomCatalogue.fromShared(await ref.watch(catalogueRepositoryProvider).details(snlCode)),
);

/// The bet ladder for a private room (`wallet.bet_options` on the Snake &
/// Ladder socket), by currency. Null when the socket isn't signed in on
/// Snake & Ladder, or no ladder is set (any stake the wallet covers).
final snlBetOptionsProvider = FutureProvider.autoDispose.family<SnlBetOffer?, String>((ref, currency) async {
  final socket = ref.watch(appSocketProvider);
  final client = socket.client;
  if (client == null || !socket.isConnected || socket.game?.id != GameId.snakesLadders) return null;
  try {
    final reply = await client.request(RoomEvent.betOptions, {'currency': currency});
    return SnlBetOffer.fromJson(reply.data['offer']);
  } on Object {
    return null;
  }
});
