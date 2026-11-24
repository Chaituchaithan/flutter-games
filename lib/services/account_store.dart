import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/account.dart';
import 'account_service.dart';
import 'api_client.dart';
import 'app_exception.dart';
import 'session.dart';
import 'token_store.dart';

/// Holds the signed-in player's full [Me] (`GET /users/me`) for the profile,
/// account, addresses, privacy and game-settings screens, and replaces the
/// matching part after every successful write (02-profile-and-sessions.md).
///
/// Filled from the same `GET /users/me` sign-in already makes ([seed]), so
/// the screens need no extra read. Cleared on sign-out.
class AccountStore extends Notifier<Me?> {
  /// This install as the gateway knows it (§10): its numeric id is what the
  /// push-token route takes.
  Device? _device;

  /// The latest push token from the platform; null = none / denied.
  String? _pushToken;

  @override
  Me? build() {
    ref.listen(sessionProvider.select((u) => u?.id), (prev, id) {
      if (id == null) {
        state = null;
        _device = null;
        return;
      }
      if (id == prev) return;
      // A new player on this phone: register the install (§10a). A fresh
      // account read only when sign-in didn't already seed it.
      unawaited(registerThisDevice());
      if (state?.id != id) unawaited(load());
    });
    return null;
  }

  AccountApi get _api => ref.read(accountApiProvider);

  /// From the raw `GET /users/me` the auth layer just read.
  void seed(Map<String, dynamic> me) {
    try {
      state = Me.fromJson(me);
    } on Object catch (_) {/* keep what we have */}
  }

  /// (Re)read `GET /users/me`. Keeps the current value on failure.
  Future<Me?> load() async {
    try {
      state = await _api.me();
    } on Object catch (_) {/* keep */}
    return state;
  }

  /// The current value, reading it once when missing.
  Future<Me?> ensure() async => state ?? await load();

  // ── Profile (§2) ──

  /// One request for the whole form. Updates [Me] and the session's player
  /// (name and avatar everywhere) from the reply.
  Future<Me> updateProfile(ProfilePatch patch) async {
    final current = await ensure();
    if (patch.isEmpty && current != null) return current;
    final reply = await _api.updateProfile(patch);
    final base = current ?? await _api.me();
    final next = base.withProfileReply(reply);
    state = next;
    ref.read(sessionProvider.notifier).applyProfileReply(reply);
    return next;
  }

  /// Avatar picker: `PATCH /users/me/profile {avatar_id}`.
  Future<Me> pickAvatar(int avatarId) => updateProfile(ProfilePatch(avatarId: avatarId));

  // ── Account (§4) ──

  Future<Me> updateAccount({String? username, String? email, String? phone, String? currentPassword}) async {
    final reply = await _api.updateAccount(
        username: username, email: email, phone: phone, currentPassword: currentPassword);
    final base = await ensure() ?? await _api.me();
    final next = base.withAccountReply(reply);
    state = next;
    ref.read(sessionProvider.notifier).applyAccountReply(reply);
    return next;
  }

  // ── Addresses (§5) ──

  Future<Address> saveAddress(AddressKind kind, Address address) async {
    final saved = await _api.saveAddress(kind, address);
    final base = await ensure();
    if (base != null) state = base.copyWith(addresses: base.addresses.withAddress(kind, saved));
    // A home address also sets the profile country.
    if (kind == AddressKind.home && saved.country != null) {
      ref.read(sessionProvider.notifier).applyProfileReply({'country': saved.country});
      final s = state;
      if (s != null) {
        state = s.copyWith(
          profile: PublicProfile(
            userId: s.profile.userId,
            displayName: s.profile.displayName,
            avatarId: s.profile.avatarId,
            avatarUrl: s.profile.avatarUrl,
            bio: s.profile.bio,
            country: saved.country,
            dateOfBirth: s.profile.dateOfBirth,
            preferredLanguage: s.profile.preferredLanguage,
            updatedAt: s.profile.updatedAt,
          ),
        );
      }
    }
    return saved;
  }

  /// "Billing same as home" = no billing address.
  Future<void> removeAddress(AddressKind kind) async {
    await _api.removeAddress(kind);
    final base = state;
    if (base != null) state = base.copyWith(addresses: base.addresses.withAddress(kind, null));
  }

  // ── Privacy (§6) and game preferences (§7): optimistic, rolled back ──

  Future<void> setPrivacy(Map<String, dynamic> changes) async {
    // Synchronous when [Me] is loaded, so the switch moves at once.
    final before = state ?? await ensure();
    if (before != null) state = before.copyWith(privacy: before.privacy.merge(changes));
    try {
      final saved = await _api.updatePrivacy(changes);
      final s = state;
      if (s != null) state = s.copyWith(privacy: saved);
    } on Object {
      if (before != null) state = before;
      rethrow;
    }
  }

  Future<void> setPreferences(Map<String, dynamic> changes) async {
    // Synchronous when [Me] is loaded, so the switch moves at once.
    final before = state ?? await ensure();
    if (before != null) state = before.copyWith(preferences: before.preferences.merge(changes));
    try {
      final saved = await _api.updatePreferences(changes);
      final s = state;
      if (s != null) state = s.copyWith(preferences: saved);
    } on Object {
      if (before != null) state = before;
      rethrow;
    }
  }

  // ── Devices and push tokens (§10) ──

  /// `POST /devices/register` with this install's id, name, platform and
  /// current push token. Never blocks or fails sign-in: errors are swallowed
  /// (and never logged with the token).
  Future<Device?> registerThisDevice() async {
    final platform = devicePlatform();
    if (platform == null) return null;
    try {
      final id = await ref.read(tokenStoreProvider).deviceId();
      _device = await _api.registerDevice(
        deviceId: id,
        deviceName: deviceDisplayName(),
        platform: platform,
        pushToken: _pushToken,
      );
    } on Object catch (e) {
      if (kDebugMode) debugPrint('device register failed: ${e is AppException ? e.code : e.runtimeType}');
    }
    return _device;
  }

  /// A new token from the push provider (Firebase `onTokenRefresh`), or null
  /// when the player turned notifications off. Unknown device id (`404`) →
  /// register again.
  Future<void> onPushToken(String? token) async {
    _pushToken = (token == null || token.isEmpty) ? null : token;
    if (ref.read(sessionProvider) == null) return;
    final d = _device;
    if (d == null) {
      await registerThisDevice();
      return;
    }
    try {
      _device = await _api.setPushToken(d.id, _pushToken);
    } on AppException catch (e) {
      if (e.statusCode == 404) await registerThisDevice();
    } on Object catch (_) {}
  }

  /// Log out, step 0: stop pushes to this phone so the next player doesn't
  /// get them. Failure never blocks the log-out.
  Future<void> clearPushTokenForLogout() async {
    final d = _device;
    if (d == null || d.pushToken == null) return;
    try {
      await _api.setPushToken(d.id, null).timeout(const Duration(seconds: 3));
    } on Object catch (_) {}
  }

  Future<List<Device>> devices() => _api.devices();
  Future<void> removeDevice(int id) => _api.removeDevice(id);

  // ── Sessions (§11) ──

  Future<List<SignedInSession>> sessions() => _api.sessions();

  /// This phone's session: the `session_id` claim of the access token.
  String? get thisSessionId => sessionIdFromAccessToken(ref.read(apiClientProvider).authToken);

  /// Sign out one session. This phone's own → a log out. A `404` (already
  /// gone) is success: the caller drops the row and re-reads.
  Future<void> revokeSession(String sessionId) async {
    final own = sessionId == thisSessionId;
    try {
      await _api.revokeSession(sessionId);
    } on AppException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    if (own) ref.read(sessionProvider.notifier).forceSignOut();
  }

  /// "Sign out all other devices": one call per other row (no bulk route).
  /// Requires [thisSessionId]; returns how many were signed out.
  Future<int> revokeOtherSessions(List<SignedInSession> rows) async {
    final me = thisSessionId;
    if (me == null) throw const AppException("Couldn't tell which device this is. Use Sign out everywhere.");
    var n = 0;
    for (final s in rows) {
      if (s.sessionId == me) continue;
      await revokeSession(s.sessionId);
      n++;
    }
    return n;
  }

  /// `DELETE /sessions` — this phone too: clear the session locally.
  Future<int> signOutEverywhere() async {
    final n = await _api.revokeAllSessions();
    ref.read(sessionProvider.notifier).forceSignOut();
    return n;
  }

  // ── Delete account (§12) ──

  /// On success every session is gone: clear tokens and cached player data.
  Future<void> deleteAccount(String password) async {
    await _api.deleteAccount(password);
    ref.read(sessionProvider.notifier).forceSignOut();
    state = null;
    _device = null;
  }
}

final accountStoreProvider = NotifierProvider<AccountStore, Me?>(AccountStore.new);

/// The game preferences to apply on the device (§7): the saved ones once
/// read, the defaults before.
final gamePreferencesProvider =
    Provider<GamePreferences>((ref) => ref.watch(accountStoreProvider)?.preferences ?? const GamePreferences());

/// `GET /cosmetics/avatars`, cached for the session.
final avatarCatalogueProvider = FutureProvider<List<AvatarItem>>((ref) => ref.watch(accountApiProvider).avatarCatalogue());

/// `GET /users/me/inventory`; refreshed by the avatar picker.
final inventoryProvider = FutureProvider<Inventory>((ref) {
  ref.watch(sessionProvider.select((u) => u?.id));
  return ref.watch(accountApiProvider).inventory();
});

/// Another player's card (§8).
final playerProfileProvider =
    FutureProvider.family<PublicProfile, String>((ref, id) => ref.watch(accountApiProvider).playerProfile(id));

/// `ios` · `android` · `web`; null on a platform the gateway doesn't take.
String? devicePlatform() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => null,
  };
}

/// A name the player recognises in a device list. Without a device-info
/// plugin the platform is the best we have.
String deviceDisplayName() {
  if (kIsWeb) return 'Web browser';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android phone',
    TargetPlatform.iOS => 'iPhone',
    _ => 'Device',
  };
}
