// The social contract (docs/services/09-social.md): model parsing for the
// doc's real replies, SocialApi requests, each route's error → player text,
// the gift Idempotency-Key reuse on retry, the presence heartbeat timer,
// friends state rules (mutual requests, duplicate → "sent", block clears a
// friend), referral apply, and that blocked players are hidden in chat and
// the gift sheet. Dio runs against a stand-in adapter that answers like the
// gateway and records each request.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/configs/feature_flags.dart';
import 'package:snakeladder/data/models/referral.dart';
import 'package:snakeladder/data/models/social.dart';
import 'package:snakeladder/data/models/wallet.dart';
import 'package:snakeladder/data/sources/referral_source.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/social_api.dart';
import 'package:snakeladder/services/social_store.dart';
import 'package:snakeladder/widgets/send_gift_sheet.dart';

class _Req {
  _Req(this.method, this.path, this.query, this.headers, this.body);
  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Map<String, dynamic> headers;
  final dynamic body;
}

typedef _Handler = FutureOr<(int, Object?)> Function(_Req);

class _Gateway implements HttpClientAdapter {
  _Gateway(this.routes);
  final Map<String, _Handler> routes;
  final List<_Req> log = [];

  /// Fail this many requests with "no network" before answering.
  int dropNext = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final req = _Req(o.method, o.uri.path.replaceFirst('/api/v1', ''), o.uri.queryParameters, Map.of(o.headers), o.data);
    log.add(req);
    if (dropNext > 0) {
      dropNext--;
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
    }
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

(int, Object?) _err(int status, String code, [Map<String, Object?> extra = const {}]) =>
    (status, {'error': code, 'message': 'developer text: $code', ...extra});

const _a = '21ad6a00-c5ee-47d7-a92b-32ec0c3ed99d';
const _b = '0ffa6d8b-a5f5-4b62-a1d1-2ff765d78303';
const _c = '2195e313-e807-4a69-b562-afc27625821f';

const _request = {
  'id': 1,
  'from_user_id': _a,
  'to_user_id': _b,
  'status': 'pending',
  'created_at': '2026-11-24T09:44:42.021757Z',
  'responded_at': null,
};

const _gift = {
  'id': '5e3933a0-d5e3-4282-a1ab-28a54a8bbbd2',
  'sender_id': _a,
  'receiver_id': _b,
  'item_type': 'rose',
  'item_id': 'rose',
  'amount': 5,
  'currency': 'gold',
  'message': 'for you',
  'created_at': '2026-11-24T09:45:17.564106Z',
};

Map<String, Object?> _page(List<Object?> data, {int page = 1, int perPage = 20, int? total, int? totalPages}) => {
      'data': data,
      'total': total ?? data.length,
      'page': page,
      'per_page': perPage,
      'total_pages': totalPages ?? (data.isEmpty ? 0 : 1),
    };

void main() {
  group('models parse the real replies', () {
    test('friend request and the pending page list', () {
      final r = FriendRequest.fromJson(_request);
      expect(r.id, 1);
      expect(r.fromUserId, _a);
      expect(r.pending, isTrue);
      expect(r.respondedAt, isNull);
      expect(r.createdAt, DateTime.parse('2026-11-24T09:44:42.021757Z'));

      final p = PageList.fromJson(_page([_request]), FriendRequest.fromJson);
      expect(p.total, 1);
      expect(p.data.single.toUserId, _b);
      expect(p.hasMore, isFalse);
      final empty = PageList.fromJson({'data': [], 'total': 0, 'page': 1, 'per_page': 20, 'total_pages': 0}, FriendRequest.fromJson);
      expect(empty.data, isEmpty);
      expect(empty.hasMore, isFalse);
    });

    test('friend list is ids only', () {
      final p = PageList.fromJson(
          _page([{'user_id': _b, 'created_at': '2026-11-24T09:44:48.829078Z'}]), FriendLink.fromJson);
      expect(p.data.single.userId, _b);
      expect(p.data.single.createdAt, isNotNull);
    });

    test('friends-online: ids and cards (null name falls back)', () {
      final o = FriendsOnline.fromJson({
        'online_friends': [_b],
        'friends': [{'user_id': _b, 'username': 'w09docb1795513466', 'avatar_url': null}],
      });
      expect(o.ids, {_b});
      expect(o.friends.single.name, 'w09docb1795513466');
      expect(const UserCard(userId: 'x').name, 'Player');
      expect(FriendsOnline.fromJson({'online_friends': [], 'friends': []}).ids, isEmpty);
    });

    test('chat lines: send reply (micro s) and history (milli s)', () {
      final sent = ChatMessage.fromJson({
        'id': '1795513509258-0',
        'room_type': 'lobby',
        'room_id': 'w09doc-1795513466',
        'sender_user_id': _a,
        'body': 'hello from A',
        'created_at': '2026-11-24T09:45:09.259236Z',
      });
      expect(sent.id, '1795513509258-0');
      expect(sent.createdAt, isNotNull);
      final hist = ChatMessage.fromJson({
        'id': '1795513510773-0',
        'room_type': 'lobby',
        'room_id': 'w09doc-1795513466',
        'sender_user_id': _c,
        'body': 'C joins',
        'created_at': '2026-11-24T09:45:10.774Z',
      });
      expect(hist.createdAt!.millisecond, 774);
    });

    test('gift: amount as number or string, tokens → token, null message', () {
      final g = Gift.fromJson(_gift);
      expect(g.amount, 5);
      expect(g.currency, WalletCurrency.gold);
      expect(g.message, 'for you');
      expect(GiftLook.of(g.itemType), GiftLook.rose);
      final s = Gift.fromJson({..._gift, 'amount': '7', 'currency': 'token', 'message': null, 'item_type': 'currency'});
      expect(s.amount, 7);
      expect(s.currency, WalletCurrency.token);
      expect(s.message, isNull);
      expect(GiftLook.of(s.itemType), isNull);
    });

    test('blocks page has names', () {
      final p = PageList.fromJson(
          _page([
            {
              'blocker_id': _b,
              'blocked_id': _a,
              'user_id': _a,
              'created_at': '2026-11-24T09:45:35.816963Z',
              'username': 'w09doca1795513466',
              'avatar_url': null,
            }
          ]),
          BlockedUser.fromJson);
      expect(p.data.single.userId, _a);
      expect(p.data.single.card.name, 'w09doca1795513466');
    });

    test('referral code and stats', () {
      final c = ReferralCode.fromJson({'code': '39UVKDVP', 'uses': 2, 'max_uses': null, 'expires_at': null});
      expect(c.code, '39UVKDVP');
      expect(c.uses, 2);
      expect(c.usedUp, isFalse);
      final s = ReferralStats.fromJson({'total_referrals': 2, 'rewards_granted': 0});
      expect(s.totalReferrals, 2);
    });

    test('invite links: built on the device, parsed upper-cased', () {
      expect(inviteLink('39uvkdvp').toString(), 'royalearcade://invite?code=39UVKDVP');
      expect(inviteLink('abc', host: 'example.com').toString(), 'https://example.com/invite?code=ABC');
      expect(parseInviteLink(Uri.parse('royalearcade://invite?code=39uvkdvp')), '39UVKDVP');
      expect(parseInviteLink(Uri.parse('https://example.com/invite?code=%2039UVKDVP%20')), '39UVKDVP');
      expect(parseInviteLink(Uri.parse('royalearcade://join/ludo/abcd1234')), isNull);
      expect(parseInviteLink(Uri.parse('https://example.com/invite')), isNull);
      expect(normalizeReferralCode(' 39uvkdvp '), '39UVKDVP');
    });
  });

  group('RemoteSocialApi requests', () {
    test('friends: send, pending, accept, reject, list with per_page, remove (404 = done)', () async {
      final g = _Gateway({
        'POST /friends/request': (r) => (201, {..._request, 'to_user_id': (r.body as Map)['to_user_id']}),
        'GET /friends/requests/pending': (_) => (200, _page([_request])),
        'POST /friends/request/1/accept': (_) => (200, {'status': 'accepted'}),
        'POST /friends/request/1/reject': (_) => (200, {'status': 'rejected'}),
        'GET /friends': (r) => (200, _page([{'user_id': _b, 'created_at': '2026-11-24T09:44:48.829078Z'}], perPage: 100)),
        'DELETE /friends/$_b': (_) => _err(404, 'NOT_FOUND'),
      });
      final api = RemoteSocialApi(_client(g));
      expect((await api.sendFriendRequest(_b)).toUserId, _b);
      expect(g.log.last.body, {'to_user_id': _b});
      expect((await api.incomingRequests()).data.single.id, 1);
      expect(g.log.last.query, {'page': '1', 'per_page': '20'});
      await api.acceptRequest(1);
      await api.rejectRequest(1);
      final f = await api.friends(perPage: 500);
      expect(g.log.last.query['per_page'], '100', reason: 'per_page is clamped to 1-100');
      expect(f.data.single.userId, _b);
      await api.removeFriend(_b); // 404 → done
    });

    test('heartbeat sends {} or a valid game_id', () async {
      final g = _Gateway({'POST /presence/heartbeat': (_) => (200, {'status': 'ok'})});
      final api = RemoteSocialApi(_client(g));
      await api.heartbeat();
      expect(g.log.last.body, <String, dynamic>{});
      await api.heartbeat(gameId: 'snake-and-ladder');
      expect(g.log.last.body, {'game_id': 'snake-and-ladder'});
      await api.heartbeat(gameId: 'bad id!');
      expect(g.log.last.body, <String, dynamic>{});
    });

    test('presence and online count', () async {
      final g = _Gateway({
        'GET /presence/friends-online': (_) => (200, {
              'online_friends': [_b],
              'friends': [{'user_id': _b, 'username': 'bee', 'avatar_url': null}],
            }),
        'GET /presence/online-count': (_) => (200, {'global_count': 2}),
      });
      final api = RemoteSocialApi(_client(g));
      expect((await api.friendsOnline()).friends.single.name, 'bee');
      expect(await api.onlineCount(), 2);
    });

    test('chat send and history with count/before', () async {
      final g = _Gateway({
        'POST /chat/lobby/ludo/send': (r) => (201, {
              'id': '1795513509258-0',
              'room_type': 'lobby',
              'room_id': 'ludo',
              'sender_user_id': _a,
              'body': (r.body as Map)['body'],
              'created_at': '2026-11-24T09:45:09.259236Z',
            }),
        'GET /chat/lobby/ludo/history': (_) => (200, []),
      });
      final api = RemoteSocialApi(_client(g));
      expect((await api.sendChat(ChatRoomType.lobby, 'ludo', 'hi')).body, 'hi');
      expect(await api.chatHistory(ChatRoomType.lobby, 'ludo', count: 2, before: '1795513510004-0'), isEmpty);
      expect(g.log.last.query, {'count': '2', 'before': '1795513510004-0'});
    });

    test('gift body and header; a retry after no network reuses the Idempotency-Key', () async {
      final g = _Gateway({'POST /gifts/send': (_) => (201, _gift)})..dropNext = 1;
      final api = RemoteSocialApi(_client(g), retryDelay: Duration.zero);
      final gift = await api.sendGift(
        receiverId: _b,
        itemType: 'rose',
        itemId: 'rose',
        amount: 5,
        currency: WalletCurrency.gold,
        message: 'for you',
        idempotencyKey: 'key-1',
      );
      expect(gift.id, _gift['id']);
      expect(g.log, hasLength(2));
      expect(g.log.map((r) => r.headers['Idempotency-Key']), ['key-1', 'key-1']);
      expect(g.log.last.body, {
        'receiver_id': _b,
        'item_type': 'rose',
        'item_id': 'rose',
        'amount': 5,
        'currency': 'gold',
        'message': 'for you',
      });
    });

    test('a refused gift is not retried', () async {
      final g = _Gateway({'POST /gifts/send': (_) => _err(409, 'INSUFFICIENT_FUNDS')});
      final api = RemoteSocialApi(_client(g), retryDelay: Duration.zero);
      await expectLater(
        api.sendGift(receiverId: _b, itemType: 'rose', itemId: 'rose', amount: 5, currency: WalletCurrency.gold, idempotencyKey: 'k'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'INSUFFICIENT_FUNDS')),
      );
      expect(g.log, hasLength(1));
    });

    test('gift history pages', () async {
      final g = _Gateway({
        'GET /gifts/received': (_) => (200, _page([_gift], perPage: 2)),
        'GET /gifts/sent': (_) => (200, _page([], perPage: 2)),
      });
      final api = RemoteSocialApi(_client(g));
      expect((await api.giftsReceived(perPage: 2)).data.single.amount, 5);
      expect((await api.giftsSent(perPage: 2)).data, isEmpty);
    });

    test('blocks: 409 on block and 404 on unblock count as done', () async {
      final g = _Gateway({
        'POST /blocks/$_b': (_) => _err(409, 'CONFLICT'),
        'DELETE /blocks/$_b': (_) => _err(404, 'NOT_FOUND'),
        'GET /blocks': (_) => (200, _page([])),
      });
      final api = RemoteSocialApi(_client(g));
      await api.block(_b);
      await api.unblock(_b);
      expect((await api.blocks()).data, isEmpty);
    });

    test('referral apply sends the code upper-cased (204)', () async {
      final g = _Gateway({'POST /referrals/apply': (_) => (204, null)});
      await RemoteReferralSource(_client(g)).apply(' 39uvkdvp ');
      expect(g.log.single.body, {'code': '39UVKDVP'});
    });
  });

  group('errors → player text', () {
    Future<AppException> failWith(String route, (int, Object?) reply, Future<void> Function(RemoteSocialApi) call) async {
      final g = _Gateway({route: (_) => reply});
      try {
        await call(RemoteSocialApi(_client(g), retryDelay: Duration.zero));
      } on AppException catch (e) {
        return e;
      }
      throw StateError('expected an error');
    }

    test('friend request', () async {
      Future<String> t((int, Object?) r) async =>
          socialErrorText(await failWith('POST /friends/request', r, (a) => a.sendFriendRequest(_b)), SocialOp.friendRequest);
      expect(await t(_err(403, 'FORBIDDEN')), "This player isn't accepting friend requests.");
      expect(await t(_err(404, 'NOT_FOUND')), 'Player not found.');
      expect(await t(_err(409, 'USER_BLOCKED')), "You can't add this player.");
      expect(await t(_err(409, 'CONFLICT')), "You're already friends.");
      expect(await t(_err(409, 'DUPLICATE_FRIEND_REQUEST')), 'Request already sent');
      expect(await t(_err(400, 'BAD_REQUEST')), 'Something went wrong. Try again.');
    });

    test('accept / decline', () async {
      final e = await failWith('POST /friends/request/9/accept', _err(404, 'NOT_FOUND'), (a) => a.acceptRequest(9));
      expect(socialErrorText(e, SocialOp.answerRequest), 'This request is no longer open.');
      final f = await failWith('POST /friends/request/9/reject', _err(403, 'FORBIDDEN'), (a) => a.rejectRequest(9));
      expect(socialErrorText(f, SocialOp.answerRequest), 'Something went wrong. Try again.');
    });

    test('chat', () async {
      final v = await failWith('POST /chat/lobby/x/send', _err(400, 'VALIDATION_ERROR', {'field': 'body'}),
          (a) => a.sendChat(ChatRoomType.lobby, 'x', 'hi'));
      expect(socialErrorText(v, SocialOp.chatSend), 'Messages must be 1 to 2000 characters.');
      final m = await failWith('POST /chat/lobby/x/send', _err(403, 'FORBIDDEN'), (a) => a.sendChat(ChatRoomType.lobby, 'x', 'hi'));
      expect(socialErrorText(m, SocialOp.chatSend), "You can't chat right now.");
      expect(socialErrorText(m, SocialOp.matchChat), 'Only players in this match can chat here.');
    });

    test('gift', () async {
      Future<String> t((int, Object?) r, {WalletCurrency c = WalletCurrency.gold}) async => socialErrorText(
          await failWith('POST /gifts/send', r,
              (a) => a.sendGift(receiverId: _b, itemType: 'rose', itemId: 'rose', amount: 5, currency: c, idempotencyKey: 'k')),
          SocialOp.gift,
          currency: c);
      expect(await t(_err(400, 'VALIDATION_ERROR', {'field': 'amount'})), 'Enter an amount of 1 or more.');
      expect(await t(_err(404, 'NOT_FOUND')), "That player can't receive gifts.");
      expect(await t(_err(409, 'INSUFFICIENT_FUNDS')), 'Not enough gold.');
      expect(await t(_err(409, 'INSUFFICIENT_FUNDS'), c: WalletCurrency.token), 'Not enough tokens.');
      expect(await t(_err(429, 'GIFT_QUOTA_EXCEEDED')), "You've reached today's gift limit.");
      expect(await t(_err(409, 'CONFLICT')), 'Something went wrong. Try again.');
      expect(await t((503, {'error': 'KILL_SWITCH_ENGAGED', 'message': 'Gifts are paused for maintenance.'})),
          'Gifts are paused for maintenance.');
    });

    test('block an unknown player (500 DATABASE_ERROR) → Player not found', () async {
      final e = await failWith('POST /blocks/$_c', _err(500, 'DATABASE_ERROR'), (a) => a.block(_c));
      expect(socialErrorText(e, SocialOp.block), 'Player not found.');
    });

    test('referral apply', () {
      String t(int s, String c) => socialErrorText(AppException('', statusCode: s, code: c), SocialOp.referralApply);
      expect(t(400, 'VALIDATION_ERROR'), 'Enter a code.');
      expect(t(400, 'BAD_REQUEST'), "You can't use this code.");
      expect(t(404, 'NOT_FOUND'), 'Code not found.');
      expect(t(409, 'CONFLICT'), "You've already used a referral code.");
    });

    test('no network', () {
      expect(socialErrorText(const AppException('x', kind: AppErrorKind.offline), SocialOp.friendRequest),
          "Can't reach the server. Check your connection.");
    });
  });

  testWidgets('heartbeat: now, every 60 s in the foreground, stops in the background', (tester) async {
    final beats = <String?>[];
    String? game;
    final svc = PresenceService(({String? gameId}) async => beats.add(gameId), gameId: () => game);
    svc.start();
    expect(beats, [null]);
    await tester.pump(const Duration(seconds: 60));
    expect(beats, hasLength(2));
    game = 'ludo';
    await tester.pump(const Duration(seconds: 60));
    expect(beats.last, 'ludo');
    svc.onLifecycle(AppLifecycleState.inactive); // a system sheet: no change
    expect(svc.running, isTrue);
    svc.onLifecycle(AppLifecycleState.paused);
    expect(svc.running, isFalse);
    await tester.pump(const Duration(minutes: 5));
    expect(beats, hasLength(3));
    svc.onLifecycle(AppLifecycleState.resumed); // one at once on resume
    expect(beats, hasLength(4));
    svc.stop();
  });

  test('a failing heartbeat is ignored and not retried', () async {
    var calls = 0;
    final svc = PresenceService(({String? gameId}) async {
      calls++;
      throw const AppException('x');
    }, interval: const Duration(hours: 1));
    svc.start();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    svc.stop();
  });

  group('friends state', () {
    late ProviderContainer c;
    late DemoSocialApi api;

    setUp(() {
      api = DemoSocialApi();
      c = ProviderContainer(overrides: [
        useRemoteAuthProvider.overrideWithValue(false),
        socialApiProvider.overrideWithValue(api),
      ]);
    });
    tearDown(() => c.dispose());

    test('Add friend → Request sent; a duplicate also reads as sent', () async {
      await c.read(friendsProvider.future);
      expect(c.read(friendRelationProvider('demo-dustdevil')), FriendRelation.none);
      expect(await c.read(friendsProvider.notifier).add('demo-dustdevil'), FriendRelation.sent);
      expect(c.read(friendRelationProvider('demo-dustdevil')), FriendRelation.sent);
      // After a "restart" (local memory gone) the server says DUPLICATE.
      c.read(sentFriendRequestsProvider.notifier).forget('demo-dustdevil');
      await expectLater(c.read(friendsProvider.notifier).add('demo-dustdevil'),
          throwsA(isA<AppException>().having((e) => e.code, 'code', ApiErrorCode.duplicateFriendRequest)));
      expect(c.read(friendRelationProvider('demo-dustdevil')), FriendRelation.sent);
    });

    test('their request is pending → Accept instead of Add', () async {
      final s = await c.read(friendsProvider.future);
      expect(s.incomingTotal, 2);
      expect(c.read(friendRelationProvider('demo-echoray')), FriendRelation.incoming);
      expect(await c.read(friendsProvider.notifier).add('demo-echoray'), FriendRelation.friend);
      expect(c.read(friendRelationProvider('demo-echoray')), FriendRelation.friend);
      expect(c.read(friendsProvider).value!.incomingTotal, 1);
    });

    test('online first, then by name', () async {
      final s = await c.read(friendsProvider.future);
      final names = {'demo-zerocool': 'ZeroCool', 'demo-lunawolf': 'LunaWolf', 'demo-kaistorm': 'KaiStorm', 'demo-novabyte': 'NovaByte', 'demo-pixelfox': 'PixelFox'};
      expect(s.sorted((id) => names[id]!).map((f) => names[f.userId]),
          ['KaiStorm', 'LunaWolf', 'ZeroCool', 'NovaByte', 'PixelFox']);
    });

    test('block removes the friend and lists the player; unblock removes them', () async {
      await c.read(friendsProvider.future);
      await c.read(blockListProvider.notifier).load();
      await c.read(blockListProvider.notifier).block('demo-zerocool', card: const UserCard(userId: 'demo-zerocool', username: 'ZeroCool'));
      expect(c.read(friendsProvider).value!.isFriend('demo-zerocool'), isFalse);
      expect(c.read(friendRelationProvider('demo-zerocool')), FriendRelation.blocked);
      expect(c.read(blockListProvider)['demo-zerocool']!.card.name, 'ZeroCool');
      await c.read(blockListProvider.notifier).unblock('demo-zerocool');
      expect(c.read(friendRelationProvider('demo-zerocool')), FriendRelation.none);
    });

    test('name cache fetches unknown ids and seeds known cards', () async {
      final cache = c.read(playerNameCacheProvider.notifier);
      cache.seed([const UserCard(userId: 'x', username: 'Xavier')]);
      cache.seed([const UserCard(userId: 'x')]); // no name never replaces one
      cache.ensure(['demo-novabyte', 'x']);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(playerNameCacheProvider)['x']!.name, 'Xavier');
      expect(c.read(playerNameCacheProvider)['demo-novabyte']!.name, 'NovaByte');
    });
  });

  group('chat room', () {
    test('merge by id, newest poll, load older, blocked lines hidden', () async {
      final api = DemoSocialApi();
      final blocked = <String>{};
      final chat = ChatRoomController(api, type: ChatRoomType.lobby, roomId: 'ludo', pageSize: 1, isBlocked: blocked.contains);
      await chat.open();
      chat.stopPolling();
      expect(chat.messages.map((m) => m.body), ['Anyone up for a quick game?']);
      await chat.loadOlder();
      expect(chat.messages.map((m) => m.body), ['gg everyone', 'Anyone up for a quick game?']);
      await chat.send('hello');
      await chat.pollNewest(); // brings back the same line: no duplicate
      expect(chat.messages.where((m) => m.body == 'hello'), hasLength(1));
      blocked.add('demo-zerocool');
      chat.isBlocked = blocked.contains;
      expect(chat.messages.map((m) => m.body), isNot(contains('gg everyone')));
      await expectLater(chat.send('   '), throwsA(isA<AppException>()));
      chat.dispose();
    });

    test('a 403 on send disables the input', () async {
      final g = _Gateway({
        'GET /chat/lobby/x/history': (_) => (200, []),
        'POST /chat/lobby/x/send': (_) => _err(403, 'FORBIDDEN'),
      });
      final chat = ChatRoomController(RemoteSocialApi(_client(g)), type: ChatRoomType.lobby, roomId: 'x');
      await chat.open();
      chat.stopPolling();
      await expectLater(chat.send('hi'), throwsA(isA<AppException>()));
      expect(chat.sendDisabled, isTrue);
      chat.dispose();
    });
  });

  test('withoutBlocked hides blocked players from any list', () {
    final list = withoutBlocked(['a', 'b', 'c'], {'b': const BlockedUser(userId: 'b')}, (s) => s);
    expect(list, ['a', 'c']);
  });

  testWidgets('gift sheet refuses a blocked player', (tester) async {
    final api = DemoSocialApi();
    await api.block('demo-zerocool');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        useRemoteAuthProvider.overrideWithValue(false),
        socialApiProvider.overrideWithValue(api),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SendGiftSheet(recipientId: 'demo-zerocool', recipientName: 'ZeroCool')),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('You blocked this player'), findsOneWidget);
    expect(find.text('Send gift'), findsNothing);
  });

  testWidgets('gift sheet for a friend offers looks and Send', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        useRemoteAuthProvider.overrideWithValue(false),
        socialApiProvider.overrideWithValue(DemoSocialApi()),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SendGiftSheet(recipientId: 'demo-lunawolf', recipientName: 'LunaWolf')),
      ),
    ));
    await tester.pump();
    expect(find.text('Send gift'), findsOneWidget);
    expect(find.text('Rose'), findsOneWidget);
  });

  test('demo referral apply: own code, then once, then 409', () async {
    final s = StaticReferralSource();
    await expectLater(s.apply('demo2026'), throwsA(isA<AppException>().having((e) => e.code, 'code', 'BAD_REQUEST')));
    await s.apply('39uvkdvp');
    await expectLater(s.apply('39UVKDVP'), throwsA(isA<AppException>().having((e) => e.code, 'code', 'CONFLICT')));
  });
}
