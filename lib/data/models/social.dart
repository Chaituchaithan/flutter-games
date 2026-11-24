import 'package:flutter/material.dart';

import '../../utils/amount.dart';
import 'wallet.dart';

/// Wire models for the social routes (docs/services/09-social.md). Parsing is
/// lenient: unknown fields are ignored, missing ones fall back to defaults.

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;
String _str(Object? v) => v == null ? '' : v.toString();
String? _strOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;
int _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 0 : 0);

Map<String, dynamic> _obj(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};

/// Page list shape 2 (00-conventions.md "Lists"):
/// `{data, total, page, per_page, total_pages}`.
@immutable
class PageList<T> {
  const PageList({required this.data, this.total = 0, this.page = 1, this.perPage = 20, this.totalPages = 0});

  final List<T> data;
  final int total;
  final int page;
  final int perPage;
  final int totalPages;

  /// More pages after this one.
  bool get hasMore => page < totalPages;

  factory PageList.fromJson(Object? body, T Function(Map<String, dynamic>) item) {
    final j = _obj(body);
    final raw = j['data'] is List ? j['data'] as List : (body is List ? body : const []);
    final data = [for (final e in raw) if (e is Map) item(e.cast<String, dynamic>())];
    return PageList(
      data: data,
      total: j.containsKey('total') ? _int(j['total']) : data.length,
      page: j.containsKey('page') ? _int(j['page']) : 1,
      perPage: j.containsKey('per_page') ? _int(j['per_page']) : data.length,
      totalPages: j.containsKey('total_pages') ? _int(j['total_pages']) : (data.isEmpty ? 0 : 1),
    );
  }
}

/// A friend request (`POST /friends/request`, `GET /friends/requests/pending`).
/// [id] is a number, unlike player ids.
@immutable
class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    this.status = 'pending',
    this.createdAt,
    this.respondedAt,
  });

  final int id;
  final String fromUserId;
  final String toUserId;

  /// `pending`, `accepted`, `declined` or `cancelled`.
  final String status;
  final DateTime? createdAt;
  final DateTime? respondedAt;

  bool get pending => status == 'pending';

  factory FriendRequest.fromJson(Map<String, dynamic> j) => FriendRequest(
        id: _int(j['id']),
        fromUserId: _str(j['from_user_id']),
        toUserId: _str(j['to_user_id']),
        status: _str(j['status']).isEmpty ? 'pending' : _str(j['status']),
        createdAt: _time(j['created_at']),
        respondedAt: _time(j['responded_at']),
      );
}

/// One row of `GET /friends`: ids only (names come from [UserCard]s).
@immutable
class FriendLink {
  const FriendLink({required this.userId, this.createdAt});

  final String userId;

  /// When the two became friends.
  final DateTime? createdAt;

  factory FriendLink.fromJson(Map<String, dynamic> j) =>
      FriendLink(userId: _str(j['user_id']), createdAt: _time(j['created_at']));
}

/// A player's name and avatar, from `/presence/friends-online`, `/blocks` or
/// `GET /users/{id}/profile`. Both may be null on the wire.
@immutable
class UserCard {
  const UserCard({required this.userId, this.username, this.avatarUrl});

  final String userId;
  final String? username;
  final String? avatarUrl;

  /// The name to draw ("Player" when the server has none).
  String get name => (username == null || username!.trim().isEmpty) ? 'Player' : username!;

  factory UserCard.fromJson(Map<String, dynamic> j) => UserCard(
        userId: _str(j['user_id']),
        username: _strOrNull(j['username']) ?? _strOrNull(j['display_name']),
        avatarUrl: _strOrNull(j['avatar_url']),
      );
}

/// `GET /presence/friends-online`.
@immutable
class FriendsOnline {
  const FriendsOnline({this.onlineIds = const [], this.friends = const []});

  /// Ids of friends with a heartbeat in the last 120 s (kept for old clients).
  final List<String> onlineIds;

  /// The same players, with name and avatar. Prefer these.
  final List<UserCard> friends;

  Set<String> get ids => {...onlineIds, for (final f in friends) f.userId};

  factory FriendsOnline.fromJson(Map<String, dynamic> j) => FriendsOnline(
        onlineIds: [for (final e in (j['online_friends'] is List ? j['online_friends'] as List : const [])) _str(e)],
        friends: [
          for (final e in (j['friends'] is List ? j['friends'] as List : const []))
            if (e is Map) UserCard.fromJson(e.cast<String, dynamic>()),
        ],
      );
}

/// Chat room kinds (§3). Anything else is a `400`.
enum ChatRoomType {
  lobby,
  global,
  match;

  String get wire => name;
}

/// A chat line (`POST /chat/.../send`, `GET /chat/.../history`).
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomType,
    required this.roomId,
    required this.senderUserId,
    required this.body,
    this.createdAt,
  });

  /// `<epoch ms>-<n>`: the list key and the paging cursor. Never parsed.
  final String id;
  final String roomType;
  final String roomId;
  final String senderUserId;
  final String body;
  final DateTime? createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: _str(j['id']),
        roomType: _str(j['room_type']),
        roomId: _str(j['room_id']),
        senderUserId: _str(j['sender_user_id']),
        body: _str(j['body']),
        createdAt: _time(j['created_at']),
      );
}

/// A gift (§4): money with a label. [amount] may be a number or a string.
@immutable
class Gift {
  const Gift({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.itemType,
    required this.itemId,
    required this.amount,
    required this.currency,
    this.message,
    this.createdAt,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final String itemType;
  final String itemId;
  final int amount;
  final WalletCurrency currency;
  final String? message;
  final DateTime? createdAt;

  factory Gift.fromJson(Map<String, dynamic> j) => Gift(
        id: _str(j['id']),
        senderId: _str(j['sender_id']),
        receiverId: _str(j['receiver_id']),
        itemType: _str(j['item_type']),
        itemId: _str(j['item_id']),
        amount: parseAmount(j['amount']),
        currency: WalletCurrency.tryParse(j['currency']) ?? WalletCurrency.gold,
        message: _strOrNull(j['message']),
        createdAt: _time(j['created_at']),
      );
}

/// One row of `GET /blocks`: a player I blocked, with their name.
@immutable
class BlockedUser {
  const BlockedUser({required this.userId, this.username, this.avatarUrl, this.createdAt});

  final String userId;
  final String? username;
  final String? avatarUrl;
  final DateTime? createdAt;

  UserCard get card => UserCard(userId: userId, username: username, avatarUrl: avatarUrl);

  factory BlockedUser.fromJson(Map<String, dynamic> j) => BlockedUser(
        userId: _str(j['user_id'] ?? j['blocked_id']),
        username: _strOrNull(j['username']),
        avatarUrl: _strOrNull(j['avatar_url']),
        createdAt: _time(j['created_at']),
      );
}

/// The gift looks the app offers (§4 "Suggested app use"). Sent as both
/// `item_type` and `item_id`; the server doesn't check them.
enum GiftLook {
  rose('rose', 'Rose', Icons.local_florist_rounded),
  cake('cake', 'Cake', Icons.cake_rounded),
  trophy('trophy', 'Trophy', Icons.emoji_events_rounded);

  const GiftLook(this.wire, this.label, this.icon);
  final String wire;
  final String label;
  final IconData icon;

  /// The look for a received `item_type` (a plain currency gift → null).
  static GiftLook? of(String itemType) {
    for (final l in values) {
      if (l.wire == itemType) return l;
    }
    return null;
  }
}
