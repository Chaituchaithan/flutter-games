/// Bingo's always-on live rooms from the gateway
/// (docs/services/05-matchmaking-and-rooms.md §3). The gateway gives each
/// room's fixed setup; the Bingo socket plays the rounds (`live.join` with the
/// room's [LiveRoom.id]). Don't poll: live counts and phases come from the
/// socket.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/endpoints/api_endpoints.dart';
import '../../utils/amount.dart';
import '../api_client.dart';

int _int(Object? v) => parseAmount(v);

@immutable
class LivePrize {
  const LivePrize({required this.code, required this.displayName, required this.maxWinners, required this.sharePct});
  final String code;
  final String displayName;
  final int maxWinners;

  /// Share of the pool this prize pays.
  final int sharePct;

  factory LivePrize.fromJson(Map<String, dynamic> j) => LivePrize(
    code: '${j['code'] ?? ''}',
    displayName: '${j['display_name'] ?? j['code'] ?? ''}',
    maxWinners: _int(j['max_winners'] ?? 1),
    sharePct: _int(j['share_pct']),
  );
}

/// One row of `GET /live-rooms`.
@immutable
class LiveRoom {
  const LiveRoom({
    required this.id,
    required this.name,
    required this.variant,
    required this.currency,
    required this.isActive,
    required this.ticketPrice,
    this.sortOrder = 0,
    this.minTickets = 1,
    this.maxTickets = 1,
    this.buyingDuration = Duration.zero,
    this.countdownDuration = Duration.zero,
    this.resultsDuration = Duration.zero,
    this.callInterval = Duration.zero,
    this.minPlayers = 0,
    this.maxPlayers = 0,
    this.rakePct = 0,
    this.guaranteedPool = 0,
    this.prizes = const [],
  });

  /// Sent as `room_id` in Bingo's `live.join`.
  final String id;
  final String name;

  /// `75ball` / `90ball`.
  final String variant;
  final String currency;
  final bool isActive;
  final int sortOrder;

  /// Per card. Grey the room out when the wallet can't pay it.
  final int ticketPrice;
  final int minTickets;
  final int maxTickets;
  final Duration buyingDuration;
  final Duration countdownDuration;
  final Duration resultsDuration;
  final Duration callInterval;

  /// A round is skipped with fewer buyers.
  final int minPlayers;
  final int maxPlayers;
  final int rakePct;

  /// A floor on the pool (`0` = none). Show the pool the socket sends.
  final int guaranteedPool;
  final List<LivePrize> prizes;

  /// "75-ball" / "90-ball".
  String get variantLabel => switch (variant) {
    '75ball' => '75-ball',
    '90ball' => '90-ball',
    _ => variant,
  };

  /// "10 tokens a card".
  String get priceLabel => '$ticketPrice ${currency == 'gold' ? 'gold' : (ticketPrice == 1 ? 'token' : 'tokens')} a card';

  factory LiveRoom.fromJson(Map<String, dynamic> j) {
    Duration ms(String k) => Duration(milliseconds: _int(j[k]));
    final prizes = (j['prize_config'] is Map ? (j['prize_config'] as Map)['prizes'] : null);
    return LiveRoom(
      id: '${j['id'] ?? ''}',
      name: '${j['name'] ?? ''}',
      variant: '${j['variant'] ?? ''}',
      currency: '${j['currency'] ?? 'token'}',
      isActive: j['is_active'] != false,
      sortOrder: _int(j['sort_order']),
      ticketPrice: _int(j['ticket_price']),
      minTickets: _int(j['min_tickets'] ?? 1),
      maxTickets: _int(j['max_tickets'] ?? 1),
      buyingDuration: ms('buying_duration_ms'),
      countdownDuration: ms('countdown_duration_ms'),
      resultsDuration: ms('results_duration_ms'),
      callInterval: ms('call_interval_ms'),
      minPlayers: _int(j['min_players']),
      maxPlayers: _int(j['max_players']),
      rakePct: _int(j['rake_pct']),
      guaranteedPool: _int(j['guaranteed_pool']),
      prizes: [for (final p in (prizes is List ? prizes : const [])) if (p is Map) LivePrize.fromJson(p.cast<String, dynamic>())],
    );
  }
}

class LiveRoomsApi {
  const LiveRoomsApi(this._api);
  final ApiClient _api;

  /// `GET /live-rooms` — the app sends `is_active=true` (only rooms that are
  /// on). [variant] `75ball` / `90ball` (anything else returns `[]`). Kept in
  /// the server's display order.
  Future<List<LiveRoom>> list({bool? isActive = true, String? variant}) async {
    final rows = await _api.get(ApiEndpoints.liveRooms, query: {
      if (isActive != null) 'is_active': '$isActive',
      'variant': ?variant,
    });
    return [for (final r in (rows is List ? rows : const [])) if (r is Map) LiveRoom.fromJson(r.cast<String, dynamic>())];
  }

  /// `GET /live-rooms/{id}` (a deep link). An inactive room is still
  /// returned: check [LiveRoom.isActive] before joining. `404` → reload the
  /// list.
  Future<LiveRoom> get(String id) async =>
      LiveRoom.fromJson(((await _api.get(ApiEndpoints.liveRoom(id))) as Map).cast<String, dynamic>());
}

final liveRoomsApiProvider = Provider<LiveRoomsApi>((ref) => LiveRoomsApi(ref.watch(apiClientProvider)));

/// Active Bingo live rooms (invalidate to reload, e.g. after a 404).
final liveRoomsProvider = FutureProvider.autoDispose<List<LiveRoom>>((ref) => ref.watch(liveRoomsApiProvider).list());
