import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/configs.dart';
import '../data/models/safety.dart';
import 'api_client.dart';
import 'app_exception.dart';
import 'safety_service.dart';
import 'server_clock.dart';
import 'session.dart';

/// What the account may do right now (docs/services/12-safety.md §4-§6):
/// the newest active ban from `GET /moderation/bans/check`, a chat refusal
/// seen on send (mutes are not in the ban check), a tournament break learned
/// from a tournament refusal, and the region gate.
///
/// Features read this before acting; it is the single place that decides:
/// * chat input → [canChat] / [chatBlockedText];
/// * Play / Find match / staked games (lobby, wallet stakes) → [canPlay],
///   [canStake] / [playBlockedText];
/// * tournament Join → [canJoinTournaments] / [tournamentBlockedText];
/// * store and purchases → [storeAvailable].
///
/// The server does not enforce matchmaking bans (Known issues 6): the app
/// disables Play itself from [canPlay].
@immutable
class AccountStanding {
  const AccountStanding({
    this.check,
    this.chatRefused = false,
    this.tournamentBreakUntil,
    this.geo = GeoBlock.none,
    this.clock,
  });

  /// The last ban check; null until read (or signed out).
  final BanCheck? check;

  /// A chat send was refused with `403` (mute or chat ban, end unknown).
  final bool chatRefused;

  /// Self-excluded or cooling off, from a tournament refusal (§5).
  final DateTime? tournamentBreakUntil;

  /// The region gate's last answer.
  final GeoBlock geo;

  /// Test clock; null = the server clock (ban, break and limit ends are
  /// server times).
  final DateTime Function()? clock;
  DateTime get _now => (clock ?? ServerClock.now)();

  static const initial = AccountStanding();

  /// The active ban's scope, or null.
  BanScope? get scope => check?.scopeAt(_now);

  /// When the active ban ends (null: no ban, or until staff lift it).
  DateTime? get banUntil => scope == null ? null : check?.ban?.expiresAt;

  bool get _full => scope == BanScope.full;

  bool get canChat =>
      !chatRefused && !_full && scope != BanScope.chat && geo != GeoBlock.full && geo != GeoBlock.writes;

  /// Find or join a game (free or staked).
  bool get canPlay => !_full && scope != BanScope.matchmaking && geo != GeoBlock.full;

  /// Put tokens or gold at stake (a staked table, a buy-in): play rules plus
  /// a region that allows changes.
  bool get canStake => canPlay && geo != GeoBlock.writes;

  bool get _onBreak {
    final b = tournamentBreakUntil;
    return b != null && b.isAfter(_now);
  }

  bool get canJoinTournaments =>
      !_full && scope != BanScope.tournaments && !_onBreak && (geo == GeoBlock.none || geo == GeoBlock.store);

  /// Store, purchases and subscriptions may be shown.
  bool get storeAvailable => geo == GeoBlock.none;

  String _until(DateTime? t, String forNow) => t == null ? forNow : 'until ${formatLocalTime(t)}';

  /// Banner text for the chat input, or null when chat is open.
  String? get chatBlockedText {
    if (canChat) return null;
    if (geo != GeoBlock.none) return "This action isn't available in your region.";
    // A refused send has no known end; a chat ban may.
    final t = scope == BanScope.chat && !chatRefused ? banUntil : null;
    return "You can't send messages ${_until(t, 'for now')}.";
  }

  /// Banner text for Play buttons, or null when play is open.
  String? get playBlockedText {
    if (canStake) return null;
    if (geo == GeoBlock.full) return "Games aren't available in your region.";
    if (geo == GeoBlock.writes && canPlay) return "This action isn't available in your region.";
    return "You can't join games ${_until(banUntil, 'for now')}.";
  }

  /// Banner text for tournament Join, or null when joining is open.
  String? get tournamentBlockedText {
    if (canJoinTournaments) return null;
    if (geo != GeoBlock.none && geo != GeoBlock.store) return "This action isn't available in your region.";
    if (_onBreak && scope != BanScope.tournaments && !_full) {
      return "You've taken a break from tournaments until ${formatLocalTime(tournamentBreakUntil!)}.";
    }
    return "You can't join tournaments ${_until(banUntil, 'for now')}.";
  }

  /// A ban with a scope this app doesn't know: a banner, no button changes.
  String? get unknownRestrictionText =>
      scope == BanScope.unknown ? 'Some features are limited on your account for now.' : null;

  AccountStanding copyWith({
    BanCheck? check,
    bool clearCheck = false,
    bool? chatRefused,
    DateTime? tournamentBreakUntil,
    bool clearBreak = false,
    GeoBlock? geo,
  }) =>
      AccountStanding(
        check: clearCheck ? null : (check ?? this.check),
        chatRefused: chatRefused ?? this.chatRefused,
        tournamentBreakUntil: clearBreak ? null : (tournamentBreakUntil ?? this.tournamentBreakUntil),
        geo: geo ?? this.geo,
        clock: clock,
      );
}

/// Keeps [AccountStanding] current: reads the ban check after sign-in, on
/// resume (at most once a minute), after a chat or tournament `403`, and
/// when a shown ban end passes. Never polls.
class AccountStandingController extends Notifier<AccountStanding> {
  static const minGap = Duration(minutes: 1);

  DateTime? _checkedAt;
  Timer? _expiry;
  Future<void>? _inFlight;

  @override
  AccountStanding build() {
    ref.onDispose(() => _expiry?.cancel());
    ref.listen<String?>(sessionProvider.select((u) => u?.id), (prev, next) {
      if (next == null) {
        _reset();
      } else if (prev != next) {
        _checkedAt = null;
        unawaited(refresh(force: true));
      }
    });
    return AccountStanding.initial;
  }

  bool _attached = false;

  /// Called once by the app root: resume re-checks, and region refusals from
  /// any route land here.
  void attach() {
    if (_attached) return;
    _attached = true;
    try {
      final l = AppLifecycleListener(onResume: () => unawaited(refresh()));
      ref.onDispose(l.dispose);
    } catch (_) {/* no binding (unit tests) */}
    if (ref.read(sessionProvider) != null) unawaited(refresh(force: true));
  }

  void _reset() {
    _expiry?.cancel();
    _checkedAt = null;
    state = AccountStanding(geo: state.geo);
  }

  bool get _live => ref.read(useRemoteAuthProvider) && ref.read(sessionProvider) != null;

  /// `GET /moderation/bans/check`; skipped within a minute of the last read
  /// unless [force]. Failures keep what is known.
  Future<void> refresh({bool force = false}) {
    if (!_live) return Future.value();
    final at = _checkedAt;
    if (!force && at != null && DateTime.now().difference(at) < minGap) return Future.value();
    return _inFlight ??= _read().whenComplete(() => _inFlight = null);
  }

  Future<void> _read() async {
    try {
      final check = await ref.read(safetyApiProvider).checkBan();
      _checkedAt = DateTime.now();
      // A clean check also clears a chat refusal seen earlier... unless it
      // was a mute, which the check never reports; keep that until resume.
      state = state.copyWith(check: check);
      _scheduleExpiry(check);
      if (state.scope == BanScope.full) _endSession(check.ban?.expiresAt);
    } on AppException catch (_) {
      // Offline / server trouble: keep the last known standing.
    } on Object catch (_) {}
  }

  /// Re-read when the shown end passes (one shot, not a poll).
  void _scheduleExpiry(BanCheck check) {
    _expiry?.cancel();
    final end = check.ban?.expiresAt;
    if (!check.isBanned || end == null) return;
    // The end is a server time: count down on the server's clock.
    final left = ServerClock.until(end);
    if (left <= Duration.zero) return;
    final wait = left + const Duration(seconds: 2);
    _expiry = Timer(wait, () {
      state = state.copyWith(chatRefused: false);
      unawaited(refresh(force: true));
    });
  }

  /// A full ban seen in the check (between the ban and the token ending):
  /// handled as `ACCOUNT_BANNED`.
  void _endSession(DateTime? until) {
    final api = ref.read(apiClientProvider);
    final handler = api.onUnauthorized;
    final reason = AppException(banMessage(until),
        kind: AppErrorKind.unauthorized, statusCode: 403, code: ApiErrorCode.accountBanned, until: until);
    if (handler != null) {
      handler(reason);
    } else {
      ref.read(sessionProvider.notifier).forceSignOut();
    }
  }

  /// A gateway chat send answered `403 FORBIDDEN` (muted or chat-banned):
  /// disable the input and re-read the check.
  Future<void> chatRefused() {
    state = state.copyWith(chatRefused: true);
    return refresh(force: true);
  }

  /// A tournament join answered `403 FORBIDDEN`: re-read the check, note a
  /// break, and return the player's text (§5).
  String tournamentRefused(AppException e) {
    final refusal = TournamentRefusal.parse(e.detail);
    if (refusal.kind == TournamentRefusalKind.onBreak && refusal.until != null) {
      state = state.copyWith(tournamentBreakUntil: refusal.until);
    }
    unawaited(refresh(force: true));
    return refusal.text;
  }

  /// A region refusal from any route ([ApiClient.onGeoBlocked]).
  void geoBlocked(GeoBlock kind) {
    // A store-only refusal never downgrades a wider one.
    if (kind.index < state.geo.index) return;
    state = state.copyWith(geo: kind);
  }

  /// Retry on the region screen worked.
  void clearGeo() => state = state.copyWith(geo: GeoBlock.none);
}

/// The account's standing; see [AccountStanding] for what to check.
final accountStandingProvider =
    NotifierProvider<AccountStandingController, AccountStanding>(AccountStandingController.new);

enum TournamentRefusalKind { banned, onBreak, limit, other }

/// The tournament join `403 FORBIDDEN` texts all share one code; the
/// hand-off says to tell them apart by `message` (§5).
class TournamentRefusal {
  const TournamentRefusal(this.kind, this.text, [this.until]);
  final TournamentRefusalKind kind;
  final String text;
  final DateTime? until;

  static final _untilRe = RegExp(r'until\s+(\S+(?:\s\d{1,2}:\d{2}(?::\d{2}(?:\.\d+)?)?\s?(?:UTC|Z|[+-]\d{2}:?\d{2})?)?)');

  static TournamentRefusal parse(String? message) {
    final m = (message ?? '').toLowerCase();
    if (m.contains('loss limit') || m.contains('spend limit')) {
      return const TournamentRefusal(TournamentRefusalKind.limit, 'This would pass your spending limit.');
    }
    if (m.contains('self-excluded') || m.contains('cooling off')) {
      final until = _parseUntil(message ?? '');
      return TournamentRefusal(
        TournamentRefusalKind.onBreak,
        until == null
            ? "You've taken a break from tournaments for now."
            : "You've taken a break from tournaments until ${formatLocalTime(until)}.",
        until,
      );
    }
    if (m.contains('banned from tournaments')) {
      return const TournamentRefusal(TournamentRefusalKind.banned, "You can't join tournaments for now.");
    }
    return const TournamentRefusal(TournamentRefusalKind.other, "You can't join right now.");
  }

  static DateTime? _parseUntil(String message) {
    final hit = _untilRe.firstMatch(message);
    if (hit == null) return null;
    final raw = hit.group(1)!.replaceAll(' UTC', 'Z').replaceFirst(' ', 'T');
    return DateTime.tryParse(raw);
  }
}
