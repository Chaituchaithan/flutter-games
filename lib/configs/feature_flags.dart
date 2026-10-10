/// On/off switches. Compile-time constants for build-level switches; Riverpod
/// providers for data switches so tests can override them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'build_overrides.dart';

/// MASTER SWITCH for the realtime socket ("turn on/off socket").
///
/// `true`  = login → socket `auth.login` → Home only on `auth.login_success`;
///           Online Play uses the live game service.
/// `false` = BYPASS: login goes straight to Home without the socket, and Online
///           Play opens the offline practice board.
/// Override one run with `--dart-define=SOCKET_ENABLED=true|false`.
const bool socketEnabledByDefault = true;

const bool kSocketEnabled =
    BuildOverrides.socketEnabled == '' ? socketEnabledByDefault : BuildOverrides.socketEnabled == 'true';

/// Data domains (friends / leaderboard / wallet / store / tournaments / inbox /
/// history): static → live API. Stays `false` until each domain's response
/// shape is verified against the live API.
final useRemoteSourcesProvider = Provider<bool>((ref) => false);

/// Auth + profile use the live API (login/register/refresh/logout,
/// /users/me, /users/{id}/profile). Override to `false` for an offline demo.
final useRemoteAuthProvider = Provider<bool>((ref) => true);
