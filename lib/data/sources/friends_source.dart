import '../../widgets/aura.dart' show AuraColors;
import '../models/friend.dart';

/// Friend suggestions. The gateway has no player search and no suggestion
/// route (docs/services/09-social.md "what the backend does not have"), so
/// only the offline demo shows any; the live app suggests nobody. Friends,
/// requests and presence come from `SocialApi` (lib/services/social_api.dart).
abstract class FriendsSource {
  Future<List<Friend>> suggested();
}

/// Demo suggestions (offline build).
class StaticFriendsSource implements FriendsSource {
  const StaticFriendsSource();

  @override
  Future<List<Friend>> suggested() async => const [
        Friend(userId: 'demo-dustdevil', name: 'DustDevil', level: 11, status: 'Played you recently', online: false, color: AuraColors.avatarGreen),
        Friend(userId: 'demo-soloace', name: 'SoloAce', level: 7, status: 'Played you recently', online: false, color: AuraColors.avatarPink),
        Friend(userId: 'demo-riftwalker', name: 'RiftWalker', level: 18, status: 'Played you recently', online: false, color: AuraColors.avatarPurple),
      ];
}

/// The live app: no suggestion route exists.
class NoFriendsSource implements FriendsSource {
  const NoFriendsSource();

  @override
  Future<List<Friend>> suggested() async => const [];
}
