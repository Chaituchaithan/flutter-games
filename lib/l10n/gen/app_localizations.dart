import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
  ];

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Play. Win. Repeat.'**
  String get tagline;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @logInAgain.
  ///
  /// In en, this message translates to:
  /// **'Log in again'**
  String get logInAgain;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @soon.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get soon;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get chooseLanguage;

  /// No description provided for @chooseLanguageSub.
  ///
  /// In en, this message translates to:
  /// **'You can change this anytime in Settings.'**
  String get chooseLanguageSub;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Log in to pick up where you left off.'**
  String get loginSubtitle;

  /// No description provided for @continueWithApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get continueWithApple;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @orLogInWithEmail.
  ///
  /// In en, this message translates to:
  /// **'or log in with email'**
  String get orLogInWithEmail;

  /// No description provided for @emailHint.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get emailHint;

  /// No description provided for @passwordHint.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordHint;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @logIn.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get logIn;

  /// No description provided for @continueAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Continue as guest'**
  String get continueAsGuest;

  /// No description provided for @newToApp.
  ///
  /// In en, this message translates to:
  /// **'New to {appName}? '**
  String newToApp(String appName);

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @quickPlay.
  ///
  /// In en, this message translates to:
  /// **'Quick Play'**
  String get quickPlay;

  /// No description provided for @quickPlaySub.
  ///
  /// In en, this message translates to:
  /// **'Play vs computer'**
  String get quickPlaySub;

  /// No description provided for @friends.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get friends;

  /// No description provided for @friendsSub.
  ///
  /// In en, this message translates to:
  /// **'Play with a room code'**
  String get friendsSub;

  /// No description provided for @featured.
  ///
  /// In en, this message translates to:
  /// **'FEATURED'**
  String get featured;

  /// No description provided for @onlinePlay.
  ///
  /// In en, this message translates to:
  /// **'Online Play'**
  String get onlinePlay;

  /// No description provided for @onlinePlaySub.
  ///
  /// In en, this message translates to:
  /// **'{game} · stake to enter, winner takes the pot'**
  String onlinePlaySub(String game);

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @onlineComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Online {game} is coming soon — try Quick Play'**
  String onlineComingSoon(String game);

  /// No description provided for @gameComingSoon.
  ///
  /// In en, this message translates to:
  /// **'{game} is coming soon'**
  String gameComingSoon(String game);

  /// No description provided for @earnRewards.
  ///
  /// In en, this message translates to:
  /// **'Earn rewards'**
  String get earnRewards;

  /// No description provided for @dailyBonus.
  ///
  /// In en, this message translates to:
  /// **'Daily Bonus'**
  String get dailyBonus;

  /// No description provided for @luckyWheel.
  ///
  /// In en, this message translates to:
  /// **'Lucky Wheel'**
  String get luckyWheel;

  /// No description provided for @spinsLeft.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 spin left} other{{count} spins left}}'**
  String spinsLeft(int count);

  /// No description provided for @checking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get checking;

  /// No description provided for @openRewards.
  ///
  /// In en, this message translates to:
  /// **'Open rewards'**
  String get openRewards;

  /// No description provided for @dayReady.
  ///
  /// In en, this message translates to:
  /// **'Day {day} ready'**
  String dayReady(int day);

  /// No description provided for @nextIn.
  ///
  /// In en, this message translates to:
  /// **'Next in {time}'**
  String nextIn(String time);

  /// No description provided for @claimedToday.
  ///
  /// In en, this message translates to:
  /// **'Claimed today'**
  String get claimedToday;

  /// No description provided for @recentMatches.
  ///
  /// In en, this message translates to:
  /// **'Recent matches'**
  String get recentMatches;

  /// No description provided for @tournaments.
  ///
  /// In en, this message translates to:
  /// **'Tournaments'**
  String get tournaments;

  /// No description provided for @live.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get live;

  /// No description provided for @startupPreparing.
  ///
  /// In en, this message translates to:
  /// **'Getting things ready…'**
  String get startupPreparing;

  /// No description provided for @startupSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Signing you in…'**
  String get startupSigningIn;

  /// No description provided for @startupConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to game server…'**
  String get startupConnecting;

  /// No description provided for @startupLoadingProfile.
  ///
  /// In en, this message translates to:
  /// **'Loading your profile…'**
  String get startupLoadingProfile;

  /// No description provided for @startupReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get startupReady;

  /// No description provided for @errOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Check your connection and try again.'**
  String get errOffline;

  /// No description provided for @errSlowServer.
  ///
  /// In en, this message translates to:
  /// **'The server is taking too long to respond. Check your connection and try again.'**
  String get errSlowServer;

  /// No description provided for @errServerUnreachable.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t reach the server. Please try again in a moment.'**
  String get errServerUnreachable;

  /// No description provided for @errSlowGameServer.
  ///
  /// In en, this message translates to:
  /// **'The game server is taking too long to respond. Please try again.'**
  String get errSlowGameServer;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
