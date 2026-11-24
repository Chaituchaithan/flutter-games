import 'package:flutter/material.dart';

import '../onboarding/onboarding_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/onboarding/splash_screen.dart';
import '../screens/onboarding/language_screen.dart';
import '../screens/onboarding/otp_screen.dart';
import '../screens/onboarding/reset_password_screen.dart';
import '../screens/onboarding/welcome_bonus_screen.dart';
import '../screens/match/match_setup_screen.dart';
import '../screens/match/match_preview_screen.dart';
import '../screens/match/match_result_screen.dart';
import '../screens/economy/purchase_confirm_screen.dart';
import '../screens/economy/purchase_complete_screen.dart';
import '../screens/economy/transactions_screen.dart';
import '../screens/economy/daily_rewards_screen.dart';
import '../screens/economy/season_pass_screen.dart';
import '../screens/economy/referral_screen.dart';
import '../screens/economy/quests_screen.dart';
import '../screens/economy/bonus_game_screen.dart';
import '../screens/economy/bonus_games_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/avatars_screen.dart';
import '../screens/profile/game_history_screen.dart';
import '../screens/profile/achievements_screen.dart';

import 'package:snakeladder/screens/profile/level_up_screen.dart';

import '../screens/settings/settings_screen.dart';
import '../screens/social/inbox_screen.dart';
import '../screens/social/friends_screen.dart';
import '../screens/social/play_with_friends_screen.dart';
import '../screens/social/player_profile_screen.dart';
import '../screens/leaderboard/leaderboard_screen.dart';
import '../screens/tournaments/tournaments_screen.dart';
import '../screens/match/matchmaking_screen.dart';
import '../screens/match/lobby_screens.dart';
import '../configs/games/core/game_id.dart';
import '../screens/system/maintenance_screen.dart';
import '../screens/system/force_update_screen.dart';
import '../screens/system/loading_skeleton_screen.dart';
import '../screens/settings/change_password_screen.dart';
import '../screens/settings/account_screen.dart';
import '../screens/settings/addresses_screen.dart';
import '../screens/settings/delete_account_screen.dart';
import '../screens/settings/game_settings_screen.dart';
import '../screens/settings/privacy_screen.dart';
import '../screens/settings/notification_settings_screen.dart';
import '../screens/settings/sessions_screen.dart';
import '../screens/safety/my_reports_screen.dart';
import '../screens/safety/safety_screens.dart';
import 'app_profile.dart';
import 'main_shell.dart';

/// Named routes for the app. Screens that live inside the bottom-tab shell
/// (Home/Wheel/Store/Profile) are not routed directly — they live in [MainShell].
class Routes {
  static const splash = '/splash';
  static const language = '/language';
  static const onboarding = '/onboarding'; // intro carousel
  static const login = '/login';
  static const register = '/register';
  static const otp = '/otp';
  static const resetPassword = '/reset-password';
  static const welcomeBonus = '/welcome-bonus';
  static const home = '/home'; // MainShell
  static const settings = '/settings';
  static const matchSetup = '/match/setup';
  static const matchPreview = '/match/preview';
  static const matchResult = '/match/result';
  static const purchaseConfirm = '/economy/purchase-confirm';
  static const purchaseComplete = '/economy/purchase-complete';
  static const transactions = '/economy/transactions';
  static const dailyRewards = '/economy/daily-rewards';
  static const seasonPass = '/economy/season-pass';
  static const referral = '/economy/referral';
  static const quests = '/economy/quests';
  static const bonusGames = '/economy/bonus-games';
  static const bonusGame = '/economy/bonus-game'; // args: code, trigger, triggerRef
  static const inbox = '/social/inbox';
  static const friends = '/social/friends';
  static const playFriends = '/social/play';
  static const playerProfile = '/social/player';
  static const leaderboard = '/leaderboard';
  static const tournaments = '/tournaments';
  static const matchmaking = '/match/vs';
  static const openTables = '/match/open-tables'; // args: {'game': GameId}
  static const liveRooms = '/match/live-rooms'; // Bingo
  static const maintenance = '/system/maintenance';
  static const forceUpdate = '/system/update';
  static const loading = '/system/loading';
  static const editProfile = '/profile/edit';
  static const changePassword = '/settings/change-password';
  // Account screens (docs/services/02-profile-and-sessions.md)
  static const account = '/settings/account';
  static const addresses = '/settings/addresses';
  static const privacy = '/settings/privacy';
  static const gameSettings = '/settings/game';
  static const notificationSettings = '/settings/notifications';
  static const sessions = '/settings/sessions';
  static const deleteAccount = '/settings/delete-account';
  static const avatars = '/profile/avatars';
  static const gameHistory = '/profile/history';
  static const achievements = '/profile/achievements';
  static const levelUp = '/game/level-up';
  static const resultVictory = '/result/victory';
  static const resultDefeat = '/result/defeat';
  static const resultDraw = '/result/draw';
  // Safety (docs/services/12-safety.md)
  static const myReports = '/settings/my-reports';
  static const responsibleGaming = '/settings/responsible-gaming';
  static const accountRestricted = '/system/account-restricted'; // args: {'until': DateTime?}
  static const regionBlocked = '/system/region-blocked';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) =>
      MaterialPageRoute(builder: (_) => pageFor(settings), settings: settings);

  /// The same route as a soft cross-fade (e.g. leaving the splash).
  static Route<dynamic> fadeRoute(String name, {Object? arguments}) {
    final settings = RouteSettings(name: name, arguments: arguments);
    return PageRouteBuilder<dynamic>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, _, _) => pageFor(settings),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: child,
      ),
    );
  }

  /// The screen for [settings] (shared screens here; game screens from the
  /// app's game modules).
  static Widget pageFor(RouteSettings settings) {
    Widget page;
    switch (settings.name) {
      case splash:
        page = const SplashScreen();
      case language:
        final args = settings.arguments as Map<String, dynamic>?;
        page = LanguageScreen(fromSettings: args?['fromSettings'] as bool? ?? false);
      case onboarding:
        page = const OnboardingScreen();
      case login:
        final args = settings.arguments as Map<String, dynamic>?;
        page = LoginScreen(initialEmail: args?['email'] as String?);
      case register:
        final args = settings.arguments as Map<String, dynamic>?;
        page = RegisterScreen(
            saveProgress: args?['saveProgress'] as bool? ?? false, referralCode: args?['referralCode'] as String?);
      case otp:
        final args = settings.arguments as Map<String, dynamic>?;
        page = OtpScreen(
          mode: args?['mode'] == 'login' ? OtpMode.login : OtpMode.verifyEmail,
          email: args?['email'] as String?,
          minutes: args?['minutes'] as int? ?? 10,
        );
      case resetPassword:
        page = const ResetPasswordScreen();
      case welcomeBonus:
        page = const WelcomeBonusScreen();
      case home:
        final args = settings.arguments as Map<String, dynamic>?;
        page = MainShell(dailyBonusPrompt: args?['dailyBonusPrompt'] as bool? ?? false);
      case Routes.settings:
        page = const SettingsScreen();
      case matchSetup:
        page = const MatchSetupScreen();
      case matchPreview:
        page = const MatchPreviewScreen();
      case matchResult:
        page = const MatchResultScreen();
      case resultVictory:
        page = const MatchResultScreen(outcome: MatchOutcome.victory);
      case resultDefeat:
        page = const MatchResultScreen(outcome: MatchOutcome.defeat);
      case resultDraw:
        page = const MatchResultScreen(outcome: MatchOutcome.draw);
      case levelUp:
        page = const LevelUpScreen();
      case purchaseConfirm:
        page = const PurchaseConfirmScreen();
      case purchaseComplete:
        final args = settings.arguments as Map<String, dynamic>?;
        page = PurchaseCompleteScreen(
          amount: args?['amount'] as String?,
          unit: args?['unit'] as String?,
          gold: args?['gold'] as bool? ?? true,
        );
      case transactions:
        page = const TransactionsScreen();
      case dailyRewards:
        page = const DailyRewardsScreen();
      case seasonPass:
        page = const SeasonPassScreen();
      case quests:
        page = const QuestsScreen();
      case bonusGames:
        page = const BonusGamesScreen();
      case bonusGame:
        final args = settings.arguments as Map<String, dynamic>?;
        page = BonusGameScreen(
          code: args?['code'] as String? ?? 'scratch_gold',
          trigger: args?['trigger'] as String? ?? 'store',
          triggerRef: args?['triggerRef'] as String?,
        );
      case referral:
        page = const ReferralScreen();
      case inbox:
        page = const InboxScreen();
      case friends:
        page = const FriendsScreen();
      case playFriends:
        page = const PlayWithFriendsScreen();
      case playerProfile:
        final args = settings.arguments as Map<String, dynamic>?;
        page = PlayerProfileScreen(userId: args?['userId'] as String?, name: args?['name'] as String? ?? 'ZeroCool');
      case leaderboard:
        page = const LeaderboardScreen();
      case tournaments:
        page = const TournamentsScreen();
      case matchmaking:
        final args = settings.arguments as Map<String, dynamic>?;
        page = MatchmakingScreen(
          stake: args?['stake'] as int? ?? 200,
          tokens: args?['tokens'] as bool? ?? true,
          label: args?['label'] as String? ?? 'Friends room',
        );
      case openTables:
        final args = settings.arguments as Map<String, dynamic>?;
        page = OpenTablesScreen(game: args?['game'] as GameId? ?? GameId.ludo, variant: args?['variant'] as String?);
      case liveRooms:
        page = const LiveRoomsScreen();
      case maintenance:
        page = const MaintenanceScreen();
      case forceUpdate:
        page = const ForceUpdateScreen();
      case loading:
        page = const LoadingSkeletonScreen();
      case account:
        page = const AccountScreen();
      case addresses:
        page = const AddressesScreen();
      case privacy:
        page = const PrivacyScreen();
      case gameSettings:
        page = const GameSettingsScreen();
      case notificationSettings:
        page = const NotificationSettingsScreen();
      case sessions:
        page = const SessionsScreen();
      case deleteAccount:
        page = const DeleteAccountScreen();
      case changePassword:
        page = const ChangePasswordScreen();
      case editProfile:
        page = const EditProfileScreen();
      case avatars:
        page = const AvatarsScreen();
      case gameHistory:
        page = const GameHistoryScreen();
      case achievements:
        page = const AchievementsScreen();
      case myReports:
        page = const MyReportsScreen();
      case responsibleGaming:
        page = const ResponsibleGamingScreen();
      case accountRestricted:
        final args = settings.arguments as Map<String, dynamic>?;
        page = AccountRestrictedScreen(until: args?['until'] as DateTime?);
      case regionBlocked:
        page = const RegionBlockedScreen();
      default:
        // A game screen owned by one of this app's game modules; otherwise
        // the entry point ('/' on web maps here) — start at Splash.
        page = AppProfile.current.buildRoute(settings.name, settings.arguments) ?? const SplashScreen();
    }
    return page;
  }
}
