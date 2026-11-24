import 'package:flutter/foundation.dart';

import '../../utils/amount.dart';
import 'wallet.dart' show WalletCurrency;

/// Tournament models (docs/services/06-tournaments.md). Every enum has an
/// `unknown` fallback: the server adds values without notice, and an unknown
/// one must show a neutral label, never crash.

String? _str(Object? v) => v == null ? null : (v is String ? v : '$v');
int? _intOrNull(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;
Map<String, dynamic> _obj(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
List<Object?> _arr(Object? v) => v is List ? v : const [];

/// `status`: announced → registering → running ⇄ paused → completed, or
/// cancelled → refunded.
enum TournamentStatus {
  announced,
  registering,
  running,
  paused,
  completed,
  cancelled,
  refunded,
  unknown;

  static TournamentStatus parse(Object? v) =>
      values.where((s) => s != unknown && s.name == v).firstOrNull ?? unknown;

  /// The lobby tab it belongs to (null = unknown: listed nowhere by status).
  TournamentTab? get tab => switch (this) {
        announced || registering => TournamentTab.upcoming,
        running || paused => TournamentTab.running,
        completed || cancelled || refunded => TournamentTab.finished,
        unknown => null,
      };

  bool get isCancelled => this == cancelled || this == refunded;
  bool get isOver => this == completed || isCancelled;

  /// A neutral word for a chip.
  String get label => switch (this) {
        announced => 'Opens soon',
        registering => 'Open',
        running => 'Live',
        paused => 'Paused',
        completed => 'Finished',
        cancelled => 'Cancelled',
        refunded => 'Cancelled',
        unknown => 'Unavailable',
      };
}

/// `tournament_type`, the format. Only [singleTableSng] and
/// [leaderboardWindow] are run by the server today (Known issues, 1).
enum TournamentType {
  singleTableSng('single_table_sng', 'Sit & Go'),
  leaderboardWindow('leaderboard_window', 'Score window'),
  multiTableMtt('multi_table_mtt', 'Multi-table'),
  bracketSingleElim('bracket_single_elim', 'Knockout'),
  bracketDoubleElim('bracket_double_elim', 'Knockout'),
  swiss('swiss', 'Swiss'),
  roundRobin('round_robin', 'Round robin'),
  ladder('ladder', 'Ladder'),
  arena('arena', 'Arena'),
  chipRace('chip_race', 'Chip race'),
  pointsSeries('points_series', 'Points series'),
  heatsKnockout('heats_knockout', 'Heats knockout'),
  tableKnockout('table_knockout', 'Table knockout'),
  unknown('', 'Tournament');

  const TournamentType(this.wire, this.label);
  final String wire;

  /// Name to show.
  final String label;

  static TournamentType parse(Object? v) =>
      values.where((t) => t != unknown && t.wire == v).firstOrNull ?? unknown;

  /// The server's engine starts and runs it. Others are "Coming soon".
  bool get runsOnServer => this == singleTableSng || this == leaderboardWindow;

  bool get isSitAndGo => this == singleTableSng;
}

/// `entry_status` on `my-table` and `standings` (null = not entered).
enum EntryStatus {
  registered,
  active,
  busted,
  winner,
  withdrawn,
  disqualified,
  unknown;

  static EntryStatus? parse(Object? v) =>
      v == null ? null : (values.where((s) => s != unknown && s.name == v).firstOrNull ?? unknown);

  String get label => switch (this) {
        registered => 'Registered',
        active => 'Playing',
        busted => 'Out',
        winner => 'Winner',
        withdrawn => 'Withdrawn',
        disqualified => 'Disqualified',
        unknown => '',
      };
}

/// `leave_reason` of a seat (null while playing).
enum LeaveReason {
  finished,
  busted,
  withdrawn,
  noShow,
  unknown;

  static LeaveReason? parse(Object? v) => switch (v) {
        null => null,
        'finished' => finished,
        'busted' => busted,
        'withdrawn' => withdrawn,
        'no_show' => noShow,
        _ => unknown,
      };

  String get label => switch (this) {
        finished => 'Finished',
        busted => 'Out',
        withdrawn => 'Withdrawn',
        noShow => 'No show',
        unknown => '',
      };
}

/// A table's `status`. Unknown values are treated as [waiting].
enum TableStatus {
  waiting,
  playing,
  closed;

  static TableStatus parse(Object? v) => switch (v) {
        'playing' => playing,
        'closed' => closed,
        _ => waiting,
      };
}

/// The three lobby tabs and the statuses each one reads (one per call).
enum TournamentTab {
  upcoming([TournamentStatus.registering, TournamentStatus.announced]),
  running([TournamentStatus.running, TournamentStatus.paused]),
  finished([TournamentStatus.completed, TournamentStatus.refunded, TournamentStatus.cancelled]);

  const TournamentTab(this.statuses);
  final List<TournamentStatus> statuses;

  String get label => switch (this) {
        upcoming => 'Upcoming',
        running => 'Running',
        finished => 'Finished',
      };
}

/// One tournament (`GET /tournaments` row and `GET /tournaments/{id}`).
@immutable
class Tournament {
  const Tournament({
    required this.id,
    required this.gameId,
    required this.name,
    required this.type,
    required this.status,
    this.modeId,
    this.maxPlayers,
    this.currentPlayers = 0,
    this.entryFee = 0,
    this.feeAmount = 0,
    this.currencyWire = 'token',
    this.prizePool = 0,
    this.startsAt,
    this.typeWire,
    this.statusWire,
  });

  final String id;

  /// The game's numeric catalogue id (Ludo is 1 on the dev server).
  final int gameId;
  final int? modeId;
  final String name;
  final TournamentType type;
  final TournamentStatus status;

  /// Seats in total; null = no limit.
  final int? maxPlayers;
  final int currentPlayers;

  /// The buy-in (into the prize pool); 0 = free.
  final int entryFee;

  /// The house fee on top. The player pays [entryFee] + [feeAmount].
  final int feeAmount;

  /// `token` or `gold` as sent.
  final String currencyWire;

  /// max(guaranteed, collected). 0 for a Sit & Go until it starts.
  final int prizePool;

  /// Scheduled start. Meaningless for a Sit & Go: never show it there.
  final DateTime? startsAt;

  /// The raw values, for diagnostics when parsed as unknown.
  final String? typeWire;
  final String? statusWire;

  factory Tournament.fromJson(Map<String, dynamic> j) => Tournament(
        id: _str(j['id']) ?? '',
        gameId: _intOrNull(j['game_id']) ?? 0,
        modeId: _intOrNull(j['mode_id']),
        name: _str(j['name']) ?? '',
        type: TournamentType.parse(j['tournament_type']),
        typeWire: _str(j['tournament_type']),
        status: TournamentStatus.parse(j['status']),
        statusWire: _str(j['status']),
        maxPlayers: _intOrNull(j['max_players']),
        currentPlayers: parseAmount(j['current_players']),
        entryFee: parseAmount(j['entry_fee']),
        feeAmount: parseAmount(j['fee_amount']),
        currencyWire: _str(j['currency']) ?? 'token',
        prizePool: parseAmount(j['prize_pool']),
        startsAt: _time(j['starts_at']),
      );

  WalletCurrency get currency => WalletCurrency.tryParse(currencyWire) ?? WalletCurrency.token;

  /// What joining costs: buy-in + fee.
  int get totalCost => entryFee + feeAmount;
  bool get isFree => totalCost == 0;
  bool get isSitAndGo => type.isSitAndGo;

  /// Every seat taken.
  bool get isFull => maxPlayers != null && currentPlayers >= maxPlayers!;

  /// Joinable formats only: the rest show "Coming soon" without Join.
  bool get comingSoon => !type.runsOnServer;

  /// "250 + 25 tokens", "Free".
  String get priceText {
    if (isFree) return 'Free';
    final noun = currency.noun;
    if (feeAmount == 0) return '${formatCount(entryFee)} $noun';
    return '${formatCount(entryFee)} + ${formatCount(feeAmount)} $noun';
  }

  /// "3 / 4", or "3 entered" without a limit.
  String get seatsText => maxPlayers == null ? '$currentPlayers entered' : '$currentPlayers / $maxPlayers';

  /// "Prize pool 5,000 tokens", or for a Sit & Go not yet started "Pool:
  /// 1,000 tokens when full" (the full pool, not a payout). Null = nothing
  /// to show (and always null once cancelled: the numbers are stale).
  String? get poolText {
    if (status.isCancelled) return null;
    if (prizePool > 0) return 'Prize pool ${formatCount(prizePool)} ${currency.noun}';
    if (isSitAndGo && maxPlayers != null && entryFee > 0) {
      return 'Pool: ${formatCount(entryFee * maxPlayers!)} ${currency.noun} when full';
    }
    return null;
  }

  Tournament copyWith({TournamentStatus? status, int? currentPlayers, int? prizePool, DateTime? startsAt}) => Tournament(
        id: id,
        gameId: gameId,
        modeId: modeId,
        name: name,
        type: type,
        status: status ?? this.status,
        maxPlayers: maxPlayers,
        currentPlayers: currentPlayers ?? this.currentPlayers,
        entryFee: entryFee,
        feeAmount: feeAmount,
        currencyWire: currencyWire,
        prizePool: prizePool ?? this.prizePool,
        startsAt: startsAt ?? this.startsAt,
        typeWire: typeWire,
        statusWire: statusWire,
      );
}

/// A page of the list (list shape 2: `{data, total, page, per_page,
/// total_pages}`), sorted by `starts_at`, oldest first.
@immutable
class TournamentPage {
  const TournamentPage({this.items = const [], this.total = 0, this.page = 1, this.perPage = 20, this.totalPages = 0});

  final List<Tournament> items;
  final int total;
  final int page;
  final int perPage;
  final int totalPages;

  factory TournamentPage.fromJson(Object? body) {
    // A plain array is accepted too (lenient).
    if (body is List) {
      final items = [for (final e in body) Tournament.fromJson(_obj(e))];
      return TournamentPage(items: items, total: items.length, totalPages: items.isEmpty ? 0 : 1);
    }
    final j = _obj(body);
    return TournamentPage(
      items: [for (final e in _arr(j['data'])) Tournament.fromJson(_obj(e))],
      total: parseAmount(j['total']),
      page: _intOrNull(j['page']) ?? 1,
      perPage: _intOrNull(j['per_page']) ?? 20,
      totalPages: parseAmount(j['total_pages']),
    );
  }
}

/// `POST /tournaments/{id}/register` → 201, the entry.
@immutable
class TournamentEntry {
  const TournamentEntry({required this.tournamentId, required this.userId, this.status, this.rebuys = 0, this.registeredAt});

  final String tournamentId;
  final String userId;
  final EntryStatus? status;
  final int rebuys;
  final DateTime? registeredAt;

  factory TournamentEntry.fromJson(Map<String, dynamic> j) => TournamentEntry(
        tournamentId: _str(j['tournament_id']) ?? '',
        userId: _str(j['user_id']) ?? '',
        status: EntryStatus.parse(j['status']),
        rebuys: parseAmount(j['rebuys']),
        registeredAt: _time(j['registered_at']),
      );
}

/// One seat at a table (`my-table` `players[]`, `rounds` `seats[]`).
@immutable
class TableSeat {
  const TableSeat({required this.playerId, required this.username, required this.seat, this.place, this.leaveReason});

  final String playerId;
  final String username;

  /// The seat number in the tournament draw (from 0). Only for ordering:
  /// the board seat and colour come from the game socket.
  final int seat;
  final int? place;
  final LeaveReason? leaveReason;

  factory TableSeat.fromJson(Map<String, dynamic> j) => TableSeat(
        playerId: _str(j['player_id']) ?? '',
        username: _str(j['username']) ?? '',
        seat: parseAmount(j['seat']),
        place: _intOrNull(j['place']),
        leaveReason: LeaveReason.parse(j['leave_reason']),
      );
}

/// The player's latest table (`my-table` `table`).
@immutable
class TournamentTable {
  const TournamentTable({
    required this.round,
    required this.tableNumber,
    required this.status,
    this.seat,
    this.roomCode,
    this.matchId,
    this.seatDeadlineAt,
    this.place,
    this.players = const [],
  });

  final int round;
  final int tableNumber;
  final TableStatus status;
  final int? seat;

  /// Send in `room.join`; null while [TableStatus.waiting].
  final String? roomCode;
  final String? matchId;

  /// Join before this; after it the game starts without the missing players.
  final DateTime? seatDeadlineAt;

  /// The player's place at this table once it ends.
  final int? place;
  final List<TableSeat> players;

  /// "Round 1, Table 1".
  String get label => 'Round $round, Table $tableNumber';

  /// Open now: go to the table.
  bool get isReady => status == TableStatus.playing && (roomCode?.isNotEmpty ?? false);

  factory TournamentTable.fromJson(Map<String, dynamic> j) => TournamentTable(
        round: parseAmount(j['round']),
        tableNumber: parseAmount(j['table_number']),
        status: TableStatus.parse(j['status']),
        seat: _intOrNull(j['seat']),
        roomCode: _str(j['room_code']),
        matchId: _str(j['match_id']),
        seatDeadlineAt: _time(j['seat_deadline_at']),
        place: _intOrNull(j['place']),
        players: [for (final p in _arr(j['players'])) TableSeat.fromJson(_obj(p))]..sort((a, b) => a.seat.compareTo(b.seat)),
      );
}

/// `GET /tournaments/{id}/my-table`: the player's entry and table.
@immutable
class MyTable {
  const MyTable({required this.tournamentStatus, this.entryStatus, this.table});

  final TournamentStatus tournamentStatus;

  /// Null = not entered.
  final EntryStatus? entryStatus;

  /// Null until seated; then the latest table.
  final TournamentTable? table;

  /// The player has (or had) an entry. `withdrawn` counts: after a cancel the
  /// entry reads withdrawn too.
  bool get entered => entryStatus != null;

  /// Holds a live entry (registered or playing).
  bool get inPlay => entryStatus == EntryStatus.registered || entryStatus == EntryStatus.active;

  factory MyTable.fromJson(Map<String, dynamic> j) => MyTable(
        tournamentStatus: TournamentStatus.parse(j['tournament_status']),
        entryStatus: EntryStatus.parse(j['entry_status']),
        table: j['table'] is Map ? TournamentTable.fromJson(_obj(j['table'])) : null,
      );
}

/// One row of `GET /tournaments/{id}/standings`, best place first.
@immutable
class Standing {
  const Standing({
    required this.playerId,
    required this.username,
    this.place,
    this.entryStatus,
    this.matchesWon = 0,
    this.matchesLost = 0,
    this.prizeAmount = 0,
    this.prizeCurrencyWire,
  });

  final String playerId;
  final String username;

  /// 1 = winner; null until decided. Ties share a place.
  final int? place;
  final EntryStatus? entryStatus;
  final int matchesWon;
  final int matchesLost;

  /// 0 = no prize.
  final int prizeAmount;
  final String? prizeCurrencyWire;

  bool get hasPrize => prizeAmount > 0;
  WalletCurrency get prizeCurrency => WalletCurrency.tryParse(prizeCurrencyWire) ?? WalletCurrency.token;

  /// "650 tokens".
  String get prizeText => hasPrize ? '${formatCount(prizeAmount)} ${prizeCurrency.noun}' : '';

  factory Standing.fromJson(Map<String, dynamic> j) => Standing(
        playerId: _str(j['player_id']) ?? '',
        username: _str(j['username']) ?? '',
        place: _intOrNull(j['place']),
        entryStatus: EntryStatus.parse(j['entry_status']),
        matchesWon: parseAmount(j['matches_won']),
        matchesLost: parseAmount(j['matches_lost']),
        prizeAmount: parseAmount(j['prize_amount']),
        prizeCurrencyWire: _str(j['prize_currency']),
      );

  static List<Standing> listFromJson(Object? body) => [for (final e in _arr(body)) Standing.fromJson(_obj(e))];
}

/// A table in `GET /tournaments/{id}/rounds`. `last_error` is diagnostics:
/// not kept.
@immutable
class RoundTable {
  const RoundTable({
    required this.id,
    required this.tableNumber,
    required this.status,
    this.matchId,
    this.openedAt,
    this.seatDeadlineAt,
    this.closedAt,
    this.seats = const [],
  });

  final String id;
  final int tableNumber;
  final TableStatus status;
  final String? matchId;
  final DateTime? openedAt;
  final DateTime? seatDeadlineAt;
  final DateTime? closedAt;
  final List<TableSeat> seats;

  factory RoundTable.fromJson(Map<String, dynamic> j) => RoundTable(
        id: _str(j['id']) ?? '',
        tableNumber: parseAmount(j['table_number']),
        status: TableStatus.parse(j['status']),
        matchId: _str(j['match_id']),
        openedAt: _time(j['opened_at']),
        seatDeadlineAt: _time(j['seat_deadline_at']),
        closedAt: _time(j['closed_at']),
        seats: [for (final s in _arr(j['seats'])) TableSeat.fromJson(_obj(s))],
      );
}

/// A round in `GET /tournaments/{id}/rounds` (`[]` before the first).
/// `status` is `active` or `completed` (kept raw). `seed` is ignored.
@immutable
class Round {
  const Round({required this.number, required this.status, this.startsAt, this.endsAt, this.tables = const []});

  final int number;
  final String status;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final List<RoundTable> tables;

  bool get isCompleted => status == 'completed';

  factory Round.fromJson(Map<String, dynamic> j) => Round(
        number: parseAmount(j['number']),
        status: _str(j['status']) ?? '',
        startsAt: _time(j['starts_at']),
        endsAt: _time(j['ends_at']),
        tables: [for (final t in _arr(j['tables'])) RoundTable.fromJson(_obj(t))],
      );

  static List<Round> listFromJson(Object? body) => [for (final e in _arr(body)) Round.fromJson(_obj(e))];
}

/// A knockout pairing (`GET /tournaments/{id}/bracket`; always `[]` today).
@immutable
class BracketNode {
  const BracketNode({
    required this.id,
    required this.tournamentId,
    required this.bracketType,
    required this.round,
    required this.position,
    required this.status,
    this.playerAId,
    this.playerBId,
    this.winnerId,
    this.matchId,
    this.parentBracketId,
  });

  final String id;
  final String tournamentId;

  /// `winners`, `losers`, `grand_final` (raw).
  final String bracketType;
  final int round;
  final int position;

  /// `pending`, `ready`, `active`, `completed`, `walkover` (raw).
  final String status;
  final String? playerAId;
  final String? playerBId;
  final String? winnerId;
  final String? matchId;
  final String? parentBracketId;

  factory BracketNode.fromJson(Map<String, dynamic> j) => BracketNode(
        id: _str(j['id']) ?? '',
        tournamentId: _str(j['tournament_id']) ?? '',
        bracketType: _str(j['bracket_type']) ?? '',
        round: parseAmount(j['round']),
        position: parseAmount(j['position']),
        status: _str(j['status']) ?? '',
        playerAId: _str(j['player_a_id']),
        playerBId: _str(j['player_b_id']),
        winnerId: _str(j['winner_id']),
        matchId: _str(j['match_id']),
        parentBracketId: _str(j['parent_bracket_id']),
      );

  static List<BracketNode> listFromJson(Object? body) => [for (final e in _arr(body)) BracketNode.fromJson(_obj(e))];
}

/// "1,000".
String formatCount(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
