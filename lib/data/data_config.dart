import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Master switch for the **data domains** static → dynamic migration
/// (friends / leaderboard / wallet / store / tournaments / inbox / history).
///
/// Stays `false` until each domain's real response shape is verified against the
/// live API (list `{data:[…]}` envelope + snake_case fields). See
/// docs/INTEGRATION_PLAN.md §7b. Auth is switched separately below.
final useRemoteSourcesProvider = Provider<bool>((ref) => false);

/// Auth is the primary integration and is verified against the Portal Gateway
/// API, so it defaults to the **live** service (login/register/refresh/logout
/// hit `${API_BASE_URL}/auth/*`; the user is read from `/users/me`). Override to
/// `false` for a fully offline/demo build. See docs/INTEGRATION_PLAN.md §7b.
final useRemoteAuthProvider = Provider<bool>((ref) => true);
