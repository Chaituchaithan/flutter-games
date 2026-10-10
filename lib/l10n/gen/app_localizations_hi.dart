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
}
