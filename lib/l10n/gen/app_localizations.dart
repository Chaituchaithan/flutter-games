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

  /// No description provided for @acceptTermsPrompt.
  ///
  /// In en, this message translates to:
  /// **'Please accept the Terms & Privacy Policy'**
  String get acceptTermsPrompt;

  /// No description provided for @accountCreated.
  ///
  /// In en, this message translates to:
  /// **'Account created — please log in'**
  String get accountCreated;

  /// No description provided for @registerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Join the community in under a minute.'**
  String get registerSubtitle;

  /// No description provided for @orSignUpWithEmail.
  ///
  /// In en, this message translates to:
  /// **'or sign up with email'**
  String get orSignUpWithEmail;

  /// No description provided for @usernameHint.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameHint;

  /// No description provided for @createPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Create password'**
  String get createPasswordHint;

  /// No description provided for @createAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccountButton;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get alreadyHaveAccount;

  /// No description provided for @logInLink.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get logInLink;

  /// No description provided for @iAgreeTo.
  ///
  /// In en, this message translates to:
  /// **'I agree to the '**
  String get iAgreeTo;

  /// No description provided for @terms.
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get terms;

  /// No description provided for @privacyPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicyTitle;

  /// No description provided for @logOutQuestion.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get logOutQuestion;

  /// No description provided for @logOutBody.
  ///
  /// In en, this message translates to:
  /// **'Your progress is saved to your account. You can sign back in anytime.'**
  String get logOutBody;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logOut;

  /// No description provided for @stay.
  ///
  /// In en, this message translates to:
  /// **'Stay'**
  String get stay;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// No description provided for @soundEffects.
  ///
  /// In en, this message translates to:
  /// **'Sound effects'**
  String get soundEffects;

  /// No description provided for @music.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get music;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @haptics.
  ///
  /// In en, this message translates to:
  /// **'Haptics'**
  String get haptics;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfile;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @changeAvatar.
  ///
  /// In en, this message translates to:
  /// **'Change avatar'**
  String get changeAvatar;

  /// No description provided for @friendsAndBlocked.
  ///
  /// In en, this message translates to:
  /// **'Friends & blocked players'**
  String get friendsAndBlocked;

  /// No description provided for @transactionsReceipts.
  ///
  /// In en, this message translates to:
  /// **'Transactions & receipts'**
  String get transactionsReceipts;

  /// No description provided for @inviteFriends.
  ///
  /// In en, this message translates to:
  /// **'Invite friends · earn rewards'**
  String get inviteFriends;

  /// No description provided for @gameHistory.
  ///
  /// In en, this message translates to:
  /// **'Game history'**
  String get gameHistory;

  /// No description provided for @support.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get support;

  /// No description provided for @helpCenter.
  ///
  /// In en, this message translates to:
  /// **'Help center'**
  String get helpCenter;

  /// No description provided for @helpCenterSoon.
  ///
  /// In en, this message translates to:
  /// **'Help center coming soon'**
  String get helpCenterSoon;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicy;

  /// No description provided for @privacyPolicySoon.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy coming soon'**
  String get privacyPolicySoon;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get appVersion;

  /// No description provided for @upgradeToVip.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to VIP'**
  String get upgradeToVip;

  /// No description provided for @vipPerks.
  ///
  /// In en, this message translates to:
  /// **'2× rewards, no ads & more'**
  String get vipPerks;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get passwordChanged;

  /// No description provided for @passwordChangedBody.
  ///
  /// In en, this message translates to:
  /// **'For your security you’ve been signed out on all devices. Log in with your new password.'**
  String get passwordChangedBody;

  /// No description provided for @currentPasswordWrong.
  ///
  /// In en, this message translates to:
  /// **'Current password is incorrect'**
  String get currentPasswordWrong;

  /// No description provided for @tooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in a few minutes.'**
  String get tooManyAttempts;

  /// No description provided for @changePasswordNote.
  ///
  /// In en, this message translates to:
  /// **'You’ll be signed out on all devices after changing it.'**
  String get changePasswordNote;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get confirmNewPassword;

  /// No description provided for @passwordRuleHint.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters, mixing letters and numbers.'**
  String get passwordRuleHint;

  /// No description provided for @updatePassword.
  ///
  /// In en, this message translates to:
  /// **'Update password'**
  String get updatePassword;

  /// No description provided for @displayNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Display name can’t be empty'**
  String get displayNameEmpty;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved'**
  String get profileSaved;

  /// No description provided for @editProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfileTitle;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// No description provided for @displayNameHint.
  ///
  /// In en, this message translates to:
  /// **'Your display name'**
  String get displayNameHint;

  /// No description provided for @bio.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get bio;

  /// No description provided for @bioHint.
  ///
  /// In en, this message translates to:
  /// **'Tell players about yourself'**
  String get bioHint;

  /// No description provided for @addBirthday.
  ///
  /// In en, this message translates to:
  /// **'Add your birthday'**
  String get addBirthday;

  /// No description provided for @country.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get country;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @alreadyClaimed.
  ///
  /// In en, this message translates to:
  /// **'Already claimed today — come back tomorrow.'**
  String get alreadyClaimed;

  /// No description provided for @dailyRewards.
  ///
  /// In en, this message translates to:
  /// **'Daily Rewards'**
  String get dailyRewards;

  /// No description provided for @thisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get thisWeek;

  /// No description provided for @claimEveryDay.
  ///
  /// In en, this message translates to:
  /// **'Claim every day to grow your streak.'**
  String get claimEveryDay;

  /// No description provided for @readyToClaim.
  ///
  /// In en, this message translates to:
  /// **'READY TO CLAIM'**
  String get readyToClaim;

  /// No description provided for @nextReward.
  ///
  /// In en, this message translates to:
  /// **'NEXT REWARD'**
  String get nextReward;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @gameStats.
  ///
  /// In en, this message translates to:
  /// **'Game stats'**
  String get gameStats;

  /// No description provided for @achievements.
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get achievements;

  /// No description provided for @manage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// No description provided for @addBio.
  ///
  /// In en, this message translates to:
  /// **'+ Add a bio'**
  String get addBio;

  /// No description provided for @winRate.
  ///
  /// In en, this message translates to:
  /// **'Win rate'**
  String get winRate;

  /// No description provided for @last7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get last7Days;

  /// No description provided for @tokensWon.
  ///
  /// In en, this message translates to:
  /// **'Tokens won'**
  String get tokensWon;

  /// No description provided for @goldWon.
  ///
  /// In en, this message translates to:
  /// **'Gold won'**
  String get goldWon;

  /// No description provided for @editProfileSub.
  ///
  /// In en, this message translates to:
  /// **'Name, bio, country'**
  String get editProfileSub;

  /// No description provided for @avatar.
  ///
  /// In en, this message translates to:
  /// **'Avatar'**
  String get avatar;

  /// No description provided for @chooseYourLook.
  ///
  /// In en, this message translates to:
  /// **'Choose your look'**
  String get chooseYourLook;

  /// No description provided for @settingsSub.
  ///
  /// In en, this message translates to:
  /// **'Sound, alerts, account'**
  String get settingsSub;

  /// No description provided for @claimedReward.
  ///
  /// In en, this message translates to:
  /// **'Claimed {reward}'**
  String claimedReward(String reward);

  /// No description provided for @dayStreakSuffix.
  ///
  /// In en, this message translates to:
  /// **' · {count}-day streak'**
  String dayStreakSuffix(int count);

  /// No description provided for @lessThanMinute.
  ///
  /// In en, this message translates to:
  /// **'less than a minute'**
  String get lessThanMinute;

  /// No description provided for @durationHm.
  ///
  /// In en, this message translates to:
  /// **'{h}h {m}m'**
  String durationHm(int h, int m);

  /// No description provided for @durationM.
  ///
  /// In en, this message translates to:
  /// **'{m}m'**
  String durationM(int m);

  /// No description provided for @claimedOfWeek.
  ///
  /// In en, this message translates to:
  /// **'{count}/7 claimed'**
  String claimedOfWeek(int count);

  /// No description provided for @claimDay.
  ///
  /// In en, this message translates to:
  /// **'Claim Day {day}'**
  String claimDay(int day);

  /// No description provided for @comeBackIn.
  ///
  /// In en, this message translates to:
  /// **'Come back in {time}'**
  String comeBackIn(String time);

  /// No description provided for @aBit.
  ///
  /// In en, this message translates to:
  /// **'a bit'**
  String get aBit;

  /// No description provided for @tokensAmount.
  ///
  /// In en, this message translates to:
  /// **'{amount} Tokens'**
  String tokensAmount(String amount);

  /// No description provided for @powerUpCount.
  ///
  /// In en, this message translates to:
  /// **'{count}× power-up'**
  String powerUpCount(int count);

  /// No description provided for @unlocksIn.
  ///
  /// In en, this message translates to:
  /// **'Unlocks in {time}'**
  String unlocksIn(String time);

  /// No description provided for @todaysRewardWaiting.
  ///
  /// In en, this message translates to:
  /// **'Today\'s reward is waiting'**
  String get todaysRewardWaiting;

  /// No description provided for @dayOfSeven.
  ///
  /// In en, this message translates to:
  /// **'DAY {day} / 7'**
  String dayOfSeven(int day);

  /// No description provided for @currencyGold.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get currencyGold;

  /// No description provided for @currencyTokens.
  ///
  /// In en, this message translates to:
  /// **'Tokens'**
  String get currencyTokens;

  /// No description provided for @streakDays.
  ///
  /// In en, this message translates to:
  /// **'{count}-Day Streak'**
  String streakDays(int count);

  /// No description provided for @noStreakYet.
  ///
  /// In en, this message translates to:
  /// **'No streak yet'**
  String get noStreakYet;

  /// No description provided for @onARoll.
  ///
  /// In en, this message translates to:
  /// **'You\'re on a roll — keep it going!'**
  String get onARoll;

  /// No description provided for @claimTodayToStart.
  ///
  /// In en, this message translates to:
  /// **'Claim today to start one.'**
  String get claimTodayToStart;

  /// No description provided for @tileToday.
  ///
  /// In en, this message translates to:
  /// **'TODAY'**
  String get tileToday;

  /// No description provided for @tileTomorrow.
  ///
  /// In en, this message translates to:
  /// **'TOMORROW'**
  String get tileTomorrow;

  /// No description provided for @tileDay.
  ///
  /// In en, this message translates to:
  /// **'DAY {day}'**
  String tileDay(int day);

  /// No description provided for @claimed.
  ///
  /// In en, this message translates to:
  /// **'Claimed'**
  String get claimed;

  /// No description provided for @mega.
  ///
  /// In en, this message translates to:
  /// **'MEGA'**
  String get mega;

  /// No description provided for @dateOfBirth.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get dateOfBirth;
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
