// Builds every screen at a realistic phone size and asserts it lays out
// without throwing. This catches layout errors (e.g. unbounded-height Rows)
// that `flutter analyze` cannot see.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/screens/auth/login_screen.dart';
import 'package:snakeladder/screens/auth/register_screen.dart';
import 'package:snakeladder/screens/home/home_screen.dart';
import 'package:snakeladder/screens/wheel/wheel_screen.dart';
import 'package:snakeladder/screens/store/store_screen.dart';
import 'package:snakeladder/screens/profile/profile_screen.dart';
import 'package:snakeladder/screens/settings/settings_screen.dart';
import 'package:snakeladder/screens/match/match_setup_screen.dart';
import 'package:snakeladder/screens/match/match_preview_screen.dart';
import 'package:snakeladder/screens/match/match_result_screen.dart';
import 'package:snakeladder/screens/onboarding/language_screen.dart';
import 'package:snakeladder/screens/onboarding/otp_screen.dart';
import 'package:snakeladder/screens/onboarding/reset_password_screen.dart';
import 'package:snakeladder/screens/onboarding/welcome_bonus_screen.dart';
import 'package:snakeladder/screens/economy/purchase_confirm_screen.dart';
import 'package:snakeladder/screens/economy/purchase_complete_screen.dart';
import 'package:snakeladder/screens/economy/transactions_screen.dart';
import 'package:snakeladder/screens/economy/daily_rewards_screen.dart';
import 'package:snakeladder/screens/economy/season_pass_screen.dart';
import 'package:snakeladder/screens/economy/referral_screen.dart';
import 'package:snakeladder/screens/profile/edit_profile_screen.dart';
import 'package:snakeladder/screens/profile/avatars_screen.dart';
import 'package:snakeladder/screens/profile/game_history_screen.dart';
import 'package:snakeladder/screens/profile/achievements_screen.dart';
import 'package:snakeladder/game/chess/screens/chess_screen.dart';
import 'package:snakeladder/game/chess/screens/chess_setup_screen.dart';
import 'package:snakeladder/game/chess/screens/chess_vs_computer_screen.dart';
import 'package:snakeladder/game/othello/othello_screen.dart';
import 'package:snakeladder/game/snakes/snakes_ladders_screen.dart';
import 'package:snakeladder/game/ludo/ludo_screen.dart';
import 'package:snakeladder/game/checkers/checkers_screen.dart';
import 'package:snakeladder/game/scrabble/scrabble_screen.dart';
import 'package:snakeladder/game/prototypes/trivia_screen.dart';
import 'package:snakeladder/screens/profile/level_up_screen.dart';
import 'package:snakeladder/screens/social/inbox_screen.dart';
import 'package:snakeladder/screens/social/friends_screen.dart';
import 'package:snakeladder/screens/social/play_with_friends_screen.dart';
import 'package:snakeladder/screens/leaderboard/leaderboard_screen.dart';
import 'package:snakeladder/screens/tournaments/tournaments_screen.dart';
import 'package:snakeladder/screens/match/matchmaking_screen.dart';
import 'package:snakeladder/screens/system/maintenance_screen.dart';
import 'package:snakeladder/screens/system/force_update_screen.dart';
import 'package:snakeladder/screens/system/loading_skeleton_screen.dart';
import 'package:snakeladder/screens/social/player_profile_screen.dart';

void main() {
  // Tab screens return a body only, so give them a Scaffold host with a
  // bounded height (matching how MainShell embeds them).
  Widget tab(Widget child) => Scaffold(body: SafeArea(child: child));

  final cases = <String, Widget>{
    'Login': const LoginScreen(),
    'Register': const RegisterScreen(),
    'Home': tab(const HomeScreen()),
    'Wheel': tab(const WheelScreen()),
    'Store': tab(const StoreScreen()),
    'Profile': tab(const ProfileScreen()),
    'Settings': const SettingsScreen(),
    'MatchSetup': const MatchSetupScreen(),
    'MatchPreview': const MatchPreviewScreen(),
    'MatchResult': const MatchResultScreen(),
    'Language': const LanguageScreen(),
    'Otp': const OtpScreen(),
    'ResetPassword': const ResetPasswordScreen(),
    'WelcomeBonus': const WelcomeBonusScreen(),
    'PurchaseConfirm': const PurchaseConfirmScreen(),
    'PurchaseComplete': const PurchaseCompleteScreen(amount: '1,200', unit: 'Gold'),
    'Transactions': const TransactionsScreen(),
    'DailyRewards': const DailyRewardsScreen(),
    'SeasonPass': const SeasonPassScreen(),
    'Referral': const ReferralScreen(),
    'EditProfile': const EditProfileScreen(),
    'Avatars': const AvatarsScreen(),
    'GameHistory': const GameHistoryScreen(),
    'Achievements': const AchievementsScreen(),
    'Chess': const ChessScreen(),
    'ChessSetup': const ChessSetupScreen(),
    'ChessVsComputer': const ChessVsComputerScreen(),
    'Othello': const OthelloScreen(),
    'SnakesLadders': const SnakesLaddersScreen(),
    'Ludo': const LudoScreen(),
    'Scrabble': const ScrabbleScreen(),
    'Checkers': const CheckersScreen(),
    'Trivia2P': const TriviaScreen(players: 2),
    'Trivia4P': const TriviaScreen(players: 4),
    'LevelUp': const LevelUpScreen(),
    'ResultVictory': const MatchResultScreen(outcome: MatchOutcome.victory),
    'ResultDraw': const MatchResultScreen(outcome: MatchOutcome.draw),
    'Inbox': const InboxScreen(),
    'Friends': const FriendsScreen(),
    'Tournaments': const TournamentsScreen(),
    'Leaderboard': const LeaderboardScreen(),
    'PlayWithFriends': const PlayWithFriendsScreen(),
    'Matchmaking': const MatchmakingScreen(autoStart: false),
    'Maintenance': const MaintenanceScreen(),
    'ForceUpdate': const ForceUpdateScreen(),
    'LoadingSkeleton': const LoadingSkeletonScreen(),
    'PlayerProfile': const PlayerProfileScreen(),
  };

  for (final entry in cases.entries) {
    testWidgets('${entry.key} builds without layout errors',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(ProviderScope(child: MaterialApp(home: entry.value)));
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '${entry.key} threw');
    });
  }
}
