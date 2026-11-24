/// Ludo's catalogue from the gateway: modes and stake tiers (ludo.md
/// "Server", "Modes"). Read from the server, never hard-coded: an operator
/// can switch modes off.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../configs/configs.dart';
import '../../../data/models/store_pack.dart';
import '../../../services/api_client.dart';
import '../../../services/app_exception.dart';
import '../../../services/catalogue_service.dart';
import '../../common/online_room/room_catalogue.dart';

export '../../common/online_room/room_catalogue.dart';

/// The catalogue pieces are shared with the other rooms-family games
/// (lib/game/common/online_room/room_catalogue.dart).
typedef LudoHostOption = RoomHostOption;
typedef LudoMode = RoomMode;
typedef LudoStake = RoomStake;
typedef LudoCatalogue = RoomCatalogue;

/// Ludo's code in the catalogue.
const ludoCode = 'ludo';

/// Reads Ludo's catalogue and the wallet from the gateway.
class LudoGateway {
  const LudoGateway(this._api);
  final ApiClient _api;

  /// Ludo's id is looked up by code in `GET /games?is_active=true` (never
  /// hard-coded); then its modes and stakes. Throws `GAME_NOT_FOUND` when
  /// Ludo is switched off.
  Future<LudoCatalogue> catalogue() async {
    final api = RemoteCatalogueApi(_api);
    final ludo = (await api.games()).where((g) => g.code == ludoCode).firstOrNull;
    if (ludo == null) {
      throw const AppException(gameUnavailableMessage, kind: AppErrorKind.notFound, statusCode: 404, code: ApiErrorCode.gameNotFound);
    }
    final (modes, stakes) = await (api.modes(ludo.id), api.stakes(ludo.id)).wait;
    return LudoCatalogue.fromShared(GameCatalogue(game: ludo, modes: modes, stakes: stakes));
  }

  /// `GET /wallet/balance` — before a staked game and after it ends.
  Future<Wallet> wallet() async => Wallet.fromJson((await _api.get(ApiEndpoints.walletBalance) as Map).cast<String, dynamic>());
}

final ludoGatewayProvider = Provider<LudoGateway>((ref) => LudoGateway(ref.watch(apiClientProvider)));

/// Ludo's modes and stakes (re-read when invalidated).
final ludoCatalogueProvider = FutureProvider<LudoCatalogue>(
  (ref) async => LudoCatalogue.fromShared(await ref.watch(catalogueRepositoryProvider).details(ludoCode)),
);
