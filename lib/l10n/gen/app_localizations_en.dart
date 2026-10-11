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

  @override
  String get resultVictory => 'VICTORY';

  @override
  String get resultVictorySub => 'Flawless run, champion!';

  @override
  String get resultDefeat => 'DEFEAT';

  @override
  String get resultDefeatSub => 'So close — run it back.';

  @override
  String get resultDraw => 'DRAW';

  @override
  String get resultDrawSub => 'An even match.';

  @override
  String get playAgain => 'Play Again';

  @override
  String get backToHome => 'Back to Home';

  @override
  String get you => 'You';

  @override
  String get pot => 'Pot';

  @override
  String get turnClock => 'TURN CLOCK';

  @override
  String get waiting => 'Waiting';

  @override
  String get forfeitTitle => 'Forfeit the match?';

  @override
  String get forfeitBody =>
      'This round will count as a defeat and you will earn no reward.';

  @override
  String get forfeit => 'Forfeit';

  @override
  String get keepPlaying => 'Keep playing';

  @override
  String get paused => 'Paused';

  @override
  String get resume => 'Resume';

  @override
  String get forfeitMatch => 'Forfeit match';

  @override
  String get chatHint => 'Say hi or send an emote';

  @override
  String get messageHint => 'Message…';

  @override
  String get lastMove => 'LAST MOVE';

  @override
  String get players => 'Players';

  @override
  String get yourColour => 'Your colour';

  @override
  String get startGame => 'Start game';

  @override
  String get ludoBlurb =>
      'Roll a 6 to bring a token out, capture rivals, and get all four tokens home first.';

  @override
  String get youForfeitedMatch => 'You forfeited the match.';

  @override
  String get ludoWinSub => 'All four tokens home — champion!';

  @override
  String get gameOver => 'Game over';

  @override
  String get rolling => 'Rolling…';

  @override
  String get pickToken => 'Pick a token to move';

  @override
  String get yourTurnRoll => 'Your turn — roll';

  @override
  String get snakesBlurb =>
      'Race to 100 against the computer. Ladders lift you up, snakes slide you down — land on 100 exactly.';

  @override
  String get youForfeitedRace => 'You forfeited the race.';

  @override
  String get snakesWinSub => 'First to 100 — what a climb!';

  @override
  String get bestAi => 'Best AI';

  @override
  String get pausedSubtitle => 'The clock is stopped for everyone.';

  @override
  String forfeitBodyStake(String amount) {
    return 'You will lose your $amount stake and the round counts as a defeat.';
  }

  @override
  String youPlusAi(int count) {
    return 'You + $count AI';
  }

  @override
  String moveOnHold(int move) {
    return 'Move $move · the game is on hold.';
  }

  @override
  String playerMoving(String name) {
    return '$name moving…';
  }

  @override
  String playerPlaying(String name) {
    return '$name is playing…';
  }

  @override
  String playerRolling(String name) {
    return '$name is rolling…';
  }

  @override
  String get tapDiceToRoll => 'Tap the dice\nto roll';

  @override
  String get tapGlowingToken => 'Tap a glowing\ntoken';

  @override
  String get moving => 'Moving…';

  @override
  String get waitEllipsis => 'Wait…';

  @override
  String tokensHomeOut(int home, int out) {
    return '$home home · $out out';
  }

  @override
  String squareN(int n) {
    return 'Square $n';
  }

  @override
  String get startSquare => 'Start';

  @override
  String moveAndPlayers(int move, int players) {
    return 'Move $move · $players players';
  }

  @override
  String ludoLoseSub(String name) {
    return '$name got all four tokens home first.';
  }

  @override
  String snakesLoseSub(String name) {
    return '$name reached 100 first.';
  }

  @override
  String get timePerTurn => 'Time per turn';

  @override
  String timeSec(int n) {
    return '$n sec';
  }

  @override
  String timeMin(int n) {
    return '$n min';
  }

  @override
  String get unlimited => 'Unlimited';

  @override
  String get timeUpRule => 'If time runs out, your turn is played for you.';

  @override
  String get timeUpPlayed => 'Time\'s up — your turn was played for you';

  @override
  String turnRolling(int secs) {
    return 'Rolling… · ${secs}s';
  }

  @override
  String turnYourRoll(int secs) {
    return 'Your roll · ${secs}s';
  }

  @override
  String turnPick(int secs) {
    return 'Pick a token · ${secs}s';
  }

  @override
  String get turnRollingNoClock => 'Rolling…';

  @override
  String get turnYourRollNoClock => 'Your roll';

  @override
  String get playAs => 'Play as';

  @override
  String get difficulty => 'Difficulty';

  @override
  String get easy => 'Easy';

  @override
  String get medium => 'Medium';

  @override
  String get hard => 'Hard';

  @override
  String get relaxed => 'Relaxed';

  @override
  String get balanced => 'Balanced';

  @override
  String get tough => 'Tough';

  @override
  String get randomSide => 'Random';

  @override
  String get playVsComputer => 'Play vs Computer';

  @override
  String get timePerMove => 'Time per move';

  @override
  String get timeOutLoses => 'Run out of time on a move and you lose the game.';

  @override
  String get computer => 'Computer';

  @override
  String discsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count discs',
      one: '1 disc',
    );
    return '$_temp0';
  }

  @override
  String yourMoveSecs(int secs) {
    return 'Your move · ${secs}s';
  }

  @override
  String get yourMove => 'Your move';

  @override
  String thinkingSecs(int secs) {
    return 'Thinking… · ${secs}s';
  }

  @override
  String get thinking => 'Thinking…';

  @override
  String get computerThinking => 'Computer is thinking…';

  @override
  String othelloPlayed(String who, String square, int count) {
    return '$who played $square · flipped $count';
  }

  @override
  String mustPass(String who) {
    return '$who has no move — pass';
  }

  @override
  String get othelloBlurb =>
      'Outflank the computer: every disc you trap flips to your colour. Most discs when the board fills wins.';

  @override
  String get black => 'Black';

  @override
  String get white => 'White';

  @override
  String get youRanOutOfTime => 'You ran out of time.';

  @override
  String get computerRanOutOfTime => 'The computer ran out of time.';

  @override
  String othelloWinSub(int you, int them) {
    return '$you–$them — the board is yours!';
  }

  @override
  String othelloLoseSub(int you, int them) {
    return '$you–$them — outflanked this time.';
  }

  @override
  String othelloDrawSub(int you, int them) {
    return '$you–$them — an even board.';
  }

  @override
  String get checkersBlurb =>
      'Jump to capture — it\'s compulsory, and multi-jumps must be finished. Reach the far row to crown a king.';

  @override
  String get checkersDark => 'Red';

  @override
  String get checkersLight => 'Ivory';

  @override
  String piecesKings(int pieces, int kings) {
    return '$pieces pieces · $kings kings';
  }

  @override
  String checkersMoved(String who, int from, int to) {
    return '$who moved $from–$to';
  }

  @override
  String checkersCaptured(String who, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pieces',
      one: '1 piece',
    );
    return '$who captured $_temp0';
  }

  @override
  String get checkersWinSub => 'The computer has no moves left — well played!';

  @override
  String get checkersLoseSub => 'Out of moves — run it back.';

  @override
  String get checkersDrawSub => '40 moves without a capture — a draw.';

  @override
  String get scrabbleBlurb =>
      'Build words on the board against the computer. Premium squares multiply letters and words; use all 7 tiles for a 50-point bingo.';

  @override
  String get scrabbleTimeRule => 'If time runs out, your turn is passed.';

  @override
  String get loadingDictionary => 'Loading dictionary…';

  @override
  String scoreN(int n) {
    return 'Score $n';
  }

  @override
  String bagN(int n) {
    return 'Bag $n';
  }

  @override
  String get shuffle => 'Shuffle';

  @override
  String get recall => 'Recall';

  @override
  String get swap => 'Swap';

  @override
  String get pass => 'Pass';

  @override
  String playScore(int score) {
    return 'Play · $score';
  }

  @override
  String get errPlaceTiles => 'Place tiles on the board';

  @override
  String get errInLine => 'Tiles must be in one row or column';

  @override
  String get errGap => 'No gaps between your tiles';

  @override
  String get errConnect => 'Connect to the tiles on the board';

  @override
  String get errCenter => 'The first word must cover the centre star';

  @override
  String get errTooShort => 'Words need at least 2 letters';

  @override
  String errNotWord(String word) {
    return '$word isn\'t in the dictionary';
  }

  @override
  String scrabblePlayed(String who, String word, int score) {
    return '$who played $word · $score';
  }

  @override
  String scrabbleExchanged(String who, int count) {
    return '$who swapped $count tiles';
  }

  @override
  String scrabblePassed(String who) {
    return '$who passed';
  }

  @override
  String get timeUpPassed => 'Time\'s up — your turn was passed';

  @override
  String get swapTitle => 'Choose tiles to swap';

  @override
  String swapN(int count) {
    return 'Swap $count';
  }

  @override
  String get passConfirmTitle => 'Pass your turn?';

  @override
  String get passConfirmBody =>
      'You score nothing this turn. Six scoreless turns in a row end the game.';

  @override
  String get pickLetter => 'Choose a letter for the blank';

  @override
  String get bagTooSmall => 'Not enough tiles in the bag to swap';

  @override
  String scrabbleWinSub(int you, int them) {
    return '$you–$them — word master!';
  }

  @override
  String scrabbleLoseSub(int you, int them) {
    return '$you–$them — the computer out-spelled you.';
  }

  @override
  String scrabbleDrawSub(int you, int them) {
    return '$you–$them — a tie!';
  }

  @override
  String get cancel => 'Cancel';
}
