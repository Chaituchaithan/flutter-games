// Live inbox + notifications against the running gateway
// (docs/services/10-inbox-and-notifications.md), with a fresh guest.
// Skipped unless the address is given:
//
//   flutter test test/live_inbox_test.dart \
//     --dart-define=LIVE_API=http://192.168.0.235:1280/api/v1
//
// Only the admin console creates inbox items, so a new player's lists are
// empty: this checks the lists, preferences, quiet hours, the offers ↔
// privacy link and the error paths. Claim/read on real items need an admin
// message (see the doc's "Test accounts").

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/services/account_service.dart';
import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/app_exception.dart';
import 'package:snakeladder/services/auth_service.dart';
import 'package:snakeladder/services/inbox_service.dart';

const _api = String.fromEnvironment('LIVE_API');

void _log(String s) => debugPrint('[INBOX] $s');

void main() {
  test('inbox, notifications and preferences against the live gateway', () async {
    final client = ApiClient(dio: Dio(BaseOptions(baseUrl: '$_api/', contentType: 'application/json')));
    final g = await RemoteAuthService(client).loginGuest();
    client.authToken = g.accessToken;
    _log('guest ${g.user.username}');
    final inbox = RemoteInboxApi(client);
    final account = RemoteAccountApi(client);

    // Lists: empty pages for a new player, page fields parsed.
    final msgs = await inbox.inbox();
    expect(msgs.items, isEmpty);
    expect((msgs.total, msgs.page), (0, 1));
    final notes = await inbox.notifications();
    expect(notes.items, isEmpty);
    expect(notes.total, 0);
    _log('inbox: ${msgs.total} messages, notifications: ${notes.total}');

    // Preferences: the seven toggles, then a one-field change reads back.
    final p0 = await inbox.preferences();
    expect(p0.toggle('your_turn'), isTrue);
    final p1 = await inbox.updatePreferences({'your_turn': false});
    expect(p1.yourTurn, isFalse);
    expect(p1.friendRequests, p0.friendRequests, reason: 'omitted fields keep their values');
    expect((await inbox.preferences()).yourTurn, isFalse);
    await inbox.updatePreferences({'your_turn': true});
    _log('toggle your_turn off → on: ok');

    // Offers ↔ privacy marketing_push are one stored value.
    await inbox.updatePreferences({'promotions': false});
    expect((await account.privacy()).marketingPush, isFalse);
    await account.updatePrivacy({'marketing_push': true});
    expect((await inbox.preferences()).promotions, isTrue);
    _log('offers ↔ privacy marketing push stay in step: ok');

    // Quiet hours: on with both times + zone, off with three nulls.
    final q = await inbox.updatePreferences({'quiet_hours_start': '22:00:00', 'quiet_hours_end': '07:00:00', 'timezone': 'Asia/Kolkata'});
    expect((q.quietHoursOn, q.timezone), (true, 'Asia/Kolkata'));
    final off = await inbox.updatePreferences({'quiet_hours_start': null, 'quiet_hours_end': null, 'timezone': null});
    expect(off.quietHoursOn, isFalse);
    _log('quiet hours on/off: ok');

    // A bad zone → "Choose a valid time zone".
    try {
      await inbox.updatePreferences({'quiet_hours_start': '22:00:00', 'quiet_hours_end': '07:00:00', 'timezone': 'Mars/Olympus'});
      fail('a bad zone was accepted');
    } on AppException catch (e) {
      _log('bad zone → ${e.statusCode} ${e.code}: "${preferencesErrorText(e)}"');
      expect(preferencesErrorText(e), 'Choose a valid time zone.');
    }

    // Error paths on an id that doesn't exist.
    Future<InboxIssue> issue(Future<void> Function() call, InboxOp op) async {
      try {
        await call();
      } on AppException catch (e) {
        return inboxIssue(e, op);
      }
      fail('expected an error for $op');
    }

    expect((await issue(() => inbox.message(999999999), InboxOp.open)).kind, InboxIssueKind.gone);
    expect((await issue(() => inbox.delete(999999999), InboxOp.delete)).kind, InboxIssueKind.done);
    expect((await issue(() => inbox.claim(999999999), InboxOp.claim)).kind, InboxIssueKind.gone);
    _log('missing message: open → gone, delete → done, claim → gone: ok');
  }, timeout: const Timeout(Duration(minutes: 2)), skip: _api.isEmpty ? 'set --dart-define=LIVE_API=<gateway>/api/v1' : false);
}
