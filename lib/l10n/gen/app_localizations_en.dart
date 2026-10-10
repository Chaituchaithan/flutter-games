// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get tagline => 'Play. Win. Repeat.';

  @override
  String get retry => 'Retry';

  @override
  String get logInAgain => 'Log in again';

  @override
  String get continueLabel => 'Continue';

  @override
  String get soon => 'Soon';

  @override
  String get languageTitle => 'Language';

  @override
  String get chooseLanguage => 'Choose your language';

  @override
  String get chooseLanguageSub => 'You can change this anytime in Settings.';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get loginSubtitle => 'Log in to pick up where you left off.';

  @override
  String get continueWithApple => 'Continue with Apple';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get orLogInWithEmail => 'or log in with email';

  @override
  String get emailHint => 'Email address';

  @override
  String get passwordHint => 'Password';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get logIn => 'Log In';

  @override
  String get continueAsGuest => 'Continue as guest';

  @override
  String newToApp(String appName) {
    return 'New to $appName? ';
  }

  @override
  String get createAccount => 'Create account';

  @override
  String get quickPlay => 'Quick Play';

  @override
  String get quickPlaySub => 'Play vs computer';

  @override
  String get friends => 'Friends';

  @override
  String get friendsSub => 'Play with a room code';

  @override
  String get featured => 'FEATURED';

  @override
  String get onlinePlay => 'Online Play';

  @override
  String onlinePlaySub(String game) {
    return '$game · stake to enter, winner takes the pot';
  }

  @override
  String get play => 'Play';

  @override
  String onlineComingSoon(String game) {
    return 'Online $game is coming soon — try Quick Play';
  }

  @override
  String gameComingSoon(String game) {
    return '$game is coming soon';
  }

  @override
  String get earnRewards => 'Earn rewards';

  @override
  String get dailyBonus => 'Daily Bonus';

  @override
  String get luckyWheel => 'Lucky Wheel';

  @override
  String spinsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count spins left',
      one: '1 spin left',
    );
    return '$_temp0';
  }

  @override
  String get checking => 'Checking…';

  @override
  String get openRewards => 'Open rewards';

  @override
  String dayReady(int day) {
    return 'Day $day ready';
  }

  @override
  String nextIn(String time) {
    return 'Next in $time';
  }

  @override
  String get claimedToday => 'Claimed today';

  @override
  String get recentMatches => 'Recent matches';

  @override
  String get tournaments => 'Tournaments';

  @override
  String get live => 'LIVE';

  @override
  String get startupPreparing => 'Getting things ready…';

  @override
  String get startupSigningIn => 'Signing you in…';

  @override
  String get startupConnecting => 'Connecting to game server…';

  @override
  String get startupLoadingProfile => 'Loading your profile…';

  @override
  String get startupReady => 'Ready';

  @override
  String get errOffline =>
      'You\'re offline. Check your connection and try again.';

  @override
  String get errSlowServer =>
      'The server is taking too long to respond. Check your connection and try again.';

  @override
  String get errServerUnreachable =>
      'We couldn\'t reach the server. Please try again in a moment.';

  @override
  String get errSlowGameServer =>
      'The game server is taking too long to respond. Please try again.';
}
