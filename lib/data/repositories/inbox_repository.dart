import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/account_store.dart';
import '../../services/app_exception.dart';
import '../../services/app_prefs.dart';
import '../../services/inbox_service.dart';
import '../../services/session.dart';
import '../../services/wallet_store.dart';
import '../models/inbox_message.dart';
import '../models/wallet.dart';

/// Inbox state (docs/services/10-inbox-and-notifications.md): the two lists,
/// the badge and the notification preferences. Nothing is pushed by the
/// server: everything is re-read (app start, resume, screen open, after an
/// inbox action).

// ── Paged lists ──────────────────────────────────────────────────────────

/// A list loaded page by page (`page + 1` until `page >= total_pages`).
@immutable
class PagedList<T> {
  const PagedList({
    this.items = const [],
    this.page = 0,
    this.totalPages = 0,
    this.total = 0,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  final List<T> items;

  /// The last page read; 0 = nothing read yet.
  final int page;
  final int totalPages;
  final int total;
  final bool loading;
  final bool loadingMore;

  /// The last failure (shown with Retry when there is nothing to show).
  final AppException? error;

  bool get loaded => page > 0;
  bool get hasMore => loaded && page < totalPages;
  bool get isEmpty => loaded && items.isEmpty;

  PagedList<T> copyWith({
    List<T>? items,
    int? page,
    int? totalPages,
    int? total,
    bool? loading,
    bool? loadingMore,
    AppException? error,
    bool clearError = false,
  }) =>
      PagedList(
        items: items ?? this.items,
        page: page ?? this.page,
        totalPages: totalPages ?? this.totalPages,
        total: total ?? this.total,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
      );
}

abstract class _PagedStore<T> extends Notifier<PagedList<T>> {
  static const perPage = 20;
  int _gen = 0;

  Future<InboxPage<T>> fetch(InboxApi api, int page);
  Object keyOf(T item);

  @override
  PagedList<T> build() {
    ref.watch(sessionProvider.select((u) => u?.id));
    ref.watch(inboxApiProvider);
    _gen++;
    return PagedList<T>();
  }

  /// Page 1 (screen open, pull to refresh). Keeps the old rows on a failure.
  Future<void> reload() async {
    final gen = ++_gen;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final p = await fetch(ref.read(inboxApiProvider), 1);
      if (gen != _gen) return;
      state = PagedList(items: p.items, page: p.page < 1 ? 1 : p.page, totalPages: p.totalPages, total: p.total);
    } on AppException catch (e) {
      if (gen == _gen) state = state.copyWith(loading: false, error: e);
    }
  }

  /// The next page; rows already shown are not repeated.
  Future<void> loadMore() async {
    if (!state.hasMore || state.loading || state.loadingMore) return;
    final gen = _gen;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final p = await fetch(ref.read(inboxApiProvider), state.page + 1);
      if (gen != _gen) return;
      final seen = {for (final i in state.items) keyOf(i)};
      state = PagedList(
        items: [...state.items, ...p.items.where((i) => !seen.contains(keyOf(i)))],
        page: p.page,
        totalPages: p.totalPages,
        total: p.total,
      );
    } on AppException catch (e) {
      if (gen == _gen) state = state.copyWith(loadingMore: false, error: e);
    }
  }
}

/// What a claim ended as, for the detail screen.
enum ClaimOutcomeKind { claimed, alreadyClaimed, expired, gone, noReward, failed }

@immutable
class ClaimOutcome {
  const ClaimOutcome(this.kind, {this.text, this.message, this.result});
  final ClaimOutcomeKind kind;

  /// Player text ("+500 tokens", "Already claimed.", …); null = nothing.
  final String? text;

  /// The message as it is now (null when gone).
  final InboxMessage? message;
  final ClaimResult? result;

  /// Treated as success (a `409` too).
  bool get ok => kind == ClaimOutcomeKind.claimed || kind == ClaimOutcomeKind.alreadyClaimed;
}

/// The Inbox list and every action on a message.
class InboxStore extends _PagedStore<InboxMessage> {
  @override
  Future<InboxPage<InboxMessage>> fetch(InboxApi api, int page) => api.inbox(page: page, perPage: _PagedStore.perPage);

  @override
  Object keyOf(InboxMessage item) => item.id;

  InboxApi get _api => ref.read(inboxApiProvider);
  InboxBadgeStore get _badge => ref.read(inboxBadgeProvider.notifier);

  int get unread => state.items.where((m) => !m.isRead).length;

  void _replace(InboxMessage m) {
    if (!state.items.any((i) => i.id == m.id)) return;
    state = state.copyWith(items: [for (final i in state.items) i.id == m.id ? m : i]);
  }

  void _remove(int id) {
    if (!state.items.any((i) => i.id == id)) return;
    state = state.copyWith(items: state.items.where((i) => i.id != id).toList(), total: state.total > 0 ? state.total - 1 : 0);
  }

  /// `GET /inbox/{id}` — opening from elsewhere (a future push). Null when
  /// it is gone (also removed from the list).
  Future<InboxMessage?> fetchMessage(int id) async {
    try {
      final m = await _api.message(id);
      _replace(m);
      return m;
    } on AppException catch (e) {
      if (inboxIssue(e, InboxOp.open).kind == InboxIssueKind.gone) {
        _remove(id);
        return null;
      }
      rethrow;
    }
  }

  /// The player opened [m]: mark it read here and on the badge at once, then
  /// on the server. A `404` removes it. Returns the message as now shown.
  Future<InboxMessage> open(InboxMessage m) async {
    if (m.isRead) return m;
    final read = m.copyWith(isRead: true, readAt: DateTime.now().toUtc());
    _replace(read);
    _badge.markedRead(m);
    try {
      await _api.markRead(m.id);
    } on AppException catch (e) {
      if (inboxIssue(e, InboxOp.read).kind == InboxIssueKind.gone) _remove(m.id);
    }
    _badge.refresh();
    return read;
  }

  /// No "mark all" route: one call per unread message.
  Future<void> markAllRead() async {
    final unread = state.items.where((m) => !m.isRead).toList();
    for (final m in unread) {
      await open(m);
    }
  }

  /// `POST /inbox/{id}/claim-reward`. On `200` the reply's amounts are
  /// shown and the wallet is re-read; a `409` is "Already claimed" (the
  /// message and the wallet are re-read); a timeout re-reads the message to
  /// learn whether the claim went through.
  Future<ClaimOutcome> claim(InboxMessage m) async {
    try {
      final r = await _api.claim(m.id);
      final now = DateTime.now().toUtc();
      final next = m.copyWith(isRead: true, readAt: m.readAt ?? now, claimedAt: now);
      _replace(next);
      _badge.claimed(m);
      _creditWallet(r);
      _badge.refresh();
      return ClaimOutcome(ClaimOutcomeKind.claimed, text: r.label.isEmpty ? 'Claimed.' : r.label, message: next, result: r);
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.timeout) {
        final again = await _reread(m);
        if (again?.claimedAt != null) {
          _badge.claimed(m);
          _creditWallet(null);
          _badge.refresh();
          return ClaimOutcome(ClaimOutcomeKind.claimed, text: 'Claimed.', message: again);
        }
      }
      final issue = inboxIssue(e, InboxOp.claim, hasReward: m.hasReward);
      switch (issue.kind) {
        case InboxIssueKind.alreadyClaimed:
          final again = await _reread(m) ?? m.copyWith(isRead: true, claimedAt: DateTime.now().toUtc());
          _replace(again);
          _badge.claimed(m);
          _creditWallet(null);
          _badge.refresh();
          return ClaimOutcome(ClaimOutcomeKind.alreadyClaimed, text: issue.text, message: again);
        case InboxIssueKind.gone:
          _remove(m.id);
          _badge.removed(m);
          return ClaimOutcome(ClaimOutcomeKind.gone, text: issue.text);
        case InboxIssueKind.noReward:
          return ClaimOutcome(ClaimOutcomeKind.noReward, message: m);
        case InboxIssueKind.expired:
          final now = DateTime.now().toUtc();
          final expired = m.isExpired() ? m : m.copyWith(expiresAt: now);
          // The list leaves expired messages out.
          _remove(m.id);
          _badge.removed(m);
          return ClaimOutcome(ClaimOutcomeKind.expired, text: issue.text, message: expired);
        default:
          return ClaimOutcome(ClaimOutcomeKind.failed, text: issue.text, message: m);
      }
    }
  }

  Future<InboxMessage?> _reread(InboxMessage m) async {
    try {
      final again = await _api.message(m.id);
      _replace(again);
      return again;
    } on Object catch (_) {
      return null;
    }
  }

  /// Live: re-read `GET /wallet/balance`. Demo: there is no server to
  /// re-read, so the demo credit is applied to the shown balance.
  void _creditWallet(ClaimResult? r) {
    final wallet = ref.read(walletProvider.notifier);
    if (ref.read(inboxIsLiveProvider)) {
      unawaited(wallet.moneyMoved());
      return;
    }
    final w = ref.read(walletProvider).value;
    if (r == null || w == null) return;
    if (r.tokenCredited > 0) wallet.applyBalance(WalletCurrency.token, w.tokens + r.tokenCredited);
    if (r.goldCredited > 0) wallet.applyBalance(WalletCurrency.gold, w.goldCoins + r.goldCredited);
  }

  /// `DELETE /inbox/{id}`; a `404` is done. Ask first when a reward is
  /// waiting ([needsDeleteConfirm]). Throws [AppException] on other errors.
  Future<void> delete(InboxMessage m) async {
    try {
      await _api.delete(m.id);
    } on AppException catch (e) {
      if (inboxIssue(e, InboxOp.delete).kind != InboxIssueKind.done) rethrow;
    }
    _remove(m.id);
    _badge.removed(m);
    _badge.refresh();
  }
}

/// Delete asks "The reward inside will be lost." only while one is waiting.
bool needsDeleteConfirm(InboxMessage m, {DateTime? now}) => m.rewardWaiting(now);

final inboxStoreProvider = NotifierProvider<InboxStore, PagedList<InboxMessage>>(InboxStore.new);

/// The Notifications list.
class NotificationsStore extends _PagedStore<PlayerNotification> {
  @override
  Future<InboxPage<PlayerNotification>> fetch(InboxApi api, int page) =>
      api.notifications(page: page, perPage: _PagedStore.perPage);

  @override
  Object keyOf(PlayerNotification item) => item.id;

  /// The list is on screen: everything in it is seen (server time).
  Future<void> markSeen() async {
    DateTime? newest;
    for (final n in state.items) {
      final t = n.sentAt;
      if (t != null && (newest == null || t.isAfter(newest))) newest = t;
    }
    if (newest != null) await ref.read(inboxBadgeProvider.notifier).notificationsSeen(newest);
  }
}

final notificationsStoreProvider =
    NotifierProvider<NotificationsStore, PagedList<PlayerNotification>>(NotificationsStore.new);

// ── Badge ────────────────────────────────────────────────────────────────

/// The two numbers for the bell and the tab dot (§1g, §2b).
@immutable
class InboxBadge {
  const InboxBadge({this.inboxUnread = 0, this.inboxCapped = false, this.rewardsWaiting = 0, this.notificationsNew = 0});

  /// Unread inbox messages (from `GET /inbox?per_page=100`).
  final int inboxUnread;

  /// `total > 100`: show "99+" rather than loading more pages.
  final bool inboxCapped;

  /// Messages with a reward waiting.
  final int rewardsWaiting;

  /// Notifications sent after the local "last seen".
  final int notificationsNew;

  bool get any => inboxUnread > 0 || inboxCapped || notificationsNew > 0;

  /// The bell: "99+" when capped.
  String get label {
    if (inboxCapped) return '99+';
    final n = inboxUnread + notificationsNew;
    return n > 99 ? '99+' : '$n';
  }

  /// The inbox count: "99+" when capped.
  String get inboxLabel => inboxCapped || inboxUnread > 99 ? '99+' : '$inboxUnread';

  /// The notifications count: "9+" above 9.
  String get notificationsLabel => notificationsNew > 9 ? '9+' : '$notificationsNew';

  InboxBadge copyWith({int? inboxUnread, bool? inboxCapped, int? rewardsWaiting, int? notificationsNew}) => InboxBadge(
        inboxUnread: inboxUnread ?? this.inboxUnread,
        inboxCapped: inboxCapped ?? this.inboxCapped,
        rewardsWaiting: rewardsWaiting ?? this.rewardsWaiting,
        notificationsNew: notificationsNew ?? this.notificationsNew,
      );

  /// From the inbox list read with `per_page=100`.
  static InboxBadge fromInbox(InboxPage<InboxMessage> page, {DateTime? now}) => InboxBadge(
        inboxUnread: page.items.where((m) => !m.isRead).length,
        inboxCapped: page.total > 100,
        rewardsWaiting: page.items.where((m) => m.rewardWaiting(now)).length,
      );

  /// New notifications on page 1: sent after [lastSeen]. A fresh install
  /// ([lastSeen] null) counts nothing.
  static int newNotifications(List<PlayerNotification> page1, DateTime? lastSeen) {
    if (lastSeen == null) return 0;
    return page1.where((n) => n.sentAt != null && n.sentAt!.isAfter(lastSeen)).length;
  }
}

/// `notificationsLastSeenAt` per player, on the device (§2b).
class NotificationsSeenStore {
  const NotificationsSeenStore(this._prefs);
  final AppPrefs _prefs;

  static String _key(String player) => 'notifications_last_seen.$player';

  Future<DateTime?> read(String player) async => DateTime.tryParse(await _prefs.get(_key(player)) ?? '');
  Future<void> write(String player, DateTime at) => _prefs.set(_key(player), at.toUtc().toIso8601String());
}

/// Holds [InboxBadge]. Refreshes on app start, on resume, after an inbox
/// action and when the Inbox opens, never more than once every
/// [minInterval]: a refresh asked for sooner runs when the interval is up.
/// Local changes (read, claim, delete, seen) show at once.
class InboxBadgeStore extends Notifier<InboxBadge> {
  static Duration minInterval = const Duration(seconds: 10);

  DateTime? _lastRead;
  Future<void>? _reading;
  Timer? _later;
  DateTime? _lastSeen;
  bool _lastSeenRead = false;

  String get _player => ref.read(sessionProvider)?.id ?? 'demo';
  NotificationsSeenStore get _seen => NotificationsSeenStore(ref.read(appPrefsProvider));

  @override
  InboxBadge build() {
    ref.watch(sessionProvider.select((u) => u?.id));
    ref.watch(inboxApiProvider);
    _lastRead = null;
    _lastSeen = null;
    _lastSeenRead = false;
    _later?.cancel();
    ref.onDispose(() => _later?.cancel());
    return const InboxBadge();
  }

  /// Re-reads both lists, at most once every [minInterval].
  Future<void> refresh() {
    final last = _lastRead;
    if (last != null) {
      final wait = minInterval - DateTime.now().difference(last);
      if (wait > Duration.zero) {
        _later ??= Timer(wait, () {
          _later = null;
          refresh();
        });
        return Future.value();
      }
    }
    return _reading ??= () async {
      _lastRead = DateTime.now();
      try {
        await _read();
      } on Object catch (_) {
        // Keep the last numbers; the next refresh tries again.
      } finally {
        _reading = null;
      }
    }();
  }

  Future<void> _read() async {
    final api = ref.read(inboxApiProvider);
    final player = _player;
    final (inbox, notes) = await (api.inbox(perPage: 100), api.notifications(perPage: 20)).wait;
    if (!_lastSeenRead) {
      _lastSeen = await _seen.read(player);
      _lastSeenRead = true;
    }
    if (_lastSeen == null) {
      // Fresh install: nothing is new; remember the newest from now on.
      final newest = _newest(notes.items);
      if (newest != null) {
        _lastSeen = newest;
        await _seen.write(player, newest);
      }
    }
    state = InboxBadge.fromInbox(inbox).copyWith(notificationsNew: InboxBadge.newNotifications(notes.items, _lastSeen));
  }

  static DateTime? _newest(List<PlayerNotification> list) {
    DateTime? n;
    for (final x in list) {
      final t = x.sentAt;
      if (t != null && (n == null || t.isAfter(n))) n = t;
    }
    return n;
  }

  void markedRead(InboxMessage m) {
    if (m.isRead || state.inboxUnread == 0) return;
    state = state.copyWith(inboxUnread: state.inboxUnread - 1);
  }

  void claimed(InboxMessage m) {
    var s = state;
    if (!m.isRead && s.inboxUnread > 0) s = s.copyWith(inboxUnread: s.inboxUnread - 1);
    if (m.rewardWaiting() && s.rewardsWaiting > 0) s = s.copyWith(rewardsWaiting: s.rewardsWaiting - 1);
    state = s;
  }

  void removed(InboxMessage m) => claimed(m);

  /// The Notifications list was shown, newest [at] (server time).
  Future<void> notificationsSeen(DateTime at) async {
    final cur = _lastSeen;
    if (cur == null || at.isAfter(cur)) {
      _lastSeen = at;
      _lastSeenRead = true;
      await _seen.write(_player, at);
    }
    state = state.copyWith(notificationsNew: 0);
  }
}

final inboxBadgeProvider = NotifierProvider<InboxBadgeStore, InboxBadge>(InboxBadgeStore.new);

// ── Preferences ──────────────────────────────────────────────────────────

/// `GET /notifications/preferences`, re-read every time the settings open.
/// [change] is optimistic and rolled back on an error.
class NotificationPrefsStore extends AsyncNotifier<NotificationPreferences> {
  @override
  Future<NotificationPreferences> build() {
    ref.watch(sessionProvider.select((u) => u?.id));
    return ref.watch(inboxApiProvider).preferences();
  }

  /// PATCHes only [changes] (null clears quiet hours / the zone) and shows the
  /// returned value. Throws [AppException] after rolling back.
  Future<NotificationPreferences> change(Map<String, Object?> changes) async {
    final before = state.value;
    if (before != null) state = AsyncData(before.merge(changes));
    try {
      final saved = await ref.read(inboxApiProvider).updatePreferences(changes);
      state = AsyncData(saved);
      // `promotions` is privacy `marketing_push`: re-read it there too.
      if (changes.containsKey('promotions')) unawaited(ref.read(accountStoreProvider.notifier).load());
      return saved;
    } on Object {
      if (before != null) state = AsyncData(before);
      rethrow;
    }
  }

  /// Quiet hours on: both times and the zone. Off: all three `null`.
  Future<NotificationPreferences> setQuietHours({required bool on, String? start, String? end, String? timezone}) =>
      change(on
          ? {'quiet_hours_start': start, 'quiet_hours_end': end, 'timezone': timezone}
          : {'quiet_hours_start': null, 'quiet_hours_end': null, 'timezone': null});
}

final notificationPrefsProvider =
    AsyncNotifierProvider.autoDispose<NotificationPrefsStore, NotificationPreferences>(NotificationPrefsStore.new,
        retry: (_, _) => null);

/// Re-read the inbox, the notifications and the badge (a push tap, resume).
void refreshInboxEverywhere(Ref ref) {
  ref.read(inboxBadgeProvider.notifier).refresh();
  ref.read(inboxStoreProvider.notifier).reload();
  ref.read(notificationsStoreProvider.notifier).reload();
}
