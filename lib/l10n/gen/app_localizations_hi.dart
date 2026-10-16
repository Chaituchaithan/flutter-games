// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get tagline => 'खेलो। जीतो। दोहराओ।';

  @override
  String get retry => 'फिर से कोशिश करें';

  @override
  String get logInAgain => 'फिर से लॉग इन करें';

  @override
  String get continueLabel => 'आगे बढ़ें';

  @override
  String get soon => 'जल्द';

  @override
  String get languageTitle => 'भाषा';

  @override
  String get chooseLanguage => 'अपनी भाषा चुनें';

  @override
  String get chooseLanguageSub => 'आप इसे कभी भी सेटिंग्स में बदल सकते हैं।';

  @override
  String get welcomeBack => 'फिर से स्वागत है';

  @override
  String get loginSubtitle =>
      'जहाँ छोड़ा था, वहीं से जारी रखने के लिए लॉग इन करें।';

  @override
  String get continueWithApple => 'Apple के साथ जारी रखें';

  @override
  String get continueWithGoogle => 'Google के साथ जारी रखें';

  @override
  String get orLogInWithEmail => 'या ईमेल से लॉग इन करें';

  @override
  String get emailHint => 'ईमेल पता';

  @override
  String get passwordHint => 'पासवर्ड';

  @override
  String get forgotPassword => 'पासवर्ड भूल गए?';

  @override
  String get logIn => 'लॉग इन';

  @override
  String get continueAsGuest => 'मेहमान के रूप में जारी रखें';

  @override
  String newToApp(String appName) {
    return '$appName पर नए हैं? ';
  }

  @override
  String get createAccount => 'खाता बनाएँ';

  @override
  String get quickPlay => 'क्विक प्ले';

  @override
  String get quickPlaySub => 'कंप्यूटर के खिलाफ खेलें';

  @override
  String get friends => 'दोस्त';

  @override
  String get friendsSub => 'रूम कोड से खेलें';

  @override
  String get featured => 'विशेष';

  @override
  String get onlinePlay => 'ऑनलाइन खेलें';

  @override
  String onlinePlaySub(String game) {
    return '$game · दांव लगाएँ, विजेता पूरा पॉट ले जाता है';
  }

  @override
  String get play => 'खेलें';

  @override
  String onlineComingSoon(String game) {
    return 'ऑनलाइन $game जल्द आ रहा है — तब तक क्विक प्ले खेलें';
  }

  @override
  String gameComingSoon(String game) {
    return '$game जल्द आ रहा है';
  }

  @override
  String get earnRewards => 'इनाम कमाएँ';

  @override
  String get dailyBonus => 'डेली बोनस';

  @override
  String get luckyWheel => 'लकी व्हील';

  @override
  String spinsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count स्पिन बाकी',
      one: '1 स्पिन बाकी',
    );
    return '$_temp0';
  }

  @override
  String get checking => 'जाँच हो रही है…';

  @override
  String get openRewards => 'इनाम खोलें';

  @override
  String dayReady(int day) {
    return 'दिन $day तैयार';
  }

  @override
  String nextIn(String time) {
    return 'अगला $time में';
  }

  @override
  String get claimedToday => 'आज ले लिया';

  @override
  String get recentMatches => 'हाल के मैच';

  @override
  String get tournaments => 'टूर्नामेंट';

  @override
  String get live => 'लाइव';

  @override
  String get startupPreparing => 'तैयारी हो रही है…';

  @override
  String get startupSigningIn => 'आपको साइन इन किया जा रहा है…';

  @override
  String get startupConnecting => 'गेम सर्वर से जुड़ रहे हैं…';

  @override
  String get startupLoadingProfile => 'आपकी प्रोफ़ाइल लोड हो रही है…';

  @override
  String get startupReady => 'तैयार';

  @override
  String get errOffline =>
      'आप ऑफ़लाइन हैं। अपना कनेक्शन जाँचें और फिर से कोशिश करें।';

  @override
  String get errSlowServer =>
      'सर्वर जवाब देने में बहुत समय ले रहा है। अपना कनेक्शन जाँचें और फिर से कोशिश करें।';

  @override
  String get errServerUnreachable =>
      'सर्वर तक नहीं पहुँच सके। थोड़ी देर में फिर से कोशिश करें।';

  @override
  String get errSlowGameServer =>
      'गेम सर्वर जवाब देने में बहुत समय ले रहा है। फिर से कोशिश करें।';

  @override
  String get acceptTermsPrompt => 'कृपया नियम और गोपनीयता नीति स्वीकार करें';

  @override
  String get accountCreated => 'खाता बन गया — कृपया लॉग इन करें';

  @override
  String get registerSubtitle => 'एक मिनट से कम में समुदाय से जुड़ें।';

  @override
  String get orSignUpWithEmail => 'या ईमेल से साइन अप करें';

  @override
  String get usernameHint => 'यूज़रनेम';

  @override
  String get createPasswordHint => 'पासवर्ड बनाएँ';

  @override
  String get createAccountButton => 'खाता बनाएँ';

  @override
  String get alreadyHaveAccount => 'पहले से खाता है? ';

  @override
  String get logInLink => 'लॉग इन करें';

  @override
  String get iAgreeTo => 'मैं इनसे सहमत हूँ: ';

  @override
  String get terms => 'नियम';

  @override
  String get privacyPolicyTitle => 'गोपनीयता नीति';

  @override
  String get logOutQuestion => 'लॉग आउट करें?';

  @override
  String get logOutBody =>
      'आपकी प्रगति आपके खाते में सुरक्षित है। आप कभी भी फिर से साइन इन कर सकते हैं।';

  @override
  String get logOut => 'लॉग आउट';

  @override
  String get stay => 'रुकें';

  @override
  String get settings => 'सेटिंग्स';

  @override
  String get preferences => 'प्राथमिकताएँ';

  @override
  String get soundEffects => 'साउंड इफ़ेक्ट';

  @override
  String get music => 'संगीत';

  @override
  String get notifications => 'सूचनाएँ';

  @override
  String get haptics => 'वाइब्रेशन';

  @override
  String get account => 'खाता';

  @override
  String get editProfile => 'प्रोफ़ाइल बदलें';

  @override
  String get changePassword => 'पासवर्ड बदलें';

  @override
  String get changeAvatar => 'अवतार बदलें';

  @override
  String get friendsAndBlocked => 'दोस्त और ब्लॉक किए गए खिलाड़ी';

  @override
  String get transactionsReceipts => 'लेन-देन और रसीदें';

  @override
  String get inviteFriends => 'दोस्तों को बुलाएँ · इनाम कमाएँ';

  @override
  String get gameHistory => 'गेम इतिहास';

  @override
  String get support => 'सहायता';

  @override
  String get helpCenter => 'सहायता केंद्र';

  @override
  String get helpCenterSoon => 'सहायता केंद्र जल्द आ रहा है';

  @override
  String get privacyPolicy => 'गोपनीयता नीति';

  @override
  String get privacyPolicySoon => 'गोपनीयता नीति जल्द आ रही है';

  @override
  String get appVersion => 'ऐप वर्ज़न';

  @override
  String get upgradeToVip => 'VIP में अपग्रेड करें';

  @override
  String get vipPerks => '2× इनाम, कोई विज्ञापन नहीं, और भी बहुत कुछ';

  @override
  String get passwordChanged => 'पासवर्ड बदल गया';

  @override
  String get passwordChangedBody =>
      'आपकी सुरक्षा के लिए सभी डिवाइस से साइन आउट कर दिया गया है। नए पासवर्ड से लॉग इन करें।';

  @override
  String get currentPasswordWrong => 'मौजूदा पासवर्ड गलत है';

  @override
  String get tooManyAttempts =>
      'बहुत ज़्यादा कोशिशें। कुछ मिनट बाद फिर से कोशिश करें।';

  @override
  String get changePasswordNote =>
      'बदलने के बाद आप सभी डिवाइस से साइन आउट हो जाएँगे।';

  @override
  String get currentPassword => 'मौजूदा पासवर्ड';

  @override
  String get newPassword => 'नया पासवर्ड';

  @override
  String get confirmNewPassword => 'नए पासवर्ड की पुष्टि करें';

  @override
  String get passwordRuleHint => 'कम से कम 8 अक्षर, अक्षरों और अंकों का मेल।';

  @override
  String get updatePassword => 'पासवर्ड अपडेट करें';

  @override
  String get displayNameEmpty => 'डिस्प्ले नाम खाली नहीं हो सकता';

  @override
  String get profileSaved => 'प्रोफ़ाइल सेव हो गई';

  @override
  String get editProfileTitle => 'प्रोफ़ाइल बदलें';

  @override
  String get displayName => 'डिस्प्ले नाम';

  @override
  String get displayNameHint => 'आपका डिस्प्ले नाम';

  @override
  String get bio => 'परिचय';

  @override
  String get bioHint => 'खिलाड़ियों को अपने बारे में बताएँ';

  @override
  String get addBirthday => 'अपना जन्मदिन जोड़ें';

  @override
  String get country => 'देश';

  @override
  String get saveChanges => 'बदलाव सेव करें';

  @override
  String get alreadyClaimed => 'आज का इनाम ले लिया — कल फिर आएँ।';

  @override
  String get dailyRewards => 'डेली इनाम';

  @override
  String get thisWeek => 'इस हफ़्ते';

  @override
  String get claimEveryDay => 'अपनी स्ट्रीक बढ़ाने के लिए रोज़ इनाम लें।';

  @override
  String get readyToClaim => 'लेने के लिए तैयार';

  @override
  String get nextReward => 'अगला इनाम';

  @override
  String get profile => 'प्रोफ़ाइल';

  @override
  String get gameStats => 'गेम आँकड़े';

  @override
  String get achievements => 'उपलब्धियाँ';

  @override
  String get manage => 'प्रबंधन';

  @override
  String get addBio => '+ परिचय जोड़ें';

  @override
  String get winRate => 'जीत दर';

  @override
  String get last7Days => 'पिछले 7 दिन';

  @override
  String get tokensWon => 'जीते गए टोकन';

  @override
  String get goldWon => 'जीता गया गोल्ड';

  @override
  String get editProfileSub => 'नाम, परिचय, देश';

  @override
  String get avatar => 'अवतार';

  @override
  String get chooseYourLook => 'अपना लुक चुनें';

  @override
  String get settingsSub => 'आवाज़, अलर्ट, खाता';

  @override
  String claimedReward(String reward) {
    return '$reward मिल गया';
  }

  @override
  String dayStreakSuffix(int count) {
    return ' · $count दिन की स्ट्रीक';
  }

  @override
  String get lessThanMinute => 'एक मिनट से कम';

  @override
  String durationHm(int h, int m) {
    return '$h घं $m मि';
  }

  @override
  String durationM(int m) {
    return '$m मि';
  }

  @override
  String claimedOfWeek(int count) {
    return '$count/7 लिए गए';
  }

  @override
  String claimDay(int day) {
    return 'दिन $day का इनाम लें';
  }

  @override
  String comeBackIn(String time) {
    return '$time में वापस आएँ';
  }

  @override
  String get aBit => 'थोड़ी देर';

  @override
  String tokensAmount(String amount) {
    return '$amount टोकन';
  }

  @override
  String powerUpCount(int count) {
    return '$count× पावर-अप';
  }

  @override
  String unlocksIn(String time) {
    return '$time में खुलेगा';
  }

  @override
  String get todaysRewardWaiting => 'आज का इनाम आपका इंतज़ार कर रहा है';

  @override
  String dayOfSeven(int day) {
    return 'दिन $day / 7';
  }

  @override
  String get currencyGold => 'गोल्ड';

  @override
  String get currencyTokens => 'टोकन';

  @override
  String streakDays(int count) {
    return '$count दिन की स्ट्रीक';
  }

  @override
  String get noStreakYet => 'अभी कोई स्ट्रीक नहीं';

  @override
  String get onARoll => 'आप शानदार चल रहे हैं — जारी रखें!';

  @override
  String get claimTodayToStart => 'शुरू करने के लिए आज का इनाम लें।';

  @override
  String get tileToday => 'आज';

  @override
  String get tileTomorrow => 'कल';

  @override
  String tileDay(int day) {
    return 'दिन $day';
  }

  @override
  String get claimed => 'ले लिया';

  @override
  String get mega => 'मेगा';

  @override
  String get dateOfBirth => 'जन्म तिथि';

  @override
  String get resultVictory => 'जीत';

  @override
  String get resultVictorySub => 'शानदार खेल, चैंपियन!';

  @override
  String get resultDefeat => 'हार';

  @override
  String get resultDefeatSub => 'बस थोड़ा सा — फिर से खेलें।';

  @override
  String get resultDraw => 'ड्रॉ';

  @override
  String get resultDrawSub => 'बराबरी का मुकाबला।';

  @override
  String get playAgain => 'फिर से खेलें';

  @override
  String get backToHome => 'होम पर वापस';

  @override
  String get you => 'आप';

  @override
  String get pot => 'पॉट';

  @override
  String get turnClock => 'चाल का समय';

  @override
  String get waiting => 'इंतज़ार';

  @override
  String get forfeitTitle => 'मैच छोड़ना है?';

  @override
  String get forfeitBody =>
      'यह राउंड हार माना जाएगा और आपको कोई इनाम नहीं मिलेगा।';

  @override
  String get forfeit => 'छोड़ें';

  @override
  String get keepPlaying => 'खेलते रहें';

  @override
  String get paused => 'रुका हुआ';

  @override
  String get resume => 'फिर से शुरू करें';

  @override
  String get forfeitMatch => 'मैच छोड़ें';

  @override
  String get chatHint => 'हाय कहें या इमोट भेजें';

  @override
  String get messageHint => 'संदेश…';

  @override
  String get lastMove => 'आख़िरी चाल';

  @override
  String get players => 'खिलाड़ी';

  @override
  String get yourColour => 'आपका रंग';

  @override
  String get startGame => 'गेम शुरू करें';

  @override
  String get ludoBlurb =>
      'टोकन बाहर लाने के लिए 6 लाएँ, विरोधियों को काटें, और सबसे पहले चारों टोकन घर पहुँचाएँ।';

  @override
  String get youForfeitedMatch => 'आपने मैच छोड़ दिया।';

  @override
  String get ludoWinSub => 'चारों टोकन घर — चैंपियन!';

  @override
  String get gameOver => 'गेम खत्म';

  @override
  String get rolling => 'पासा फेंका जा रहा है…';

  @override
  String get pickToken => 'चलाने के लिए टोकन चुनें';

  @override
  String get yourTurnRoll => 'आपकी बारी — पासा फेंकें';

  @override
  String get snakesBlurb =>
      'कंप्यूटर से 100 तक की दौड़। सीढ़ियाँ ऊपर ले जाती हैं, साँप नीचे — ठीक 100 पर पहुँचें।';

  @override
  String get youForfeitedRace => 'आपने दौड़ छोड़ दी।';

  @override
  String get snakesWinSub => 'सबसे पहले 100 — क्या चढ़ाई है!';

  @override
  String get bestAi => 'सबसे अच्छा AI';

  @override
  String get pausedSubtitle => 'सभी के लिए घड़ी रुकी हुई है।';

  @override
  String forfeitBodyStake(String amount) {
    return 'आपका $amount का दांव चला जाएगा और यह राउंड हार माना जाएगा।';
  }

  @override
  String youPlusAi(int count) {
    return 'आप + $count AI';
  }

  @override
  String moveOnHold(int move) {
    return 'चाल $move · गेम रुका हुआ है।';
  }

  @override
  String playerMoving(String name) {
    return '$name चल रहा है…';
  }

  @override
  String playerPlaying(String name) {
    return '$name खेल रहा है…';
  }

  @override
  String playerRolling(String name) {
    return '$name पासा फेंक रहा है…';
  }

  @override
  String get tapDiceToRoll => 'पासा फेंकने के लिए\nटैप करें';

  @override
  String get tapGlowingToken => 'चमकते टोकन पर\nटैप करें';

  @override
  String get moving => 'चल रहा है…';

  @override
  String get waitEllipsis => 'रुकें…';

  @override
  String tokensHomeOut(int home, int out) {
    return '$home घर · $out बाहर';
  }

  @override
  String squareN(int n) {
    return 'खाना $n';
  }

  @override
  String get startSquare => 'शुरुआत';

  @override
  String moveAndPlayers(int move, int players) {
    return 'चाल $move · $players खिलाड़ी';
  }

  @override
  String ludoLoseSub(String name) {
    return '$name ने सबसे पहले चारों टोकन घर पहुँचाए।';
  }

  @override
  String snakesLoseSub(String name) {
    return '$name सबसे पहले 100 पर पहुँचा।';
  }

  @override
  String get timePerTurn => 'हर चाल का समय';

  @override
  String timeSec(int n) {
    return '$n सेकंड';
  }

  @override
  String timeMin(int n) {
    return '$n मिनट';
  }

  @override
  String get unlimited => 'असीमित';

  @override
  String get timeUpRule => 'समय खत्म होने पर आपकी चाल अपने आप चल दी जाएगी।';

  @override
  String get timeUpPlayed => 'समय खत्म — आपकी चाल अपने आप चल दी गई';

  @override
  String turnRolling(int secs) {
    return 'पासा फेंक रहे हैं… · $secs से';
  }

  @override
  String turnYourRoll(int secs) {
    return 'आपकी बारी · $secs से';
  }

  @override
  String turnPick(int secs) {
    return 'टोकन चुनें · $secs से';
  }

  @override
  String get turnRollingNoClock => 'पासा फेंक रहे हैं…';

  @override
  String get turnYourRollNoClock => 'आपकी बारी';

  @override
  String get playAs => 'इस रंग से खेलें';

  @override
  String get difficulty => 'कठिनाई';

  @override
  String get easy => 'आसान';

  @override
  String get medium => 'मध्यम';

  @override
  String get hard => 'कठिन';

  @override
  String get relaxed => 'आरामदायक';

  @override
  String get balanced => 'संतुलित';

  @override
  String get tough => 'कड़ा';

  @override
  String get randomSide => 'कोई भी';

  @override
  String get playVsComputer => 'कंप्यूटर के खिलाफ खेलें';

  @override
  String get timePerMove => 'हर चाल का समय';

  @override
  String get timeOutLoses => 'किसी चाल पर समय खत्म होने पर आप गेम हार जाएँगे।';

  @override
  String get computer => 'कंप्यूटर';

  @override
  String discsCount(int count) {
    return '$count डिस्क';
  }

  @override
  String yourMoveSecs(int secs) {
    return 'आपकी चाल · $secs से';
  }

  @override
  String get yourMove => 'आपकी चाल';

  @override
  String thinkingSecs(int secs) {
    return 'सोच रहा है… · $secs से';
  }

  @override
  String get thinking => 'सोच रहा है…';

  @override
  String get computerThinking => 'कंप्यूटर सोच रहा है…';

  @override
  String othelloPlayed(String who, String square, int count) {
    return '$who ने $square पर चाल चली · $count पलटे';
  }

  @override
  String mustPass(String who) {
    return '$who के पास कोई चाल नहीं — पास';
  }

  @override
  String get othelloBlurb =>
      'कंप्यूटर को घेरें: आप जो भी डिस्क फँसाते हैं वह आपके रंग में पलट जाती है। बोर्ड भरने पर सबसे ज़्यादा डिस्क वाला जीतता है।';

  @override
  String get black => 'काला';

  @override
  String get white => 'सफ़ेद';

  @override
  String get youRanOutOfTime => 'आपका समय खत्म हो गया।';

  @override
  String get computerRanOutOfTime => 'कंप्यूटर का समय खत्म हो गया।';

  @override
  String othelloWinSub(int you, int them) {
    return '$you–$them — बोर्ड आपका है!';
  }

  @override
  String othelloLoseSub(int you, int them) {
    return '$you–$them — इस बार घिर गए।';
  }

  @override
  String othelloDrawSub(int you, int them) {
    return '$you–$them — बराबरी का बोर्ड।';
  }

  @override
  String get checkersBlurb =>
      'कूदकर काटें — यह ज़रूरी है, और लगातार कूद पूरी करनी होती है। आख़िरी पंक्ति तक पहुँचकर राजा बनें।';

  @override
  String get checkersDark => 'लाल';

  @override
  String get checkersLight => 'सफ़ेद';

  @override
  String piecesKings(int pieces, int kings) {
    return '$pieces मोहरे · $kings राजा';
  }

  @override
  String checkersMoved(String who, int from, int to) {
    return '$who ने $from–$to चला';
  }

  @override
  String checkersCaptured(String who, int count) {
    return '$who ने $count मोहरे काटे';
  }

  @override
  String get checkersWinSub =>
      'कंप्यूटर के पास कोई चाल नहीं बची — बढ़िया खेला!';

  @override
  String get checkersLoseSub => 'चालें खत्म — फिर से खेलें।';

  @override
  String get checkersDrawSub => 'बिना काटे 40 चालें — ड्रॉ।';

  @override
  String get scrabbleBlurb =>
      'कंप्यूटर के खिलाफ बोर्ड पर शब्द बनाएँ। प्रीमियम खाने अक्षरों और शब्दों को गुणा करते हैं; सभी 7 टाइल इस्तेमाल करने पर 50 अंक का बिंगो।';

  @override
  String get scrabbleTimeRule => 'समय खत्म होने पर आपकी बारी पास हो जाएगी।';

  @override
  String get loadingDictionary => 'शब्दकोश लोड हो रहा है…';

  @override
  String scoreN(int n) {
    return 'स्कोर $n';
  }

  @override
  String bagN(int n) {
    return 'थैला $n';
  }

  @override
  String get shuffle => 'मिलाएँ';

  @override
  String get recall => 'वापस लें';

  @override
  String get swap => 'बदलें';

  @override
  String get pass => 'पास';

  @override
  String playScore(int score) {
    return 'चलें · $score';
  }

  @override
  String get errPlaceTiles => 'बोर्ड पर टाइल रखें';

  @override
  String get errInLine => 'टाइल एक ही पंक्ति या कॉलम में हों';

  @override
  String get errGap => 'आपकी टाइलों के बीच खाली जगह न हो';

  @override
  String get errConnect => 'बोर्ड की टाइलों से जोड़ें';

  @override
  String get errCenter => 'पहला शब्द बीच के तारे पर होना चाहिए';

  @override
  String get errTooShort => 'शब्द में कम से कम 2 अक्षर हों';

  @override
  String errNotWord(String word) {
    return '$word शब्दकोश में नहीं है';
  }

  @override
  String scrabblePlayed(String who, String word, int score) {
    return '$who ने $word खेला · $score';
  }

  @override
  String scrabbleExchanged(String who, int count) {
    return '$who ने $count टाइल बदलीं';
  }

  @override
  String scrabblePassed(String who) {
    return '$who ने पास किया';
  }

  @override
  String get timeUpPassed => 'समय खत्म — आपकी बारी पास हो गई';

  @override
  String get swapTitle => 'बदलने के लिए टाइल चुनें';

  @override
  String swapN(int count) {
    return '$count बदलें';
  }

  @override
  String get passConfirmTitle => 'अपनी बारी पास करें?';

  @override
  String get passConfirmBody =>
      'इस बारी कोई अंक नहीं मिलेगा। लगातार छह बिना-अंक वाली बारियाँ गेम खत्म कर देती हैं।';

  @override
  String get pickLetter => 'खाली टाइल के लिए अक्षर चुनें';

  @override
  String get bagTooSmall => 'बदलने के लिए थैले में पर्याप्त टाइल नहीं';

  @override
  String scrabbleWinSub(int you, int them) {
    return '$you–$them — शब्दों के उस्ताद!';
  }

  @override
  String scrabbleLoseSub(int you, int them) {
    return '$you–$them — इस बार कंप्यूटर आगे रहा।';
  }

  @override
  String scrabbleDrawSub(int you, int them) {
    return '$you–$them — बराबरी!';
  }

  @override
  String get cancel => 'रद्द करें';

  @override
  String get practiceChips => 'अभ्यास चिप्स';

  @override
  String get bet => 'दांव';

  @override
  String betAmount(int amount) {
    return 'दांव $amount';
  }

  @override
  String cashOutAmount(int amount) {
    return 'कैश आउट $amount';
  }

  @override
  String wonAmount(int amount) {
    return 'जीते $amount';
  }

  @override
  String get nextRoundBet => 'दांव · अगला राउंड';

  @override
  String get cancelNextRound => 'रद्द · अगला राउंड';

  @override
  String nextRoundIn(String secs) {
    return 'अगला राउंड $secs से में';
  }

  @override
  String get flewAway => 'उड़ गया!';

  @override
  String get autoCashOut => 'ऑटो कैश-आउट';

  @override
  String get liveBets => 'लाइव दांव';

  @override
  String playersCount(int count) {
    return '$count खिलाड़ी';
  }

  @override
  String get outOfChips => 'चिप्स खत्म — खेलते रहने के लिए टॉप अप करें';

  @override
  String get topUp => 'टॉप अप';

  @override
  String get crashNote => 'अभ्यास मोड — चिप्स का कोई असली मूल्य नहीं है।';

  @override
  String get bingoBlurb =>
      'कंप्यूटर के खिलाफ 75-बॉल बिंगो। बोले गए नंबरों पर निशान लगाएँ और सबसे पहले BINGO बोलकर जीतें।';

  @override
  String get pattern => 'पैटर्न';

  @override
  String get patternLine => 'लाइन';

  @override
  String get patternCorners => 'चार कोने';

  @override
  String get patternFullHouse => 'फ़ुल हाउस';

  @override
  String get callSpeed => 'बोलने की गति';

  @override
  String get speedFast => 'तेज़';

  @override
  String get speedNormal => 'सामान्य';

  @override
  String get speedSlow => 'धीमा';

  @override
  String ballOf(int n) {
    return 'बॉल $n/75';
  }

  @override
  String needsN(int count) {
    return '$count बाकी';
  }

  @override
  String get bingoButton => 'बिंगो!';

  @override
  String get notYet => 'अभी नहीं — निशान लगाते रहें!';

  @override
  String get autoDaub => 'ऑटो-निशान';

  @override
  String bingoWinSub(int ball) {
    return 'बॉल $ball पर बिंगो!';
  }

  @override
  String bingoLoseSub(String name) {
    return '$name ने पहले बिंगो बोला।';
  }

  @override
  String get bingoNoWinner => 'सभी 75 बॉल बोले गए — कोई विजेता नहीं।';

  @override
  String get daubHint => 'अपने कार्ड पर बोले गए नंबरों पर टैप करें';

  @override
  String get computerPlayers => 'कंप्यूटर खिलाड़ी';

  @override
  String get cashedOutBanner => 'कैश आउट';

  @override
  String chipsWon(String amount) {
    return '+$amount चिप्स';
  }

  @override
  String get oneToGoTag => '1 बाकी';

  @override
  String get calledNumbers => 'बोले गए नंबर';

  @override
  String get tapForBoard => 'बोर्ड देखने के लिए टैप करें';

  @override
  String botCalledBingo(String name) {
    return '$name ने बिंगो बोला!';
  }

  @override
  String get placeYourBets => 'अपना दांव लगाएं';

  @override
  String get spinButton => 'घुमाएं';

  @override
  String get undo => 'पूर्ववत';

  @override
  String get clearBets => 'हटाएं';

  @override
  String get doubleBets => 'दोगुना';

  @override
  String get repeatBets => 'दोहराएं';

  @override
  String get noMoreBets => 'अब और दांव नहीं';

  @override
  String youWinAmount(String amount) {
    return 'आप जीते $amount';
  }

  @override
  String get noWinThisTime => 'इस बार कोई जीत नहीं';

  @override
  String totalBetAmount(String amount) {
    return 'दांव $amount';
  }

  @override
  String get tableLimitReached => 'टेबल सीमा पूरी';

  @override
  String get notEnoughChips => 'पर्याप्त चिप्स नहीं';

  @override
  String get practiceNote => 'अभ्यास मोड — चिप्स का कोई असली मूल्य नहीं है।';

  @override
  String get betRed => 'लाल';

  @override
  String get betBlack => 'काला';

  @override
  String get betOdd => 'विषम';

  @override
  String get betEven => 'सम';

  @override
  String get rouletteHint =>
      'किसी नंबर पर टैप करें, या स्प्लिट और कॉर्नर के लिए नंबरों के बीच की रेखा पर';

  @override
  String get lastResults => 'पिछले परिणाम';

  @override
  String get startRace => 'रेस शुरू करें';

  @override
  String get nextRace => 'अगली रेस';

  @override
  String raceNumber(int n) {
    return 'रेस $n';
  }

  @override
  String get winBet => 'जीत';

  @override
  String get top3Bet => 'टॉप 3';

  @override
  String takesTheLead(String name) {
    return '$name आगे निकल गया!';
  }

  @override
  String get photoFinish => 'फोटो फिनिश!';

  @override
  String winsTheRace(String name) {
    return '$name जीता!';
  }

  @override
  String get andTheyreOff => 'रेस शुरू!';

  @override
  String get finalStretch => 'आखिरी हिस्से में!';

  @override
  String get raceBetsHint => 'चुनी हुई चिप लगाने के लिए ऑड्स पर टैप करें';

  @override
  String racePayout(String amount) {
    return 'भुगतान $amount';
  }

  @override
  String get watchRace => 'रेस देखें';

  @override
  String get pokerFold => 'फोल्ड';

  @override
  String get pokerCheck => 'चेक';

  @override
  String pokerCall(String amount) {
    return 'कॉल $amount';
  }

  @override
  String get pokerRaise => 'रेज़';

  @override
  String pokerRaiseTo(String amount) {
    return '$amount तक रेज़';
  }

  @override
  String get pokerAllIn => 'ऑल-इन';

  @override
  String pokerPot(String amount) {
    return 'पॉट $amount';
  }

  @override
  String get pokerMin => 'न्यूनतम';

  @override
  String get pokerHalfPot => '½ पॉट';

  @override
  String get pokerFullPot => 'पॉट';

  @override
  String pokerWinsWith(String name, String amount, String hand) {
    return '$name जीते $amount · $hand';
  }

  @override
  String pokerWins(String name, String amount) {
    return '$name जीते $amount';
  }

  @override
  String pokerSplit(String hand) {
    return 'बँटा हुआ पॉट · $hand';
  }

  @override
  String pokerHand(int n) {
    return 'हैंड $n';
  }

  @override
  String pokerBlinds(String sb, String bb) {
    return 'ब्लाइंड्स $sb/$bb';
  }

  @override
  String pokerWaiting(String name) {
    return '$name का इंतज़ार…';
  }

  @override
  String get pokerBlurb =>
      'कंप्यूटर के खिलाफ टेक्सास होल्डेम। टेबल की हर चिप जीतें।';

  @override
  String get pokerStakes => 'दांव';

  @override
  String get pokerWinSub => 'आपने टेबल की हर चिप जीत ली!';

  @override
  String get pokerLoseSub => 'आपकी चिप्स खत्म हो गईं।';

  @override
  String get handHighCard => 'हाई कार्ड';

  @override
  String get handPair => 'पेयर';

  @override
  String get handTwoPair => 'टू पेयर';

  @override
  String get handThreeKind => 'थ्री ऑफ़ अ काइंड';

  @override
  String get handStraight => 'स्ट्रेट';

  @override
  String get handFlush => 'फ्लश';

  @override
  String get handFullHouse => 'फुल हाउस';

  @override
  String get handFourKind => 'फोर ऑफ़ अ काइंड';

  @override
  String get handStraightFlush => 'स्ट्रेट फ्लश';

  @override
  String get handRoyalFlush => 'रॉयल फ्लश';

  @override
  String get rummyBlurb =>
      'कंप्यूटर के खिलाफ 13 पत्तों की पॉइंट्स रमी। दो सीक्वेंस (एक प्योर) बनाएं और पहले डिक्लेयर करें।';

  @override
  String rummySubtitle(String card) {
    return 'पॉइंट्स रमी · वाइल्ड $card';
  }

  @override
  String get closedDeck => 'बंद डेक';

  @override
  String get openDeck => 'खुला डेक';

  @override
  String get wildJoker => 'वाइल्ड जोकर';

  @override
  String get rummySort => 'सॉर्ट';

  @override
  String get rummyGroup => 'ग्रुप';

  @override
  String get rummyDiscard => 'फेंकें';

  @override
  String get rummyDeclare => 'डिक्लेयर';

  @override
  String get rummyDrop => 'ड्रॉप';

  @override
  String get meldPure => 'प्योर सीक्वेंस';

  @override
  String get meldSequence => 'सीक्वेंस';

  @override
  String get meldSet => 'सेट';

  @override
  String get meldInvalid => 'अमान्य';

  @override
  String rummyPoints(int n) {
    return 'पॉइंट्स $n';
  }

  @override
  String get rummyDrawHint => 'आपकी बारी — बंद या खुले डेक से पत्ता लें';

  @override
  String get rummyDiscardHint => 'फेंकने के लिए पत्ता चुनें, या डिक्लेयर करें';

  @override
  String rummyPicked(String name, String card) {
    return '$name ने $card उठाया';
  }

  @override
  String rummyDrew(String name) {
    return '$name ने डेक से पत्ता लिया';
  }

  @override
  String rummyDiscarded(String name, String card) {
    return '$name ने $card फेंका';
  }

  @override
  String rummyDropped(String name) {
    return '$name ड्रॉप हो गया';
  }

  @override
  String get rummyDeclareTitle => 'अपना हाथ डिक्लेयर करें?';

  @override
  String get rummyValidShow => 'मान्य शो — आप यह डील जीतेंगे।';

  @override
  String get rummyInvalidShow =>
      'यह हाथ अभी मान्य नहीं है — गलत शो पर 80 पॉइंट्स लगेंगे।';

  @override
  String get rummyDropTitle => 'यह डील ड्रॉप करें?';

  @override
  String rummyDropBody(int n) {
    return 'आपको $n पॉइंट्स मिलेंगे और आप डील छोड़ देंगे।';
  }

  @override
  String get rummyWinSub => 'मान्य शो — आपने डील जीत ली!';

  @override
  String rummyLoseSub(String name, int n) {
    return '$name ने पहले डिक्लेयर किया। आपके पॉइंट्स: $n';
  }

  @override
  String get rummyWrongShowSub => 'गलत शो — 80 पॉइंट्स।';

  @override
  String rummyDroppedSub(int n) {
    return 'आप ड्रॉप हुए — $n पॉइंट्स।';
  }

  @override
  String cardsCount(int n) {
    return '$n पत्ते';
  }

  @override
  String get rummyPicking => 'पत्ता ले रहा है…';

  @override
  String get rummyThinking => 'सोच रहा है…';

  @override
  String get droppedLabel => 'ड्रॉप';

  @override
  String get referralHeadline => 'साथ खेलें, साथ कमाएं';

  @override
  String get referralBody =>
      'अपना कोड शेयर करें। जब कोई दोस्त इससे साइन अप करता है, तो आप दोनों को इनाम मिलता है।';

  @override
  String get yourInviteCode => 'आपका इनवाइट कोड';

  @override
  String get copyLabel => 'कॉपी';

  @override
  String get codeCopied => 'कोड कॉपी हो गया';

  @override
  String get shareInvite => 'इनवाइट शेयर करें';

  @override
  String inviteMessage(String app, String code) {
    return '$app पर मेरे साथ जुड़ें! वेलकम बोनस पाने के लिए मेरे कोड $code से साइन अप करें।';
  }

  @override
  String codeUses(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n बार उपयोग हुआ',
      one: 'एक बार उपयोग हुआ',
      zero: 'अभी उपयोग नहीं हुआ',
    );
    return '$_temp0';
  }

  @override
  String codeUsesOf(int n, int max) {
    return '$max में से $n उपयोग';
  }

  @override
  String codeExpires(String date) {
    return '$date को समाप्त';
  }

  @override
  String get codeExpired => 'यह कोड समाप्त हो गया है';

  @override
  String get codeUsedUp => 'यह कोड अपनी सीमा तक पहुँच गया है';

  @override
  String get friendsJoined => 'जुड़े दोस्त';

  @override
  String get rewardsEarned => 'मिले इनाम';

  @override
  String get howItWorks => 'यह कैसे काम करता है';

  @override
  String get referralStep1 => 'अपना कोड दोस्तों के साथ शेयर करें';

  @override
  String get referralStep2 => 'वे आपके कोड से साइन अप करते हैं';

  @override
  String get referralStep3 => 'आप दोनों को इनाम मिलता है';

  @override
  String get noReferralsYet =>
      'अभी कोई दोस्त नहीं जुड़ा — शुरू करने के लिए अपना कोड शेयर करें।';

  @override
  String referralsJoined(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n दोस्त आपके कोड से जुड़े',
      one: '1 दोस्त आपके कोड से जुड़ा',
    );
    return '$_temp0';
  }

  @override
  String get referralCouldntLoad => 'आपका इनवाइट कोड लोड नहीं हो सका।';

  @override
  String get inviteFriendsTitle => 'दोस्तों को बुलाएं';

  @override
  String get yourTurnTapDice => 'आपकी बारी · डाइस पर टैप करें';

  @override
  String playerTurnName(String name) {
    return '$name की बारी';
  }

  @override
  String youRolledN(int n) {
    return 'आपने $n डाला';
  }

  @override
  String playerRolledN(String name, int n) {
    return '$name ने $n डाला';
  }

  @override
  String get diceTap => 'टैप';

  @override
  String get youAreRolling => 'डाइस घूम रहा है…';

  @override
  String youRolledPick(int n) {
    return 'आपने $n डाला · एक मोहरा चुनें';
  }
}
