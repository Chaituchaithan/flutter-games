import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Best-effort persistence for the auth token pair (access + refresh). Every
/// call is guarded so a missing platform channel (e.g. in unit tests) degrades
/// to a no-op / null instead of throwing. See docs/SERVICES_AND_REALTIME.md.
class TokenStore {
  const TokenStore([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  static const _accessKey = 'aura.auth.access';
  static const _refreshKey = 'aura.auth.refresh';

  Future<String?> readAccess() => _read(_accessKey);
  Future<String?> readRefresh() => _read(_refreshKey);

  Future<void> save({required String access, String? refresh}) async {
    await _write(_accessKey, access);
    if (refresh != null) await _write(_refreshKey, refresh);
  }

  Future<void> clear() async {
    await _delete(_accessKey);
    await _delete(_refreshKey);
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {/* no-op */}
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {/* no-op */}
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => const TokenStore());
