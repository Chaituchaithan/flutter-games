import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_profile.dart';
import '../configs/games/games.dart';
import '../data/languages.dart';
import '../data/models/user.dart';
import 'account_store.dart';
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

  /// When account + profile were last read from the API.
  DateTime? _fetchedAt;

  @override
  User? build() => null;

  /// Set the player from a fresh API read; the profile's saved language
  /// becomes the app language.
  void _setFetched(User u) {
    state = u;
    _fetchedAt = DateTime.now();
    _cache(u);
    final i = languageIndexFor(u.preferredLanguage);
    if (i != null) ref.read(languageProvider.notifier).select(i);
  }

  /// Keep the display copy on the device for an instant next start.
  void _cache(User u) => ref.read(tokenStoreProvider).saveProfile(jsonEncode(u.toCache()));

  Future<void> _apply(AuthResult r) async {
    // Only replace the access token when the call actually returned one (e.g.
    // OTP verify returns no token pair and must keep the current session).
    if (r.accessToken.isNotEmpty) {
      final api = ref.read(apiClientProvider);
      final expiresAt = r.expiresIn == null ? null : DateTime.now().add(r.expiresIn!);
      api.authToken = r.accessToken;
      api.accessExpiry = expiresAt;
      _refreshToken = r.refreshToken ?? _refreshToken;
      // Both tokens together: the old refresh token is dead after a refresh.
      await ref.read(tokenStoreProvider).save(access: r.accessToken, refresh: _refreshToken, expiresAt: expiresAt);
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

  /// Welcome fields sent on sign-up and guest create: the install's device
  /// id, the game this app is for, and how the player arrived.
  Future<SignUpExtras> _extras({String? referralCode, String? entrySource}) async => SignUpExtras(
        referralCode: referralCode,
        entrySource: entrySource ?? 'direct',
        entryGame: entryGameCode(),
        deviceId: await ref.read(tokenStoreProvider).deviceId(),
      );

  /// Sign up signs the user in (01-auth.md §1).
  /// [entrySource] `invite` when the app opened from a friend's invite link.
  Future<User> register(
      {required String name, required String email, required String password, String? referralCode, String? entrySource}) async {
    final r = await ref.read(authServiceProvider).register(
        name: name,
        email: email,
        password: password,
        extras: await _extras(referralCode: referralCode, entrySource: entrySource));
    await _apply(r);
    return r.user;
  }

  /// "Save your progress": the guest becomes a full account with the same id.
  /// Both tokens are replaced; from now on the player logs in by email.
  Future<User> convertGuest({required String username, required String email, required String password}) async {
    final r = await ref.read(authServiceProvider).convertGuest(username: username, email: email, password: password);
    await _apply(r);
    return r.user;
  }

  /// Log in with an email code, step 1 (public). Returns the code's lifetime.
  Future<Duration> sendLoginCode(String email) => ref.read(authServiceProvider).sendLoginCode(email: email);

  /// Step 2: a right code signs in (and marks the email verified).
  Future<User> loginWithCode({required String email, required String code}) async {
    final r = await ref.read(authServiceProvider).verifyLoginCode(email: email, code: code);
    await _apply(r);
    _saveFirstLaunchLanguage(r.user);
    return r.user;
  }

  /// Verify email (signed in), step 1: the code goes to the account's email.
  Future<Duration> sendEmailVerifyCode() => ref.read(authServiceProvider).sendEmailVerifyCode();

  /// Step 2: true when verified (then `email_verified_at` is re-read).
  Future<bool> verifyEmail(String code) async {
    final ok = await ref.read(authServiceProvider).verifyEmail(code: code);
    if (ok) await reloadProfile();
    return ok;
  }

  /// "Play as guest" (public POST /guest/create). Each call makes a NEW
  /// account, so a stored session is resumed instead (one guest per install).
  Future<User> loginGuest() async {
    final current = state;
    if (current != null && current.isGuest) return current;
    final stored = await ref.read(tokenStoreProvider).readRefresh();
    if (stored != null && stored.isNotEmpty && await restore()) {
      final u = state;
      if (u != null) return u;
    }
    final r = await ref.read(authServiceProvider).loginGuest(extras: await _extras());
    await _apply(r);
    return r.user;
  }

  /// Exchange the stored refresh token for a new token pair (rotation: the
  /// old refresh token stops working). With [rethrowErrors], the failure's
  /// [AppException] is thrown instead of returning false (the HTTP client uses
  /// it to tell a ban or a dead session from no network).
  ///
  /// One refresh at a time (01-auth.md §4): the refresh token is single-use,
  /// so the HTTP client, the socket and startup all share one in-flight call.
  Future<bool> refreshSession({bool rethrowErrors = false}) async {
    try {
      return await (_refreshing ??= _refreshNow().whenComplete(() => _refreshing = null));
    } on AppException {
      if (rethrowErrors) rethrow;
      return false;
    } on Object catch (_) {
      return false;
    }
  }

  Future<bool>? _refreshing;

  Future<bool> _refreshNow() async {
    final rt = _refreshToken ?? await ref.read(tokenStoreProvider).readRefresh();
    if (rt == null || rt.isEmpty) return false;
    final api = ref.read(apiClientProvider);
    api.refreshingFrom = api.authToken ?? '';
    try {
      await _apply(await ref.read(authServiceProvider).refresh(rt, current: state));
    } finally {
      api.refreshingFrom = null;
    }
    return true;
  }

  /// A usable access token for the realtime socket's reconnects: the current
  /// one while it has more than a minute left (per the stored `expires_in`
  /// expiry), else a refreshed one. Null = signed out or the refresh failed.
  Future<String?> validAccessToken() async {
    final api = ref.read(apiClientProvider);
    final store = ref.read(tokenStoreProvider);
    final access = api.authToken ?? await store.readAccess();
    if (access == null || access.isEmpty) return null;
    final exp = api.accessExpiry ?? await store.readExpiry();
    if (exp == null || exp.isAfter(DateTime.now().add(const Duration(minutes: 1)))) return access;
    // Expired / about to expire: refresh once.
    if (!await refreshSession()) return null;
    return api.authToken;
  }

  /// Forgot password 1 → 2 → 3 (public calls, no session needed). See
  /// [AuthService.requestPasswordReset].
  Future<PasswordResetRequest> requestPasswordReset(String email) =>
      ref.read(authServiceProvider).requestPasswordReset(email: email);

  Future<String> verifyResetCode({required String email, required String code}) =>
      ref.read(authServiceProvider).verifyResetCode(email: email, code: code);

  /// Step 3. Success signs out every session of the account — including one
  /// on this device — so the local session is cleared too.
  Future<void> resetPassword({required String resetToken, required String newPassword}) async {
    await ref.read(authServiceProvider).resetPassword(resetToken: resetToken, newPassword: newPassword);
    forceSignOut();
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
    final api = ref.read(apiClientProvider);
    api.authToken = access;
    api.accessExpiry = await store.readExpiry();
    _refreshToken = await store.readRefresh();
    // Saved player from last time → show it now and confirm with the server
    // in the background (the socket sign-in that follows checks the token).
    final cached = _readCache(await store.readProfile());
    if (cached != null) {
      state = cached;
      unawaited(_verifyInBackground());
      return true;
    }
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

  static User? _readCache(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return User.fromCache(jsonDecode(raw) as Map<String, dynamic>);
    } on Object catch (_) {
      return null;
    }
  }

  /// Background half of a cached [restore]: replace the saved copy with the
  /// server's. Offline / slow → keep showing the saved copy; a rejected token
  /// that can't be refreshed signs out (same rule as [restore]).
  Future<void> _verifyInBackground() async {
    try {
      _setFetched(await ref.read(authServiceProvider).fetchMe());
    } on AppException catch (e) {
      if (e.isOffline || e.kind == AppErrorKind.timeout || e.kind == AppErrorKind.server) return;
      if (await refreshSession()) {
        await reloadProfile();
      } else {
        forceSignOut();
      }
    } on Object catch (_) {
      if (!await refreshSession()) forceSignOut();
    }
  }

  /// Re-read the account + profile from the API (pull-to-refresh, after a
  /// match, back from the background). Keeps the current player if the call
  /// fails. With [ifOlderThan], skipped while the data is newer than that.
  Future<void> reloadProfile({Duration? ifOlderThan}) async {
    if (state == null) return;
    final at = _fetchedAt;
    if (ifOlderThan != null && at != null && DateTime.now().difference(at) < ifOlderThan) return;
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
    if (current != null) _cache(next);
    final i = languageIndexFor(next.preferredLanguage);
    if (i != null) ref.read(languageProvider.notifier).select(i);
  }

  /// Show a `PATCH /users/me/profile` reply (or part of one) everywhere:
  /// name, avatar, country, language (02-profile-and-sessions.md §2).
  void applyProfileReply(Map<String, dynamic> reply) {
    final current = state;
    if (current == null) return;
    final next = current.withProfile(reply);
    state = next;
    _cache(next);
    final i = languageIndexFor(next.preferredLanguage);
    if (i != null) ref.read(languageProvider.notifier).select(i);
  }

  /// Show a `PATCH /users/me` reply (username, email) everywhere (§4).
  void applyAccountReply(Map<String, dynamic> reply) {
    final current = state;
    if (current == null) return;
    final next = current.withAccount(reply);
    state = next;
    _cache(next);
  }

  /// Change the password. The server revokes every session and refresh token
  /// (this one too), so the player is signed out locally and must log in with
  /// the new password. Throws [AppException] on failure (`401
  /// INVALID_CREDENTIALS` = wrong current password; the session is kept).
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    await ref.read(authServiceProvider).changePassword(currentPassword: currentPassword, newPassword: newPassword);
    forceSignOut(); // tokens are already revoked — no /auth/logout call
  }

  /// Log out (POST /auth/logout ends this device's session only). Whatever
  /// the reply — success, 401 or no network — the local session is cleared:
  /// the user asked to leave.
  Future<void> signOut() async {
    ref.read(appSocketProvider).logout();
    // First stop pushes to this phone (02-profile-and-sessions.md §10c);
    // a failure never blocks the log-out.
    try {
      await ref.read(accountStoreProvider.notifier).clearPushTokenForLogout();
    } on Object catch (_) {}
    try {
      await ref.read(authServiceProvider).logout();
    } on Object catch (_) {
      // Ignored on purpose — see above.
    } finally {
      final api = ref.read(apiClientProvider);
      api.authToken = null;
      api.accessExpiry = null;
      _refreshToken = null;
      await ref.read(tokenStoreProvider).clear();
      state = null;
      _fetchedAt = null;
    }
  }

  /// Clear the session locally without calling the API — used by the 401 handler
  /// (calling logout there could recurse on another 401).
  void forceSignOut() {
    ref.read(appSocketProvider).disconnect();
    final api = ref.read(apiClientProvider);
    api.authToken = null;
    api.accessExpiry = null;
    _refreshToken = null;
    ref.read(tokenStoreProvider).clear();
    state = null;
  }
}

final sessionProvider = NotifierProvider<SessionController, User?>(SessionController.new);

/// The player to render. Falls back to the demo player when signed out so
/// screens (and tests that build them directly) always have data.
final currentUserProvider = Provider<User>((ref) => ref.watch(sessionProvider) ?? User.demo);

/// The `entry_game` code for sign-up / guest create: the game a single-game
/// app is built for. Only the codes the auth hand-off names are sent; the
/// all-games app and other games send none until the games hand-off lists them.
String? entryGameCode() {
  final p = AppProfile.current;
  if (!p.singleGame) return null;
  return switch (p.modules.single.id) {
    GameId.ludo => 'ludo',
    GameId.snakesLadders => 'snake-and-ladder',
    _ => null,
  };
}
