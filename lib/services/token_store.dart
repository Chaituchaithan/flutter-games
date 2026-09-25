import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Best-effort persistence for the auth token. Every call is guarded so a
/// missing platform channel (e.g. in unit tests) degrades to a no-op / null
/// instead of throwing. See docs/INTEGRATION_PLAN.md §5.
class TokenStore {
  const TokenStore([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  static const _key = 'aura.auth.token';

  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String token) async {
    try {
      await _storage.write(key: _key, value: token);
    } catch (_) {/* no-op */}
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {/* no-op */}
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => const TokenStore());
