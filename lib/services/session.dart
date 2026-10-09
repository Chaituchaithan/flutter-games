import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/user.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'token_store.dart';

/// Holds the signed-in [User] (null when logged out) and drives auth actions.
/// Persists the token best-effort so a session survives a restart. See
/// docs/INTEGRATION_PLAN.md §5.
class SessionController extends Notifier<User?> {
  /// Latest opaque refresh token (7-day, rotated) for /auth/refresh.
  String? _refreshToken;

  @override
  User? build() => null;

  Future<void> _apply(AuthResult r) async {
    // Only replace the access token when the call actually returned one (e.g.
    // OTP verify returns no token pair and must keep the current session).
    if (r.accessToken.isNotEmpty) {
      ref.read(apiClientProvider).authToken = r.accessToken;
      _refreshToken = r.refreshToken ?? _refreshToken;
      await ref.read(tokenStoreProvider).save(access: r.accessToken, refresh: _refreshToken);
    }
    state = r.user;
  }

  Future<User> login({required String email, required String password}) async {
    final r = await ref.read(authServiceProvider).login(email: email, password: password);
    await _apply(r);
    return r.user;
  }

  Future<User> register({required String name, required String email, required String password}) async {
    final r = await ref.read(authServiceProvider).register(name: name, email: email, password: password);
    await _apply(r);
    return r.user;
  }

  /// Create an account WITHOUT signing in — the user then logs in with their
  /// new credentials on the login screen. Does not establish a session or
  /// persist tokens (clears the token the register call set).
  Future<User> registerAccount({required String name, required String email, required String password}) async {
    final r = await ref.read(authServiceProvider).register(name: name, email: email, password: password);
    ref.read(apiClientProvider).authToken = null;
    return r.user;
  }

  /// Anonymous guest sign-in (public POST /guest/create) — no credentials.
  Future<User> loginGuest() async {
    final r = await ref.read(authServiceProvider).loginGuest();
    await _apply(r);
    return r.user;
  }

  /// Dev-only: seed a signed-in session from `--dart-define` values so online
  /// play can be exercised without a real auth backend (e.g. two emulators
  /// against the local chess relay in tools/chess_relay_server.dart). The token
  /// doubles as the server-side user id, so each build must pass a distinct
  /// `DEMO_TOKEN`. No-op (returns false) when `DEMO_TOKEN` is empty, so release
  /// builds behave exactly as before.
  Future<bool> startDemoSession() async {
    const token = String.fromEnvironment('DEMO_TOKEN');
    if (token.isEmpty) return false;
    const uidDefine = String.fromEnvironment('DEMO_USER_ID');
    const name = String.fromEnvironment('DEMO_NAME', defaultValue: 'Demo Player');
    final uid = uidDefine.isEmpty ? token : uidDefine;
    ref.read(apiClientProvider).authToken = token;
    await ref.read(tokenStoreProvider).save(access: token);
    state = User.fromJson({'id': uid, 'display_name': name, 'level': 1, 'tier': 'Bronze I'});
    return true;
  }

  Future<User> verifyOtp(String code) async {
    final r = await ref.read(authServiceProvider).verifyOtp(code: code);
    await _apply(r);
    return r.user;
  }

  /// Exchange the stored refresh token for a fresh access token (rotation).
  Future<bool> refreshSession() async {
    final rt = _refreshToken ?? await ref.read(tokenStoreProvider).readRefresh();
    if (rt == null || rt.isEmpty) return false;
    try {
      await _apply(await ref.read(authServiceProvider).refresh(rt));
      return true;
    } on Object catch (_) {
      return false;
    }
  }

  /// Restore a persisted session on boot. Returns true if signed in.
  Future<bool> restore() async {
    final store = ref.read(tokenStoreProvider);
    final access = await store.readAccess();
    if (access == null || access.isEmpty) return false;
    ref.read(apiClientProvider).authToken = access;
    _refreshToken = await store.readRefresh();
    try {
      state = await ref.read(authServiceProvider).fetchMe();
    } on Object catch (_) {
      // Expired/invalid token: try the refresh token once, else signed out.
      if (!await refreshSession()) {
        forceSignOut();
        return false;
      }
    }
    return true;
  }

  /// Re-read the account + profile from the API (Profile screen open /
  /// pull-to-refresh). Keeps the current player if the call fails.
  Future<void> reloadProfile() async {
    if (state == null) return;
    try {
      state = await ref.read(authServiceProvider).fetchMe();
    } on Object catch (_) {/* keep what we have */}
  }

  /// Save Edit-profile changes via PATCH /users/me/profile, then show the
  /// server's result everywhere (Profile, HUD). Throws on failure so the
  /// screen can report it. Signed out (demo build) → applied locally only.
  Future<void> updateProfile({String? displayName, String? bio, String? country}) async {
    final current = state;
    if (current == null) {
      state = User.demo.copyWith(displayName: displayName, bio: bio, country: country);
      return;
    }
    state = await ref
        .read(authServiceProvider)
        .updateProfile(current, displayName: displayName, bio: bio, country: country);
  }

  Future<void> signOut() async {
    await ref.read(authServiceProvider).logout();
    ref.read(apiClientProvider).authToken = null;
    _refreshToken = null;
    await ref.read(tokenStoreProvider).clear();
    state = null;
  }

  /// Clear the session locally without calling the API — used by the 401 handler
  /// (calling logout there could recurse on another 401).
  void forceSignOut() {
    ref.read(apiClientProvider).authToken = null;
    _refreshToken = null;
    ref.read(tokenStoreProvider).clear();
    state = null;
  }
}

final sessionProvider = NotifierProvider<SessionController, User?>(SessionController.new);

/// The player to render. Falls back to the demo player when signed out so
/// screens (and tests that build them directly) always have data.
final currentUserProvider = Provider<User>((ref) => ref.watch(sessionProvider) ?? User.demo);
