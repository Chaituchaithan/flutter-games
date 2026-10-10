import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_prefs.dart';

/// An app language: ISO 639-1 [code] (what the profile API's
/// `preferred_language` stores), names and a flag for pickers.
class AppLanguage {
  const AppLanguage(this.code, this.native, this.english, this.flag);
  final String code;
  final String native;
  final String english;
  final String flag;

  /// "🇬🇧 English".
  String get label => '$flag $english';
}

const appLanguages = <AppLanguage>[
  AppLanguage('en', 'English', 'English', '🇬🇧'),
  AppLanguage('es', 'Español', 'Spanish', '🇪🇸'),
  AppLanguage('fr', 'Français', 'French', '🇫🇷'),
  AppLanguage('de', 'Deutsch', 'German', '🇩🇪'),
  AppLanguage('pt', 'Português', 'Portuguese', '🇧🇷'),
  AppLanguage('hi', 'हिन्दी', 'Hindi', '🇮🇳'),
  AppLanguage('ar', 'العربية', 'Arabic', '🇸🇦'),
  AppLanguage('ja', '日本語', 'Japanese', '🇯🇵'),
  AppLanguage('ko', '한국어', 'Korean', '🇰🇷'),
  AppLanguage('id', 'Bahasa Indonesia', 'Indonesian', '🇮🇩'),
  AppLanguage('tr', 'Türkçe', 'Turkish', '🇹🇷'),
  AppLanguage('ru', 'Русский', 'Russian', '🇷🇺'),
];

/// Index of an API language value ("en", "en-GB", or "English"), or null.
int? languageIndexFor(String? value) {
  if (value == null || value.isEmpty) return null;
  final v = value.toLowerCase();
  final i = appLanguages.indexWhere(
      (l) => l.code == v || v.startsWith('${l.code}-') || v.startsWith('${l.code}_') || l.english.toLowerCase() == v);
  return i < 0 ? null : i;
}

/// The chosen app language (index into [appLanguages]). Picked on first
/// launch; kept in step with the profile's `preferred_language` once signed in.
class LanguageController extends Notifier<int> {
  @override
  int build() => 0; // English

  /// The player picked a language: apply and remember it on the device.
  void select(int index) {
    state = index;
    ref.read(appPrefsProvider).setLanguage(index);
  }

  /// Apply the language saved on the device (startup) without re-saving.
  void restore(int index) {
    if (index >= 0 && index < appLanguages.length) state = index;
  }
}

final languageProvider = NotifierProvider<LanguageController, int>(LanguageController.new);

/// "🇬🇧 English" for the Settings row.
String languageLabel(int index) => appLanguages[index].label;
