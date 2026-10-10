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

  @override
  String get acceptTermsPrompt => 'Please accept the Terms & Privacy Policy';

  @override
  String get accountCreated => 'Account created — please log in';

  @override
  String get registerSubtitle => 'Join the community in under a minute.';

  @override
  String get orSignUpWithEmail => 'or sign up with email';

  @override
  String get usernameHint => 'Username';

  @override
  String get createPasswordHint => 'Create password';

  @override
  String get createAccountButton => 'Create Account';

  @override
  String get alreadyHaveAccount => 'Already have an account? ';

  @override
  String get logInLink => 'Log in';

  @override
  String get iAgreeTo => 'I agree to the ';

  @override
  String get terms => 'Terms';

  @override
  String get privacyPolicyTitle => 'Privacy Policy';

  @override
  String get logOutQuestion => 'Log out?';

  @override
  String get logOutBody =>
      'Your progress is saved to your account. You can sign back in anytime.';

  @override
  String get logOut => 'Log out';

  @override
  String get stay => 'Stay';

  @override
  String get settings => 'Settings';

  @override
  String get preferences => 'Preferences';

  @override
  String get soundEffects => 'Sound effects';

  @override
  String get music => 'Music';

  @override
  String get notifications => 'Notifications';

  @override
  String get haptics => 'Haptics';

  @override
  String get account => 'Account';

  @override
  String get editProfile => 'Edit profile';

  @override
  String get changePassword => 'Change password';

  @override
  String get changeAvatar => 'Change avatar';

  @override
  String get friendsAndBlocked => 'Friends & blocked players';

  @override
  String get transactionsReceipts => 'Transactions & receipts';

  @override
  String get inviteFriends => 'Invite friends · earn rewards';

  @override
  String get gameHistory => 'Game history';

  @override
  String get support => 'Support';

  @override
  String get helpCenter => 'Help center';

  @override
  String get helpCenterSoon => 'Help center coming soon';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get privacyPolicySoon => 'Privacy policy coming soon';

  @override
  String get appVersion => 'App version';

  @override
  String get upgradeToVip => 'Upgrade to VIP';

  @override
  String get vipPerks => '2× rewards, no ads & more';

  @override
  String get passwordChanged => 'Password changed';

  @override
  String get passwordChangedBody =>
      'For your security you’ve been signed out on all devices. Log in with your new password.';

  @override
  String get currentPasswordWrong => 'Current password is incorrect';

  @override
  String get tooManyAttempts =>
      'Too many attempts. Try again in a few minutes.';

  @override
  String get changePasswordNote =>
      'You’ll be signed out on all devices after changing it.';

  @override
  String get currentPassword => 'Current password';

  @override
  String get newPassword => 'New password';

  @override
  String get confirmNewPassword => 'Confirm new password';

  @override
  String get passwordRuleHint =>
      'At least 8 characters, mixing letters and numbers.';

  @override
  String get updatePassword => 'Update password';

  @override
  String get displayNameEmpty => 'Display name can’t be empty';

  @override
  String get profileSaved => 'Profile saved';

  @override
  String get editProfileTitle => 'Edit Profile';

  @override
  String get displayName => 'Display name';

  @override
  String get displayNameHint => 'Your display name';

  @override
  String get bio => 'Bio';

  @override
  String get bioHint => 'Tell players about yourself';

  @override
  String get addBirthday => 'Add your birthday';

  @override
  String get country => 'Country';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get alreadyClaimed => 'Already claimed today — come back tomorrow.';

  @override
  String get dailyRewards => 'Daily Rewards';

  @override
  String get thisWeek => 'This week';

  @override
  String get claimEveryDay => 'Claim every day to grow your streak.';

  @override
  String get readyToClaim => 'READY TO CLAIM';

  @override
  String get nextReward => 'NEXT REWARD';

  @override
  String get profile => 'Profile';

  @override
  String get gameStats => 'Game stats';

  @override
  String get achievements => 'Achievements';

  @override
  String get manage => 'Manage';

  @override
  String get addBio => '+ Add a bio';

  @override
  String get winRate => 'Win rate';

  @override
  String get last7Days => 'Last 7 days';

  @override
  String get tokensWon => 'Tokens won';

  @override
  String get goldWon => 'Gold won';

  @override
  String get editProfileSub => 'Name, bio, country';

  @override
  String get avatar => 'Avatar';

  @override
  String get chooseYourLook => 'Choose your look';

  @override
  String get settingsSub => 'Sound, alerts, account';

  @override
  String claimedReward(String reward) {
    return 'Claimed $reward';
  }

  @override
  String dayStreakSuffix(int count) {
    return ' · $count-day streak';
  }

  @override
  String get lessThanMinute => 'less than a minute';

  @override
  String durationHm(int h, int m) {
    return '${h}h ${m}m';
  }

  @override
  String durationM(int m) {
    return '${m}m';
  }

  @override
  String claimedOfWeek(int count) {
    return '$count/7 claimed';
  }

  @override
  String claimDay(int day) {
    return 'Claim Day $day';
  }

  @override
  String comeBackIn(String time) {
    return 'Come back in $time';
  }

  @override
  String get aBit => 'a bit';

  @override
  String tokensAmount(String amount) {
    return '$amount Tokens';
  }

  @override
  String powerUpCount(int count) {
    return '$count× power-up';
  }

  @override
  String unlocksIn(String time) {
    return 'Unlocks in $time';
  }

  @override
  String get todaysRewardWaiting => 'Today\'s reward is waiting';

  @override
  String dayOfSeven(int day) {
    return 'DAY $day / 7';
  }

  @override
  String get currencyGold => 'Gold';

  @override
  String get currencyTokens => 'Tokens';

  @override
  String streakDays(int count) {
    return '$count-Day Streak';
  }

  @override
  String get noStreakYet => 'No streak yet';

  @override
  String get onARoll => 'You\'re on a roll — keep it going!';

  @override
  String get claimTodayToStart => 'Claim today to start one.';

  @override
  String get tileToday => 'TODAY';

  @override
  String get tileTomorrow => 'TOMORROW';

  @override
  String tileDay(int day) {
    return 'DAY $day';
  }

  @override
  String get claimed => 'Claimed';

  @override
  String get mega => 'MEGA';

  @override
  String get dateOfBirth => 'Date of birth';
}
