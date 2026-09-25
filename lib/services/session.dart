import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/user.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'token_store.dart';

/// Holds the signed-in [User] (null when logged out) and drives auth actions.
/// Persists the token best-effort so a session survives a restart. See
/// docs/INTEGRATION_PLAN.md §5.
class SessionController extends Notifier<User?> {
  @override
  User? build() => null;

  Future<void> _apply(AuthResult r) async {
    ref.read(apiClientProvider).authToken = r.token;
    await ref.read(tokenStoreProvider).write(r.token);
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

  Future<User> verifyOtp(String code) async {
    final r = await ref.read(authServiceProvider).verifyOtp(code: code);
    await _apply(r);
    return r.user;
  }

  /// Restore a persisted session on boot. Returns true if signed in.
  Future<bool> restore() async {
    final token = await ref.read(tokenStoreProvider).read();
    if (token == null || token.isEmpty) return false;
    ref.read(apiClientProvider).authToken = token;
    // Remote phase would GET /me here; static phase restores the demo player.
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
    await ref.read(tokenStoreProvider).clear();
    state = null;
  }

  /// Clear the session locally without calling the API — used by the 401 handler
  /// (calling logout there could recurse on another 401).
  void forceSignOut() {
    ref.read(apiClientProvider).authToken = null;
    ref.read(tokenStoreProvider).clear();
    state = null;
  }
}

final sessionProvider = NotifierProvider<SessionController, User?>(SessionController.new);

/// The player to render. Falls back to the demo player when signed out so
/// screens (and tests that build them directly) always have data.
final currentUserProvider = Provider<User>((ref) => ref.watch(sessionProvider) ?? User.demo);
