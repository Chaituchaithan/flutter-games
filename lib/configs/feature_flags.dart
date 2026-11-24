/// On/off switches. Compile-time constants for build-level switches; Riverpod
/// providers for data switches so tests can override them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'build_overrides.dart';
import 'games/core/game_id.dart';

/// MASTER SWITCH for the realtime socket ("turn on/off socket").
///
/// `true`  = login → socket `auth.login` → Home only on `auth.login_success`;
///           Online Play uses the live game service.
/// `false` = BYPASS: login goes straight to Home without the socket, and Online
///           Play opens the offline practice board.
/// Override one run with `--dart-define=SOCKET_ENABLED=true|false`.
const bool socketEnabledByDefault = true;

/// Game servers that are running and documented (00-conventions.md
/// "Servers": Ludo on `ws://<host>:1285/ws`; snake-and-ladder.md: Snake &
/// Ladder on `ws://<host>:1292/ws`). Add a game when its hand-off file gives
/// its server.
const Set<GameId> liveSocketGames = {GameId.ludo, GameId.snakesLadders};

/// The game server the app signs in to right after login when the active
/// game has no live server yet.
const GameId signInSocketGame = GameId.ludo;

const bool kSocketEnabled =
    BuildOverrides.socketEnabled == '' ? socketEnabledByDefault : BuildOverrides.socketEnabled == 'true';

/// Data domains (friends / leaderboard / wallet / store / tournaments / inbox /
/// history): static → live API. Stays `false` until each domain's response
/// shape is verified against the live API.
final useRemoteSourcesProvider = Provider<bool>((ref) => false);

/// Auth + profile use the live API (login/register/refresh/logout,
/// /users/me, /users/{id}/profile). Override to `false` for an offline demo.
///
/// `--dart-define=DEMO=true`: an offline demo build (no server needed; the
/// demo player signs in and Quick Play works).
const bool kDemoBuild = bool.fromEnvironment('DEMO');
final useRemoteAuthProvider = Provider<bool>((ref) => !kDemoBuild);
