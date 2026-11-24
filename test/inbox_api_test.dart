// The inbox and notifications contract (docs/services/10-inbox-and-notifications.md):
// model parsing for every sample (real and "from the code"), each route's
// request and error mapping, claim → wallet re-read, 409 = "already
// claimed", delete confirmation, preferences PATCH sends only what changed
// (null clears quiet hours), the badge counts, and the push switch. Dio runs
// against a stand-in adapter that answers like the gateway.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/account.dart';
import 'package:snakeladder/data/models/inbox_message.dart';
import 'package:snakeladder/data/repositories/inbox_repository.dart';
import 'package:snakeladder/screens/settings/notification_settings_screen.dart';
import 'package:snakeladder/screens/social/inbox_message_screen.dart';
import 'package:snakeladder/screens/social/inbox_screen.dart';
import 'package:snakeladder/services/account_store.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/app_prefs.dart';
import 'package:snakeladder/services/inbox_service.dart';
import 'package:snakeladder/services/push_service.dart';
import 'package:snakeladder/services/wallet_api.dart';
import 'package:snakeladder/services/wallet_store.dart';

class _Req {
  _Req(this.method, this.path, this.query, this.body);
  final String method;
  final String path;
  final Map<String, dynamic> query;
  final dynamic body;
  @override
  String toString() => '$method $path';
}

typedef _Handler = FutureOr<(int, Object?)> Function(_Req);

class _Gateway implements HttpClientAdapter {
  _Gateway(this.routes);
  final Map<String, _Handler> routes;
  final List<_Req> log = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final req = _Req(o.method, o.uri.path.replaceFirst('/api/v1', ''), o.uri.queryParameters, o.data);
    log.add(req);
    final handler = routes['${req.method} ${req.path}'];
    final (status, json) = handler == null ? (404, {'error': 'NOT_FOUND', 'message': 'no route'}) : await handler(req);
    return ResponseBody.fromString(json == null ? '' : jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(_Gateway g) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1/', contentType: 'application/json'))..httpClientAdapter = g;
  return ApiClient(dio: dio)..authToken = 'tok';
}

(int, Object?) _err(int status, String code, String message, [Map<String, Object?> extra = const {}]) =>
    (status, {'error': code, 'message': message, ...extra});

const _empty = {'data': [], 'total': 0, 'page': 1, 'per_page': 20, 'total_pages': 0};

/// §1a, from the code: an admin message with a reward.
const _reward = {
  'id': 42,
  'user_id': '8c3be682-6b86-482d-964f-c2a25d92b0fe',
  'title': 'Sorry for the outage',
  'body': 'Here is a little something.',
  'icon_url': null,
  'cta_label': null,
  'cta_action': null,
  'attached_token': 500,
  'attached_gold': 0,
  'attached_power_ups': [],
  'is_read': false,
  'read_at': null,
  'claimed_at': null,
  'expires_at': '2099-12-01T00:00:00Z',
  'created_at': '2026-11-24T10:00:00.123456Z',
};

/// §1a, from the code: a dunning reminder (no reward).
const _dunning = {
  'id': 43, 'user_id': '8c3be682-6b86-482d-964f-c2a25d92b0fe', 'title': 'Payment failed',
  'body': 'Update your card to keep your subscription.', 'icon_url': null, 'cta_label': null, 'cta_action': null,
  'attached_token': 0, 'attached_gold': 0, 'attached_power_ups': [], 'is_read': false, 'read_at': null,
  'claimed_at': null, 'expires_at': '2026-12-08T10:00:00.5Z', 'created_at': '2026-11-24T10:00:00.5Z',
};

/// §2a, from the code.
const _notes = {
  'data': [
    {'id': '5b0e6a64-4f9e-4a39-8d0e-2f1f7b3c9a11', 'title': 'Weekend tournament', 'body': 'Ludo Sit & Go entries are half price until Sunday.', 'target_type': 'all', 'sent_at': '2026-11-24T10:05:00.123456Z'},
    {'id': '0c4d2f8e-7a61-4b1a-9f3c-6e5d4a3b2c10', 'title': 'Account check', 'body': 'Your support ticket was answered.', 'target_type': 'user', 'sent_at': '2026-11-23T18:00:00Z'},
  ],
  'total': 2, 'page': 1, 'per_page': 20, 'total_pages': 1,
};

/// §3a, real.
const _prefs = {
  'user_id': '8c3be682-6b86-482d-964f-c2a25d92b0fe', 'friend_requests': true, 'match_invites': true, 'promotions': true,
  'gift_received': true, 'daily_bonus_reminder': true, 'tournament_announcement': true, 'your_turn': true,
  'quiet_hours_start': null, 'quiet_hours_end': null, 'timezone': null, 'updated_at': '2026-11-24T09:54:38.187869Z',
};

const _notFound = 'not found: inbox message not found';

class _MemPrefs extends AppPrefs {
  final Map<String, String> data = {};
  @override
  Future<String?> get(String key) async => data[key];
  @override
  Future<void> set(String key, String value) async => data[key] = value;
}

class _FakeAccountStore extends AccountStore {
  final List<String?> tokens = [];
  @override
  Me? build() => null;
  @override
  Future<void> onPushToken(String? token) async => tokens.add(token);
  @override
  Future<Me?> load() async => null;
}

class _FakePush implements PushPlatform {
  PushPermission perm = PushPermission.notDetermined;
  PushPermission answer = PushPermission.granted;
  int asked = 0;
  final opensCtl = StreamController<void>.broadcast();
  final refreshCtl = StreamController<String>.broadcast();
  @override
  bool get supported => true;
  @override
  Future<PushPermission> permission() async => perm;
  @override
  Future<PushPermission> requestPermission() async {
    asked++;
    return perm = answer;
  }

  @override
  Future<String?> token() async => perm == PushPermission.granted ? 'fcm-token' : null;
  @override
  Stream<String> get tokenRefreshes => refreshCtl.stream;
  @override
  Stream<void> get opens => opensCtl.stream;
  @override
  Future<bool> openSystemSettings() async => true;
}

void main() {
  setUp(() => InboxBadgeStore.minInterval = const Duration(seconds: 10));

  group('parsing', () {
    test('reward message (from the code)', () {
      final m = InboxMessage.fromJson(Map.of(_reward));
      expect(m.id, 42);
      expect(m.attachedToken, 500);
      expect(m.hasReward, isTrue);
      expect(m.isRead, isFalse);
      expect(m.rewardWaiting(), isTrue);
      expect(m.rewardLabel, '+500 tokens');
      expect(m.ctaAction, isNull);
      expect(m.createdAt, DateTime.utc(2026, 11, 24, 10, 0, 0, 123, 456));
    });

    test('dunning message: no reward; expired by the rule', () {
      final m = InboxMessage.fromJson(Map.of(_dunning));
      expect(m.hasReward, isFalse);
      expect(m.isExpired(DateTime.utc(2026, 12, 8, 10, 0, 1)), isTrue);
      expect(m.isExpired(DateTime.utc(2026, 12, 1)), isFalse);
      expect(needsDeleteConfirm(m), isFalse);
    });

    test('money as strings, unknown cta_action and extra fields never throw', () {
      final m = InboxMessage.fromJson({
        ..._reward,
        'attached_token': '250',
        'attached_gold': '20',
        'cta_label': 'Open',
        'cta_action': {'kind': 'something-new', 'x': [1, 2]},
        'new_field': true,
      });
      expect(m.attachedToken, 250);
      expect(m.attachedGold, 20);
      expect(m.rewardLabel, '+250 tokens · +20 gold');
      expect(m.ctaLabel, 'Open');
    });

    test('page list (real, empty) and notifications (from the code)', () {
      final p = InboxPage.fromJson(_empty, InboxMessage.fromJson);
      expect(p.items, isEmpty);
      expect(p.totalPages, 0);
      expect(p.hasMore, isFalse);
      final n = InboxPage.fromJson(_notes, PlayerNotification.fromJson);
      expect(n.items.length, 2);
      expect(n.items.first.label, 'Announcement');
      expect(n.items.last.forMe, isTrue);
      expect(n.items.last.label, 'For you');
    });

    test('preferences (real) and claim reply (from the code)', () {
      final p = NotificationPreferences.fromJson(Map.of(_prefs));
      expect(p.promotions, isTrue);
      expect(p.quietHoursOn, isFalse);
      final q = NotificationPreferences.fromJson(
          {..._prefs, 'promotions': false, 'quiet_hours_start': '22:30:00', 'quiet_hours_end': '07:00:00', 'timezone': 'Asia/Kolkata'});
      expect(q.quietHoursOn, isTrue);
      expect(parseQuietTime(q.quietHoursStart), (22, 30));
      final c = ClaimResult.fromJson({'status': 'claimed', 'token_credited': 500, 'gold_credited': 0});
      expect(c.label, '+500 tokens');
    });

    test('preferences diff: only changed fields; null clears quiet hours', () {
      final a = NotificationPreferences.fromJson(
          {..._prefs, 'quiet_hours_start': '22:30:00', 'quiet_hours_end': '07:00:00', 'timezone': 'Asia/Kolkata'});
      final b = a.merge({'your_turn': false});
      expect(a.diff(b), {'your_turn': false});
      final off = a.merge({'quiet_hours_start': null, 'quiet_hours_end': null, 'timezone': null});
      expect(a.diff(off), {'quiet_hours_start': null, 'quiet_hours_end': null, 'timezone': null});
      expect(cleanPreferencePatch({'push_enabled': true, 'promotions': false}), {'promotions': false});
    });

    test('badge counts', () {
      final page = InboxPage.fromJson({
        'data': [_reward, _dunning, {..._dunning, 'id': 44, 'is_read': true, 'read_at': '2026-11-24T11:00:00Z'}],
        'total': 3, 'page': 1, 'per_page': 100, 'total_pages': 1,
      }, InboxMessage.fromJson);
      final b = InboxBadge.fromInbox(page, now: DateTime.utc(2026, 11, 25));
      expect(b.inboxUnread, 2);
      expect(b.rewardsWaiting, 1);
      expect(b.inboxCapped, isFalse);
      expect(InboxBadge.fromInbox(InboxPage(items: const [], total: 101)).label, '99+');
      final notes = InboxPage.fromJson(_notes, PlayerNotification.fromJson).items;
      expect(InboxBadge.newNotifications(notes, null), 0, reason: 'fresh install counts nothing');
      expect(InboxBadge.newNotifications(notes, DateTime.utc(2026, 11, 24)), 1);
      expect(const InboxBadge(notificationsNew: 12).notificationsLabel, '9+');
    });

    test('time zone guess and expiry text', () {
      expect(guessTimeZone(profileZone: 'Europe/Rome'), 'Europe/Rome');
      expect(guessTimeZone(offset: const Duration(hours: 5, minutes: 30)), 'Asia/Kolkata');
      expect(guessTimeZone(offset: const Duration(hours: 13)), 'UTC');
      final now = DateTime.utc(2026, 11, 24);
      expect(expiryText(now.add(const Duration(days: 3, hours: 1)), now: now), 'Expires in 3 days');
      expect(expiryText(now, now: now), 'Expired');
      expect(expiryText(null), isNull);
    });
  });

  group('requests and errors', () {
    test('list sends page and per_page; per_page out of range is a validation error', () async {
      final g = _Gateway({
        'GET /inbox': (r) => r.query['per_page'] == '0'
            ? _err(400, 'VALIDATION_ERROR', 'validation error: per_page: must be between 1 and 100', {'field': 'per_page'})
            : (200, {..._empty, 'page': int.parse(r.query['page'] as String), 'per_page': int.parse(r.query['per_page'] as String)}),
        'GET /notifications': (_) => (200, _notes),
      });
      final api = RemoteInboxApi(_client(g));
      final p = await api.inbox(page: 2, perPage: 5);
      expect(p.page, 2);
      expect(p.perPage, 5);
      expect(g.log.last.query, {'page': '2', 'per_page': '5'});
      // The client clamps per_page to 1-100.
      await api.inbox(perPage: 500);
      expect(g.log.last.query['per_page'], '100');
      final n = await api.notifications();
      expect(n.items.length, 2);
    });

    test('read, open and delete of an unknown id', () async {
      final g = _Gateway({
        'POST /inbox/42/read': (_) => _err(404, 'NOT_FOUND', _notFound),
        'GET /inbox/42': (_) => _err(404, 'NOT_FOUND', _notFound),
        'DELETE /inbox/42': (_) => _err(404, 'NOT_FOUND', _notFound),
      });
      final api = RemoteInboxApi(_client(g));
      Future<InboxIssue> issue(Future<void> f, InboxOp op) async {
        try {
          await f;
        } on AppException catch (e) {
          return inboxIssue(e, op);
        }
        fail('no error');
      }

      expect((await issue(api.markRead(42), InboxOp.read)).kind, InboxIssueKind.gone);
      final open = await issue(api.message(42), InboxOp.open);
      expect(open.kind, InboxIssueKind.gone);
      expect(open.text, 'This message is no longer available.');
      expect((await issue(api.delete(42), InboxOp.delete)).kind, InboxIssueKind.done);
      expect(g.log.map((r) => '$r'), ['POST /inbox/42/read', 'GET /inbox/42', 'DELETE /inbox/42']);
    });

    test('claim errors → what the app shows', () async {
      AppException ex(int s, String code, String msg) => AppException('x', statusCode: s, code: code, detail: msg);
      InboxIssue claim(AppException e, {bool hasReward = true}) => inboxIssue(e, InboxOp.claim, hasReward: hasReward);

      final gone = claim(ex(404, 'NOT_FOUND', _notFound));
      expect((gone.kind, gone.text), (InboxIssueKind.gone, 'This message is no longer available.'));
      expect(claim(ex(404, 'NOT_FOUND', 'not found: no claimable reward on this message'), hasReward: false).kind,
          InboxIssueKind.noReward);
      final again = claim(ex(409, 'CONFLICT', 'conflict: reward already claimed'));
      expect((again.kind, again.text), (InboxIssueKind.alreadyClaimed, 'Already claimed.'));
      final expired = claim(ex(400, 'BAD_REQUEST', 'bad request: inbox message has expired'));
      expect((expired.kind, expired.text), (InboxIssueKind.expired, 'This reward has expired.'));
      final later = claim(ex(503, 'UNAVAILABLE', 'unavailable: power-up rewards cannot be claimed yet'));
      expect((later.kind, later.text), (InboxIssueKind.message, "This reward can't be claimed yet. Try again later."));
      expect(claim(ex(500, 'DATABASE_ERROR', '')).text, 'Something went wrong. Try again.');
      expect(claim(ex(429, 'RATE_LIMITED', '')).text, 'Too many requests. Wait a moment and try again.');
      expect(claim(const AppException('Your session has ended. Please log in again.', statusCode: 401, code: 'UNAUTHORIZED')).kind,
          InboxIssueKind.signIn);
    });

    test('429 waits and retries once', () async {
      var n = 0;
      final g = _Gateway({
        'GET /inbox': (_) => ++n == 1 ? _err(429, 'RATE_LIMITED', 'too many') : (200, _empty),
      });
      final api = RemoteInboxApi(_client(g), rateLimitWait: Duration.zero);
      await api.inbox();
      expect(n, 2);
    });

    test('preferences errors (real bodies) → player text', () async {
      final g = _Gateway({
        'PATCH /notifications/preferences': (r) {
          final body = r.body as Map;
          if (body['timezone'] == 'Mars/Base') {
            return _err(400, 'VALIDATION_ERROR', 'validation error: timezone: must be an IANA timezone name (e.g. Asia/Kolkata)', {'field': 'timezone'});
          }
          if (body['quiet_hours_start'] == '25:00:00') {
            return _err(400, 'BAD_REQUEST', 'bad request: Json deserialize error: input is out of range at line 1 column 29');
          }
          return (200, {..._prefs, ...body});
        },
      });
      final api = RemoteInboxApi(_client(g));
      Future<String> text(Map<String, Object?> c) async {
        try {
          await api.updatePreferences(c);
        } on AppException catch (e) {
          return preferencesErrorText(e);
        }
        return 'ok';
      }

      expect(await text({'timezone': 'Mars/Base'}), 'Choose a valid time zone.');
      expect(await text({'quiet_hours_start': '25:00:00'}), 'Choose a valid time.');
      // Never sends a field the server doesn't take.
      expect(await text({'push_enabled': true, 'your_turn': false}), 'ok');
      expect(g.log.last.body, {'your_turn': false});
    });
  });

  group('stores', () {
    late _Gateway g;
    late ProviderContainer c;
    late _MemPrefs prefs;
    late _FakeAccountStore account;
    var claimed = false;

    setUp(() {
      claimed = false;
      prefs = _MemPrefs();
      account = _FakeAccountStore();
      g = _Gateway({
        'GET /inbox': (_) => (200, {'data': [_reward, _dunning], 'total': 2, 'page': 1, 'per_page': 20, 'total_pages': 1}),
        'GET /inbox/42': (_) => (200, {..._reward, 'is_read': true, 'read_at': '2026-11-24T10:01:00Z', 'claimed_at': claimed ? '2026-11-24T10:01:00Z' : null}),
        'POST /inbox/42/read': (_) => (200, {'status': 'read'}),
        'POST /inbox/43/read': (_) => (200, {'status': 'read'}),
        'POST /inbox/42/claim-reward': (_) {
          if (claimed) return _err(409, 'CONFLICT', 'conflict: reward already claimed');
          claimed = true;
          return (200, {'status': 'claimed', 'token_credited': 500, 'gold_credited': 0});
        },
        'DELETE /inbox/42': (_) => (200, {'status': 'deleted'}),
        'GET /notifications': (_) => (200, _notes),
        'GET /wallet/balance': (_) => (200, {'user_id': 'u', 'balance_tokens': claimed ? '600' : '100', 'balance_gold': '500', 'updated_at': '2026-11-24T10:00:00Z'}),
        'GET /notifications/preferences': (_) => (200, _prefs),
        'PATCH /notifications/preferences': (r) {
          final body = (r.body as Map).cast<String, Object?>();
          if (body['timezone'] == 'Mars/Base') {
            return _err(400, 'VALIDATION_ERROR', 'validation error: timezone', {'field': 'timezone'});
          }
          return (200, {..._prefs, ...body});
        },
      });
      final client = _client(g);
      c = ProviderContainer(overrides: [
        inboxApiProvider.overrideWithValue(RemoteInboxApi(client)),
        inboxIsLiveProvider.overrideWithValue(true),
        walletApiProvider.overrideWithValue(RemoteWalletApi(client)),
        appPrefsProvider.overrideWithValue(prefs),
        accountStoreProvider.overrideWith(() => account),
      ]);
      addTearDown(c.dispose);
    });

    int walletReads() => g.log.where((r) => r.path == '/wallet/balance').length;

    test('claim: reply amounts, message updated, wallet re-read; second claim = already claimed', () async {
      final sub = c.listen(inboxStoreProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(walletProvider.future);
      final store = c.read(inboxStoreProvider.notifier);
      await store.reload();
      final m = c.read(inboxStoreProvider).items.first;
      final before = walletReads();

      final out = await store.claim(m);
      expect(out.kind, ClaimOutcomeKind.claimed);
      expect(out.text, '+500 tokens');
      expect(out.message!.claimedAt, isNotNull);
      expect(c.read(inboxStoreProvider).items.first.rewardWaiting(), isFalse);
      await pumpEventQueue();
      expect(walletReads(), before + 1);
      expect(c.read(walletProvider).value!.tokens, 600);

      final again = await store.claim(m);
      expect(again.kind, ClaimOutcomeKind.alreadyClaimed);
      expect(again.ok, isTrue);
      expect(again.text, 'Already claimed.');
      expect(g.log.any((r) => '$r' == 'GET /inbox/42'), isTrue, reason: '409 re-reads the message');
      await pumpEventQueue();
      expect(walletReads(), before + 2, reason: '409 re-reads the wallet');
    });

    test('open marks read and lowers the badge at once; delete removes', () async {
      final sub = c.listen(inboxStoreProvider, (_, _) {});
      final sub2 = c.listen(inboxBadgeProvider, (_, _) {});
      addTearDown(sub.close);
      addTearDown(sub2.close);
      await c.read(inboxBadgeProvider.notifier).refresh();
      expect(c.read(inboxBadgeProvider).inboxUnread, 2);
      final store = c.read(inboxStoreProvider.notifier);
      await store.reload();
      final m = c.read(inboxStoreProvider).items.first;
      final opened = store.open(m);
      expect(c.read(inboxBadgeProvider).inboxUnread, 1, reason: 'lowered before the reply');
      expect(c.read(inboxStoreProvider).items.first.isRead, isTrue);
      await opened;
      expect(g.log.any((r) => '$r' == 'POST /inbox/42/read'), isTrue);
      expect(needsDeleteConfirm(c.read(inboxStoreProvider).items.first), isTrue);
      await store.delete(c.read(inboxStoreProvider).items.first);
      expect(c.read(inboxStoreProvider).items.map((m) => m.id), [43]);
    });

    test('badge refreshes at most once every 10 seconds', () async {
      final sub = c.listen(inboxBadgeProvider, (_, _) {});
      addTearDown(sub.close);
      final badge = c.read(inboxBadgeProvider.notifier);
      await badge.refresh();
      await badge.refresh();
      await badge.refresh();
      expect(g.log.where((r) => r.path == '/inbox').length, 1);
      expect(g.log.firstWhere((r) => r.path == '/inbox').query['per_page'], '100');
    });

    test('notifications last seen: fresh install counts nothing, then new items count', () async {
      final sub = c.listen(inboxBadgeProvider, (_, _) {});
      addTearDown(sub.close);
      InboxBadgeStore.minInterval = Duration.zero;
      final badge = c.read(inboxBadgeProvider.notifier);
      await badge.refresh();
      expect(c.read(inboxBadgeProvider).notificationsNew, 0);
      expect(prefs.data.values.single, '2026-11-24T10:05:00.123456Z');
      // An older "last seen": one item is new.
      prefs.data[prefs.data.keys.single] = '2026-11-24T00:00:00.000Z';
      c.invalidate(inboxBadgeProvider);
      await c.read(inboxBadgeProvider.notifier).refresh();
      expect(c.read(inboxBadgeProvider).notificationsNew, 1);
      // Shown → cleared and remembered.
      final notes = c.read(notificationsStoreProvider.notifier);
      final sub2 = c.listen(notificationsStoreProvider, (_, _) {});
      addTearDown(sub2.close);
      await notes.reload();
      await notes.markSeen();
      expect(c.read(inboxBadgeProvider).notificationsNew, 0);
      expect(prefs.data.values.single, '2026-11-24T10:05:00.123456Z');
    });

    test('preferences: PATCH only the changed field, quiet hours off = three nulls, rollback on error', () async {
      final sub = c.listen(notificationPrefsProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(notificationPrefsProvider.future);
      final store = c.read(notificationPrefsProvider.notifier);
      await store.change({'your_turn': false});
      expect(g.log.last.body, {'your_turn': false});
      expect(c.read(notificationPrefsProvider).value!.yourTurn, isFalse);

      await store.setQuietHours(on: true, start: '22:30:00', end: '07:00:00', timezone: 'Asia/Kolkata');
      expect(g.log.last.body, {'quiet_hours_start': '22:30:00', 'quiet_hours_end': '07:00:00', 'timezone': 'Asia/Kolkata'});
      await store.setQuietHours(on: false);
      expect(g.log.last.body, {'quiet_hours_start': null, 'quiet_hours_end': null, 'timezone': null});

      final before = c.read(notificationPrefsProvider).value!;
      await expectLater(store.change({'timezone': 'Mars/Base'}), throwsA(isA<AppException>()));
      expect(c.read(notificationPrefsProvider).value!.timezone, before.timezone);
    });
  });

  group('push switch', () {
    test('on asks the OS once and sends the token; off clears it; token refresh and OS denial', () async {
      final push = _FakePush();
      final account = _FakeAccountStore();
      final prefs = _MemPrefs();
      final c = ProviderContainer(overrides: [
        pushPlatformProvider.overrideWithValue(push),
        accountStoreProvider.overrideWith(() => account),
        appPrefsProvider.overrideWithValue(prefs),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(pushControllerProvider, (_, _) {});
      addTearDown(sub.close);
      final ctl = c.read(pushControllerProvider.notifier);
      await ctl.start();
      expect(c.read(pushControllerProvider).on, isFalse);
      expect(account.tokens, isEmpty);

      await ctl.askAfterGame();
      expect(push.asked, 1);
      expect(account.tokens, ['fcm-token']);
      await ctl.askAfterGame();
      expect(push.asked, 1, reason: 'asked once');

      await ctl.setWanted(false);
      expect(account.tokens.last, isNull);
      expect(c.read(pushControllerProvider).on, isFalse);
      await ctl.setWanted(true);
      expect(account.tokens.last, 'fcm-token');
      expect(c.read(pushControllerProvider).on, isTrue);

      push.refreshCtl.add('fcm-token-2');
      await pumpEventQueue();
      expect(account.tokens.last, 'fcm-token-2');

      push.perm = PushPermission.denied;
      await ctl.recheckPermission();
      expect(c.read(pushControllerProvider).deniedByOs, isTrue);
      expect(c.read(pushControllerProvider).on, isFalse);
    });
  });

  group('screens (demo)', () {
    Future<void> pump(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(ProviderScope(
        overrides: [appPrefsProvider.overrideWithValue(_MemPrefs())],
        child: MaterialApp(home: w),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('inbox lists messages with a reward chip, notifications tab, claim and delete', (tester) async {
      await pump(tester, const InboxScreen());
      expect(find.text('Sorry for the outage'), findsOneWidget);
      expect(find.text('+500 tokens'), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox-unread-dot')), findsNWidgets(2));

      await tester.tap(find.text('Sorry for the outage'));
      await tester.pumpAndSettle();
      expect(find.byType(InboxMessageScreen), findsOneWidget);
      expect(find.text('Claim'), findsOneWidget);
      await tester.tap(find.text('Claim'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Claimed'), findsOneWidget);
      expect(find.text('Claim'), findsNothing);
      await tester.pump(const Duration(seconds: 3));

      // The demo's gold message: delete asks first.
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weekend gift'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.text('The reward inside will be lost.'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Weekend gift'), findsNothing);

      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
      expect(find.text('Weekend tournament'), findsOneWidget);
      expect(find.text('For you'), findsOneWidget);
    });

    testWidgets('notification settings show the seven toggles and quiet hours', (tester) async {
      await pump(tester, const NotificationSettingsScreen());
      await tester.pumpAndSettle();
      for (final label in NotificationPreferences.toggles.values) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text("Push notifications aren't available in this version yet."), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('quiet-hours')), matching: find.byType(GestureDetector)).last);
      await tester.pumpAndSettle();
      expect(find.text('From'), findsOneWidget);
      expect(find.text('22:00'), findsOneWidget);
    });
  });
}
