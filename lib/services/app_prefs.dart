import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small on-device preferences that must survive a restart: whether the
/// first-launch onboarding was completed and the chosen app language.
/// Best-effort — storage failures read as "not set".
class AppPrefs {
  const AppPrefs([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  static const _onboardedKey = 'aura.prefs.onboarded';
  static const _languageKey = 'aura.prefs.language';

  Future<bool> onboarded() async => await _read(_onboardedKey) == '1';
  Future<void> setOnboarded() => _write(_onboardedKey, '1');

  /// Language index into `appLanguages` (null = never picked).
  Future<int?> language() async => int.tryParse(await _read(_languageKey) ?? '');
  Future<void> setLanguage(int index) => _write(_languageKey, '$index');

  /// A small named setting (games keep their own options here, e.g. the
  /// chess board style). Null = never set.
  Future<String?> get(String key) => _read('aura.prefs.$key');
  Future<void> set(String key, String value) => _write('aura.prefs.$key', value);

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
    } catch (_) {/* best effort */}
  }
}

final appPrefsProvider = Provider<AppPrefs>((ref) => const AppPrefs());
