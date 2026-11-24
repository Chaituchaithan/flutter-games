// The safety contract (docs/services/12-safety.md): parsers fed the doc's live
// replies, SafetyApi requests, each route's error text, the device-side
// repeat guard, the chat-line resend, ACCOUNT_BANNED / GEO_BLOCKED from any
// route, and the account standing that features check. Dio runs against a
// stand-in adapter that answers like the gateway and records each request.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/safety.dart';
import 'package:snakeladder/services/account_standing.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/app_prefs.dart';
import 'package:snakeladder/services/safety_service.dart';

class _Req {
  _Req(this.method, this.path, this.body);
  final String method;
  final String path;
  final dynamic body;
}

typedef _Handler = FutureOr<(int, Object?)> Function(_Req);

class _Gateway implements HttpClientAdapter {
  _Gateway(this.routes);
  final Map<String, _Handler> routes;
  final List<_Req> log = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final req = _Req(o.method, o.uri.path.replaceFirst('/api/v1', ''), o.data);
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
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1/', contentType: 'application/json'))
    ..httpClientAdapter = g;
  return ApiClient(dio: dio)..authToken = 'tok';
}

(int, Object?) _err(int status, String code, [Map<String, Object?> extra = const {}]) =>
    (status, {'error': code, 'message': 'developer text: $code', ...extra});

class _MemPrefs extends AppPrefs {
  final Map<String, String> data = {};
  @override
  Future<String?> get(String key) async => data[key];
  @override
  Future<void> set(String key, String value) async => data[key] = value;
}

const _a = 'b327ea3e-b571-487d-9967-431e7e19df5b';
const _b = '42dcdefc-d372-4668-be6d-ac16c96284a2';
const _match = '82e6509c-1bc9-43c6-8941-e2f3b4fc1c51';

/// §1, live: A reports B for a line in their match chat.
const _withLine = {
  'id': 5,
  'reporter_id': _a,
  'reported_user_id': _b,
  'reason': 'abuse',
  'description': 'Insult in match chat',
  'status': 'pending',
  'reviewed_by': null,
  'chat_message_ref': '1795514318726-0',
  'evidence': {
    'chat_message': {
      'body': 'you are bad at this',
      'created_at': '2026-11-24T09:58:38.727Z',
      'id': '1795514318726-0',
      'room_id': _match,
      'room_type': 'match',
      'sender_user_id': _b,
    }
  },
  'created_at': '2026-11-24T09:58:40.883420Z',
  'reported_username': 'w12docb1795514294',
  'reported_avatar_url': null,
};

/// §1, live: no chat line (`evidence` is `{}`).
const _noLine = {
  'id': 3,
  'reporter_id': _a,
  'reported_user_id': _b,
  'reason': 'cheating',
  'description': null,
  'status': 'pending',
  'reviewed_by': null,
  'chat_message_ref': null,
  'evidence': {},
  'created_at': '2026-11-24T09:58:37.288831Z',
  'reported_username': 'w12docb1795514294',
  'reported_avatar_url': null,
};

/// §2, live (first two of A's list).
const _myReports = [
  {
    'id': 9, 'reporter_id': _a, 'reported_user_id': _b, 'reason': 'other', 'description': '', //
    'status': 'pending', 'reviewed_by': null, 'chat_message_ref': null, 'evidence': {},
    'created_at': '2026-11-24T09:58:52.257319Z', 'reported_username': 'w12docb1795514294', 'reported_avatar_url': null,
  },
  {
    'id': 6, 'reporter_id': _a, 'reported_user_id': _b, 'reason': 'spam', 'description': null, //
    'status': 'pending', 'reviewed_by': null, 'chat_message_ref': '1795514319444-0',
    'evidence': {
      'chat_message': {
        'body': 'spam spam spam', 'created_at': '2026-11-24T09:58:39.445Z', 'id': '1795514319444-0', //
        'room_id': 'ludo-w12-1795514294', 'room_type': 'lobby', 'sender_user_id': _b,
      }
    },
    'created_at': '2026-11-24T09:58:41.600507Z', 'reported_username': 'w12docb1795514294', 'reported_avatar_url': null,
  },
];

/// §3, live.
const _flag = {
  'id': 1,
  'match_id': _match,
  'flagged_by': _a,
  'reason': 'Opponent seemed to use a bot.',
  'status': 'pending',
  'reviewed_by': null,
  'reviewed_at': null,
};

/// §4a, from code.
const _chatBan = {
  'is_banned': true,
  'ban': {
    'id': 12,
    'user_id': _a,
    'scope': 'chat',
    'reason': 'Repeated abuse in lobby chat',
    'banned_by': 1,
    'expires_at': '2026-11-25T10:00:00Z',
    'created_at': '2026-11-24T10:00:00Z',
  },
};

void main() {
  group('parsers', () {
    test('report with a chat line', () {
      final r = Report.fromJson(_withLine);
      expect(r.id, 5);
      expect(r.reason, ReportReason.abuse);
      expect(r.status, ReportStatus.pending);
      expect(r.chatMessage!.body, 'you are bad at this');
      expect(r.chatMessage!.roomType, ChatRoomType.match);
      expect(r.chatMessage!.messageId, '1795514318726-0');
      expect(r.reportedUsername, 'w12docb1795514294');
      expect(r.createdAt, DateTime.utc(2026, 11, 24, 9, 58, 40, 883, 420));
      // Never prints other players' words.
      expect(r.toString(), isNot(contains('bad at this')));
      expect(r.toString(), isNot(contains('Insult')));
    });

    test('report without a line, and "" read as no description', () {
      final r = Report.fromJson(_noLine);
      expect(r.chatMessage, isNull);
      expect(r.hasDescription, isFalse);
      expect(Report.fromJson(_myReports.first).hasDescription, isFalse);
    });

    test('my reports keep the server order', () {
      final list = [for (final j in _myReports) Report.fromJson(j)];
      expect(list.map((r) => r.id), [9, 6]);
      expect(list[1].chatMessage!.roomType, ChatRoomType.lobby);
    });

    test('unknown reason, status and scope never crash', () {
      final r = Report.fromJson({..._noLine, 'reason': 'griefing', 'status': 'escalated', 'id': '7'});
      expect(r.reason, ReportReason.unknown);
      expect(r.status, ReportStatus.unknown);
      expect(r.status.chip, 'Received');
      expect(r.id, 7);
      final c = BanCheck.fromJson({
        'is_banned': true,
        'ban': {'scope': 'voice', 'expires_at': null}
      });
      expect(c.ban!.scope, BanScope.unknown);
      expect(Report.fromJson(const {}).reason, ReportReason.unknown);
    });

    test('status chips', () {
      expect(ReportStatus.parse('reviewed').chip, 'In review');
      expect(ReportStatus.parse('actiontaken').chip, 'Action taken');
      expect(ReportStatus.parse('dismissed').chip, 'Closed');
    });

    test('match flag', () {
      final f = MatchFlag.fromJson(_flag);
      expect(f.id, 1);
      expect(f.matchId, _match);
      expect(f.status, 'pending');
    });

    test('ban check: clear and chat ban; staff reason is not kept', () {
      expect(BanCheck.fromJson({'is_banned': false, 'ban': null}).scopeAt(DateTime.now()), isNull);
      final c = BanCheck.fromJson(_chatBan);
      expect(c.ban!.scope, BanScope.chat);
      expect(c.ban!.expiresAt, DateTime.utc(2026, 11, 25, 10));
      expect(c.scopeAt(DateTime.utc(2026, 11, 24, 12)), BanScope.chat);
      expect(c.scopeAt(DateTime.utc(2026, 11, 26)), isNull);
      expect(c.ban.toString(), isNot(contains('abuse')));
    });
  });

  group('SafetyApi', () {
    test('report body: reason wire name, empty description left out, chat line', () async {
      final g = _Gateway({'POST /moderation/report': (_) => (201, _withLine)});
      final api = RemoteSafetyApi(_client(g));
      await api.report(reportedUserId: _b, reason: ReportReason.inappropriateContent, description: '  ');
      expect(g.log.last.body, {'reported_user_id': _b, 'reason': 'inappropriate_content'});
      await api.report(
        reportedUserId: _b,
        reason: ReportReason.abuse,
        description: 'Insult in match chat',
        chatMessage: const ChatEvidence(roomType: ChatRoomType.match, roomId: _match, messageId: '1795514318726-0'),
      );
      expect(g.log.last.body, {
        'reported_user_id': _b,
        'reason': 'abuse',
        'description': 'Insult in match chat',
        'chat_message': {'room_type': 'match', 'room_id': _match, 'message_id': '1795514318726-0'},
      });
    });

    test('my reports, ban check, flag', () async {
      final g = _Gateway({
        'GET /moderation/my-reports': (_) => (200, _myReports),
        'GET /moderation/bans/check': (_) => (200, _chatBan),
        'POST /matches/$_match/flag': (_) => (201, _flag),
      });
      final api = RemoteSafetyApi(_client(g));
      expect((await api.myReports()).length, 2);
      expect((await api.checkBan()).ban!.scope, BanScope.chat);
      final f = await api.flagMatch(_match, '  Opponent seemed to use a bot. ');
      expect(f.id, 1);
      expect(g.log.last.body, {'reason': 'Opponent seemed to use a bot.'});
    });
  });

  group('error text', () {
    Future<AppException> fail(String route, (int, Object?) reply, Future<void> Function(SafetyApi) call) async {
      final api = RemoteSafetyApi(_client(_Gateway({route: (_) => reply})));
      try {
        await call(api);
      } on AppException catch (e) {
        return e;
      }
      throw StateError('no error');
    }

    Future<void> report(SafetyApi a) => a.report(reportedUserId: _b, reason: ReportReason.spam);
    Future<void> flag(SafetyApi a) => a.flagMatch(_match, 'a bot again');

    test('report', () async {
      expect(safetyErrorText(await fail('POST /moderation/report', _err(404, 'NOT_FOUND'), report), SafetyOp.report),
          'Player not found.');
      expect(
          safetyErrorText(
              await fail('POST /moderation/report', _err(400, 'VALIDATION_ERROR', {'field': 'description'}), report),
              SafetyOp.report),
          'Keep it under 2000 characters.');
      expect(safetyErrorText(await fail('POST /moderation/report', _err(429, 'RATE_LIMITED'), report), SafetyOp.report),
          'Too many attempts. Try again in a minute.');
      expect(safetyErrorText(await fail('POST /moderation/report', _err(400, 'BAD_REQUEST'), report), SafetyOp.report),
          'Something went wrong. Try again.');
    });

    test('flag', () async {
      const route = 'POST /matches/$_match/flag';
      expect(safetyErrorText(await fail(route, _err(403, 'FORBIDDEN'), flag), SafetyOp.flagMatch),
          'You can only report matches you played.');
      expect(safetyErrorText(await fail(route, _err(404, 'MATCH_NOT_FOUND'), flag), SafetyOp.flagMatch),
          'Match not found.');
      expect(
          safetyErrorText(
              await fail(route, _err(400, 'VALIDATION_ERROR', {'field': 'reason'}), flag), SafetyOp.flagMatch),
          'Write 5 to 500 characters.');
    });

    test('client rules', () {
      expect(SafetyRules.flagReason('abcd'), isNotNull);
      expect(SafetyRules.flagReason('abcde'), isNull);
      expect(SafetyRules.flagReason('x' * 501), isNotNull);
      expect(SafetyRules.description('x' * 2000), isNull);
      expect(SafetyRules.description('x' * 2001), isNotNull);
      expect(SafetyRules.withMatch('', _match), 'Match $_match');
      expect(SafetyRules.withMatch('bot', _match), 'Match $_match. bot');
    });
  });

  group('SafetyController', () {
    late _Gateway g;
    late ProviderContainer c;
    late _MemPrefs prefs;
    var clock = DateTime(2026, 11, 24, 12);

    setUp(() {
      clock = DateTime(2026, 11, 24, 12);
      prefs = _MemPrefs();
      g = _Gateway({
        'POST /moderation/report': (_) => (201, _noLine),
        'POST /matches/$_match/flag': (_) => (201, _flag),
      });
      final client = _client(g);
      c = ProviderContainer(overrides: [
        safetyApiProvider.overrideWithValue(RemoteSafetyApi(client)),
        reportedTrackerProvider.overrideWithValue(ReportedTracker(prefs, clock: () => clock)),
      ]);
      addTearDown(c.dispose);
    });

    test('a second report of the same player within 24 h makes no call', () async {
      final s = c.read(safetyControllerProvider);
      expect(await s.reportPlayer(playerId: _b, reason: ReportReason.spam), ReportOutcome.sent);
      expect(g.log.length, 1);
      expect(await s.reportPlayer(playerId: _b, reason: ReportReason.abuse), ReportOutcome.alreadyReported);
      expect(g.log.length, 1);
      // After 24 hours it may be sent again.
      clock = clock.add(const Duration(hours: 25));
      expect(await s.reportPlayer(playerId: _b, reason: ReportReason.abuse), ReportOutcome.sent);
      expect(g.log.length, 2);
    });

    test('the record survives a restart (kept on the device)', () async {
      await c.read(safetyControllerProvider).reportPlayer(playerId: _b, reason: ReportReason.spam);
      final fresh = ReportedTracker(prefs, clock: () => clock);
      expect(await fresh.alreadyReported('demo', playerId: _b), isTrue);
      expect(await fresh.alreadyReported('other-account', playerId: _b), isFalse);
    });

    test('a chat line that is gone: resent without it, quoted in description', () async {
      var n = 0;
      g.routes['POST /moderation/report'] = (req) {
        n++;
        final body = req.body as Map;
        if (body.containsKey('chat_message')) {
          return _err(400, 'BAD_REQUEST', {'message': 'bad request: chat message not found in that room'});
        }
        return (201, _noLine);
      };
      const line = ChatEvidence(
          roomType: ChatRoomType.lobby, roomId: 'ludo-1', messageId: '1795514319444-0', body: 'spam spam spam');
      final out = await c
          .read(safetyControllerProvider)
          .reportPlayer(playerId: _b, reason: ReportReason.spam, chatMessage: line);
      expect(out, ReportOutcome.sent);
      expect(n, 2);
      final last = g.log.last.body as Map;
      expect(last.containsKey('chat_message'), isFalse);
      expect(last['description'], 'Message: "spam spam spam"');
    });

    test('match id and a socket line go into the description', () async {
      await c.read(safetyControllerProvider).reportPlayer(
          playerId: _b, reason: ReportReason.abuse, matchId: _match, quote: 'Good game!');
      expect((g.log.last.body as Map)['description'], 'Match $_match\nMessage: "Good game!"');
    });

    test('flag is remembered per match', () async {
      final s = c.read(safetyControllerProvider);
      expect(await s.matchFlagged(_match), isFalse);
      await s.flagMatch(_match, 'Opponent seemed to use a bot.');
      expect(await s.matchFlagged(_match), isTrue);
    });
  });

  group('any route', () {
    test('ACCOUNT_BANNED signs out with until, never retried', () async {
      final g = _Gateway({
        'GET /moderation/bans/check': (_) =>
            _err(403, 'ACCOUNT_BANNED', {'until': '2026-11-25T10:00:00Z', 'message': 'account is banned until …'}),
      });
      final client = _client(g);
      AppException? reason;
      client.onUnauthorized = (r) => reason = r;
      await expectLater(RemoteSafetyApi(client).checkBan(), throwsA(isA<AppException>()));
      await Future<void>.delayed(Duration.zero);
      expect(g.log.length, 1);
      expect(reason!.isBanned, isTrue);
      expect(reason!.until, DateTime.utc(2026, 11, 25, 10));
      expect(reason!.message, banMessage(DateTime.utc(2026, 11, 25, 10)));
      expect(reason!.message, contains(formatLocalTime(DateTime.utc(2026, 11, 25, 10))));
    });

    test('ACCOUNT_BANNED without until', () {
      expect(banMessage(null), 'Your account is suspended. Contact support.');
    });

    test('GEO_BLOCKED: read, write and store kinds', () async {
      final g = _Gateway({
        'GET /moderation/my-reports': (_) => _err(403, 'GEO_BLOCKED'),
        'POST /moderation/report': (_) => _err(403, 'GEO_BLOCKED'),
        'GET /sensitive/shop/items': (_) => _err(403, 'GEO_BLOCKED'),
      });
      final client = _client(g);
      final kinds = <GeoBlock>[];
      client.onGeoBlocked = kinds.add;
      final texts = <String>[];
      for (final call in [
        () => client.get('/moderation/my-reports'),
        () => client.post('/moderation/report', body: {}),
        () => client.get('/sensitive/shop/items'),
      ]) {
        try {
          await call();
        } on AppException catch (e) {
          texts.add(e.message);
        }
      }
      expect(kinds, [GeoBlock.full, GeoBlock.writes, GeoBlock.store]);
      expect(texts, [GeoBlock.full.text, "This action isn't available in your region.", GeoBlock.store.text]);
      expect(ApiClient.geoBlockFor('POST', '/auth/login'), GeoBlock.full);
    });
  });

  group('AccountStanding', () {
    final now = DateTime.utc(2026, 11, 24, 12);
    AccountStanding withScope(String scope, {String? until = '2026-11-25T10:00:00Z'}) => AccountStanding(
          check: BanCheck.fromJson({
            'is_banned': true,
            'ban': {'scope': scope, 'expires_at': until}
          }),
          clock: () => now,
        );

    test('clear', () {
      final s = AccountStanding(check: BanCheck.clear, clock: () => now);
      expect([s.canChat, s.canPlay, s.canStake, s.canJoinTournaments, s.storeAvailable], everyElement(isTrue));
      expect(s.chatBlockedText, isNull);
      expect(s.playBlockedText, isNull);
    });

    test('chat ban: only chat closes, with its end time', () {
      final s = withScope('chat');
      expect(s.canChat, isFalse);
      expect(s.canPlay && s.canJoinTournaments, isTrue);
      expect(s.chatBlockedText,
          "You can't send messages until ${formatLocalTime(DateTime.utc(2026, 11, 25, 10))}.");
    });

    test('matchmaking ban closes play; tournaments ban closes Join', () {
      expect(withScope('matchmaking').canPlay, isFalse);
      expect(withScope('matchmaking').canStake, isFalse);
      expect(withScope('matchmaking', until: null).playBlockedText, "You can't join games for now.");
      expect(withScope('tournaments').canJoinTournaments, isFalse);
      expect(withScope('tournaments').canPlay, isTrue);
    });

    test('unknown scope: banner only', () {
      final s = withScope('voice');
      expect([s.canChat, s.canPlay, s.canJoinTournaments], everyElement(isTrue));
      expect(s.unknownRestrictionText, isNotNull);
    });

    test('an expired ban reads as clear', () {
      final s = AccountStanding(check: withScope('chat').check, clock: () => DateTime.utc(2026, 11, 26));
      expect(s.canChat, isTrue);
    });

    test('a refused chat send without a ban (mute)', () {
      final s = AccountStanding(check: BanCheck.clear, chatRefused: true, clock: () => now);
      expect(s.chatBlockedText, "You can't send messages for now.");
    });

    test('region: store-only keeps play, writes stop stakes', () {
      expect(const AccountStanding(geo: GeoBlock.store).storeAvailable, isFalse);
      expect(const AccountStanding(geo: GeoBlock.store).canStake, isTrue);
      expect(const AccountStanding(geo: GeoBlock.writes).canStake, isFalse);
      expect(const AccountStanding(geo: GeoBlock.full).canPlay, isFalse);
    });

    test('tournament refusals', () {
      expect(TournamentRefusal.parse('forbidden: buy-in would exceed your daily loss limit (100 lost of 50)').text,
          'This would pass your spending limit.');
      expect(TournamentRefusal.parse('forbidden: buy-in would exceed your daily tournament spend limit (1 spent of 2)').kind,
          TournamentRefusalKind.limit);
      final r = TournamentRefusal.parse('forbidden: you are self-excluded until 2026-12-01T00:00:00Z');
      expect(r.kind, TournamentRefusalKind.onBreak);
      expect(r.until, DateTime.utc(2026, 12));
      expect(r.text, "You've taken a break from tournaments until ${formatLocalTime(DateTime.utc(2026, 12))}.");
      expect(TournamentRefusal.parse('forbidden: you are cooling off until 2026-12-01 00:00:00 UTC').until,
          DateTime.utc(2026, 12));
      expect(TournamentRefusal.parse('forbidden: you are banned from tournaments').kind, TournamentRefusalKind.banned);
      expect(TournamentRefusal.parse(null).text, "You can't join right now.");
    });

    test('controller: chat refusal and tournament break', () {
      final c = ProviderContainer(overrides: [safetyApiProvider.overrideWithValue(DemoSafetyApi())]);
      addTearDown(c.dispose);
      final n = c.read(accountStandingProvider.notifier);
      n.chatRefused();
      expect(c.read(accountStandingProvider).canChat, isFalse);
      final text = n.tournamentRefused(const AppException('x',
          statusCode: 403, code: 'FORBIDDEN', detail: 'forbidden: you are cooling off until 2099-01-01T00:00:00Z'));
      expect(text, contains("You've taken a break"));
      expect(c.read(accountStandingProvider).canJoinTournaments, isFalse);
      n.geoBlocked(GeoBlock.writes);
      n.geoBlocked(GeoBlock.store); // never narrows
      expect(c.read(accountStandingProvider).geo, GeoBlock.writes);
    });
  });
}
