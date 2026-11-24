// Safety screens (docs/services/12-safety.md) build at phone size, and the
// report sheet blocks a repeat report without a network call.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/safety.dart';
import 'package:snakeladder/screens/match/match_result_screen.dart';
import 'package:snakeladder/screens/safety/my_reports_screen.dart';
import 'package:snakeladder/screens/safety/report_sheets.dart';
import 'package:snakeladder/screens/safety/safety_screens.dart';
import 'package:snakeladder/services/app_prefs.dart';
import 'package:snakeladder/services/safety_service.dart';
import 'package:snakeladder/widgets/restriction_banner.dart';
import 'package:snakeladder/services/account_standing.dart';

class _MemPrefs extends AppPrefs {
  final Map<String, String> data = {};
  @override
  Future<String?> get(String key) async => data[key];
  @override
  Future<void> set(String key, String value) async => data[key] = value;
}

class _CountingApi extends DemoSafetyApi {
  int reports = 0;
  final List<Report> rows;
  _CountingApi([this.rows = const []]);
  @override
  Future<Report> report({required String reportedUserId, required ReportReason reason, String? description, ChatEvidence? chatMessage}) {
    reports++;
    return super.report(reportedUserId: reportedUserId, reason: reason, description: description, chatMessage: chatMessage);
  }

  @override
  Future<List<Report>> myReports() async => rows;
}

Widget _host(Widget child, List overrides) => ProviderScope(
      overrides: [reportedTrackerProvider.overrideWithValue(ReportedTracker(_MemPrefs())), ...overrides.cast()],
      child: MaterialApp(home: child),
    );

void main() {
  setUp(() {
    final b = TestWidgetsFlutterBinding.ensureInitialized();
    b.platformDispatcher.views.first.physicalSize = const Size(1170, 2532);
    b.platformDispatcher.views.first.devicePixelRatio = 3;
  });

  testWidgets('My reports: chips, quoted line, unknown status', (t) async {
    final rows = [
      Report.fromJson(const {
        'id': 6, 'reason': 'spam', 'status': 'actiontaken', 'reported_username': 'bob', //
        'evidence': {'chat_message': {'id': '1-0', 'body': 'spam spam spam', 'room_type': 'lobby', 'room_id': 'r'}},
        'created_at': '2026-11-24T09:58:41.600507Z',
      }),
      Report.fromJson(const {'id': 5, 'reason': 'x', 'status': 'weird', 'reported_username': 'eve'}),
    ];
    await t.pumpWidget(_host(const MyReportsScreen(), [safetyApiProvider.overrideWithValue(_CountingApi(rows))]));
    await t.pumpAndSettle();
    expect(find.text('Action taken'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
    expect(find.text('"spam spam spam"'), findsOneWidget);
  });

  testWidgets('My reports: empty list', (t) async {
    await t.pumpWidget(_host(const MyReportsScreen(), [safetyApiProvider.overrideWithValue(_CountingApi())]));
    await t.pumpAndSettle();
    expect(find.text("You haven't reported anyone."), findsOneWidget);
  });

  testWidgets('full screens and help page build', (t) async {
    for (final w in [
      AccountRestrictedScreen(until: DateTime.utc(2026, 11, 25, 10)),
      const AccountRestrictedScreen(),
      const RegionBlockedScreen(),
      const ResponsibleGamingScreen(),
    ]) {
      await t.pumpWidget(_host(w, const []));
      await t.pump();
      expect(t.takeException(), isNull);
    }
    expect(find.textContaining('Contact support to set or change a limit'), findsOneWidget);
  });

  testWidgets('report sheet: send, then a repeat is refused on the device', (t) async {
    final api = _CountingApi();
    await t.pumpWidget(_host(
      Scaffold(body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showReportPlayerSheet(context, playerId: 'p-1', playerName: 'Bob'),
          child: const Text('open'),
        ),
      )),
      [safetyApiProvider.overrideWithValue(api)],
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Report Bob'), findsOneWidget);
    await t.tap(find.text('Spam'));
    await t.pump();
    await t.tap(find.text('Send report'));
    await t.pumpAndSettle();
    expect(api.reports, 1);
    // "Also block Bob?" → Not now.
    if (find.text('Not now').evaluate().isNotEmpty) {
      await t.tap(find.text('Not now'));
      await t.pumpAndSettle();
    }
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Report Bob'), findsNothing);
    expect(api.reports, 1);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('match result offers report hooks only with ids', (t) async {
    await t.pumpWidget(_host(const MatchResultScreen(matchId: 'm-1', opponentId: 'p-2', oppName: 'Bob'), const []));
    await t.pumpAndSettle();
    expect(find.text('Report player'), findsOneWidget);
    expect(find.text('Report a problem with this match'), findsOneWidget);
    await t.pumpWidget(_host(const MatchResultScreen(), const []));
    await t.pumpAndSettle();
    expect(find.text('Report player'), findsNothing);
  });

  testWidgets('restriction banner follows the standing', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: RestrictionBanner(feature: RestrictedFeature.chat))),
    ));
    expect(find.textContaining("can't send messages"), findsNothing);
    c.read(accountStandingProvider.notifier).chatRefused();
    await t.pump();
    expect(find.text("You can't send messages for now."), findsOneWidget);
  });
}
