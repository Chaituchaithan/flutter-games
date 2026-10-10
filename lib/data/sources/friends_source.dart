import '../../services/api_client.dart';
import '../../widgets/aura.dart' show AuraColors;
import '../models/friend.dart';
import '../../configs/endpoints/api_endpoints.dart';

/// Reads social lists. Implemented twice: [StaticFriendsSource] (bundled data,
/// today's behaviour) and [RemoteFriendsSource] (live API). The repository
/// picks one; see docs/SERVICES_AND_REALTIME.md.
abstract class FriendsSource {
  Future<List<Friend>> friends();
  Future<List<Friend>> requests();
  Future<List<Friend>> suggested();
}

/// The data that used to live inline in `friends_screen.dart`.
class StaticFriendsSource implements FriendsSource {
  const StaticFriendsSource();

  @override
  Future<List<Friend>> friends() async => const [
        Friend(name: 'ZeroCool', level: 9, status: 'In lobby', online: true, color: AuraColors.avatarBlue),
        Friend(name: 'LunaWolf', level: 6, status: 'Online', online: true, color: AuraColors.avatarPurple),
        Friend(name: 'KaiStorm', level: 21, status: 'In a match', online: true, color: AuraColors.avatarOrange),
        Friend(name: 'NovaByte', level: 12, status: 'Last seen 2h ago', online: false, color: AuraColors.avatarGreen),
        Friend(name: 'PixelFox', level: 4, status: 'Last seen yesterday', online: false, color: AuraColors.avatarPink),
      ];

  @override
  Future<List<Friend>> requests() async => const [
        Friend(name: 'EchoRay', level: 8, status: '2 mutual friends', online: false, color: AuraColors.avatarBlue),
        Friend(name: 'MysticJin', level: 15, status: '1 mutual friend', online: false, color: AuraColors.avatarOrange),
      ];

  @override
  Future<List<Friend>> suggested() async => const [
        Friend(name: 'DustDevil', level: 11, status: 'Played you recently', online: false, color: AuraColors.avatarGreen),
        Friend(name: 'SoloAce', level: 7, status: 'Played you recently', online: false, color: AuraColors.avatarPink),
        Friend(name: 'RiftWalker', level: 18, status: 'Played you recently', online: false, color: AuraColors.avatarPurple),
      ];
}

/// Live-API implementation. Wired but unused until remote sources are switched
/// on (`useRemoteSourcesProvider`). Endpoints per docs/SERVICES_AND_REALTIME.md.
class RemoteFriendsSource implements FriendsSource {
  const RemoteFriendsSource(this._api);
  final ApiClient _api;

  Future<List<Friend>> _list(String path) async {
    final data = await _api.get(path) as List<dynamic>;
    return data.map((e) => Friend.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<Friend>> friends() => _list(ApiEndpoints.friends);

  @override
  Future<List<Friend>> requests() => _list(ApiEndpoints.friendRequests);

  @override
  Future<List<Friend>> suggested() => _list(ApiEndpoints.friendSuggestions);
}
