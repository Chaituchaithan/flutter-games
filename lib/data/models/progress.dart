import 'package:flutter/foundation.dart';

import '../../utils/amount.dart';

/// Progress and history (docs/services/08-progress-and-history.md): per-game
/// levels and XP, ratings, the one-game stats, leaderboards, match history
/// and one past match. Every parser is lenient: unknown fields are ignored,
/// most fields may be `null`, and numbers may come as `1016.0` or `1016`.

int? _i(Object? v) => v is num ? v.toInt() : (v is String ? num.tryParse(v)?.toInt() : null);
num? _n(Object? v) => v is num ? v : (v is String ? num.tryParse(v) : null);
String? _s(Object? v) => v == null ? null : (v is String ? v : v.toString());
DateTime? _t(Object? v) => v is String ? DateTime.tryParse(v) : null;
bool _b(Object? v) => v == true;
Map<String, dynamic>? _m(Object? v) => v is Map ? v.cast<String, dynamic>() : null;
List<Object?> _l(Object? v) => v is List ? v : const [];

// ── XP rules ──────────────────────────────────────────────────────────────

/// XP to go from [level] to `level + 1`: `100 × level` (Known issues 1).
int xpForNextLevel(int level) => 100 * (level < 1 ? 1 : level);

/// XP earned per finished match, by the player's `result`. Null for an
/// unknown result (or none).
int? xpForResult(String? result) => switch (result) {
      'win' => 100,
      'draw' => 50,
      'loss' => 25,
      'forfeit' => 10,
      _ => null,
    };

/// Lifetime XP at [level] with [xp] toward the next one (level 1, 0 XP = 0).
int lifetimeXp(int level, int xp) {
  var total = xp;
  for (var l = 1; l < level; l++) {
    total += xpForNextLevel(l);
  }
  return total;
}

// ── 1. Levels ─────────────────────────────────────────────────────────────

@immutable
class GameLevel {
  const GameLevel({required this.gameId, this.level = 1, this.xp = 0, this.userId, this.updatedAt, this.expToNextLevel});

  /// A game the player has never finished: level 1, empty bar.
  const GameLevel.none(this.gameId)
      : level = 1,
        xp = 0,
        userId = null,
        updatedAt = null,
        expToNextLevel = null;

  final String? userId;
  final int gameId;
  final int level;

  /// XP toward the next level (resets on each level-up), not the lifetime total.
  final int xp;
  final DateTime? updatedAt;

  /// Sent by a future server (`exp_to_next_level`); preferred when present.
  final int? expToNextLevel;

  /// The XP bar's full width.
  int get xpNeeded => (expToNextLevel != null && expToNextLevel! > 0) ? expToNextLevel! : xpForNextLevel(level);

  /// The XP bar's fill, 0..1.
  double get fraction => xpNeeded <= 0 ? 0 : (xp / xpNeeded).clamp(0.0, 1.0);

  int get lifetime => lifetimeXp(level, xp);

  factory GameLevel.fromJson(Map<String, dynamic> j) => GameLevel(
        userId: _s(j['user_id']),
        gameId: _i(j['game_id']) ?? 0,
        level: (_i(j['level']) ?? 1).clamp(1, 1 << 30),
        xp: (_i(j['xp']) ?? 0).clamp(0, 1 << 30),
        updatedAt: _t(j['updated_at']),
        expToNextLevel: _i(j['exp_to_next_level']),
      );
}

// ── 2. Ratings ────────────────────────────────────────────────────────────

@immutable
class GameRating {
  const GameRating({required this.gameId, required this.rating, this.wins = 0, this.losses = 0, this.draws = 0, this.userId, this.updatedAt});

  final String? userId;
  final int gameId;

  /// The MMR as sent (`1016.0`); show [whole].
  final num rating;

  /// Every mode, not only ranked. Forfeits are in none of them.
  final int wins;
  final int losses;
  final int draws;
  final DateTime? updatedAt;

  int get whole => rating.round();

  factory GameRating.fromJson(Map<String, dynamic> j) => GameRating(
        userId: _s(j['user_id']),
        gameId: _i(j['game_id']) ?? 0,
        rating: _n(j['rating']) ?? 1000,
        wins: _i(j['wins']) ?? 0,
        losses: _i(j['losses']) ?? 0,
        draws: _i(j['draws']) ?? 0,
        updatedAt: _t(j['updated_at']),
      );
}

// ── 3. One game ───────────────────────────────────────────────────────────

@immutable
class GameMmr {
  const GameMmr({required this.gameId, required this.mmr, required this.peakMmr, this.gamesPlayed = 0, this.userId, this.updatedAt});

  final String? userId;
  final int gameId;
  final int mmr;
  final int peakMmr;

  /// Ranked matches only.
  final int gamesPlayed;
  final DateTime? updatedAt;

  factory GameMmr.fromJson(Map<String, dynamic> j) {
    final mmr = _n(j['mmr'])?.round() ?? 1000;
    return GameMmr(
      userId: _s(j['user_id']),
      gameId: _i(j['game_id']) ?? 0,
      mmr: mmr,
      peakMmr: _n(j['peak_mmr'])?.round() ?? mmr,
      gamesPlayed: _i(j['games_played']) ?? 0,
      updatedAt: _t(j['updated_at']),
    );
  }
}

/// `GET /progression/{game_id}/stats`: each part may be `null` on its own.
@immutable
class GameStats {
  const GameStats({this.level, this.rating, this.mmr});

  /// Null before the first finished match.
  final GameLevel? level;

  /// Null (with [mmr]) before the first ranked match.
  final GameRating? rating;
  final GameMmr? mmr;

  bool get ranked => rating != null;

  factory GameStats.fromJson(Map<String, dynamic> j) {
    final l = _m(j['level']), r = _m(j['rating']), m = _m(j['mmr']);
    return GameStats(
      level: l == null ? null : GameLevel.fromJson(l),
      rating: r == null ? null : GameRating.fromJson(r),
      mmr: m == null ? null : GameMmr.fromJson(m),
    );
  }
}

// ── 4. Leaderboards ───────────────────────────────────────────────────────

/// A leaderboard's metric (the path segment).
enum LeaderboardMetric {
  wins('wins', 'Wins'),
  rating('rating', 'Rating'),
  tokensEarned('tokens_earned', 'Tokens');

  const LeaderboardMetric(this.wire, this.label);
  final String wire;
  final String label;

  /// "You" row text when the player isn't on the board.
  String get offBoardText => switch (this) {
        LeaderboardMetric.rating => 'Play a ranked match to get on the board',
        LeaderboardMetric.tokensEarned => 'Win tokens in a staked match to get on the board',
        LeaderboardMetric.wins => 'Play a match to get on the board',
      };
}

@immutable
class LeaderboardEntry {
  const LeaderboardEntry({required this.rank, required this.userId, required this.score, this.username, this.avatarUrl});

  /// 1 = best, counted over the whole board.
  final int rank;
  final String userId;
  final num score;

  /// Null when the account is gone: show [name].
  final String? username;
  final String? avatarUrl;

  String get name => (username == null || username!.trim().isEmpty) ? 'Player' : username!;
  int get whole => score.round();

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
        rank: _i(j['rank']) ?? 0,
        userId: _s(j['user_id']) ?? '',
        score: _n(j['score']) ?? 0,
        username: _s(j['username']),
        avatarUrl: _s(j['avatar_url']),
      );
}

/// `GET /leaderboards/{game_id}/{metric}/my-rank`: both null = not on it.
@immutable
class MyRank {
  const MyRank({this.rank, this.score});
  final int? rank;
  final num? score;

  bool get onBoard => rank != null;

  factory MyRank.fromJson(Map<String, dynamic> j) => MyRank(rank: _i(j['rank']), score: _n(j['score']));
}

// ── 5. History ────────────────────────────────────────────────────────────

/// The player's own bet in a live-round game (Crash and similar).
@immutable
class RoundBet {
  const RoundBet({required this.betIndex, required this.amount, this.autoCashoutAt, this.cashoutMultiplier, this.payoutAmount = 0, this.outcome});
  final int betIndex;
  final int amount;
  final num? autoCashoutAt;

  /// Null when it did not cash out.
  final num? cashoutMultiplier;
  final int payoutAmount;

  /// `won` or `lost`.
  final String? outcome;

  bool get won => outcome == 'won';

  factory RoundBet.fromJson(Map<String, dynamic> j) => RoundBet(
        betIndex: _i(j['bet_index']) ?? 0,
        amount: parseAmount(j['amount']),
        autoCashoutAt: _n(j['auto_cashout_at']),
        cashoutMultiplier: _n(j['cashout_multiplier']),
        payoutAmount: parseAmount(j['payout_amount']),
        outcome: _s(j['outcome']),
      );
}

/// How a match row reads: its result chip.
enum MatchChip { won, lost, draw, forfeit, playing, cancelled, finished }

extension MatchChipText on MatchChip {
  String get label => switch (this) {
        MatchChip.won => 'Won',
        MatchChip.lost => 'Lost',
        MatchChip.draw => 'Draw',
        MatchChip.forfeit => 'Forfeit',
        MatchChip.playing => 'Playing',
        MatchChip.cancelled => 'Cancelled',
        MatchChip.finished => 'Finished',
      };
}

/// The chip for a `status` and the player's `result`. Unknown values read
/// "Finished" and never fail.
MatchChip matchChip(String? status, String? result) {
  switch (result) {
    case 'win':
      return MatchChip.won;
    case 'loss':
      return MatchChip.lost;
    case 'draw':
      return MatchChip.draw;
    case 'forfeit':
      return MatchChip.forfeit;
  }
  return switch (status) {
    'in_progress' || 'waiting' => MatchChip.playing,
    'cancelled' || 'abandoned' => MatchChip.cancelled,
    _ => MatchChip.finished,
  };
}

/// One row of `GET /matches/my-history`.
@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.matchId,
    this.gameId,
    this.modeId,
    this.status = '',
    this.result,
    this.stakeAmount = 0,
    this.payoutAmount = 0,
    this.createdAt,
    this.endedAt,
    this.gameCode,
    this.gameName,
    this.modeCode,
    this.modeName,
    this.bets = const [],
  });

  final String matchId;
  final int? gameId;
  final int? modeId;

  /// `waiting`, `in_progress`, `completed`, `abandoned`, `cancelled` or new values.
  final String status;

  /// `win`, `loss`, `draw`, `forfeit` or null (running, cancelled, abandoned).
  final String? result;
  final int stakeAmount;
  final int payoutAmount;
  final DateTime? createdAt;
  final DateTime? endedAt;
  final String? gameCode;
  final String? gameName;
  final String? modeCode;
  final String? modeName;
  final List<RoundBet> bets;

  MatchChip get chip => matchChip(status, result);
  bool get inProgress => status == 'in_progress' || status == 'waiting';
  bool get staked => stakeAmount > 0 || payoutAmount > 0;

  /// `payout - stake` (shown for a staked match only). No currency: the row has none.
  int get net => payoutAmount - stakeAmount;

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        matchId: _s(j['match_id']) ?? '',
        gameId: _i(j['game_id']),
        modeId: _i(j['mode_id']),
        status: _s(j['status']) ?? '',
        result: _s(j['result']),
        stakeAmount: parseAmount(j['stake_amount']),
        payoutAmount: parseAmount(j['payout_amount']),
        createdAt: _t(j['created_at']),
        endedAt: _t(j['ended_at']),
        gameCode: _s(j['game_code']),
        gameName: _s(j['game_name']),
        modeCode: _s(j['mode_code']),
        modeName: _s(j['mode_name']),
        bets: [
          for (final b in _l(j['bets']))
            if (b is Map) RoundBet.fromJson(b.cast<String, dynamic>()),
        ],
      );
}

/// A page of history (list shape 2).
@immutable
class HistoryPage {
  const HistoryPage({this.data = const [], this.total = 0, this.page = 1, this.perPage = 20, this.totalPages = 0});
  final List<HistoryEntry> data;
  final int total;
  final int page;
  final int perPage;
  final int totalPages;

  bool get hasMore => page < totalPages;

  factory HistoryPage.fromJson(Map<String, dynamic> j) => HistoryPage(
        data: [
          for (final e in _l(j['data']))
            if (e is Map) HistoryEntry.fromJson(e.cast<String, dynamic>()),
        ],
        total: _i(j['total']) ?? 0,
        page: _i(j['page']) ?? 1,
        perPage: _i(j['per_page']) ?? 20,
        totalPages: _i(j['total_pages']) ?? 0,
      );
}

// ── 6. One match ──────────────────────────────────────────────────────────

@immutable
class MatchParticipant {
  const MatchParticipant({
    required this.id,
    this.userId,
    this.isBot = false,
    this.seat,
    this.stakeAmount = 0,
    this.payoutAmount = 0,
    this.result,
    this.ratingBefore,
    this.ratingAfter,
    this.finalRank,
    this.score,
    this.customStats,
  });

  /// The seat row id: a list key only.
  final int id;

  /// Null for a bot seat.
  final String? userId;
  final bool isBot;
  final int? seat;
  final int stakeAmount;
  final int payoutAmount;
  final String? result;
  final num? ratingBefore;
  final num? ratingAfter;
  final int? finalRank;
  final num? score;

  /// Game-specific; show the known keys, ignore the rest.
  final Map<String, dynamic>? customStats;

  /// `after - before`; null until settled. 0 in an unranked match.
  int? get ratingChange =>
      (ratingBefore == null || ratingAfter == null) ? null : (ratingAfter! - ratingBefore!).round();

  MatchChip get chip => matchChip(null, result);

  factory MatchParticipant.fromJson(Map<String, dynamic> j) => MatchParticipant(
        id: _i(j['id']) ?? 0,
        userId: _s(j['user_id']),
        isBot: _b(j['is_bot']),
        seat: _i(j['seat']),
        stakeAmount: parseAmount(j['stake_amount']),
        payoutAmount: parseAmount(j['payout_amount']),
        result: _s(j['result']),
        ratingBefore: _n(j['rating_before']),
        ratingAfter: _n(j['rating_after']),
        finalRank: _i(j['final_rank']),
        score: _n(j['score']),
        customStats: _m(j['custom_stats']),
      );
}

@immutable
class MatchDetail {
  const MatchDetail({
    required this.id,
    this.gameId,
    this.modeId,
    this.status = '',
    this.serverSeed,
    this.serverSeedHash,
    this.createdAt,
    this.startedAt,
    this.endedAt,
    this.participants = const [],
  });

  final String id;
  final int? gameId;
  final int? modeId;
  final String status;
  final String? serverSeed;
  final String? serverSeedHash;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// Every seat, in seat order.
  final List<MatchParticipant> participants;

  bool get inProgress => status == 'in_progress' || status == 'waiting';

  /// Seats in place order (unplaced last, then by seat).
  List<MatchParticipant> get byPlace => [...participants]..sort((a, b) {
      final ra = a.finalRank ?? 1 << 20, rb = b.finalRank ?? 1 << 20;
      if (ra != rb) return ra.compareTo(rb);
      return (a.seat ?? 0).compareTo(b.seat ?? 0);
    });

  /// `ended_at - started_at`, or null.
  Duration? get length => (startedAt == null || endedAt == null) ? null : endedAt!.difference(startedAt!);

  /// A ranked match: some seat's rating moved.
  bool get ratingMoved => participants.any((p) => (p.ratingChange ?? 0) != 0);

  MatchParticipant? seatOf(String? userId) =>
      userId == null ? null : participants.where((p) => p.userId == userId).firstOrNull;

  factory MatchDetail.fromJson(Map<String, dynamic> j) => MatchDetail(
        id: _s(j['id']) ?? '',
        gameId: _i(j['game_id']),
        modeId: _i(j['mode_id']),
        status: _s(j['status']) ?? '',
        serverSeed: _s(j['server_seed']),
        serverSeedHash: _s(j['server_seed_hash']),
        createdAt: _t(j['created_at']),
        startedAt: _t(j['started_at']),
        endedAt: _t(j['ended_at']),
        participants: [
          for (final p in _l(j['participants']))
            if (p is Map) MatchParticipant.fromJson(p.cast<String, dynamic>()),
        ],
      );
}

/// The Ludo `custom_stats` lines worth showing, in order (known keys only).
List<(String, String)> ludoStatLines(Map<String, dynamic>? s) {
  if (s == null) return const [];
  final out = <(String, String)>[];
  void n(String key, String label) {
    final v = s[key];
    if (v is num) out.add((label, '${v.round()}'));
  }

  n('captures', 'Captures');
  n('pawns_lost', 'Pawns lost');
  n('sixes', 'Sixes');
  n('total_turns', 'Turns');
  if (s['all_pawns_homed'] == true) out.add(('All pawns home', 'Yes'));
  return out;
}

// ── After a game ──────────────────────────────────────────────────────────

/// What a finished match changed for one game: from the held values before
/// and one re-read after.
@immutable
class ProgressDelta {
  const ProgressDelta({required this.gameId, this.before, required this.after, this.ratingBefore, this.ratingAfter, this.result});

  final int gameId;

  /// Null = no row before (level 1, 0 XP).
  final GameLevel? before;
  final GameStats after;
  final num? ratingBefore;
  final num? ratingAfter;

  /// The player's result when known (picks the XP from the table).
  final String? result;

  GameLevel get _before => before ?? GameLevel.none(gameId);
  GameLevel? get _after => after.level;

  /// "+N XP": from the XP table for a known result; otherwise the change in
  /// lifetime XP. Null when nothing changed yet.
  int? get xpGained {
    final table = xpForResult(result);
    if (table != null) return table;
    final a = _after;
    if (a == null) return null;
    final d = a.lifetime - _before.lifetime;
    return d > 0 ? d : null;
  }

  bool get leveledUp => _after != null && _after!.level > _before.level;
  int? get newLevel => _after?.level;

  /// Ranked: the rating change; null when unranked, unchanged, or the value
  /// before is unknown ([ratingBefore] = 1000 for a first ranked match).
  int? get ratingChange {
    final a = ratingAfter ?? after.rating?.rating;
    final b = ratingBefore;
    if (a == null || b == null) return null;
    final d = (a - b).round();
    return d == 0 ? null : d;
  }

  bool get changed => xpGained != null || ratingChange != null;

  /// "+100 XP · +16 rating".
  String get summary => [
        if (xpGained != null) '+$xpGained XP',
        if (ratingChange != null) '${ratingChange! > 0 ? '+' : ''}$ratingChange rating',
      ].join('  ·  ');
}
