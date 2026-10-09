import '../../services/api_client.dart';
import '../models/inbox_message.dart';

/// Inbox notifications.
abstract class InboxSource {
  Future<List<InboxMessage>> messages();
}

/// The seed that used to live inline in `inbox_screen.dart`.
class StaticInboxSource implements InboxSource {
  const StaticInboxSource();

  @override
  Future<List<InboxMessage>> messages() async => const [
        InboxMessage(kind: InboxKind.invite, title: 'ZeroCool invited you', body: 'Room AX7 K2Q · 4P · 200 Tokens', when: '2m', action: 'Join', unread: true),
        InboxMessage(kind: InboxKind.result, title: 'Victory vs NeonViper', body: '+250 Tokens · +50 XP', when: '18m', unread: true),
        InboxMessage(kind: InboxKind.dailyBonus, title: 'Daily bonus ready', body: 'Day 3 · 250 Gold waiting', when: '1h', action: 'Claim', unread: true),
        InboxMessage(kind: InboxKind.tournament, title: 'Neon Cup starts soon', body: 'You are seeded #12 · Round of 16', when: '3h', action: 'View', unread: true),
        InboxMessage(kind: InboxKind.friendRequest, title: 'LunaWolf sent a friend request', body: 'LV 7 · 3 mutual friends', when: 'Yesterday', action: 'Accept', unread: true),
        InboxMessage(kind: InboxKind.shop, title: 'Weekend 2× Tokens', body: 'All token packs doubled until Sunday', when: 'Yesterday', action: 'Shop', unread: true),
      ];
}

/// Live-API implementation (off until remote sources are switched on).
class RemoteInboxSource implements InboxSource {
  const RemoteInboxSource(this._api);
  final ApiClient _api;

  @override
  Future<List<InboxMessage>> messages() async {
    final data = await _api.get('/inbox') as List<dynamic>;
    return data.map((e) => InboxMessage.fromJson(e as Map<String, dynamic>)).toList();
  }
}
