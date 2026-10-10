import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart';

/// `context.l10n.welcomeBack` — the current language's texts.
extension L10nX on BuildContext {
  /// Falls back to English where no localizations are set up (e.g. a bare
  /// MaterialApp in tests) instead of throwing.
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ?? lookupAppLocalizations(const Locale('en'));
}

/// The app locale for a language code from the picker / profile: that
/// language when it has a translation, else English.
Locale appLocaleFor(String code) {
  final supported = AppLocalizations.supportedLocales.any((l) => l.languageCode == code);
  return Locale(supported ? code : 'en');
}
