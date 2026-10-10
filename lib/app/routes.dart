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
import '../screens/system/maintenance_screen.dart';
import '../screens/system/force_update_screen.dart';
import '../screens/system/loading_skeleton_screen.dart';
import '../screens/settings/change_password_screen.dart';
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
  static const inbox = '/social/inbox';
  static const friends = '/social/friends';
  static const playFriends = '/social/play';
  static const playerProfile = '/social/player';
  static const leaderboard = '/leaderboard';
  static const tournaments = '/tournaments';
  static const matchmaking = '/match/vs';
  static const maintenance = '/system/maintenance';
  static const forceUpdate = '/system/update';
  static const loading = '/system/loading';
  static const editProfile = '/profile/edit';
  static const changePassword = '/settings/change-password';
  static const avatars = '/profile/avatars';
  static const gameHistory = '/profile/history';
  static const achievements = '/profile/achievements';
  static const levelUp = '/game/level-up';
  static const resultVictory = '/result/victory';
  static const resultDefeat = '/result/defeat';
  static const resultDraw = '/result/draw';

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
        page = const LoginScreen();
      case register:
        page = const RegisterScreen();
      case otp:
        page = const OtpScreen();
      case resetPassword:
        page = const ResetPasswordScreen();
      case welcomeBonus:
        page = const WelcomeBonusScreen();
      case home:
        page = const MainShell();
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
      case referral:
        page = const ReferralScreen();
      case inbox:
        page = const InboxScreen();
      case friends:
        page = const FriendsScreen();
      case playFriends:
        page = const PlayWithFriendsScreen();
      case playerProfile:
        page = const PlayerProfileScreen();
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
      case maintenance:
        page = const MaintenanceScreen();
      case forceUpdate:
        page = const ForceUpdateScreen();
      case loading:
        page = const LoadingSkeletonScreen();
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
      default:
        // A game screen owned by one of this app's game modules; otherwise
        // the entry point ('/' on web maps here) — start at Splash.
        page = AppProfile.current.buildRoute(settings.name, settings.arguments) ?? const SplashScreen();
    }
    return page;
  }
}
