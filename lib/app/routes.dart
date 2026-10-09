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
import '../screens/games/chess_screen.dart';
import '../screens/games/chess_online_screen.dart';
import '../screens/games/chess_vs_computer_screen.dart';
import '../screens/games/chess_setup_screen.dart';
import '../screens/games/othello_screen.dart';
import '../screens/games/snakes_ladders_screen.dart';
import '../screens/games/ludo_screen.dart';
import '../screens/games/scrabble_screen.dart';
import '../screens/games/trivia_screen.dart';
import '../screens/games/level_up_screen.dart';
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
  static const avatars = '/profile/avatars';
  static const gameHistory = '/profile/history';
  static const achievements = '/profile/achievements';
  static const chess = '/game/chess';
  static const chessOnline = '/game/chess-online';
  static const chessVsComputer = '/game/chess-vs-computer';
  static const chessSetup = '/game/chess-setup';
  static const othello = '/game/othello';
  static const snakesLadders = '/game/snakes-ladders';
  static const ludo = '/game/ludo';
  static const scrabble2p = '/game/scrabble-2p';
  static const scrabble4p = '/game/scrabble-4p';
  static const trivia2p = '/game/trivia-2p';
  static const trivia4p = '/game/trivia-4p';
  static const levelUp = '/game/level-up';
  static const resultVictory = '/result/victory';
  static const resultDefeat = '/result/defeat';
  static const resultDraw = '/result/draw';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
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
      case editProfile:
        page = const EditProfileScreen();
      case avatars:
        page = const AvatarsScreen();
      case gameHistory:
        page = const GameHistoryScreen();
      case achievements:
        page = const AchievementsScreen();
      case chess:
        page = const ChessScreen();
      case chessVsComputer:
        page = const ChessVsComputerScreen();
      case chessSetup:
        page = const ChessSetupScreen();
      case chessOnline:
        final args = settings.arguments as Map<String, dynamic>?;
        page = ChessOnlineScreen(
          stake: args?['stake'] as int? ?? 0,
          tokens: args?['tokens'] as bool? ?? true,
          mode: switch (args?['mode'] as String?) {
            'create' => ChessEntryMode.create,
            'join' => ChessEntryMode.join,
            _ => ChessEntryMode.match,
          },
          joinCode: args?['code'] as String?,
        );
      case othello:
        page = const OthelloScreen();
      case snakesLadders:
        page = const SnakesLaddersScreen();
      case ludo:
        page = const LudoScreen();
      case scrabble2p:
        page = const ScrabbleScreen(players: 2);
      case scrabble4p:
        page = const ScrabbleScreen(players: 4);
      case trivia2p:
        page = const TriviaScreen(players: 2);
      case trivia4p:
        page = const TriviaScreen(players: 4);
      default:
        // Entry point ('/' on web maps here) — start at Splash.
        page = const SplashScreen();
    }
    return MaterialPageRoute(builder: (_) => page, settings: settings);
  }
}
