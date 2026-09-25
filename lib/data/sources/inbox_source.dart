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
        InboxMessage(kind: InboxKind.challenge, title: 'ZeroCool challenged you', body: 'Online 1v1 · 200 Tokens stake. Tap to accept.', when: '2m', action: 'Accept', unread: true),
        InboxMessage(kind: InboxKind.tournament, title: 'Neon Cup starts soon', body: 'Round of 16 begins in 2h · you are seed #12.', when: '18m', action: 'View bracket', unread: true),
        InboxMessage(kind: InboxKind.friendRequest, title: 'LunaWolf sent a friend request', body: 'You have 3 mutual friends.', when: '1h', action: 'Respond', unread: true),
        InboxMessage(kind: InboxKind.dailyBonus, title: 'Daily bonus ready', body: 'Day 3 reward is waiting — claim 250 Gold.', when: '5h'),
        InboxMessage(kind: InboxKind.payout, title: 'Victory payout', body: 'You won 800 Tokens in match #4821.', when: 'Yesterday'),
        InboxMessage(kind: InboxKind.announcement, title: 'Season 4 · Neon Tide is live', body: '40 new rewards and 4-player rooms. See what changed.', when: '2d'),
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
