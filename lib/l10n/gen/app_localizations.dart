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

  /// No description provided for @resultVictory.
  ///
  /// In en, this message translates to:
  /// **'VICTORY'**
  String get resultVictory;

  /// No description provided for @resultVictorySub.
  ///
  /// In en, this message translates to:
  /// **'Flawless run, champion!'**
  String get resultVictorySub;

  /// No description provided for @resultDefeat.
  ///
  /// In en, this message translates to:
  /// **'DEFEAT'**
  String get resultDefeat;

  /// No description provided for @resultDefeatSub.
  ///
  /// In en, this message translates to:
  /// **'So close — run it back.'**
  String get resultDefeatSub;

  /// No description provided for @resultDraw.
  ///
  /// In en, this message translates to:
  /// **'DRAW'**
  String get resultDraw;

  /// No description provided for @resultDrawSub.
  ///
  /// In en, this message translates to:
  /// **'An even match.'**
  String get resultDrawSub;

  /// No description provided for @playAgain.
  ///
  /// In en, this message translates to:
  /// **'Play Again'**
  String get playAgain;

  /// No description provided for @backToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get backToHome;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @pot.
  ///
  /// In en, this message translates to:
  /// **'Pot'**
  String get pot;

  /// No description provided for @turnClock.
  ///
  /// In en, this message translates to:
  /// **'TURN CLOCK'**
  String get turnClock;

  /// No description provided for @waiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get waiting;

  /// No description provided for @forfeitTitle.
  ///
  /// In en, this message translates to:
  /// **'Forfeit the match?'**
  String get forfeitTitle;

  /// No description provided for @forfeitBody.
  ///
  /// In en, this message translates to:
  /// **'This round will count as a defeat and you will earn no reward.'**
  String get forfeitBody;

  /// No description provided for @forfeit.
  ///
  /// In en, this message translates to:
  /// **'Forfeit'**
  String get forfeit;

  /// No description provided for @keepPlaying.
  ///
  /// In en, this message translates to:
  /// **'Keep playing'**
  String get keepPlaying;

  /// No description provided for @paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get paused;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @forfeitMatch.
  ///
  /// In en, this message translates to:
  /// **'Forfeit match'**
  String get forfeitMatch;

  /// No description provided for @chatHint.
  ///
  /// In en, this message translates to:
  /// **'Say hi or send an emote'**
  String get chatHint;

  /// No description provided for @messageHint.
  ///
  /// In en, this message translates to:
  /// **'Message…'**
  String get messageHint;

  /// No description provided for @lastMove.
  ///
  /// In en, this message translates to:
  /// **'LAST MOVE'**
  String get lastMove;

  /// No description provided for @players.
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get players;

  /// No description provided for @yourColour.
  ///
  /// In en, this message translates to:
  /// **'Your colour'**
  String get yourColour;

  /// No description provided for @startGame.
  ///
  /// In en, this message translates to:
  /// **'Start game'**
  String get startGame;

  /// No description provided for @ludoBlurb.
  ///
  /// In en, this message translates to:
  /// **'Roll a 6 to bring a token out, capture rivals, and get all four tokens home first.'**
  String get ludoBlurb;

  /// No description provided for @youForfeitedMatch.
  ///
  /// In en, this message translates to:
  /// **'You forfeited the match.'**
  String get youForfeitedMatch;

  /// No description provided for @ludoWinSub.
  ///
  /// In en, this message translates to:
  /// **'All four tokens home — champion!'**
  String get ludoWinSub;

  /// No description provided for @gameOver.
  ///
  /// In en, this message translates to:
  /// **'Game over'**
  String get gameOver;

  /// No description provided for @rolling.
  ///
  /// In en, this message translates to:
  /// **'Rolling…'**
  String get rolling;

  /// No description provided for @pickToken.
  ///
  /// In en, this message translates to:
  /// **'Pick a token to move'**
  String get pickToken;

  /// No description provided for @yourTurnRoll.
  ///
  /// In en, this message translates to:
  /// **'Your turn — roll'**
  String get yourTurnRoll;

  /// No description provided for @snakesBlurb.
  ///
  /// In en, this message translates to:
  /// **'Race to 100 against the computer. Ladders lift you up, snakes slide you down — land on 100 exactly.'**
  String get snakesBlurb;

  /// No description provided for @youForfeitedRace.
  ///
  /// In en, this message translates to:
  /// **'You forfeited the race.'**
  String get youForfeitedRace;

  /// No description provided for @snakesWinSub.
  ///
  /// In en, this message translates to:
  /// **'First to 100 — what a climb!'**
  String get snakesWinSub;

  /// No description provided for @bestAi.
  ///
  /// In en, this message translates to:
  /// **'Best AI'**
  String get bestAi;

  /// No description provided for @pausedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The clock is stopped for everyone.'**
  String get pausedSubtitle;

  /// No description provided for @forfeitBodyStake.
  ///
  /// In en, this message translates to:
  /// **'You will lose your {amount} stake and the round counts as a defeat.'**
  String forfeitBodyStake(String amount);

  /// No description provided for @youPlusAi.
  ///
  /// In en, this message translates to:
  /// **'You + {count} AI'**
  String youPlusAi(int count);

  /// No description provided for @moveOnHold.
  ///
  /// In en, this message translates to:
  /// **'Move {move} · the game is on hold.'**
  String moveOnHold(int move);

  /// No description provided for @playerMoving.
  ///
  /// In en, this message translates to:
  /// **'{name} moving…'**
  String playerMoving(String name);

  /// No description provided for @playerPlaying.
  ///
  /// In en, this message translates to:
  /// **'{name} is playing…'**
  String playerPlaying(String name);

  /// No description provided for @playerRolling.
  ///
  /// In en, this message translates to:
  /// **'{name} is rolling…'**
  String playerRolling(String name);

  /// No description provided for @tapDiceToRoll.
  ///
  /// In en, this message translates to:
  /// **'Tap the dice\nto roll'**
  String get tapDiceToRoll;

  /// No description provided for @tapGlowingToken.
  ///
  /// In en, this message translates to:
  /// **'Tap a glowing\ntoken'**
  String get tapGlowingToken;

  /// No description provided for @moving.
  ///
  /// In en, this message translates to:
  /// **'Moving…'**
  String get moving;

  /// No description provided for @waitEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Wait…'**
  String get waitEllipsis;

  /// No description provided for @tokensHomeOut.
  ///
  /// In en, this message translates to:
  /// **'{home} home · {out} out'**
  String tokensHomeOut(int home, int out);

  /// No description provided for @squareN.
  ///
  /// In en, this message translates to:
  /// **'Square {n}'**
  String squareN(int n);

  /// No description provided for @startSquare.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get startSquare;

  /// No description provided for @moveAndPlayers.
  ///
  /// In en, this message translates to:
  /// **'Move {move} · {players} players'**
  String moveAndPlayers(int move, int players);

  /// No description provided for @ludoLoseSub.
  ///
  /// In en, this message translates to:
  /// **'{name} got all four tokens home first.'**
  String ludoLoseSub(String name);

  /// No description provided for @snakesLoseSub.
  ///
  /// In en, this message translates to:
  /// **'{name} reached 100 first.'**
  String snakesLoseSub(String name);

  /// No description provided for @timePerTurn.
  ///
  /// In en, this message translates to:
  /// **'Time per turn'**
  String get timePerTurn;

  /// No description provided for @timeSec.
  ///
  /// In en, this message translates to:
  /// **'{n} sec'**
  String timeSec(int n);

  /// No description provided for @timeMin.
  ///
  /// In en, this message translates to:
  /// **'{n} min'**
  String timeMin(int n);

  /// No description provided for @unlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get unlimited;

  /// No description provided for @timeUpRule.
  ///
  /// In en, this message translates to:
  /// **'If time runs out, your turn is played for you.'**
  String get timeUpRule;

  /// No description provided for @timeUpPlayed.
  ///
  /// In en, this message translates to:
  /// **'Time\'s up — your turn was played for you'**
  String get timeUpPlayed;

  /// No description provided for @turnRolling.
  ///
  /// In en, this message translates to:
  /// **'Rolling… · {secs}s'**
  String turnRolling(int secs);

  /// No description provided for @turnYourRoll.
  ///
  /// In en, this message translates to:
  /// **'Your roll · {secs}s'**
  String turnYourRoll(int secs);

  /// No description provided for @turnPick.
  ///
  /// In en, this message translates to:
  /// **'Pick a token · {secs}s'**
  String turnPick(int secs);

  /// No description provided for @turnRollingNoClock.
  ///
  /// In en, this message translates to:
  /// **'Rolling…'**
  String get turnRollingNoClock;

  /// No description provided for @turnYourRollNoClock.
  ///
  /// In en, this message translates to:
  /// **'Your roll'**
  String get turnYourRollNoClock;

  /// No description provided for @playAs.
  ///
  /// In en, this message translates to:
  /// **'Play as'**
  String get playAs;

  /// No description provided for @difficulty.
  ///
  /// In en, this message translates to:
  /// **'Difficulty'**
  String get difficulty;

  /// No description provided for @easy.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get easy;

  /// No description provided for @medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get medium;

  /// No description provided for @hard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get hard;

  /// No description provided for @relaxed.
  ///
  /// In en, this message translates to:
  /// **'Relaxed'**
  String get relaxed;

  /// No description provided for @balanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get balanced;

  /// No description provided for @tough.
  ///
  /// In en, this message translates to:
  /// **'Tough'**
  String get tough;

  /// No description provided for @randomSide.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get randomSide;

  /// No description provided for @playVsComputer.
  ///
  /// In en, this message translates to:
  /// **'Play vs Computer'**
  String get playVsComputer;

  /// No description provided for @timePerMove.
  ///
  /// In en, this message translates to:
  /// **'Time per move'**
  String get timePerMove;

  /// No description provided for @timeOutLoses.
  ///
  /// In en, this message translates to:
  /// **'Run out of time on a move and you lose the game.'**
  String get timeOutLoses;

  /// No description provided for @computer.
  ///
  /// In en, this message translates to:
  /// **'Computer'**
  String get computer;

  /// No description provided for @discsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 disc} other{{count} discs}}'**
  String discsCount(int count);

  /// No description provided for @yourMoveSecs.
  ///
  /// In en, this message translates to:
  /// **'Your move · {secs}s'**
  String yourMoveSecs(int secs);

  /// No description provided for @yourMove.
  ///
  /// In en, this message translates to:
  /// **'Your move'**
  String get yourMove;

  /// No description provided for @thinkingSecs.
  ///
  /// In en, this message translates to:
  /// **'Thinking… · {secs}s'**
  String thinkingSecs(int secs);

  /// No description provided for @thinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get thinking;

  /// No description provided for @computerThinking.
  ///
  /// In en, this message translates to:
  /// **'Computer is thinking…'**
  String get computerThinking;

  /// No description provided for @othelloPlayed.
  ///
  /// In en, this message translates to:
  /// **'{who} played {square} · flipped {count}'**
  String othelloPlayed(String who, String square, int count);

  /// No description provided for @mustPass.
  ///
  /// In en, this message translates to:
  /// **'{who} has no move — pass'**
  String mustPass(String who);

  /// No description provided for @othelloBlurb.
  ///
  /// In en, this message translates to:
  /// **'Outflank the computer: every disc you trap flips to your colour. Most discs when the board fills wins.'**
  String get othelloBlurb;

  /// No description provided for @black.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get black;

  /// No description provided for @white.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get white;

  /// No description provided for @youRanOutOfTime.
  ///
  /// In en, this message translates to:
  /// **'You ran out of time.'**
  String get youRanOutOfTime;

  /// No description provided for @computerRanOutOfTime.
  ///
  /// In en, this message translates to:
  /// **'The computer ran out of time.'**
  String get computerRanOutOfTime;

  /// No description provided for @othelloWinSub.
  ///
  /// In en, this message translates to:
  /// **'{you}–{them} — the board is yours!'**
  String othelloWinSub(int you, int them);

  /// No description provided for @othelloLoseSub.
  ///
  /// In en, this message translates to:
  /// **'{you}–{them} — outflanked this time.'**
  String othelloLoseSub(int you, int them);

  /// No description provided for @othelloDrawSub.
  ///
  /// In en, this message translates to:
  /// **'{you}–{them} — an even board.'**
  String othelloDrawSub(int you, int them);

  /// No description provided for @checkersBlurb.
  ///
  /// In en, this message translates to:
  /// **'Jump to capture — it\'s compulsory, and multi-jumps must be finished. Reach the far row to crown a king.'**
  String get checkersBlurb;

  /// No description provided for @checkersDark.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get checkersDark;

  /// No description provided for @checkersLight.
  ///
  /// In en, this message translates to:
  /// **'Ivory'**
  String get checkersLight;

  /// No description provided for @piecesKings.
  ///
  /// In en, this message translates to:
  /// **'{pieces} pieces · {kings} kings'**
  String piecesKings(int pieces, int kings);

  /// No description provided for @checkersMoved.
  ///
  /// In en, this message translates to:
  /// **'{who} moved {from}–{to}'**
  String checkersMoved(String who, int from, int to);

  /// No description provided for @checkersCaptured.
  ///
  /// In en, this message translates to:
  /// **'{who} captured {count, plural, =1{1 piece} other{{count} pieces}}'**
  String checkersCaptured(String who, int count);

  /// No description provided for @checkersWinSub.
  ///
  /// In en, this message translates to:
  /// **'The computer has no moves left — well played!'**
  String get checkersWinSub;

  /// No description provided for @checkersLoseSub.
  ///
  /// In en, this message translates to:
  /// **'Out of moves — run it back.'**
  String get checkersLoseSub;

  /// No description provided for @checkersDrawSub.
  ///
  /// In en, this message translates to:
  /// **'40 moves without a capture — a draw.'**
  String get checkersDrawSub;

  /// No description provided for @scrabbleBlurb.
  ///
  /// In en, this message translates to:
  /// **'Build words on the board against the computer. Premium squares multiply letters and words; use all 7 tiles for a 50-point bingo.'**
  String get scrabbleBlurb;

  /// No description provided for @scrabbleTimeRule.
  ///
  /// In en, this message translates to:
  /// **'If time runs out, your turn is passed.'**
  String get scrabbleTimeRule;

  /// No description provided for @loadingDictionary.
  ///
  /// In en, this message translates to:
  /// **'Loading dictionary…'**
  String get loadingDictionary;

  /// No description provided for @scoreN.
  ///
  /// In en, this message translates to:
  /// **'Score {n}'**
  String scoreN(int n);

  /// No description provided for @bagN.
  ///
  /// In en, this message translates to:
  /// **'Bag {n}'**
  String bagN(int n);

  /// No description provided for @shuffle.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get shuffle;

  /// No description provided for @recall.
  ///
  /// In en, this message translates to:
  /// **'Recall'**
  String get recall;

  /// No description provided for @swap.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get swap;

  /// No description provided for @pass.
  ///
  /// In en, this message translates to:
  /// **'Pass'**
  String get pass;

  /// No description provided for @playScore.
  ///
  /// In en, this message translates to:
  /// **'Play · {score}'**
  String playScore(int score);

  /// No description provided for @errPlaceTiles.
  ///
  /// In en, this message translates to:
  /// **'Place tiles on the board'**
  String get errPlaceTiles;

  /// No description provided for @errInLine.
  ///
  /// In en, this message translates to:
  /// **'Tiles must be in one row or column'**
  String get errInLine;

  /// No description provided for @errGap.
  ///
  /// In en, this message translates to:
  /// **'No gaps between your tiles'**
  String get errGap;

  /// No description provided for @errConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect to the tiles on the board'**
  String get errConnect;

  /// No description provided for @errCenter.
  ///
  /// In en, this message translates to:
  /// **'The first word must cover the centre star'**
  String get errCenter;

  /// No description provided for @errTooShort.
  ///
  /// In en, this message translates to:
  /// **'Words need at least 2 letters'**
  String get errTooShort;

  /// No description provided for @errNotWord.
  ///
  /// In en, this message translates to:
  /// **'{word} isn\'t in the dictionary'**
  String errNotWord(String word);

  /// No description provided for @scrabblePlayed.
  ///
  /// In en, this message translates to:
  /// **'{who} played {word} · {score}'**
  String scrabblePlayed(String who, String word, int score);

  /// No description provided for @scrabbleExchanged.
  ///
  /// In en, this message translates to:
  /// **'{who} swapped {count} tiles'**
  String scrabbleExchanged(String who, int count);

  /// No description provided for @scrabblePassed.
  ///
  /// In en, this message translates to:
  /// **'{who} passed'**
  String scrabblePassed(String who);

  /// No description provided for @timeUpPassed.
  ///
  /// In en, this message translates to:
  /// **'Time\'s up — your turn was passed'**
  String get timeUpPassed;

  /// No description provided for @swapTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose tiles to swap'**
  String get swapTitle;

  /// No description provided for @swapN.
  ///
  /// In en, this message translates to:
  /// **'Swap {count}'**
  String swapN(int count);

  /// No description provided for @passConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Pass your turn?'**
  String get passConfirmTitle;

  /// No description provided for @passConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You score nothing this turn. Six scoreless turns in a row end the game.'**
  String get passConfirmBody;

  /// No description provided for @pickLetter.
  ///
  /// In en, this message translates to:
  /// **'Choose a letter for the blank'**
  String get pickLetter;

  /// No description provided for @bagTooSmall.
  ///
  /// In en, this message translates to:
  /// **'Not enough tiles in the bag to swap'**
  String get bagTooSmall;

  /// No description provided for @scrabbleWinSub.
  ///
  /// In en, this message translates to:
  /// **'{you}–{them} — word master!'**
  String scrabbleWinSub(int you, int them);

  /// No description provided for @scrabbleLoseSub.
  ///
  /// In en, this message translates to:
  /// **'{you}–{them} — the computer out-spelled you.'**
  String scrabbleLoseSub(int you, int them);

  /// No description provided for @scrabbleDrawSub.
  ///
  /// In en, this message translates to:
  /// **'{you}–{them} — a tie!'**
  String scrabbleDrawSub(int you, int them);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;
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
