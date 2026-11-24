// Rewards screens (07-rewards.md) against the demo rewards API: quests merge
// and claim, tiered achievement claims, the welcome claim → free spin flow
// and a paid bonus game.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/app/routes.dart';
import 'package:snakeladder/data/models/rewards.dart';
import 'package:snakeladder/screens/economy/bonus_game_screen.dart';
import 'package:snakeladder/screens/economy/quests_screen.dart';
import 'package:snakeladder/screens/onboarding/welcome_bonus_screen.dart';
import 'package:snakeladder/screens/profile/achievements_screen.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/rewards_service.dart';
import 'package:snakeladder/widgets/aura.dart' show GradientButton;

/// Counts calls; can be made to fail plays with INSUFFICIENT_FUNDS.
class _Api extends DemoRewardsApi {
  int questClaims = 0;
  int plays = 0;
  final tierClaims = <String?>[];
  bool broke = false;

  @override
  Future<QuestClaim> claimQuest(int questId) {
    questClaims++;
    return super.claimQuest(questId);
  }

  @override
  Future<AchievementClaim> claimAchievement(int id, {String? tier}) {
    tierClaims.add(tier);
    return super.claimAchievement(id, tier: tier);
  }

  @override
  Future<BonusPlayResult> playBonusGame(String idOrCode, {required String trigger, String? triggerRef}) async {
    plays++;
    if (broke) {
      throw const AppException('x', statusCode: 409, code: 'INSUFFICIENT_FUNDS', detail: 'insufficient funds');
    }
    return super.playBonusGame(idOrCode, trigger: trigger, triggerRef: triggerRef);
  }
}

Future<void> _pump(WidgetTester t, _Api api, Widget home) async {
  t.view.physicalSize = const Size(411, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(ProviderScope(
    overrides: [rewardsApiProvider.overrideWithValue(api)],
    child: MaterialApp(home: home, onGenerateRoute: Routes.onGenerateRoute),
  ));
  await t.pump(const Duration(milliseconds: 50));
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('quests: tabs, 0/target rows, claim once', (t) async {
    final api = _Api();
    await _pump(t, api, const QuestsScreen());
    expect(find.text('Warm-up'), findsOneWidget);
    expect(find.text('First blood'), findsOneWidget);
    expect(find.text('0 / 1'), findsOneWidget, reason: 'no progress row yet');
    expect(find.text('1 / 2'), findsOneWidget, reason: 'distinct games');
    await t.tap(find.text('Claim'));
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
    expect(api.questClaims, 1);
    expect(find.text('Claimed'), findsWidgets);
    expect(find.text('Claim'), findsNothing);
    await t.tap(find.text('Weekly'));
    await t.pump();
    expect(find.text('On a roll'), findsOneWidget);
    expect(find.text('3 / 10'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('achievements: flat claim, tier claim with its tier, mystery badge', (t) async {
    final api = _Api();
    await _pump(t, api, const AchievementsScreen());
    expect(find.text('Secret achievement'), findsOneWidget);
    expect(find.text('Dice Roller'), findsOneWidget);
    await t.tap(find.text('CLAIM'));
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
    expect(api.tierClaims, ['bronze']);
    expect(find.text('CLAIM'), findsNothing);
    await t.tap(find.text('Claim'));
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
    expect(api.tierClaims, ['bronze', null]);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('welcome: claim pays, then the free Welcome wheel opens and lands', (t) async {
    final api = _Api();
    await _pump(t, api, const WelcomeBonusScreen());
    expect(find.text('+500'), findsOneWidget);
    expect(find.textContaining('Claim within'), findsOneWidget);
    await t.tap(find.text('Claim'));
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(BonusGameScreen), findsOneWidget);
    expect(find.text('Spin'), findsOneWidget);
    await t.tap(find.text('Spin'));
    await t.pump();
    await t.tap(find.byType(GradientButton), warnIfMissed: false); // double tap
    await t.pump(const Duration(seconds: 4));
    await t.pump(const Duration(seconds: 1));
    expect(api.plays, 1);
    expect(find.text('Played'), findsOneWidget, reason: 'a second spin is not offered');
  });

  testWidgets('paid scratch card: not enough tokens', (t) async {
    final api = _Api()..broke = true;
    await _pump(t, api, const BonusGameScreen(code: 'scratch_gold', trigger: 'store'));
    expect(find.text('Play for 200 Tokens'), findsOneWidget);
    expect(find.text('Odds'), findsOneWidget);
    await t.tap(find.text('Play for 200 Tokens'));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Not enough tokens.'), findsOneWidget);
    expect(api.plays, 1);
    await t.pump(const Duration(seconds: 4));
  });
}
