import 'package:flutter/foundation.dart';

import '../../utils/amount.dart';
import '../../services/server_clock.dart';

/// Inbox and notification models (docs/services/10-inbox-and-notifications.md).
/// Parsers are lenient: unknown fields are ignored, money arrives as a number
/// or a numeric string, and an unknown `cta_action` never throws.

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;
String _str(Object? v) => v is String ? v : (v == null ? '' : '$v');
String? _optStr(Object? v) => v is String && v.isNotEmpty ? v : null;

/// Page list shape 2 (00-conventions.md "Lists"):
/// `{data, total, page, per_page, total_pages}`.
@immutable
class InboxPage<T> {
  const InboxPage({required this.items, this.total = 0, this.page = 1, this.perPage = 20, this.totalPages = 0});

  final List<T> items;
  final int total;
  final int page;
  final int perPage;
  final int totalPages;

  /// Load more with `page + 1` until `page >= total_pages`.
  bool get hasMore => page < totalPages;

  factory InboxPage.fromJson(Object? json, T Function(Map<String, dynamic>) item) {
    final j = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
    final data = j['data'] is List ? j['data'] as List : (json is List ? json : const []);
    return InboxPage(
      items: [for (final e in data) if (e is Map) item(e.cast<String, dynamic>())],
      total: parseAmount(j['total']),
      page: j['page'] == null ? 1 : parseAmount(j['page']),
      perPage: j['per_page'] == null ? 20 : parseAmount(j['per_page']),
      totalPages: parseAmount(j['total_pages']),
    );
  }
}

/// One inbox message (§1a). Ids are numbers.
@immutable
class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.title,
    required this.body,
    this.userId,
    this.iconUrl,
    this.ctaLabel,
    this.ctaAction,
    this.attachedToken = 0,
    this.attachedGold = 0,
    this.attachedPowerUps = const [],
    this.readAt,
    this.isRead = false,
    this.claimedAt,
    this.expiresAt,
    this.createdAt,
  });

  final int id;
  final String? userId;
  final String title;

  /// Plain text; shown as text with its line breaks.
  final String body;

  /// Always null today; a URL to an icon (fall back to the default icon).
  final String? iconUrl;

  /// Always null today. A button label (up to 60 chars).
  final String? ctaLabel;

  /// Always null today; free-form JSON with no defined format. Kept as is
  /// and never acted on (Known issues 8).
  final Object? ctaAction;
  final int attachedToken;
  final int attachedGold;
  final List<Object?> attachedPowerUps;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? claimedAt;

  /// Null = never expires.
  final DateTime? expiresAt;
  final DateTime? createdAt;

  /// `attached_token > 0 || attached_gold > 0`.
  bool get hasReward => attachedToken > 0 || attachedGold > 0;

  bool get rewardClaimed => claimedAt != null;

  bool isExpired([DateTime? now]) {
    final e = expiresAt;
    return e != null && !e.isAfter(now ?? ServerClock.now());
  }

  /// Has a reward, not claimed, not expired.
  bool rewardWaiting([DateTime? now]) => hasReward && claimedAt == null && !isExpired(now);

  /// "+500 tokens", "+20 gold", "+500 tokens · +20 gold".
  String get rewardLabel => rewardText(attachedToken, attachedGold);

  InboxMessage copyWith({bool? isRead, DateTime? readAt, DateTime? claimedAt, DateTime? expiresAt}) => InboxMessage(
        id: id,
        userId: userId,
        title: title,
        body: body,
        iconUrl: iconUrl,
        ctaLabel: ctaLabel,
        ctaAction: ctaAction,
        attachedToken: attachedToken,
        attachedGold: attachedGold,
        attachedPowerUps: attachedPowerUps,
        isRead: isRead ?? this.isRead,
        readAt: readAt ?? this.readAt,
        claimedAt: claimedAt ?? this.claimedAt,
        expiresAt: expiresAt ?? this.expiresAt,
        createdAt: createdAt,
      );

  factory InboxMessage.fromJson(Map<String, dynamic> j) {
    final readAt = _time(j['read_at']);
    return InboxMessage(
      id: parseAmount(j['id']),
      userId: _optStr(j['user_id']),
      title: _str(j['title']),
      body: _str(j['body']),
      iconUrl: _optStr(j['icon_url']),
      ctaLabel: _optStr(j['cta_label']),
      ctaAction: j['cta_action'],
      attachedToken: parseAmount(j['attached_token']),
      attachedGold: parseAmount(j['attached_gold']),
      attachedPowerUps: j['attached_power_ups'] is List ? List.unmodifiable(j['attached_power_ups'] as List) : const [],
      isRead: j['is_read'] is bool ? j['is_read'] as bool : readAt != null,
      readAt: readAt,
      claimedAt: _time(j['claimed_at']),
      expiresAt: _time(j['expires_at']),
      createdAt: _time(j['created_at']),
    );
  }
}

/// "+500 tokens · +20 gold" (only the non-zero parts).
String rewardText(int tokens, int gold) {
  String fmt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return [if (tokens > 0) '+${fmt(tokens)} tokens', if (gold > 0) '+${fmt(gold)} gold'].join(' · ');
}

/// `POST /inbox/{id}/claim-reward` → `{"status":"claimed","token_credited":500,"gold_credited":0}`.
@immutable
class ClaimResult {
  const ClaimResult({this.status = 'claimed', this.tokenCredited = 0, this.goldCredited = 0});
  final String status;
  final int tokenCredited;
  final int goldCredited;

  /// The text the app shows, from the reply (not from the message fields).
  String get label => rewardText(tokenCredited, goldCredited);

  factory ClaimResult.fromJson(Map<String, dynamic> j) => ClaimResult(
        status: _str(j['status']).isEmpty ? 'claimed' : _str(j['status']),
        tokenCredited: parseAmount(j['token_credited']),
        goldCredited: parseAmount(j['gold_credited']),
      );
}

/// One notification (§2a). No read state, no link, no reward.
@immutable
class PlayerNotification {
  const PlayerNotification({required this.id, required this.title, required this.body, this.targetType = 'all', this.sentAt});

  /// UUID; the list key.
  final String id;
  final String title;
  final String body;

  /// `all` (every player) or `user` (to me).
  final String targetType;
  final DateTime? sentAt;

  bool get forMe => targetType == 'user';

  /// "Announcement" / "For you".
  String get label => forMe ? 'For you' : 'Announcement';

  factory PlayerNotification.fromJson(Map<String, dynamic> j) => PlayerNotification(
        id: _str(j['id']),
        title: _str(j['title']),
        body: _str(j['body']),
        targetType: _optStr(j['target_type']) ?? 'all',
        sentAt: _time(j['sent_at']),
      );
}

/// `GET/PATCH /notifications/preferences` (§3). Stored only: nothing reads
/// the toggles or the quiet hours on the server yet.
@immutable
class NotificationPreferences {
  const NotificationPreferences({
    this.userId,
    this.friendRequests = true,
    this.matchInvites = true,
    this.promotions = true,
    this.giftReceived = true,
    this.dailyBonusReminder = true,
    this.tournamentAnnouncement = true,
    this.yourTurn = true,
    this.quietHoursStart,
    this.quietHoursEnd,
    this.timezone,
    this.updatedAt,
  });

  final String? userId;
  final bool friendRequests;
  final bool matchInvites;

  /// The same stored value as privacy `marketing_push`.
  final bool promotions;
  final bool giftReceived;
  final bool dailyBonusReminder;
  final bool tournamentAnnouncement;
  final bool yourTurn;

  /// `"HH:MM:SS"` or null.
  final String? quietHoursStart;
  final String? quietHoursEnd;

  /// IANA name, or null.
  final String? timezone;
  final DateTime? updatedAt;

  /// The seven toggles, in screen order: wire name → label.
  static const toggles = {
    'friend_requests': 'Friend requests',
    'match_invites': 'Match invites',
    'promotions': 'Offers and promotions',
    'gift_received': 'Gifts received',
    'daily_bonus_reminder': 'Daily bonus reminder',
    'tournament_announcement': 'Tournaments',
    'your_turn': 'Your turn',
  };

  /// Every field the PATCH accepts. Anything else is refused by the server.
  static final patchFields = {...toggles.keys, 'quiet_hours_start', 'quiet_hours_end', 'timezone'};

  bool get quietHoursOn => quietHoursStart != null && quietHoursEnd != null;

  bool toggle(String key) => switch (key) {
        'friend_requests' => friendRequests,
        'match_invites' => matchInvites,
        'promotions' => promotions,
        'gift_received' => giftReceived,
        'daily_bonus_reminder' => dailyBonusReminder,
        'tournament_announcement' => tournamentAnnouncement,
        'your_turn' => yourTurn,
        _ => false,
      };

  Map<String, Object?> toPatchJson() => {
        'friend_requests': friendRequests,
        'match_invites': matchInvites,
        'promotions': promotions,
        'gift_received': giftReceived,
        'daily_bonus_reminder': dailyBonusReminder,
        'tournament_announcement': tournamentAnnouncement,
        'your_turn': yourTurn,
        'quiet_hours_start': quietHoursStart,
        'quiet_hours_end': quietHoursEnd,
        'timezone': timezone,
      };

  /// The PATCH body that turns this into [next]: only the fields that
  /// changed; a cleared quiet-hours field or zone is an explicit `null`.
  Map<String, Object?> diff(NotificationPreferences next) {
    final a = toPatchJson(), b = next.toPatchJson();
    return {for (final k in b.keys) if (a[k] != b[k]) k: b[k]};
  }

  /// This with [changes] (wire names) applied: the optimistic value.
  NotificationPreferences merge(Map<String, Object?> changes) =>
      NotificationPreferences.fromJson({...toPatchJson(), 'user_id': userId, 'updated_at': updatedAt?.toIso8601String(), ...changes});

  factory NotificationPreferences.fromJson(Map<String, dynamic> j) {
    bool b(String k) => j[k] is bool ? j[k] as bool : true;
    return NotificationPreferences(
      userId: _optStr(j['user_id']),
      friendRequests: b('friend_requests'),
      matchInvites: b('match_invites'),
      promotions: b('promotions'),
      giftReceived: b('gift_received'),
      dailyBonusReminder: b('daily_bonus_reminder'),
      tournamentAnnouncement: b('tournament_announcement'),
      yourTurn: b('your_turn'),
      quietHoursStart: _optStr(j['quiet_hours_start']),
      quietHoursEnd: _optStr(j['quiet_hours_end']),
      timezone: _optStr(j['timezone']),
      updatedAt: _time(j['updated_at']),
    );
  }
}

/// `"22:30"` / `"22:30:00"` → (22, 30); null when it isn't a time.
(int, int)? parseQuietTime(String? s) {
  if (s == null) return null;
  final p = s.split(':');
  if (p.length < 2) return null;
  final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return (h, m);
}

/// (22, 30) → `"22:30:00"`, the form the PATCH sends.
String quietTimeWire(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00';
