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

  /// Anonymous guest sign-in (public POST /guest/create) — no credentials.
  Future<User> loginGuest() async {
    final r = await ref.read(authServiceProvider).loginGuest();
    await _apply(r);
    return r.user;
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
    // Remote phase would GET /users/me here; static phase restores the demo player.
    state = User.demo;
    return true;
  }

  /// Apply an Edit-profile save so Profile/HUD reflect it immediately. Seeds
  /// from the demo player when signed out so edits still show in the demo build.
  void updateProfile({String? displayName, String? bio}) {
    state = (state ?? User.demo).copyWith(displayName: displayName, bio: bio);
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
