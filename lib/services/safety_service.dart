import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/configs.dart';
import '../data/models/safety.dart';
import 'api_client.dart';
import 'app_exception.dart';
import 'app_prefs.dart';
import 'session.dart';

/// Player safety routes: report a player, my reports, the ban check and match
/// flags. Contract: docs/services/12-safety.md. Every method returns a typed
/// result or throws the shared [AppException]; [safetyErrorText] turns one
/// into the player's text.
///
/// Never log report bodies or descriptions (other players' words).
abstract class SafetyApi {
  /// `POST /moderation/report` — `201` + the report.
  Future<Report> report({
    required String reportedUserId,
    required ReportReason reason,
    String? description,
    ChatEvidence? chatMessage,
  });

  /// `GET /moderation/my-reports` — plain array, newest first, not paged.
  Future<List<Report>> myReports();

  /// `GET /moderation/bans/check`.
  Future<BanCheck> checkBan();

  /// `POST /matches/{id}/flag` with `{reason}` (5 to 500 characters).
  Future<MatchFlag> flagMatch(String matchId, String reason);
}

Map<String, dynamic> _map(dynamic body) => body is Map ? body.cast<String, dynamic>() : <String, dynamic>{};

List<Map<String, dynamic>> _list(dynamic body) {
  final raw = body is List ? body : (body is Map && body['data'] is List ? body['data'] as List : const []);
  return [for (final e in raw) if (e is Map) e.cast<String, dynamic>()];
}

class RemoteSafetyApi implements SafetyApi {
  const RemoteSafetyApi(this._api);
  final ApiClient _api;

  @override
  Future<Report> report({
    required String reportedUserId,
    required ReportReason reason,
    String? description,
    ChatEvidence? chatMessage,
  }) async {
    final text = description?.trim();
    return Report.fromJson(_map(await _api.post(ApiEndpoints.moderationReport, body: {
      'reported_user_id': reportedUserId,
      'reason': reason.wire,
      // An empty string is stored as "" (Known issues 14): leave it out.
      if (text != null && text.isNotEmpty) 'description': text,
      if (chatMessage != null) 'chat_message': chatMessage.toJson(),
    })));
  }

  @override
  Future<List<Report>> myReports() async =>
      [for (final j in _list(await _api.get(ApiEndpoints.moderationMyReports))) Report.fromJson(j)];

  @override
  Future<BanCheck> checkBan() async => BanCheck.fromJson(_map(await _api.get(ApiEndpoints.moderationBanCheck)));

  @override
  Future<MatchFlag> flagMatch(String matchId, String reason) async =>
      MatchFlag.fromJson(_map(await _api.post(ApiEndpoints.matchFlag(matchId), body: {'reason': reason.trim()})));
}

/// In-memory stand-in for the demo build and signed-out screens.
class DemoSafetyApi implements SafetyApi {
  DemoSafetyApi();
  final List<Report> _reports = [];
  int _next = 1;

  @override
  Future<Report> report({
    required String reportedUserId,
    required ReportReason reason,
    String? description,
    ChatEvidence? chatMessage,
  }) async {
    final r = Report(
      id: _next++,
      reportedUserId: reportedUserId,
      reason: reason,
      description: description,
      status: ReportStatus.pending,
      chatMessage: chatMessage,
      chatMessageRef: chatMessage?.messageId,
      createdAt: DateTime.now().toUtc(),
      reportedUsername: 'Player',
    );
    _reports.insert(0, r);
    return r;
  }

  @override
  Future<List<Report>> myReports() async => List.of(_reports);

  @override
  Future<BanCheck> checkBan() async => BanCheck.clear;

  @override
  Future<MatchFlag> flagMatch(String matchId, String reason) async =>
      MatchFlag(id: _next++, matchId: matchId, status: 'pending');
}

/// The real API while signed in; the demo one otherwise.
final safetyApiProvider = Provider<SafetyApi>((ref) {
  final remote = ref.watch(useRemoteAuthProvider);
  final signedIn = ref.watch(sessionProvider.select((u) => u != null));
  return remote && signedIn ? RemoteSafetyApi(ref.watch(apiClientProvider)) : DemoSafetyApi();
});

/// What the player was doing when an [AppException] came back.
enum SafetyOp { report, myReports, flagMatch, banCheck }

/// Player-facing text for a safety-route error (12-safety.md "Errors").
/// Decides on status + code, never on `message`.
String safetyErrorText(AppException e, SafetyOp op) {
  if (e.isOffline || e.kind == AppErrorKind.timeout) return e.message;
  switch (e.code) {
    case ApiErrorCode.rateLimited:
      return 'Too many attempts. Try again in a minute.';
    case ApiErrorCode.notFound when op == SafetyOp.report:
      return 'Player not found.';
    case ApiErrorCode.matchNotFound:
      return 'Match not found.';
    case ApiErrorCode.forbidden when op == SafetyOp.flagMatch:
      return 'You can only report matches you played.';
    case ApiErrorCode.validation:
      return switch (e.field) {
        'description' => 'Keep it under ${SafetyRules.descriptionMax} characters.',
        'reason' when op == SafetyOp.flagMatch => SafetyRules.flagReasonRule,
        _ => 'Something went wrong. Try again.',
      };
    case ApiErrorCode.badRequest || ApiErrorCode.forbidden:
      // App bugs (bad id, reason, chat line): nothing the player can fix.
      return 'Something went wrong. Try again.';
  }
  return e.message;
}

/// Client checks that match the server rules, so players never see a `400`.
abstract final class SafetyRules {
  static const descriptionMax = 2000;
  static const flagReasonMin = 5;
  static const flagReasonMax = 500;
  static const flagReasonRule = 'Write $flagReasonMin to $flagReasonMax characters.';

  /// One report per player per this long (the server has no guard).
  static const repeatWindow = Duration(hours: 24);

  static String? description(String v) =>
      v.length > descriptionMax ? 'Keep it under $descriptionMax characters.' : null;

  static String? flagReason(String v) {
    final n = v.trim().length;
    return n < flagReasonMin || n > flagReasonMax ? flagReasonRule : null;
  }

  /// "Match `id`" goes at the start of the description: a `match_id` field
  /// is silently dropped by the server (Known issues 2).
  static String withMatch(String? description, String? matchId) {
    final d = (description ?? '').trim();
    if (matchId == null || matchId.isEmpty) return d;
    return d.isEmpty ? 'Match $matchId' : 'Match $matchId. $d';
  }

  /// Quote a chat line that can't be attached (socket chat, or a gateway
  /// line that has left the room's history).
  static String withQuote(String? description, String quote) {
    final d = (description ?? '').trim();
    final q = 'Message: "${quote.trim()}"';
    final s = d.isEmpty ? q : '$d\n$q';
    return s.length > descriptionMax ? s.substring(0, descriptionMax) : s;
  }
}

/// What this account already reported, kept on the device per account
/// (the server accepts repeats: Known issues 1). Players for 24 hours,
/// chat lines and match flags for good.
class ReportedTracker {
  ReportedTracker(this._prefs, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;
  final AppPrefs _prefs;
  final DateTime Function() _now;

  /// account id → its record (players: id → epoch ms; lines; matches).
  final Map<String, _Reported> _cache = {};

  Future<_Reported> _load(String account) async {
    final hit = _cache[account];
    if (hit != null) return hit;
    final r = _Reported.decode(await _prefs.get(_key(account)));
    return _cache[account] ??= r;
  }

  static String _key(String account) => 'safety.reported.$account';

  Future<void> _save(String account, _Reported r) => _prefs.set(_key(account), r.encode());

  /// True when [playerId] was reported in the last 24 hours, or [messageId]
  /// was reported at all.
  Future<bool> alreadyReported(String account, {required String playerId, String? messageId}) async {
    final r = await _load(account);
    if (messageId != null && r.lines.contains(messageId)) return true;
    final at = r.players[playerId];
    if (at == null) return false;
    return _now().difference(DateTime.fromMillisecondsSinceEpoch(at)) < SafetyRules.repeatWindow;
  }

  Future<void> markReported(String account, {required String playerId, String? messageId}) async {
    final r = await _load(account);
    r.players[playerId] = _now().millisecondsSinceEpoch;
    if (messageId != null) r.lines.add(messageId);
    // Drop players older than the window so the record stays small.
    final cutoff = _now().subtract(SafetyRules.repeatWindow).millisecondsSinceEpoch;
    r.players.removeWhere((_, t) => t < cutoff);
    await _save(account, r);
  }

  Future<bool> flagged(String account, String matchId) async => (await _load(account)).matches.contains(matchId);

  Future<void> markFlagged(String account, String matchId) async {
    final r = await _load(account);
    r.matches.add(matchId);
    await _save(account, r);
  }
}

class _Reported {
  _Reported(this.players, this.lines, this.matches);
  final Map<String, int> players;
  final Set<String> lines;
  final Set<String> matches;

  static _Reported decode(String? raw) {
    try {
      final j = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      return _Reported(
        {for (final e in ((j['p'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()},
        {for (final s in (j['l'] as List?) ?? const []) '$s'},
        {for (final s in (j['m'] as List?) ?? const []) '$s'},
      );
    } on Object catch (_) {
      return _Reported({}, {}, {});
    }
  }

  String encode() => jsonEncode({'p': players, 'l': lines.toList(), 'm': matches.toList()});
}

final reportedTrackerProvider = Provider<ReportedTracker>((ref) => ReportedTracker(ref.watch(appPrefsProvider)));

/// The outcome of [SafetyController.reportPlayer].
enum ReportOutcome { sent, alreadyReported }

/// Report and flag actions with the device-side repeat guard. Screens call
/// these rather than [SafetyApi] directly.
class SafetyController {
  SafetyController(this._ref);
  final Ref _ref;

  String get _account => _ref.read(sessionProvider)?.id ?? 'demo';

  Future<bool> alreadyReported({required String playerId, String? messageId}) =>
      _ref.read(reportedTrackerProvider).alreadyReported(_account, playerId: playerId, messageId: messageId);

  /// Reports [playerId]. A gateway [chatMessage] is attached; when the server
  /// answers `400` because the line is gone or not theirs, the report is
  /// sent again without it, with the line quoted in the description (§1).
  /// [matchId] is written into the description. [quote] (an in-game socket
  /// line, which can't be attached) is quoted in the description.
  Future<ReportOutcome> reportPlayer({
    required String playerId,
    required ReportReason reason,
    String? description,
    ChatEvidence? chatMessage,
    String? matchId,
    String? quote,
  }) async {
    if (playerId == _ref.read(sessionProvider)?.id) {
      throw const AppException("You can't report yourself.", code: ApiErrorCode.badRequest, statusCode: 400);
    }
    final tracker = _ref.read(reportedTrackerProvider);
    final account = _account;
    if (await tracker.alreadyReported(account, playerId: playerId, messageId: chatMessage?.messageId)) {
      return ReportOutcome.alreadyReported;
    }
    var text = SafetyRules.withMatch(description, matchId);
    if (quote != null && quote.trim().isNotEmpty) text = SafetyRules.withQuote(text, quote);
    final api = _ref.read(safetyApiProvider);
    try {
      await api.report(reportedUserId: playerId, reason: reason, description: text, chatMessage: chatMessage);
    } on AppException catch (e) {
      if (chatMessage == null || e.statusCode != 400 || e.code != ApiErrorCode.badRequest) rethrow;
      // The line left the room's history (or isn't theirs): resend without it.
      final body = chatMessage.body;
      await api.report(
        reportedUserId: playerId,
        reason: reason,
        description: body == null || body.isEmpty ? text : SafetyRules.withQuote(text, body),
      );
    }
    await tracker.markReported(account, playerId: playerId, messageId: chatMessage?.messageId);
    _ref.invalidate(myReportsProvider);
    return ReportOutcome.sent;
  }

  Future<bool> matchFlagged(String matchId) => _ref.read(reportedTrackerProvider).flagged(_account, matchId);

  /// Flags a match this player played. Throws [AppException]; on `403`
  /// (not a participant) the caller hides the button.
  Future<MatchFlag> flagMatch(String matchId, String reason) async {
    final f = await _ref.read(safetyApiProvider).flagMatch(matchId, reason);
    await _ref.read(reportedTrackerProvider).markFlagged(_account, matchId);
    return f;
  }
}

final safetyControllerProvider = Provider<SafetyController>(SafetyController.new);

/// Settings > Safety > My reports. Re-read when the screen opens (no
/// "reviewed" notice exists) and on pull to refresh.
final myReportsProvider = FutureProvider.autoDispose<List<Report>>(
  (ref) => ref.watch(safetyApiProvider).myReports(),
);
