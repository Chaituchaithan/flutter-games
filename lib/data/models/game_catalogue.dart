/// The game catalogue (docs/services/04-game-catalogue.md): games, their
/// variants (rule sets), modes, stakes (entry fees), power-ups, settings and
/// achievements, as the gateway's `/games` routes send them.
///
/// Parsing is lenient (00-conventions.md): unknown fields are ignored, money
/// arrives as a number or a numeric string, and a missing field falls back to
/// a safe default instead of throwing.
library;

import 'package:flutter/foundation.dart';

import '../../utils/amount.dart';

Map<String, dynamic> _map(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) => v is List
    ? [
        for (final e in v)
          if (e is Map) e.cast<String, dynamic>(),
      ]
    : const [];
int _int(Object? v, [int fallback = 0]) => v == null
    ? fallback
    : (v is num ? v.toInt() : int.tryParse('$v'.trim()) ?? fallback);
int? _intOrNull(Object? v) =>
    v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'.trim()));
double? _doubleOrNull(Object? v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'.trim()));
String? _str(Object? v) => v is String ? v : null;
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Wallet currencies (00-conventions.md "Money").
abstract final class StakeCurrency {
  static const gold = 'gold';
  static const token = 'token';
}

// ── 1. Games ──

/// One game (`GET /games`, `GET /games/{id}`).
@immutable
class CatalogueGame {
  const CatalogueGame({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.iconUrl,
    this.minPlayers = 1,
    this.maxPlayers = 1,
    this.supportsBots = false,
    this.hasPerPlayerClock = false,
    this.hasHiddenInformation = false,
    this.isRealTime = false,
    this.isHouseBanked = false,
    this.isActive = true,
    this.sortOrder = 0,
  });

  /// Numeric id for `/games/{id}/...` — differs per server: look it up by
  /// [code] every session, never hard-code it.
  final int id;

  /// Stable key (`ludo`, `snake-and-ladder`, `teen_patti`), used as is.
  final String code;

  /// Display name, already branded (`Ludo Royale`). Never derive one from [code].
  final String name;
  final String? description;

  /// Not usable yet (not served by the gateway): ship icons in the app.
  final String? iconUrl;
  final int minPlayers;
  final int maxPlayers;
  final bool supportsBots;
  final bool hasPerPlayerClock;
  final bool hasHiddenInformation;
  final bool isRealTime;
  final bool isHouseBanked;

  /// `false` = switched off at the server: hide it.
  final bool isActive;
  final int sortOrder;

  /// "2-4" / "2" — card text for the overall player range.
  String get playersLabel =>
      minPlayers == maxPlayers ? '$maxPlayers' : '$minPlayers-$maxPlayers';

  factory CatalogueGame.fromJson(Map<String, dynamic> j) => CatalogueGame(
    id: _int(j['id']),
    code: '${j['code'] ?? ''}',
    name: _str(j['name']) ?? '${j['code'] ?? ''}',
    description: _str(j['description']),
    iconUrl: _str(j['icon_url']),
    minPlayers: _int(j['min_players'], 1),
    maxPlayers: _int(j['max_players'], _int(j['min_players'], 1)),
    supportsBots: j['supports_bots'] == true,
    hasPerPlayerClock: j['has_per_player_clock'] == true,
    hasHiddenInformation: j['has_hidden_information'] == true,
    isRealTime: j['is_real_time'] == true,
    isHouseBanked: j['is_house_banked'] == true,
    isActive: j['is_active'] != false,
    sortOrder: _int(j['sort_order']),
  );

  /// For the on-disk copy of the games list.
  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'description': description,
    'icon_url': iconUrl,
    'min_players': minPlayers,
    'max_players': maxPlayers,
    'supports_bots': supportsBots,
    'has_per_player_clock': hasPerPlayerClock,
    'has_hidden_information': hasHiddenInformation,
    'is_real_time': isRealTime,
    'is_house_banked': isHouseBanked,
    'is_active': isActive,
    'sort_order': sortOrder,
  };
}

// ── 3. Variants ──

/// A rule set (`GET /games/{id}/variants`).
@immutable
class GameVariant {
  const GameVariant({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.isDefault = false,
    this.rulesConfig = const {},
  });

  final int id;
  final String code;
  final String name;
  final String? description;

  /// At most one per game; some games have none (preselect the first).
  final bool isDefault;

  /// The engine's rule values (rules sheet only; the server applies them).
  final Map<String, dynamic> rulesConfig;

  /// The rule set the game server actually runs, when it differs (Ludo
  /// `rush` runs `classic`). Socket replies may name this one.
  String? get engineVariant => _str(rulesConfig['engine_variant']);

  factory GameVariant.fromJson(Map<String, dynamic> j) => GameVariant(
    id: _int(j['id']),
    code: '${j['code'] ?? ''}',
    name: _str(j['name']) ?? '${j['code'] ?? ''}',
    description: _str(j['description']),
    isDefault: j['is_default'] == true,
    rulesConfig: _map(j['rules_config']),
  );
}

// ── 4. Modes ──

enum ModeTimerType { turn, clock, round, none }

/// `mode_config.timer` (all values in milliseconds). For the mode card only:
/// in play, timers come from the socket's deadlines.
@immutable
class ModeTimer {
  const ModeTimer({
    this.type = ModeTimerType.none,
    this.turnMs,
    this.timeBankMs,
    this.maxTimeouts,
    this.allowedTurnSeconds = const [],
    this.initialMs,
    this.incrementMs,
    this.firstMoveMs,
    this.durationMs,
    this.raw = const {},
  });

  final ModeTimerType type;

  // "turn"
  final int? turnMs;
  final int? timeBankMs;
  final int? maxTimeouts;

  /// Host-chosen turn times (`[10, 15, 20]`).
  final List<int> allowedTurnSeconds;

  // "clock"
  final int? initialMs;
  final int? incrementMs;
  final int? firstMoveMs;

  // "round" (keys differ per game; `duration_ms` when present)
  final int? durationMs;

  /// The whole blob (round timers carry per-game keys).
  final Map<String, dynamic> raw;

  factory ModeTimer.fromJson(Object? v) {
    final j = _map(v);
    if (j.isEmpty) return const ModeTimer();
    return ModeTimer(
      type: switch (j['type']) {
        'turn' => ModeTimerType.turn,
        'clock' => ModeTimerType.clock,
        'round' => ModeTimerType.round,
        _ => ModeTimerType.none,
      },
      turnMs: _intOrNull(j['turn_ms']),
      timeBankMs: _intOrNull(j['time_bank_ms']),
      maxTimeouts: _intOrNull(j['max_timeouts']),
      allowedTurnSeconds: j['allowed_turn_seconds'] is List
          ? [
              for (final s in j['allowed_turn_seconds'] as List)
                if (_intOrNull(s) != null) _intOrNull(s)!,
            ]
          : const [],
      initialMs: _intOrNull(j['initial_ms']),
      incrementMs: _intOrNull(j['increment_ms']),
      firstMoveMs: _intOrNull(j['first_move_ms']),
      durationMs: _intOrNull(j['duration_ms']),
      raw: j,
    );
  }

  /// Short, language-neutral chip text: `10s` (turns), `3+2` (clock),
  /// `90s` (a round with a duration); null when the socket sends its own.
  String? get shortLabel {
    String secs(int ms) => '${(ms / 1000).round()}s';
    String mins(int ms) {
      final m = ms / 60000;
      return m == m.roundToDouble()
          ? '${m.round()}'
          : (m >= 1 ? m.toStringAsFixed(1) : secs(ms));
    }

    return switch (type) {
      ModeTimerType.turn => turnMs == null ? null : secs(turnMs!),
      ModeTimerType.clock =>
        initialMs == null
            ? null
            : '${mins(initialMs!)}+${((incrementMs ?? 0) / 1000).round()}',
      ModeTimerType.round => durationMs == null ? null : secs(durationMs!),
      ModeTimerType.none => null,
    };
  }
}

/// One entry of `mode_config.rule_options`.
@immutable
class RuleOption {
  const RuleOption({
    required this.key,
    required this.label,
    required this.type,
    this.defaultValue,
    this.engine,
    this.cards = const [],
  });

  final String key;
  final String label;

  /// `bool`, `choice`, `number` or `seconds`.
  final String type;
  final Object? defaultValue;

  /// `has` = the game server applies it; `pending` = not yet (don't show).
  final String? engine;

  /// The variants this option belongs to (friends modes).
  final List<String> cards;

  bool get applied => engine == 'has';

  factory RuleOption.fromJson(Map<String, dynamic> j) => RuleOption(
    key: '${j['key'] ?? ''}',
    label: _str(j['label']) ?? '${j['key'] ?? ''}',
    type: _str(j['type']) ?? 'bool',
    defaultValue: j['default'],
    engine: _str(j['engine']),
    cards: j['cards'] is List
        ? [for (final c in j['cards'] as List) '$c']
        : const [],
  );
}

/// A private-room option the host may set (`host_can_choose` + `host_options`).
@immutable
class HostOption {
  const HostOption({
    required this.key,
    required this.label,
    this.values = const [],
    this.min,
    this.max,
    this.step,
    this.type,
    this.current,
  });

  final String key;
  final String label;

  /// The choices (for a timer key: `timer.allowed_turn_seconds`).
  final List<Object?> values;
  final num? min;
  final num? max;
  final num? step;
  final String? type;

  /// The mode's current value (`mode_config.<key>` or the rule default).
  final Object? current;

  bool get isTurnTimer => key == 'turn_seconds';
}

/// `mode_config.subscription_gate`: rated matches a day per tier (null = no cap).
@immutable
class SubscriptionGate {
  const SubscriptionGate({this.free, this.silver, this.gold});
  final int? free;
  final int? silver;
  final int? gold;

  /// Both shapes; null when the blob is missing or empty.
  static SubscriptionGate? fromJson(Object? v) {
    final j = _map(v);
    if (j.isEmpty) return null;
    if (j['rated_per_day'] is Map) {
      final r = _map(j['rated_per_day']);
      return SubscriptionGate(
        free: _intOrNull(r['free']),
        silver: _intOrNull(r['silver']),
        gold: _intOrNull(r['gold']),
      );
    }
    return SubscriptionGate(
      free: _intOrNull(j['free_rated_per_day']),
      silver: _intOrNull(j['silver_rated_per_day']),
      gold: _intOrNull(j['gold_rated_per_day']),
    );
  }

  /// The daily cap for a tier (`free`, `silver`, `gold`; `royal` counts as gold).
  int? capFor(String tier) => switch (tier) {
    'silver' => silver,
    'gold' || 'royal' => gold,
    _ => free,
  };
}

/// A playable mode (`GET /games/{id}/modes`).
@immutable
class GameMode {
  const GameMode({
    required this.id,
    required this.code,
    required this.name,
    this.gameId = 0,
    this.description,
    this.playerCount = 2,
    this.minPlayers = 2,
    this.turnTimerSeconds,
    this.isRanked = false,
    this.variantId,
    this.variantCode,
    this.limitLabel,
    this.timer = const ModeTimer(),
    this.ruleOptions = const [],
    this.hostCanChoose = const [],
    this.hostOptions = const [],
    this.subscriptionGate,
    this.minTier,
    this.config = const {},
    this.json = const {},
  });

  /// Joins stakes to modes. **Never** sent on the socket.
  final int id;
  final int gameId;

  /// The key the game socket takes (`mode_code`).
  final String code;
  final String name;
  final String? description;

  /// Most seats.
  final int playerCount;

  /// Fewest players a game starts with (private-room seat range).
  final int minPlayers;
  final int? turnTimerSeconds;
  final bool isRanked;
  final int? variantId;

  /// The catalogue's variant code (not the engine's).
  final String? variantCode;

  /// Optional chip (`Standard`, `Ranked`, `Pot-Limit`).
  final String? limitLabel;
  final ModeTimer timer;

  /// Every rule option; show [appliedRules] only.
  final List<RuleOption> ruleOptions;

  /// Private-room keys the host may set (empty = no host picks).
  final List<String> hostCanChoose;
  final List<HostOption> hostOptions;
  final SubscriptionGate? subscriptionGate;

  /// `silver` / `gold`: the mode needs that subscription (show a lock).
  final String? minTier;

  /// The whole `mode_config` (game-specific keys).
  final Map<String, dynamic> config;

  /// The reply row as sent (for game-specific parsers).
  final Map<String, dynamic> json;

  /// A private-room ("with friends") mode.
  bool get isPrivateRoom => hostCanChoose.isNotEmpty;

  /// Rules the game server applies (`engine: "has"`), for the rules sheet.
  List<RuleOption> get appliedRules => [
    for (final r in ruleOptions)
      if (r.applied) r,
  ];

  /// Power-ups usable in this mode (`powerups_allowed` / `powerups_enabled`).
  bool get powerUpsAllowed {
    for (final k in const ['powerups_allowed', 'powerups_enabled']) {
      if (config[k] is bool) return config[k] as bool;
      for (final r in ruleOptions) {
        if (r.key == k && r.defaultValue is bool) return r.defaultValue as bool;
      }
    }
    return true;
  }

  factory GameMode.fromJson(Map<String, dynamic> j) {
    final cfg = _map(j['mode_config']);
    final timer = ModeTimer.fromJson(cfg['timer']);
    final rules = [
      for (final r in _maps(cfg['rule_options'])) RuleOption.fromJson(r),
    ];
    final choose = cfg['host_can_choose'] is List
        ? [for (final k in cfg['host_can_choose'] as List) '$k']
        : const <String>[];
    final opts = _map(cfg['host_options']);
    Object? current(String key) {
      if (cfg.containsKey(key) && cfg[key] != null) return cfg[key];
      if (key == 'turn_seconds' && timer.turnMs != null) {
        return timer.turnMs! ~/ 1000;
      }
      for (final r in rules) {
        if (r.key == key) return r.defaultValue;
      }
      return null;
    }

    return GameMode(
      id: _int(j['id']),
      gameId: _int(j['game_id']),
      code: '${j['code'] ?? ''}',
      name: _str(j['name']) ?? '${j['code'] ?? ''}',
      description: _str(j['description']),
      playerCount: _int(j['player_count'], 2),
      minPlayers: _int(j['min_players'], _int(j['player_count'], 2)),
      turnTimerSeconds: _intOrNull(j['turn_timer_seconds']),
      isRanked: j['is_ranked'] == true,
      variantId: _intOrNull(j['variant_id']),
      variantCode: _str(j['variant_code']),
      limitLabel: _str(j['limit_label']),
      timer: timer,
      ruleOptions: rules,
      hostCanChoose: choose,
      hostOptions: [
        for (final k in choose)
          () {
            final o = _map(opts[k]);
            final isTimer = k == 'turn_seconds';
            return HostOption(
              key: k,
              label: _str(o['label']) ?? k,
              values: o['values'] is List
                  ? List<Object?>.unmodifiable(o['values'] as List)
                  : (isTimer ? timer.allowedTurnSeconds : const []),
              min: o['min'] is num ? o['min'] as num : null,
              max: o['max'] is num ? o['max'] as num : null,
              step: o['step'] is num ? o['step'] as num : null,
              type: _str(o['type']),
              current: current(k),
            );
          }(),
      ],
      subscriptionGate: SubscriptionGate.fromJson(cfg['subscription_gate']),
      minTier: _str(cfg['min_tier']),
      config: cfg,
      json: j,
    );
  }
}

// ── 5. Stakes ──

/// The four stake row shapes (a database check makes them exclusive).
enum StakeShape { fixed, range, blinds, points }

/// A stake tier (`GET /games/{id}/stakes`). Only [StakeShape.fixed] and
/// [StakeShape.range] are playable in this version ([isSupported]).
@immutable
class Stake {
  const Stake({
    required this.id,
    required this.modeId,
    required this.currency,
    this.gameId = 0,
    this.stakeAmount,
    this.minStakeAmount,
    this.maxStakeAmount,
    this.stakeStep,
    this.smallBlind,
    this.bigBlind,
    this.pointValue,
    this.stakeLabel,
    this.tierLabel,
    this.tierOrder,
    this.basePayoutMultiplier,
  });

  /// List key only. **Never** sent on the socket.
  final int id;
  final int gameId;
  final int modeId;

  /// [StakeCurrency.gold] or [StakeCurrency.token].
  final String currency;

  /// Fixed entry fee per player (the `bet_amount` to send).
  final int? stakeAmount;
  final int? minStakeAmount;
  final int? maxStakeAmount;
  final int? stakeStep;
  final int? smallBlind;
  final int? bigBlind;

  /// Currency per point (may be fractional).
  final double? pointValue;

  /// Ladder name (`Entry`, `Boot`, …); null for older tiers.
  final String? stakeLabel;

  /// The tier as printed (`10`, `1/2`); set exactly when [stakeLabel] is.
  final String? tierLabel;
  final int? tierOrder;

  /// Not reliable — never show it as a prize (04-game-catalogue.md "Prize").
  final double? basePayoutMultiplier;

  StakeShape get shape {
    if (pointValue != null && stakeAmount == null && minStakeAmount == null) {
      return StakeShape.points;
    }
    if (smallBlind != null || bigBlind != null) return StakeShape.blinds;
    if (stakeAmount == null &&
        minStakeAmount != null &&
        maxStakeAmount != null) {
      return StakeShape.range;
    }
    return StakeShape.fixed;
  }

  /// Shown in this version: fixed and range rows. Blinds and points rows are
  /// hidden until the game's own hand-off file covers them.
  bool get isSupported => switch (shape) {
    StakeShape.fixed => stakeAmount != null,
    StakeShape.range => true,
    StakeShape.blinds || StakeShape.points => false,
  };

  bool get isLabelled => stakeLabel != null;

  /// The least a player must hold to pick this row.
  int get minimumEntry => stakeAmount ?? minStakeAmount ?? 0;

  /// The player can cover this tier with [balance] of its currency.
  bool affordable(int balance) => minimumEntry <= balance;

  /// [amount] is one this row lists (a range row: on its steps).
  bool allows(int amount) => switch (shape) {
    StakeShape.fixed => amount == stakeAmount,
    StakeShape.range =>
      amount >= minStakeAmount! &&
          amount <= maxStakeAmount! &&
          ((stakeStep ?? 1) <= 0 ||
              (amount - minStakeAmount!) % (stakeStep ?? 1) == 0),
    _ => false,
  };

  /// Chip text: the server's [tierLabel], else the amount (or `min-max`).
  String get displayLabel =>
      tierLabel ??
      switch (shape) {
        StakeShape.range => '$minStakeAmount-$maxStakeAmount',
        StakeShape.blinds => '$smallBlind/$bigBlind',
        StakeShape.points => '$pointValue',
        StakeShape.fixed => '${stakeAmount ?? 0}',
      };

  factory Stake.fromJson(Map<String, dynamic> j) {
    int? money(Object? v) => v == null ? null : parseAmount(v);
    return Stake(
      id: _int(j['id']),
      gameId: _int(j['game_id']),
      modeId: _int(j['mode_id']),
      currency: _str(j['currency']) ?? StakeCurrency.token,
      stakeAmount: money(j['stake_amount']),
      minStakeAmount: money(j['min_stake_amount']),
      maxStakeAmount: money(j['max_stake_amount']),
      stakeStep: money(j['stake_step']),
      smallBlind: money(j['small_blind']),
      bigBlind: money(j['big_blind']),
      pointValue: _doubleOrNull(j['point_value']),
      stakeLabel: _str(j['stake_label']),
      tierLabel: _str(j['tier_label']),
      tierOrder: _intOrNull(j['tier_order']),
      basePayoutMultiplier: _doubleOrNull(j['base_payout_multiplier']),
    );
  }
}

/// A stake as the picker shows it: greyed out above the balance.
@immutable
class StakeOption {
  const StakeOption(this.stake, {required this.enabled});
  final Stake stake;
  final bool enabled;
}

// ── 6. Power-ups ──

@immutable
class PowerUp {
  const PowerUp({
    required this.id,
    required this.code,
    required this.name,
    this.gameId = 0,
    this.description,
    this.priceCurrency,
    this.priceAmount,
    this.isConsumable = false,
    this.maxPerMatch,
    this.sortOrder = 0,
  });

  final int id;
  final int gameId;

  /// The key the game socket uses for it.
  final String code;
  final String name;
  final String? description;

  /// Null (both) = earned only in play.
  final String? priceCurrency;
  final int? priceAmount;
  final bool isConsumable;

  /// Null = no limit.
  final int? maxPerMatch;
  final int sortOrder;

  bool get isForSale => priceCurrency != null && priceAmount != null;

  factory PowerUp.fromJson(Map<String, dynamic> j) => PowerUp(
    id: _int(j['id']),
    gameId: _int(j['game_id']),
    code: '${j['code'] ?? ''}',
    name: _str(j['name']) ?? '${j['code'] ?? ''}',
    description: _str(j['description']),
    priceCurrency: _str(j['price_currency']),
    priceAmount: j['price_amount'] == null
        ? null
        : parseAmount(j['price_amount']),
    isConsumable: j['is_consumable'] == true,
    maxPerMatch: _intOrNull(j['max_per_match']),
    sortOrder: _int(j['sort_order']),
  );
}

// ── 7. Settings ──

/// A game's settings blob (`GET /games/{id}/config`). Named so as not to
/// clash with the app's own `GameConfig`. Read only keys the game's own
/// hand-off file names.
@immutable
class GameSettings {
  const GameSettings({
    required this.gameId,
    this.config = const {},
    this.version = 0,
    this.updatedAt,
  });
  final int gameId;
  final Map<String, dynamic> config;

  /// Raised by one on every change: the cache key.
  final int version;
  final DateTime? updatedAt;

  /// A nested value by dotted path (`board.player_colors`), or null.
  Object? at(String path) {
    Object? v = config;
    for (final part in path.split('.')) {
      if (v is! Map) return null;
      v = v[part];
    }
    return v;
  }

  /// Null when the reply is `null` (the game has no settings).
  static GameSettings? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    return GameSettings(
      gameId: _int(j['game_id']),
      config: _map(j['config']),
      version: _int(j['version']),
      updatedAt: _date(j['updated_at']),
    );
  }
}

// ── 8. Achievements ──

@immutable
class AchievementTier {
  const AchievementTier({
    required this.tier,
    required this.threshold,
    this.rewardKind,
    this.rewardAmount,
    this.rewardName,
  });
  final String tier;
  final int threshold;

  /// `tokens`, `gold` or `title`.
  final String? rewardKind;
  final int? rewardAmount;
  final String? rewardName;

  factory AchievementTier.fromJson(Map<String, dynamic> j) {
    final r = _map(j['reward']);
    return AchievementTier(
      tier: '${j['tier'] ?? ''}',
      threshold: _int(j['threshold']),
      rewardKind: _str(r['kind']),
      rewardAmount: r['amount'] == null ? null : parseAmount(r['amount']),
      rewardName: _str(r['name']),
    );
  }
}

@immutable
class GameAchievement {
  const GameAchievement({
    required this.id,
    required this.code,
    required this.name,
    this.gameId,
    this.description,
    this.rewardTokens = 0,
    this.rewardGold = 0,
    this.expReward = 0,
    this.sortOrder = 0,
    this.tiers = const [],
    this.trigger,
    this.isSecret = false,
  });

  final int id;
  final int? gameId;
  final String code;

  /// "Secret achievement" for a secret one (the server hides the real name).
  final String name;
  final String? description;
  final int rewardTokens;
  final int rewardGold;
  final int expReward;
  final int sortOrder;

  /// Empty = a one-step badge with the flat rewards.
  final List<AchievementTier> tiers;
  final String? trigger;

  /// Show a locked card.
  final bool isSecret;

  bool get isTiered => tiers.isNotEmpty;

  factory GameAchievement.fromJson(Map<String, dynamic> j) => GameAchievement(
    id: _int(j['id']),
    gameId: _intOrNull(j['game_id']),
    code: '${j['code'] ?? ''}',
    name: _str(j['name']) ?? '',
    description: _str(j['description']),
    rewardTokens: parseAmount(j['reward_tokens']),
    rewardGold: parseAmount(j['reward_gold']),
    expReward: _int(j['exp_reward']),
    sortOrder: _int(j['sort_order']),
    tiers: [for (final t in _maps(j['tiers'])) AchievementTier.fromJson(t)],
    trigger: _str(j['trigger']),
    isSecret: j['is_secret'] == true,
  );
}

// ── A game's home: variants + modes + stakes together ──

/// What the game home needs (loaded together, 3 calls).
@immutable
class GameCatalogue {
  const GameCatalogue({
    required this.game,
    this.variants = const [],
    this.modes = const [],
    this.stakes = const [],
  });

  final CatalogueGame game;

  /// Active variants, in lobby order.
  final List<GameVariant> variants;

  /// Playable modes, in the server's order.
  final List<GameMode> modes;

  /// Every row as sent (all shapes), in the server's order.
  final List<Stake> stakes;

  GameMode? mode(String? code) =>
      modes.where((m) => m.code == code).firstOrNull;
  GameVariant? variant(String? code) =>
      variants.where((v) => v.code == code).firstOrNull;

  /// The variant to preselect: the default one, else the first.
  GameVariant? get defaultVariant =>
      variants.where((v) => v.isDefault).firstOrNull ?? variants.firstOrNull;

  /// The mode picker: modes grouped by variant, in variant order. Modes whose
  /// variant isn't listed go last under a null key.
  Map<GameVariant?, List<GameMode>> get modesByVariant {
    final out = <GameVariant?, List<GameMode>>{};
    for (final v in variants) {
      final ms = [
        for (final m in modes)
          if (m.variantId == v.id ||
              (m.variantId == null && m.variantCode == v.code))
            m,
      ];
      if (ms.isNotEmpty) out[v] = ms;
    }
    final rest = [
      for (final m in modes)
        if (!out.values.any((l) => l.contains(m))) m,
    ];
    if (rest.isNotEmpty) out[null] = rest;
    return out;
  }

  /// The supported stake rows of [mode], in reply (ladder) order;
  /// optionally one [currency]. Blinds/points rows are left out.
  List<Stake> stakesFor(GameMode mode, {String? currency}) => [
    for (final s in stakes)
      if (s.modeId == mode.id &&
          s.isSupported &&
          (currency == null || s.currency == currency))
        s,
  ];

  /// The currency tabs for [mode] (in first-seen order). Empty = free only.
  List<String> currenciesFor(GameMode mode) =>
      {for (final s in stakesFor(mode)) s.currency}.toList();

  /// The stake picker rows: [mode]'s tiers in [currency], greyed out above
  /// [balance] (null = balance unknown, nothing greyed).
  List<StakeOption> stakeOptions(
    GameMode mode,
    String currency, {
    int? balance,
  }) => [
    for (final s in stakesFor(mode, currency: currency))
      StakeOption(s, enabled: balance == null || s.affordable(balance)),
  ];

  /// A mode with no stake rows is free only (free play is always allowed).
  bool isFreeOnly(GameMode mode) => stakesFor(mode).isEmpty;

  GameCatalogue withoutMode(String code) => GameCatalogue(
    game: game,
    variants: variants,
    modes: [
      for (final m in modes)
        if (m.code != code) m,
    ],
    stakes: stakes,
  );
}

// ── 9. From the catalogue to the game socket ──

/// What the player picked, handed to the game's socket code. Holds codes and
/// amounts only — never a numeric id (04-game-catalogue.md section 9).
@immutable
class PlaySelection {
  const PlaySelection({
    required this.gameCode,
    required this.modeCode,
    this.currency,
    this.betAmount = 0,
    this.hostPicks = const {},
    this.sharedSocket = false,
  });

  /// Builds a selection from catalogue rows. [amount] is required for a
  /// range row (a value on its steps); a fixed row uses its own amount; a
  /// null [stake] is free play. Throws [ArgumentError] for an amount the row
  /// doesn't list or an unsupported row shape, and drops host picks the mode
  /// doesn't allow.
  factory PlaySelection.from({
    required CatalogueGame game,
    required GameMode mode,
    Stake? stake,
    int? amount,
    Map<String, Object?> hostPicks = const {},
    bool sharedSocket = false,
  }) {
    if (stake != null && stake.modeId != mode.id) {
      throw ArgumentError('stake ${stake.id} is not for mode ${mode.code}');
    }
    int bet = 0;
    if (stake != null) {
      if (!stake.isSupported) {
        throw ArgumentError('stake shape ${stake.shape.name} is not supported');
      }
      bet = stake.shape == StakeShape.fixed
          ? stake.stakeAmount!
          : (amount ?? stake.minStakeAmount!);
      if (!stake.allows(bet)) {
        throw ArgumentError('amount $bet is not listed for stake ${stake.id}');
      }
    }
    return PlaySelection(
      gameCode: game.code,
      modeCode: mode.code,
      currency: stake?.currency,
      betAmount: bet,
      hostPicks: {
        for (final e in hostPicks.entries)
          if (mode.hostCanChoose.contains(e.key)) e.key: e.value,
      },
      sharedSocket: sharedSocket,
    );
  }

  final String gameCode;
  final String modeCode;

  /// Null = free play.
  final String? currency;

  /// 0 = free play.
  final int betAmount;

  /// One value per `host_can_choose` key (private rooms).
  final Map<String, Object?> hostPicks;

  /// The game's socket hosts several games: send `game_code` too.
  final bool sharedSocket;

  bool get isFree => betAmount <= 0 || currency == null;

  /// The fields for `room.create` / `match.find` (the general rule; a game's
  /// own file may rename the stake fields).
  Map<String, Object?> toSocketData() => {
    if (sharedSocket) 'game_code': gameCode,
    'mode_code': modeCode,
    if (!isFree) 'currency': currency,
    if (!isFree) 'bet_amount': betAmount,
    ...hostPicks,
  };
}
