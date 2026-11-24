// The Wheel tab (07-rewards.md §5): it shows the server's wheel-type bonus
// games only (free spins the player is entitled to, paid store wheels), plays
// them through the play route and lands on the reply's `slot_index`. No prize
// is picked on the device.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/app/routes.dart';
import 'package:snakeladder/data/models/daily_bonus.dart';
import 'package:snakeladder/data/models/rewards.dart';
import 'package:snakeladder/data/repositories/rewards_repository.dart';
import 'package:snakeladder/screens/economy/rewards_ui.dart';
import 'package:snakeladder/screens/system/loading_skeleton_screen.dart' show Shimmer;
import 'package:snakeladder/screens/wheel/wheel_screen.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/rewards_service.dart';
import 'package:snakeladder/services/wallet_store.dart';

/// The demo gateway with switches: counts plays, can fail the list, hide
/// every wheel, refuse plays for lack of tokens, or never answer.
class _Api extends DemoRewardsApi {
  final playLog = <(String, String, String?)>[];
  bool broke = false;
  bool listFails = false;
  bool noWheels = false;
  bool spinGone = false;
  Completer<List<BonusGame>>? hang;

  @override
  Future<List<BonusGame>> bonusGames({String? trigger}) async {
    if (hang != null) return hang!.future;
    if (listFails) throw const AppException('Something went wrong.', statusCode: 500, code: 'INTERNAL_ERROR');
    final all = await super.bonusGames(trigger: trigger);
    return noWheels ? all.where((g) => g.gameType != 'wheel').toList() : all;
  }

  @override
  Future<WelcomeBonus?> welcomeBonus() async => noWheels ? null : super.welcomeBonus();

  @override
  Future<BonusPlayResult> playBonusGame(String idOrCode, {required String trigger, String? triggerRef}) async {
    playLog.add((idOrCode, trigger, triggerRef));
    if (spinGone) {
      throw const AppException('x', statusCode: 409, code: 'CONFLICT', detail: 'conflict: no_entitlement: the free spin was used');
    }
    if (broke) {
      throw const AppException('x', statusCode: 409, code: 'INSUFFICIENT_FUNDS', detail: 'insufficient funds');
    }
    return super.playBonusGame(idOrCode, trigger: trigger, triggerRef: triggerRef);
  }
}

Future<void> _pump(WidgetTester t, _Api api) async {
  t.view.physicalSize = const Size(430, 932);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  await t.pumpWidget(ProviderScope(
    overrides: [rewardsApiProvider.overrideWithValue(api)],
    child: MaterialApp(
      home: const Scaffold(body: SafeArea(child: WheelScreen())),
      onGenerateRoute: Routes.onGenerateRoute,
    ),
  ));
  await t.pump(const Duration(milliseconds: 50));
  await t.pump(const Duration(milliseconds: 50));
}

ProviderContainer _container(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(WheelScreen)));

Future<void> _tapSpin(WidgetTester t) async {
  await t.tap(find.text('SPIN').last, warnIfMissed: false);
}

void main() {
  group('bonusWheelTarget', () {
    test('lands the server slot under the pointer after full turns', () {
      for (final slots in [4, 8, 10]) {
        final slice = 2 * math.pi / slots;
        for (var slot = 0; slot < slots; slot++) {
          for (final from in [0.0, 1.3, 7.9]) {
            final to = bonusWheelTarget(from, slot, slots);
            expect(to - from % (2 * math.pi), greaterThanOrEqualTo(2 * math.pi * 5));
            final rest = to % (2 * math.pi);
            final want = (-slot * slice) % (2 * math.pi);
            final diff = (rest - want).abs();
            expect(math.min(diff, 2 * math.pi - diff), lessThan(1e-9), reason: 'slots $slots slot $slot from $from');
          }
        }
      }
    });
  });

  group('freeSpinOffers', () {
    const day28 = DailyReward(dayNumber: 28, bonusGameId: 2);
    final claimedAt = DateTime.utc(2026, 11, 24, 9);
    final spinDay = DailyBonusStatus(
      currentStreak: 28,
      canClaim: false,
      nextReward: const DailyReward(dayNumber: 29),
      lastClaimedAt: claimedAt,
      rewards: const [day28],
    );

    test('the welcome free spin only while available', () {
      final on = WelcomeBonus.fromJson({
        'grant': {'id': 7, 'status': 'completed'},
        'free_spin': {'bonus_game_id': 1, 'code': 'welcome_wheel', 'available': true, 'trigger': 'welcome_bonus', 'trigger_ref': '7'},
      });
      final off = WelcomeBonus.fromJson({
        'grant': {'id': 7, 'status': 'completed'},
        'free_spin': {'bonus_game_id': 1, 'code': 'welcome_wheel', 'available': false, 'block_reason': 'used', 'trigger': 'welcome_bonus', 'trigger_ref': '7'},
      });
      final o = freeSpinOffers(welcome: on).single;
      expect((o.code, o.trigger, o.triggerRef), ('welcome_wheel', 'welcome_bonus', '7'));
      expect(freeSpinOffers(welcome: off), isEmpty);
      expect(freeSpinOffers(), isEmpty);
    });

    test('the daily spin after a spin-day claim, until it is played', () {
      final o = freeSpinOffers(daily: spinDay).single;
      expect((o.code, o.trigger, o.triggerRef), ('2', 'daily_bonus_day', null));
      final before = BonusPlayRecord(id: 1, trigger: 'daily_bonus_day', playedAt: claimedAt.subtract(const Duration(days: 7)));
      expect(freeSpinOffers(daily: spinDay, plays: [before]), hasLength(1), reason: 'an older claim\'s spin');
      final after = BonusPlayRecord(id: 2, trigger: 'daily_bonus_day', playedAt: claimedAt.add(const Duration(minutes: 1)));
      expect(freeSpinOffers(daily: spinDay, plays: [after]), isEmpty);
    });

    test('no daily spin on an ordinary day or before any claim', () {
      final plain = DailyBonusStatus(
        currentStreak: 3,
        canClaim: false,
        nextReward: const DailyReward(dayNumber: 4),
        lastClaimedAt: claimedAt,
        rewards: const [DailyReward(dayNumber: 3, gold: 200)],
      );
      expect(freeSpinOffers(daily: plain), isEmpty);
      expect(freeSpinOffers(daily: const DailyBonusStatus(currentStreak: 0, canClaim: true, nextReward: DailyReward(dayNumber: 1))), isEmpty);
    });
  });

  group('wheelSpinsProvider', () {
    test('free wheels first, then store wheels; scratch cards and used spins left out', () async {
      final api = DemoRewardsApi();
      final c = ProviderContainer(overrides: [rewardsApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      final sub = c.listen(wheelSpinsProvider, (_, _) {});
      addTearDown(sub.close);
      var spins = await c.read(wheelSpinsProvider.future);
      expect([for (final s in spins) (s.game.code, s.trigger, s.free)], [
        ('welcome_wheel', 'welcome_bonus', true),
        ('lucky_wheel', 'store', false),
      ]);
      final w = spins.first;
      await api.playBonusGame(w.game.code, trigger: w.trigger, triggerRef: w.triggerRef);
      c.invalidate(welcomeBonusProvider);
      spins = await c.read(wheelSpinsProvider.future);
      expect([for (final s in spins) s.game.code], ['lucky_wheel']);
    });
  });

  testWidgets('free welcome spin: server play, lands, pays from balances, not offered again', (t) async {
    final api = _Api();
    await _pump(t, api);
    expect(find.text('Lucky Spin'), findsOneWidget);
    expect(find.text('Welcome wheel'), findsOneWidget);
    expect(find.text('Lucky wheel'), findsOneWidget);
    expect(find.text('Free spin'), findsOneWidget);

    await _tapSpin(t);
    await t.pump();
    await _tapSpin(t); // double tap while the request runs
    await t.pump(const Duration(milliseconds: 100));
    await _tapSpin(t); // and while the wheel turns
    expect(api.playLog, [('welcome_wheel', 'welcome_bonus', '1')]);

    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(milliseconds: 100));
    // The demo's first draw is slot 0: "50 tokens".
    expect(find.text('+50 Tokens'), findsOneWidget);
    expect(_container(t).read(walletProvider).value?.tokens, 5050, reason: 'header balance from the reply');

    await t.pump(const Duration(seconds: 4));
    expect(find.text('Welcome wheel'), findsNothing, reason: 'the used free spin leaves the tab');
    expect(find.text('100 Tokens per spin · 10 left today'), findsOneWidget);
  });

  testWidgets('paid wheel: Not enough tokens offers the Store', (t) async {
    final api = _Api()..broke = true;
    await _pump(t, api);
    await t.tap(find.text('Lucky wheel'));
    await t.pump();
    expect(find.text('100 Tokens per spin · 10 left today'), findsOneWidget);
    await _tapSpin(t);
    await t.pump(const Duration(milliseconds: 300));
    expect(api.playLog, [('lucky_wheel', 'store', null)]);
    expect(find.text('Not enough tokens.'), findsOneWidget);
    expect(find.text('Go to Store'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('paid wheel: a play charges and pays through the server', (t) async {
    final api = _Api();
    await _pump(t, api);
    await t.tap(find.text('Lucky wheel'));
    await t.pump();
    await _tapSpin(t);
    await t.pump(const Duration(milliseconds: 100)); // the reply; the wheel starts
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(milliseconds: 100));
    expect(api.playLog, [('lucky_wheel', 'store', null)]);
    // Demo draw 0 → slot 0 "50 tokens"; cost 100: 5000 − 100 + 50.
    expect(find.text('+50 Tokens'), findsOneWidget);
    expect(_container(t).read(walletProvider).value?.tokens, 4950);
    await t.pump(const Duration(seconds: 4));
    expect(find.text('100 Tokens per spin · 9 left today'), findsOneWidget);
  });

  testWidgets('a free spin the server refuses shows its text and is not offered', (t) async {
    final api = _Api()..spinGone = true;
    await _pump(t, api);
    await _tapSpin(t);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text("This free play isn't available."), findsOneWidget);
    await t.pump(const Duration(milliseconds: 100));
    expect(api.playLog, hasLength(1));
    expect(find.text('Welcome wheel'), findsNothing, reason: 'not offered again although the list still has it');
    expect(find.text('100 Tokens per spin · 10 left today'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('odds sheet lists the server prizes', (t) async {
    await _pump(t, _Api());
    await t.tap(find.text('See odds'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(BonusOddsTable), findsOneWidget);
    expect(find.text('0.50%'), findsOneWidget);
  });

  testWidgets('loading, then error with Retry', (t) async {
    final api = _Api()..hang = Completer();
    await _pump(t, api);
    expect(find.byType(Shimmer), findsOneWidget);
    api.hang!.complete(const []);
    api
      ..hang = null
      ..listFails = true;
    // Re-read with the list failing.
    _container(t).invalidate(bonusGamesProvider);
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('SPIN'), findsNothing);
    api.listFails = false;
    await t.tap(find.text('Retry'));
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Lucky wheel'), findsOneWidget);
  });

  testWidgets('no wheel available', (t) async {
    await _pump(t, _Api()..noWheels = true);
    expect(find.text('No spins right now'), findsOneWidget);
    expect(find.text('SPIN'), findsNothing);
  });
}
