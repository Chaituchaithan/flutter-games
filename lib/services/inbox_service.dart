import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/endpoints/api_endpoints.dart';
import '../configs/feature_flags.dart';
import '../data/models/inbox_message.dart';
import 'api_client.dart';
import 'app_exception.dart';
import 'session.dart';

/// Inbox, notifications and notification preferences
/// (docs/services/10-inbox-and-notifications.md). Every method returns a
/// typed result or throws [AppException]; [inboxIssue] / [preferencesErrorText]
/// turn one into player text.
///
/// Never log claim replies or wallet amounts.
abstract class InboxApi {
  /// `GET /inbox?page=&per_page=` — newest first, expired messages left out.
  Future<InboxPage<InboxMessage>> inbox({int page = 1, int perPage = 20});

  /// `GET /inbox/{id}` — also returns an expired message.
  Future<InboxMessage> message(int id);

  /// `POST /inbox/{id}/read` — `{"status":"read"}`.
  Future<void> markRead(int id);

  /// `POST /inbox/{id}/claim-reward` — no body, no Idempotency-Key.
  Future<ClaimResult> claim(int id);

  /// `DELETE /inbox/{id}` — an unclaimed reward is lost for good.
  Future<void> delete(int id);

  /// `GET /notifications?page=&per_page=` — newest first.
  Future<InboxPage<PlayerNotification>> notifications({int page = 1, int perPage = 20});

  /// `GET /notifications/preferences`.
  Future<NotificationPreferences> preferences();

  /// `PATCH /notifications/preferences` with only the changed fields
  /// (`null` clears quiet hours / time zone). Unknown keys are dropped
  /// before sending: the server refuses them.
  Future<NotificationPreferences> updatePreferences(Map<String, Object?> changes);
}

Map<String, dynamic> _obj(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};

/// Only the fields the server accepts.
Map<String, Object?> cleanPreferencePatch(Map<String, Object?> changes) =>
    {for (final e in changes.entries) if (NotificationPreferences.patchFields.contains(e.key)) e.key: e.value};

/// The live gateway.
class RemoteInboxApi implements InboxApi {
  RemoteInboxApi(this._api, {this.rateLimitWait = const Duration(seconds: 2)});
  final ApiClient _api;

  /// `429 RATE_LIMITED`: wait this long and retry once (Errors table).
  final Duration rateLimitWait;

  Future<T> _once<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AppException catch (e) {
      if (e.statusCode != 429 || e.code != ApiErrorCode.rateLimited) rethrow;
      await Future<void>.delayed(rateLimitWait);
      return run();
    }
  }

  static int _per(int n) => n.clamp(1, 100);

  @override
  Future<InboxPage<InboxMessage>> inbox({int page = 1, int perPage = 20}) => _once(() async => InboxPage.fromJson(
        await _api.get(ApiEndpoints.inbox, query: {'page': page < 1 ? 1 : page, 'per_page': _per(perPage)}),
        InboxMessage.fromJson,
      ));

  @override
  Future<InboxMessage> message(int id) =>
      _once(() async => InboxMessage.fromJson(_obj(await _api.get(ApiEndpoints.inboxMessage(id)))));

  @override
  Future<void> markRead(int id) => _once(() => _api.post(ApiEndpoints.inboxRead(id)));

  @override
  Future<ClaimResult> claim(int id) =>
      _once(() async => ClaimResult.fromJson(_obj(await _api.post(ApiEndpoints.inboxClaim(id)))));

  @override
  Future<void> delete(int id) => _once(() => _api.delete(ApiEndpoints.inboxMessage(id)));

  @override
  Future<InboxPage<PlayerNotification>> notifications({int page = 1, int perPage = 20}) =>
      _once(() async => InboxPage.fromJson(
            await _api.get(ApiEndpoints.notifications, query: {'page': page < 1 ? 1 : page, 'per_page': _per(perPage)}),
            PlayerNotification.fromJson,
          ));

  @override
  Future<NotificationPreferences> preferences() =>
      _once(() async => NotificationPreferences.fromJson(_obj(await _api.get(ApiEndpoints.notificationPreferences))));

  @override
  Future<NotificationPreferences> updatePreferences(Map<String, Object?> changes) => _once(() async =>
      NotificationPreferences.fromJson(
          _obj(await _api.patch(ApiEndpoints.notificationPreferences, body: cleanPreferencePatch(changes)))));
}

/// One demo inbox for the whole app run (so claims and reads stick).
final _demoInboxApiProvider = Provider<DemoInboxApi>((ref) => DemoInboxApi());

/// Live when signed in against the real API; the demo otherwise.
final inboxApiProvider = Provider<InboxApi>((ref) {
  final live = ref.watch(useRemoteAuthProvider) && ref.watch(sessionProvider.select((u) => u != null));
  if (!live) return ref.watch(_demoInboxApiProvider);
  return RemoteInboxApi(ref.watch(apiClientProvider));
});

/// True when [inboxApiProvider] is the live gateway (the wallet is then
/// re-read after a claim; the demo applies the credit itself).
final inboxIsLiveProvider = Provider<bool>((ref) => ref.watch(inboxApiProvider) is! DemoInboxApi);

// ── Errors → what the app does ───────────────────────────────────────────

enum InboxOp { list, open, read, claim, delete, notifications }

enum InboxIssueKind {
  /// `409` on claim: treat as success; re-read the message and the wallet.
  alreadyClaimed,

  /// The message is gone (or another player's): remove it from the list.
  gone,

  /// Delete of a missing message: done, remove it.
  done,

  /// The message has no reward: hide the Claim button.
  noReward,

  /// The reward expired: show the message as expired.
  expired,

  /// Show [InboxIssue.text]; keep the screen (and the button).
  message,

  /// The session ended (the client signs out).
  signIn,
}

@immutable
class InboxIssue {
  const InboxIssue(this.kind, [this.text]);
  final InboxIssueKind kind;

  /// Player text; null = nothing to show.
  final String? text;

  @override
  String toString() => 'InboxIssue($kind, $text)';
}

const inboxGenericText = 'Something went wrong. Try again.';
const inboxGoneText = 'This message is no longer available.';
const inboxAlreadyClaimedText = 'Already claimed.';
const inboxExpiredText = 'This reward has expired.';
const inboxPowerUpText = "This reward can't be claimed yet. Try again later.";
const inboxRateLimitedText = 'Too many requests. Wait a moment and try again.';

InboxIssue? _common(AppException e) {
  if (e.isOffline || e.kind == AppErrorKind.timeout) return InboxIssue(InboxIssueKind.message, e.message);
  if (e.statusCode == 401) return InboxIssue(InboxIssueKind.signIn, e.message);
  if (e.isKillSwitch) return InboxIssue(InboxIssueKind.message, e.message);
  if (e.statusCode == 429) return const InboxIssue(InboxIssueKind.message, inboxRateLimitedText);
  if ((e.statusCode ?? 0) >= 500 && e.code != ApiErrorCode.unavailable) {
    return const InboxIssue(InboxIssueKind.message, inboxGenericText);
  }
  return null;
}

/// What a failed inbox call means. [hasReward]: the item held has tokens
/// or gold (tells the claim's two `404`s apart).
InboxIssue inboxIssue(AppException e, InboxOp op, {bool hasReward = true}) {
  final common = _common(e);
  if (common != null) return common;
  final s = e.statusCode;
  switch (op) {
    case InboxOp.claim:
      if (s == 409) return const InboxIssue(InboxIssueKind.alreadyClaimed, inboxAlreadyClaimedText);
      if (s == 404) {
        return hasReward ? const InboxIssue(InboxIssueKind.gone, inboxGoneText) : const InboxIssue(InboxIssueKind.noReward);
      }
      if (s == 400 && e.code == ApiErrorCode.badRequest) return const InboxIssue(InboxIssueKind.expired, inboxExpiredText);
      if (s == 503 && e.code == ApiErrorCode.unavailable) return const InboxIssue(InboxIssueKind.message, inboxPowerUpText);
    case InboxOp.delete:
      if (s == 404) return const InboxIssue(InboxIssueKind.done);
    case InboxOp.read:
      if (s == 404) return const InboxIssue(InboxIssueKind.gone);
    case InboxOp.open:
      if (s == 404 || s == 400) return const InboxIssue(InboxIssueKind.gone, inboxGoneText);
    case InboxOp.list:
    case InboxOp.notifications:
      break;
  }
  return const InboxIssue(InboxIssueKind.message, inboxGenericText);
}

/// Player text for a failed preferences PATCH (§3b): rolled back by the caller.
String preferencesErrorText(AppException e) {
  final common = _common(e);
  if (common != null) return common.text ?? inboxGenericText;
  if (e.code == ApiErrorCode.validation && e.field == 'timezone') return 'Choose a valid time zone.';
  if (e.code == ApiErrorCode.badRequest) return 'Choose a valid time.';
  return inboxGenericText;
}

// ── Demo ─────────────────────────────────────────────────────────────────

/// Signed-out demo: in-memory, shaped like the gateway's replies (the "from
/// the code" samples in the hand-off file).
class DemoInboxApi implements InboxApi {
  DemoInboxApi({DateTime? now}) {
    final t = (now ?? DateTime.now()).toUtc();
    String iso(Duration d) => t.subtract(d).toIso8601String();
    _messages = [
      {'id': 42, 'title': 'Sorry for the outage', 'body': 'Here is a little something.\nThanks for playing!', 'attached_token': 500, 'attached_gold': 0, 'expires_at': t.add(const Duration(days: 3)).toIso8601String(), 'created_at': iso(const Duration(minutes: 20))},
      {'id': 41, 'title': 'Weekend gift', 'body': 'A small gift of gold for the weekend.', 'attached_token': 0, 'attached_gold': 50, 'expires_at': null, 'created_at': iso(const Duration(hours: 5))},
      {'id': 40, 'title': 'Welcome to Royale Arcade', 'body': 'Play any game, climb the leaderboards and collect rewards every day.', 'attached_token': 0, 'attached_gold': 0, 'expires_at': null, 'created_at': iso(const Duration(days: 1)), 'read_at': iso(const Duration(hours: 20))},
    ];
    _notifications = [
      {'id': '5b0e6a64-4f9e-4a39-8d0e-2f1f7b3c9a11', 'title': 'Weekend tournament', 'body': 'Ludo Sit & Go entries are half price until Sunday.', 'target_type': 'all', 'sent_at': iso(const Duration(hours: 1))},
      {'id': '0c4d2f8e-7a61-4b1a-9f3c-6e5d4a3b2c10', 'title': 'Account check', 'body': 'Your support ticket was answered.', 'target_type': 'user', 'sent_at': iso(const Duration(days: 1))},
    ];
  }

  late final List<Map<String, Object?>> _messages;
  late final List<Map<String, Object?>> _notifications;
  NotificationPreferences _prefs = const NotificationPreferences(userId: 'demo');

  static AppException _err(int status, String code, String detail) => AppException(
      ApiClient.messageFor(kind: status == 404 ? AppErrorKind.notFound : AppErrorKind.unknown, status: status, code: code),
      kind: status == 404 ? AppErrorKind.notFound : AppErrorKind.unknown,
      statusCode: status,
      code: code,
      detail: detail);

  Map<String, Object?> _find(int id) {
    final m = _messages.where((m) => m['id'] == id).firstOrNull;
    if (m == null) throw _err(404, ApiErrorCode.notFound, 'not found: inbox message not found');
    return m;
  }

  static InboxPage<T> _page<T>(List<T> all, int page, int perPage) {
    final per = perPage.clamp(1, 100);
    final start = (page - 1) * per;
    return InboxPage(
      items: start >= all.length ? <T>[] : all.sublist(start, (start + per).clamp(0, all.length)),
      total: all.length,
      page: page,
      perPage: per,
      totalPages: (all.length + per - 1) ~/ per,
    );
  }

  @override
  Future<InboxPage<InboxMessage>> inbox({int page = 1, int perPage = 20}) async {
    final now = DateTime.now();
    final live = [
      for (final m in _messages) InboxMessage.fromJson(m.cast<String, dynamic>()),
    ].where((m) => !m.isExpired(now)).toList();
    return _page(live, page, perPage);
  }

  @override
  Future<InboxMessage> message(int id) async => InboxMessage.fromJson(_find(id).cast<String, dynamic>());

  @override
  Future<void> markRead(int id) async {
    final m = _find(id);
    m['read_at'] ??= DateTime.now().toUtc().toIso8601String();
  }

  @override
  Future<ClaimResult> claim(int id) async {
    final raw = _find(id);
    final m = InboxMessage.fromJson(raw.cast<String, dynamic>());
    if (!m.hasReward) throw _err(404, ApiErrorCode.notFound, 'not found: no claimable reward on this message');
    if (m.claimedAt != null) throw _err(409, ApiErrorCode.conflict, 'conflict: reward already claimed');
    if (m.isExpired()) throw _err(400, ApiErrorCode.badRequest, 'bad request: inbox message has expired');
    final now = DateTime.now().toUtc().toIso8601String();
    raw['claimed_at'] = now;
    raw['read_at'] ??= now;
    return ClaimResult(tokenCredited: m.attachedToken, goldCredited: m.attachedGold);
  }

  @override
  Future<void> delete(int id) async {
    _find(id);
    _messages.removeWhere((m) => m['id'] == id);
  }

  @override
  Future<InboxPage<PlayerNotification>> notifications({int page = 1, int perPage = 20}) async =>
      _page([for (final n in _notifications) PlayerNotification.fromJson(n.cast<String, dynamic>())], page, perPage);

  @override
  Future<NotificationPreferences> preferences() async => _prefs;

  @override
  Future<NotificationPreferences> updatePreferences(Map<String, Object?> changes) async {
    final tz = changes['timezone'];
    if (tz is String && (tz.isEmpty || tz.length > 40 || !tz.contains('/') && tz != 'UTC')) {
      throw AppException('Check the highlighted field and try again.',
          statusCode: 400, code: ApiErrorCode.validation, field: 'timezone');
    }
    for (final k in ['quiet_hours_start', 'quiet_hours_end']) {
      final v = changes[k];
      if (v is String && parseQuietTime(v) == null) {
        throw const AppException('Something went wrong. Try again.', statusCode: 400, code: ApiErrorCode.badRequest);
      }
    }
    final clean = {
      for (final e in cleanPreferencePatch(changes).entries)
        e.key: e.value is String && e.key.startsWith('quiet_hours_')
            ? () {
                final (h, m) = parseQuietTime(e.value as String)!;
                return quietTimeWire(h, m);
              }()
            : e.value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    return _prefs = _prefs.merge(clean);
  }
}
