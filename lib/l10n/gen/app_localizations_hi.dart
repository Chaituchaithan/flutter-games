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
}
