import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/configs.dart';
import '../data/models/social.dart';
import '../data/models/wallet.dart';
import 'account_service.dart';
import 'api_client.dart';
import 'app_exception.dart';
import 'session.dart';

/// The social routes (docs/services/09-social.md): friends, presence, room
/// chat, gifts and blocks. Referrals live in `ReferralSource`
/// (lib/data/sources/referral_source.dart). Every method returns a typed
/// result or throws the shared [AppException]; [socialErrorText] turns one
/// into player text. Gift bodies are never logged.
abstract class SocialApi {
  // Friends (§1)
  Future<FriendRequest> sendFriendRequest(String toUserId);

  /// Incoming requests only, newest first.
  Future<PageList<FriendRequest>> incomingRequests({int page = 1, int perPage = 20});
  Future<void> acceptRequest(int requestId);
  Future<void> rejectRequest(int requestId);
  Future<PageList<FriendLink>> friends({int page = 1, int perPage = 20});

  /// `DELETE /friends/{id}`; a `404` (not friends any more) counts as done.
  Future<void> removeFriend(String userId);

  // Presence (§2)
  /// `POST /presence/heartbeat`; [gameId] while in a game (1-32 of
  /// `[A-Za-z0-9_-]`, anything else is left out).
  Future<void> heartbeat({String? gameId});
  Future<FriendsOnline> friendsOnline();
  Future<int> onlineCount();

  // Chat (§3)
  Future<ChatMessage> sendChat(ChatRoomType type, String roomId, String body);

  /// Newest first; [before] = a message id (exclusive).
  Future<List<ChatMessage>> chatHistory(ChatRoomType type, String roomId, {int count = 50, String? before});

  // Gifts (§4)
  /// [idempotencyKey]: a new UUID per send attempt, reused on a retry of it.
  /// No network / a timeout retries once with the same key.
  Future<Gift> sendGift({
    required String receiverId,
    required String itemType,
    required String itemId,
    required int amount,
    required WalletCurrency currency,
    String? message,
    required String idempotencyKey,
  });
  Future<PageList<Gift>> giftsReceived({int page = 1, int perPage = 20});
  Future<PageList<Gift>> giftsSent({int page = 1, int perPage = 20});

  // Blocks (§6)
  /// `POST /blocks/{id}`; `409` (already blocked) counts as done.
  Future<void> block(String userId);

  /// `DELETE /blocks/{id}`; `404` (not blocked) counts as done.
  Future<void> unblock(String userId);
  Future<PageList<BlockedUser>> blocks({int page = 1, int perPage = 20});

  /// A player's name and avatar for the name cache (`GET /users/{id}/profile`).
  Future<UserCard> playerCard(String userId);
}

/// `game_id` rule for the heartbeat (§2a).
final _gameIdRule = RegExp(r'^[A-Za-z0-9_-]{1,32}$');
bool validHeartbeatGameId(String? id) => id != null && _gameIdRule.hasMatch(id);

Map<String, dynamic> _map(Object? body) =>
    body is Map ? body.cast<String, dynamic>() : throw const AppException('Something went wrong. Try again.');

class RemoteSocialApi implements SocialApi {
  RemoteSocialApi(this._api, {AccountApi? profiles, this.retryDelay = const Duration(seconds: 2)})
      : _profiles = profiles ?? RemoteAccountApi(_api);
  final ApiClient _api;
  final AccountApi _profiles;

  /// Wait before the one gift retry.
  final Duration retryDelay;

  static Map<String, dynamic> _page(int page, int perPage) => {'page': page, 'per_page': perPage.clamp(1, 100)};

  @override
  Future<FriendRequest> sendFriendRequest(String toUserId) async =>
      FriendRequest.fromJson(_map(await _api.post(ApiEndpoints.friendRequest, body: {'to_user_id': toUserId})));

  @override
  Future<PageList<FriendRequest>> incomingRequests({int page = 1, int perPage = 20}) async =>
      PageList.fromJson(await _api.get(ApiEndpoints.friendRequestsPending, query: _page(page, perPage)), FriendRequest.fromJson);

  @override
  Future<void> acceptRequest(int requestId) async {
    await _api.post(ApiEndpoints.friendRequestAccept(requestId));
  }

  @override
  Future<void> rejectRequest(int requestId) async {
    await _api.post(ApiEndpoints.friendRequestReject(requestId));
  }

  @override
  Future<PageList<FriendLink>> friends({int page = 1, int perPage = 20}) async =>
      PageList.fromJson(await _api.get(ApiEndpoints.friends, query: _page(page, perPage)), FriendLink.fromJson);

  @override
  Future<void> removeFriend(String userId) async {
    try {
      await _api.delete(ApiEndpoints.friend(userId));
    } on AppException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
  }

  @override
  Future<void> heartbeat({String? gameId}) async {
    // The body must be JSON: `{}` when there is nothing else.
    await _api.post(ApiEndpoints.presenceHeartbeat, body: {if (validHeartbeatGameId(gameId)) 'game_id': gameId});
  }

  @override
  Future<FriendsOnline> friendsOnline() async => FriendsOnline.fromJson(_map(await _api.get(ApiEndpoints.presenceFriendsOnline)));

  @override
  Future<int> onlineCount() async {
    final n = _map(await _api.get(ApiEndpoints.presenceOnlineCount))['global_count'];
    return n is num ? n.toInt() : 0;
  }

  @override
  Future<ChatMessage> sendChat(ChatRoomType type, String roomId, String body) async =>
      ChatMessage.fromJson(_map(await _api.post(ApiEndpoints.chatSend(type.wire, roomId), body: {'body': body})));

  @override
  Future<List<ChatMessage>> chatHistory(ChatRoomType type, String roomId, {int count = 50, String? before}) async {
    final res = await _api.get(ApiEndpoints.chatHistory(type.wire, roomId),
        query: {'count': count.clamp(1, 200), 'before': ?before});
    final raw = res is List ? res : const [];
    return [for (final e in raw) if (e is Map) ChatMessage.fromJson(e.cast<String, dynamic>())];
  }

  @override
  Future<Gift> sendGift({
    required String receiverId,
    required String itemType,
    required String itemId,
    required int amount,
    required WalletCurrency currency,
    String? message,
    required String idempotencyKey,
  }) async {
    final body = {
      'receiver_id': receiverId,
      'item_type': itemType,
      'item_id': itemId,
      'amount': amount,
      'currency': currency.wire,
      if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
    };
    Future<Gift> send() async =>
        Gift.fromJson(_map(await _api.post(ApiEndpoints.giftsSend, body: body, headers: {'Idempotency-Key': idempotencyKey})));
    try {
      return await send();
    } on AppException catch (e) {
      // It may have gone through: retry ONCE with the same key; the server
      // replays the first gift instead of sending twice.
      if (!(e.isOffline || e.kind == AppErrorKind.timeout)) rethrow;
      await Future<void>.delayed(retryDelay);
      return await send();
    }
  }

  @override
  Future<PageList<Gift>> giftsReceived({int page = 1, int perPage = 20}) async =>
      PageList.fromJson(await _api.get(ApiEndpoints.giftsReceived, query: _page(page, perPage)), Gift.fromJson);

  @override
  Future<PageList<Gift>> giftsSent({int page = 1, int perPage = 20}) async =>
      PageList.fromJson(await _api.get(ApiEndpoints.giftsSent, query: _page(page, perPage)), Gift.fromJson);

  @override
  Future<void> block(String userId) async {
    try {
      await _api.post(ApiEndpoints.block(userId));
    } on AppException catch (e) {
      if (e.code != ApiErrorCode.conflict) rethrow;
    }
  }

  @override
  Future<void> unblock(String userId) async {
    try {
      await _api.delete(ApiEndpoints.block(userId));
    } on AppException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
  }

  @override
  Future<PageList<BlockedUser>> blocks({int page = 1, int perPage = 20}) async =>
      PageList.fromJson(await _api.get(ApiEndpoints.blocks, query: _page(page, perPage)), BlockedUser.fromJson);

  @override
  Future<UserCard> playerCard(String userId) async {
    final p = await _profiles.playerProfile(userId);
    return UserCard(userId: userId, username: p.isDeleted ? 'Deleted player' : p.displayName, avatarUrl: p.avatarUrl);
  }
}

/// Offline demo (no server): a small in-memory social graph so every screen
/// works. Mirrors the server's rules closely enough to exercise the UI.
class DemoSocialApi implements SocialApi {
  DemoSocialApi();

  static const me = 'me';
  static const _names = {
    'demo-zerocool': 'ZeroCool',
    'demo-lunawolf': 'LunaWolf',
    'demo-kaistorm': 'KaiStorm',
    'demo-novabyte': 'NovaByte',
    'demo-pixelfox': 'PixelFox',
    'demo-echoray': 'EchoRay',
    'demo-mysticjin': 'MysticJin',
  };
  static const _online = {'demo-zerocool', 'demo-lunawolf', 'demo-kaistorm'};

  final _friends = <String>['demo-zerocool', 'demo-lunawolf', 'demo-kaistorm', 'demo-novabyte', 'demo-pixelfox'];
  final _incoming = <FriendRequest>[
    const FriendRequest(id: 2, fromUserId: 'demo-echoray', toUserId: me),
    const FriendRequest(id: 1, fromUserId: 'demo-mysticjin', toUserId: me),
  ];
  final _sent = <String>{};
  final _blocked = <String, BlockedUser>{};
  final _chat = <String, List<ChatMessage>>{};
  final _gifts = <Gift>[];
  var _seq = 10;

  static AppException _err(int status, String code) => AppException('', statusCode: status, code: code);

  PageList<T> _pageOf<T>(List<T> all, int page, int perPage) {
    final start = ((page - 1) * perPage).clamp(0, all.length);
    final end = (start + perPage).clamp(0, all.length);
    return PageList(
      data: all.sublist(start, end),
      total: all.length,
      page: page,
      perPage: perPage,
      totalPages: (all.length / perPage).ceil(),
    );
  }

  @override
  Future<FriendRequest> sendFriendRequest(String toUserId) async {
    if (toUserId == me) throw _err(400, ApiErrorCode.validation);
    if (_blocked.containsKey(toUserId)) throw _err(409, ApiErrorCode.userBlocked);
    if (_friends.contains(toUserId)) throw _err(409, ApiErrorCode.conflict);
    if (_sent.contains(toUserId) || _incoming.any((r) => r.fromUserId == toUserId)) {
      throw _err(409, ApiErrorCode.duplicateFriendRequest);
    }
    _sent.add(toUserId);
    return FriendRequest(id: ++_seq, fromUserId: me, toUserId: toUserId, createdAt: DateTime.now());
  }

  @override
  Future<PageList<FriendRequest>> incomingRequests({int page = 1, int perPage = 20}) async =>
      _pageOf(List.of(_incoming), page, perPage);

  FriendRequest _take(int id) {
    final i = _incoming.indexWhere((r) => r.id == id);
    if (i < 0) throw _err(404, ApiErrorCode.notFound);
    return _incoming.removeAt(i);
  }

  @override
  Future<void> acceptRequest(int requestId) async => _friends.insert(0, _take(requestId).fromUserId);

  @override
  Future<void> rejectRequest(int requestId) async => _take(requestId);

  @override
  Future<PageList<FriendLink>> friends({int page = 1, int perPage = 20}) async =>
      _pageOf([for (final id in _friends) FriendLink(userId: id)], page, perPage);

  @override
  Future<void> removeFriend(String userId) async => _friends.remove(userId);

  @override
  Future<void> heartbeat({String? gameId}) async {}

  @override
  Future<FriendsOnline> friendsOnline() async {
    final ids = [for (final id in _friends) if (_online.contains(id)) id];
    return FriendsOnline(onlineIds: ids, friends: [for (final id in ids) UserCard(userId: id, username: _names[id])]);
  }

  @override
  Future<int> onlineCount() async => 128;

  @override
  Future<ChatMessage> sendChat(ChatRoomType type, String roomId, String body) async {
    final t = body.trim();
    if (t.isEmpty || t.length > 2000) throw const AppException('', statusCode: 400, code: ApiErrorCode.validation, field: 'body');
    final m = ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}-${_seq++}',
      roomType: type.wire,
      roomId: roomId,
      senderUserId: me,
      body: t,
      createdAt: DateTime.now().toUtc(),
    );
    (_chat['${type.wire}/$roomId'] ??= _seed(type, roomId)).insert(0, m);
    return m;
  }

  List<ChatMessage> _seed(ChatRoomType type, String roomId) {
    final now = DateTime.now().toUtc();
    return [
      ChatMessage(id: '2-0', roomType: type.wire, roomId: roomId, senderUserId: 'demo-lunawolf', body: 'Anyone up for a quick game?', createdAt: now.subtract(const Duration(minutes: 2))),
      ChatMessage(id: '1-0', roomType: type.wire, roomId: roomId, senderUserId: 'demo-zerocool', body: 'gg everyone', createdAt: now.subtract(const Duration(minutes: 5))),
    ];
  }

  @override
  Future<List<ChatMessage>> chatHistory(ChatRoomType type, String roomId, {int count = 50, String? before}) async {
    final all = _chat['${type.wire}/$roomId'] ??= _seed(type, roomId);
    var start = 0;
    if (before != null) {
      final i = all.indexWhere((m) => m.id == before);
      start = i < 0 ? all.length : i + 1;
    }
    return all.sublist(start, (start + count).clamp(0, all.length));
  }

  @override
  Future<Gift> sendGift({
    required String receiverId,
    required String itemType,
    required String itemId,
    required int amount,
    required WalletCurrency currency,
    String? message,
    required String idempotencyKey,
  }) async {
    if (amount < 1) throw const AppException('', statusCode: 400, code: ApiErrorCode.validation, field: 'amount');
    if (receiverId == me) throw _err(400, ApiErrorCode.validation);
    final have = Wallet.demo.of(currency.currency);
    if (amount > have) throw _err(409, ApiErrorCode.insufficientFunds);
    final g = Gift(
      id: 'demo-gift-${_seq++}',
      senderId: me,
      receiverId: receiverId,
      itemType: itemType,
      itemId: itemId,
      amount: amount,
      currency: currency,
      message: message,
      createdAt: DateTime.now().toUtc(),
    );
    _gifts.insert(0, g);
    return g;
  }

  @override
  Future<PageList<Gift>> giftsReceived({int page = 1, int perPage = 20}) async => _pageOf([
        Gift(
          id: 'demo-gift-1',
          senderId: 'demo-zerocool',
          receiverId: me,
          itemType: 'rose',
          itemId: 'rose',
          amount: 5,
          currency: WalletCurrency.gold,
          message: 'Good game!',
          createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
        ),
      ], page, perPage);

  @override
  Future<PageList<Gift>> giftsSent({int page = 1, int perPage = 20}) async => _pageOf(List.of(_gifts), page, perPage);

  @override
  Future<void> block(String userId) async {
    if (userId == me) throw _err(400, ApiErrorCode.validation);
    _friends.remove(userId);
    _incoming.removeWhere((r) => r.fromUserId == userId);
    _sent.remove(userId);
    _blocked[userId] = BlockedUser(userId: userId, username: _names[userId], createdAt: DateTime.now().toUtc());
  }

  @override
  Future<void> unblock(String userId) async => _blocked.remove(userId);

  @override
  Future<PageList<BlockedUser>> blocks({int page = 1, int perPage = 20}) async =>
      _pageOf(_blocked.values.toList().reversed.toList(), page, perPage);

  @override
  Future<UserCard> playerCard(String userId) async => UserCard(userId: userId, username: _names[userId] ?? 'Player');
}

/// The live API while signed in against the real server; the demo otherwise.
final socialApiProvider = Provider<SocialApi>((ref) {
  final live = ref.watch(useRemoteAuthProvider) && ref.watch(sessionProvider.select((u) => u != null));
  return live ? RemoteSocialApi(ref.watch(apiClientProvider), profiles: ref.watch(accountApiProvider)) : DemoSocialApi();
});

/// What the player was doing when an error came back: the same code means
/// different things on different routes (09-social.md error tables).
enum SocialOp { load, friendRequest, answerRequest, removeFriend, chatSend, matchChat, gift, block, unblock, referralApply }

/// Player-facing text for a social-route error. Decides on status + code,
/// never on the server's `message`.
String socialErrorText(AppException e, SocialOp op, {WalletCurrency? currency}) {
  if (e.isOffline || e.kind == AppErrorKind.timeout) return "Can't reach the server. Check your connection.";
  final code = e.code;
  if (code == ApiErrorCode.rateLimited) return 'Too many requests. Try again in a minute.';
  if (code == ApiErrorCode.killSwitch) return e.message.isEmpty ? 'Sending is paused right now.' : e.message;
  switch (op) {
    case SocialOp.friendRequest:
      return switch (code) {
        ApiErrorCode.forbidden => "This player isn't accepting friend requests.",
        ApiErrorCode.notFound => 'Player not found.',
        ApiErrorCode.userBlocked => "You can't add this player.",
        ApiErrorCode.conflict => "You're already friends.",
        ApiErrorCode.duplicateFriendRequest => 'Request already sent',
        _ => _generic(e),
      };
    case SocialOp.answerRequest:
      return code == ApiErrorCode.notFound ? 'This request is no longer open.' : _generic(e);
    case SocialOp.removeFriend || SocialOp.unblock || SocialOp.load:
      return _generic(e);
    case SocialOp.chatSend || SocialOp.matchChat:
      if (code == ApiErrorCode.validation && e.field == 'body') return 'Messages must be 1 to 2000 characters.';
      if (code == ApiErrorCode.forbidden) {
        return op == SocialOp.matchChat ? 'Only players in this match can chat here.' : "You can't chat right now.";
      }
      return _generic(e);
    case SocialOp.gift:
      return switch (code) {
        ApiErrorCode.validation when e.field == 'amount' => 'Enter an amount of 1 or more.',
        ApiErrorCode.notFound => "That player can't receive gifts.",
        ApiErrorCode.insufficientFunds => 'Not enough ${(currency ?? WalletCurrency.gold).noun}.',
        ApiErrorCode.giftQuotaExceeded => "You've reached today's gift limit.",
        _ => _generic(e),
      };
    case SocialOp.block:
      // Blocking an unknown player answers 500 DATABASE_ERROR (Known issues 5).
      if (code == ApiErrorCode.databaseError || code == ApiErrorCode.notFound) return 'Player not found.';
      return _generic(e);
    case SocialOp.referralApply:
      return switch (code) {
        ApiErrorCode.validation => 'Enter a code.',
        ApiErrorCode.badRequest => "You can't use this code.",
        ApiErrorCode.notFound => 'Code not found.',
        ApiErrorCode.conflict => "You've already used a referral code.",
        _ => _generic(e),
      };
  }
}

/// Session codes keep the client's "Your session has ended…"; everything
/// else (app bugs, server faults) is the generic text.
String _generic(AppException e) =>
    e.statusCode == 401 && e.message.isNotEmpty ? e.message : 'Something went wrong. Try again.';
