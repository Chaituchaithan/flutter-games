import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/languages.dart';
import '../data/models/user.dart';
import 'api_client.dart';
import 'app_exception.dart';
import 'auth_service.dart';
import 'token_store.dart';
import 'socket/app_socket.dart';

/// Holds the signed-in [User] (null when logged out) and drives auth actions.
/// Persists the token best-effort so a session survives a restart. See
/// docs/SERVICES_AND_REALTIME.md.
class SessionController extends Notifier<User?> {
  /// Latest opaque refresh token (7-day, rotated) for /auth/refresh.
  String? _refreshToken;

  /// When account + profile were last read from the API — the Profile tab
  /// skips a re-read right after login (no duplicate /users/me + profile).
  DateTime? _fetchedAt;
  static const _freshFor = Duration(minutes: 1);

  @override
  User? build() => null;

  /// Set the player from a fresh API read; the profile's saved language
  /// becomes the app language.
  void _setFetched(User u) {
    state = u;
    _fetchedAt = DateTime.now();
    final i = languageIndexFor(u.preferredLanguage);
    if (i != null) ref.read(languageProvider.notifier).select(i);
  }

  Future<void> _apply(AuthResult r) async {
    // Only replace the access token when the call actually returned one (e.g.
    // OTP verify returns no token pair and must keep the current session).
    if (r.accessToken.isNotEmpty) {
      ref.read(apiClientProvider).authToken = r.accessToken;
      _refreshToken = r.refreshToken ?? _refreshToken;
      await ref.read(tokenStoreProvider).save(access: r.accessToken, refresh: _refreshToken);
    }
    _setFetched(r.user);
  }

  Future<User> login({required String email, required String password}) async {
    final r = await ref.read(authServiceProvider).login(email: email, password: password);
    await _apply(r);
    _saveFirstLaunchLanguage(r.user);
    return r.user;
  }

  /// The profile has no language yet → save the one picked on first launch.
  void _saveFirstLaunchLanguage(User u) {
    if (u.preferredLanguage != null) return;
    final code = appLanguages[ref.read(languageProvider)].code;
    updateProfile(preferredLanguage: code).catchError((Object _) {});
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
  ///
  /// No network / a timeout throws the [AppException] and KEEPS the saved
  /// session (the splash offers Retry); only a rejected token that can't be
  /// refreshed signs the player out.
  Future<bool> restore() async {
    final store = ref.read(tokenStoreProvider);
    final access = await store.readAccess();
    if (access == null || access.isEmpty) return false;
    ref.read(apiClientProvider).authToken = access;
    _refreshToken = await store.readRefresh();
    try {
      _setFetched(await ref.read(authServiceProvider).fetchMe());
    } on AppException catch (e) {
      if (e.isOffline || e.kind == AppErrorKind.timeout || e.kind == AppErrorKind.server) rethrow;
      if (!await refreshSession()) {
        forceSignOut();
        return false;
      }
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
  /// Skipped when the data is under a minute old unless [force]
  /// (pull-to-refresh).
  Future<void> reloadProfile({bool force = false}) async {
    if (state == null) return;
    final at = _fetchedAt;
    if (!force && at != null && DateTime.now().difference(at) < _freshFor) return;
    try {
      _setFetched(await ref.read(authServiceProvider).fetchMe());
    } on Object catch (_) {/* keep what we have */}
  }

  /// Save Edit-profile changes via PATCH /users/me/profile, then show the
  /// server's result everywhere (Profile, HUD). Throws on failure so the
  /// screen can report it. Signed out (demo build) → applied locally only.
  Future<void> updateProfile({
    String? displayName,
    String? bio,
    String? country,
    String? preferredLanguage,
    String? dateOfBirth,
  }) async {
    final current = state;
    final User next;
    if (current == null) {
      next = User.demo.copyWith(
          displayName: displayName,
          bio: bio,
          country: country,
          preferredLanguage: preferredLanguage,
          dateOfBirth: dateOfBirth);
    } else {
      next = await ref.read(authServiceProvider).updateProfile(current,
          displayName: displayName,
          bio: bio,
          country: country,
          preferredLanguage: preferredLanguage,
          dateOfBirth: dateOfBirth);
    }
    state = next;
    final i = languageIndexFor(next.preferredLanguage);
    if (i != null) ref.read(languageProvider.notifier).select(i);
  }

  /// Change the password. The server revokes every session and refresh token
  /// (this one too), so the player is signed out locally and must log in with
  /// the new password. Throws [AppException] on failure (e.g. 401 = wrong
  /// current password).
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    await ref.read(authServiceProvider).changePassword(currentPassword: currentPassword, newPassword: newPassword);
    forceSignOut(); // tokens are already revoked — no /auth/logout call
  }

  Future<void> signOut() async {
    ref.read(appSocketProvider).logout();
    await ref.read(authServiceProvider).logout();
    ref.read(apiClientProvider).authToken = null;
    _refreshToken = null;
    await ref.read(tokenStoreProvider).clear();
    state = null;
    _fetchedAt = null;
  }

  /// Clear the session locally without calling the API — used by the 401 handler
  /// (calling logout there could recurse on another 401).
  void forceSignOut() {
    ref.read(appSocketProvider).disconnect();
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
