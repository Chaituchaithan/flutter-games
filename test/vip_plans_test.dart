import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/subscription.dart';
import 'package:snakeladder/data/repositories/subscription_repository.dart';
import 'package:snakeladder/data/sources/subscription_source.dart';
import 'package:snakeladder/screens/store/store_screen.dart';
import 'package:snakeladder/services/app_exception.dart';

// The live /plans response (2026-10-11).
const _plansJson = '''[
 {"id":1,"name":"Free Monthly","tier":"free","billing_interval":"monthly","price_cents":"0","duration_days":30,"features":{},"is_active":true},
 {"id":2,"name":"Silver Monthly","tier":"silver","billing_interval":"monthly","price_cents":"499","duration_days":30,"features":{},"is_active":true},
 {"id":4,"name":"Gold Monthly","tier":"gold","billing_interval":"monthly","price_cents":"999","duration_days":30,"features":{},"is_active":true},
 {"id":3,"name":"Silver Yearly","tier":"silver","billing_interval":"yearly","price_cents":"4999","duration_days":365,"features":{},"is_active":true},
 {"id":5,"name":"Gold Yearly","tier":"gold","billing_interval":"yearly","price_cents":"9999","duration_days":365,"features":{},"is_active":true}
]''';

List<SubscriptionPlan> _plans() =>
    [for (final e in jsonDecode(_plansJson) as List) SubscriptionPlan.fromJson((e as Map).cast<String, dynamic>())];

/// The live plans; subscribe answers like the gateway today (503).
class _Src implements SubscriptionSource {
  int? subscribed;
  @override
  Future<List<SubscriptionPlan>> plans() async => _plans();
  @override
  Future<MySubscription> my() async => MySubscription.none;
  @override
  Future<void> subscribe(int planId, {bool autoRenew = true}) async {
    subscribed = planId;
    throw const AppException('Service unavailable', kind: AppErrorKind.server, statusCode: 503);
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  test('plans parse: string cents, tiers, billing periods', () {
    final p = _plans();
    expect(p.length, 5);
    final silverYear = p.firstWhere((x) => x.id == 3);
    expect(silverYear.tier, 'silver');
    expect(silverYear.yearly, isTrue);
    expect(silverYear.priceCents, 4999);
    expect(silverYear.price, '\$49.99');
    expect(p.firstWhere((x) => x.id == 1).free, isTrue);
  });

  testWidgets('VIP tab: Monthly / Yearly prices, saving badge, 503 → coming soon', (t) async {
    t.view.physicalSize = const Size(430, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final src = _Src();
    await t.pumpWidget(ProviderScope(
      overrides: [subscriptionSourceProvider.overrideWithValue(src)],
      child: const MaterialApp(home: Scaffold(body: StoreScreen())),
    ));
    ProviderScope.containerOf(t.element(find.byType(StoreScreen))).read(storeTabProvider.notifier).select(3);
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300)); // plans loaded
    expect(find.text('\$4.99'), findsOneWidget); // Silver monthly card
    expect(find.text('\$9.99'), findsWidgets); // Gold monthly (card + details)

    await t.tap(find.text('Yearly'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('\$49.99'), findsOneWidget);
    expect(find.text('\$99.99'), findsWidgets);
    expect(find.text('SAVE 17%'), findsNWidgets(2));

    await t.tap(find.textContaining('Subscribe ·'));
    await t.pump(const Duration(milliseconds: 300));
    expect(src.subscribed, 5, reason: 'Gold Yearly plan id');
    expect(find.textContaining('coming soon'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });
}
