/// A rooms-family game's catalogue from the gateway: modes and stake tiers
/// (04-game-catalogue.md). Read from the server, never hard-coded: an
/// operator can switch modes off. Shared by Ludo and Snake & Ladder.
library;

import 'package:flutter/foundation.dart';

import '../../../services/catalogue_service.dart';

/// A host option a friends room may set (`mode_config.host_can_choose`).
@immutable
class RoomHostOption {
  const RoomHostOption(this.key, this.label);
  final String key;
  final String label;
}

/// One playable mode (`GET /games/{id}/modes`).
@immutable
class RoomMode {
  const RoomMode({
    required this.id,
    required this.code,
    required this.name,
    required this.seats,
    required this.minPlayers,
    required this.turnSeconds,
    this.variant,
    this.ranked = false,
    this.friends = false,
    this.allowedTurnSeconds = const [],
    this.hostOptions = const [],
    this.ruleDefaults = const {},
    this.maxTimeouts = 3,
    this.matchClockMs,
  });

  final int id;
  final String code;
  final String name;

  /// The most it seats.
  final int seats;
  final int minPlayers;
  final int turnSeconds;
  final String? variant;
  final bool ranked;

  /// A "with friends" mode (`room.create`; host options, bots never join).
  final bool friends;

  /// Turn times the host may pick (Ludo 10 / 15 / 20; Snake & Ladder 20 / 30 / 45).
  final List<int> allowedTurnSeconds;

  /// Rule picks the host may change (not the turn timer).
  final List<RoomHostOption> hostOptions;
  final Map<String, bool> ruleDefaults;

  /// Timed-out turns in a row before a player is out.
  final int maxTimeouts;

  /// Rush: the match clock.
  final int? matchClockMs;

  factory RoomMode.fromJson(Map<String, dynamic> j) {
    final cfg = j['mode_config'] is Map ? (j['mode_config'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final timer = cfg['timer'] is Map ? (cfg['timer'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final choose = cfg['host_can_choose'] is List ? [for (final k in cfg['host_can_choose'] as List) '$k'] : const <String>[];
    final labels = cfg['host_options'] is Map ? (cfg['host_options'] as Map).cast<String, dynamic>() : const {};
    return RoomMode(
      id: (j['id'] as num?)?.toInt() ?? 0,
      code: '${j['code'] ?? ''}',
      name: '${j['name'] ?? j['code'] ?? ''}',
      seats: (j['player_count'] as num?)?.toInt() ?? 2,
      minPlayers: (j['min_players'] as num?)?.toInt() ?? 2,
      turnSeconds: timer['turn_ms'] is num ? (timer['turn_ms'] as num) ~/ 1000 : (j['turn_timer_seconds'] as num?)?.toInt() ?? 15,
      variant: j['variant_code'] as String?,
      ranked: j['is_ranked'] == true,
      friends: choose.isNotEmpty,
      allowedTurnSeconds: timer['allowed_turn_seconds'] is List
          ? [for (final s in timer['allowed_turn_seconds'] as List) (s as num).toInt()]
          : const [],
      hostOptions: [
        for (final k in choose)
          if (k != 'turn_seconds' && k != 'turn_timer_sec')
            RoomHostOption(k, (labels[k] is Map ? (labels[k] as Map)['label'] : null) as String? ?? k),
      ],
      ruleDefaults: {for (final k in choose) if (cfg[k] is bool) k: cfg[k] as bool},
      maxTimeouts: (timer['max_timeouts'] as num?)?.toInt() ?? 3,
      matchClockMs: (cfg['match_clock_ms'] as num?)?.toInt(),
    );
  }
}

/// A stake tier (`GET /games/{id}/stakes`).
@immutable
class RoomStake {
  const RoomStake({required this.modeId, required this.currency, required this.amount});
  final int modeId;

  /// `token` / `gold`.
  final String currency;
  final int amount;
}

@immutable
class RoomCatalogue {
  const RoomCatalogue({required this.gameId, required this.modes, required this.stakes});
  final int gameId;

  /// Active modes, in the server's order.
  final List<RoomMode> modes;
  final List<RoomStake> stakes;

  List<RoomMode> get quickModes => [for (final m in modes) if (!m.friends) m];
  List<RoomMode> get friendsModes => [for (final m in modes) if (m.friends) m];

  RoomMode? mode(String? code) => modes.where((m) => m.code == code).firstOrNull;

  /// A reply row for a mode built in the app (the offline demo catalogue).
  static Map<String, dynamic> _rowOf(GameMode m) => {
        'id': m.id,
        'code': m.code,
        'name': m.name,
        'player_count': m.playerCount,
        'min_players': m.minPlayers,
        'turn_timer_seconds': m.turnTimerSeconds ?? (m.timer.turnMs == null ? null : m.timer.turnMs! ~/ 1000),
        'variant_code': m.variantCode,
        'is_ranked': m.isRanked,
        'mode_config': {
          ...m.config,
          'timer': {'allowed_turn_seconds': m.timer.allowedTurnSeconds, 'max_timeouts': m.timer.maxTimeouts ?? 3},
          'host_can_choose': m.hostCanChoose,
          'host_options': {for (final o in m.hostOptions) o.key: {'label': o.label}},
        },
      };

  /// From the shared catalogue (lib/services/catalogue_service.dart): every
  /// mode, and the fixed stake tiers (range/blinds/points rows left out).
  factory RoomCatalogue.fromShared(GameCatalogue c) => RoomCatalogue(
        gameId: c.game.id,
        modes: [for (final m in c.modes) RoomMode.fromJson(m.json.isEmpty ? _rowOf(m) : m.json)],
        stakes: [
          for (final s in c.stakes)
            if (s.shape == StakeShape.fixed && s.stakeAmount != null) RoomStake(modeId: s.modeId, currency: s.currency, amount: s.stakeAmount!),
        ],
      );

  /// Stake tiers of [mode] in [currency], low to high.
  List<int> stakesFor(RoomMode mode, String currency) =>
      [for (final s in stakes) if (s.modeId == mode.id && s.currency == currency) s.amount]..sort();

  /// Currencies [mode] can be staked in.
  Set<String> currenciesFor(RoomMode mode) => {for (final s in stakes) if (s.modeId == mode.id) s.currency};
}

