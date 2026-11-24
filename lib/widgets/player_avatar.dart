import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/friend.dart' show Friend;
import '../services/account_store.dart';
import '../services/session.dart';
import 'aura_widgets.dart';

/// Where avatar images would be served from (02-profile-and-sessions.md §3).
/// Nothing serves `avatar_url` today (Known issues 1), so this is empty and
/// avatars draw as a coloured disc with the glyph. Set with
/// `--dart-define=AVATAR_BASE_URL=https://cdn.example.com` once a host exists.
const avatarAssetBase = String.fromEnvironment('AVATAR_BASE_URL');

/// The colour drawn for an avatar, from its catalogue code or its
/// `avatar_url` (`default_red`, `/assets/avatars/default/red.svg`, …).
/// Codes with no known colour get a stable colour from the code.
Color avatarColor({String? code, String? url, String fallbackName = ''}) {
  final key = (code ?? url ?? '').toLowerCase();
  const named = <String, Color>{
    'blue': Color(0xFF3B82F6),
    'green': Color(0xFF22C55E),
    'red': Color(0xFFEF4444),
    'purple': Color(0xFF8B5CF6),
    'orange': Color(0xFFF97316),
    'yellow': Color(0xFFEAB308),
    'teal': Color(0xFF14B8A6),
    'pink': Color(0xFFEC4899),
    'gold': Color(0xFFF59E0B),
  };
  for (final e in named.entries) {
    if (key.contains(e.key)) return e.value;
  }
  return Friend.colorForName(key.isEmpty ? fallbackName : key);
}

/// An avatar disc: the image at [avatarAssetBase] + [avatarUrl] when a host
/// is configured, else (and as the placeholder) the [glyph] over the
/// avatar's colour.
class AvatarDisc extends StatelessWidget {
  const AvatarDisc({
    super.key,
    required this.glyph,
    this.avatarUrl,
    this.code,
    this.name = '',
    this.size = 44,
    this.glow = false,
  });

  final String glyph;
  final String? avatarUrl;
  final String? code;
  final String name;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final color = (avatarUrl == null && code == null)
        ? Friend.colorForName(name)
        : avatarColor(code: code, url: avatarUrl, fallbackName: name);
    final letters = LetterAvatar(letter: glyph, color: color, size: size, glow: glow);
    final url = avatarUrl;
    if (avatarAssetBase.isEmpty || url == null || url.isEmpty || url.endsWith('.svg')) return letters;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network('$avatarAssetBase$url',
            fit: BoxFit.cover, errorBuilder: (_, _, _) => letters, frameBuilder: (_, child, frame, sync) => frame == null && !sync ? letters : child),
      ),
    );
  }
}

/// The signed-in player's avatar (picked avatar + glyph from `GET /users/me`).
class MyAvatar extends ConsumerWidget {
  const MyAvatar({super.key, this.size = 44, this.glow = false});
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final me = ref.watch(accountStoreProvider);
    final glyph = me != null && me.id == user.id ? me.glyph : user.initials;
    return AvatarDisc(glyph: glyph, avatarUrl: user.avatarUrl, name: user.displayName, size: size, glow: glow);
  }
}
