/// Player-safety records (docs/services/12-safety.md): reports, match flags
/// and the account's ban check. Parsers are lenient: unknown enum values map
/// to `unknown`, missing fields to null, so a new server value never crashes.
library;

/// Why a player is reported (§1). `unknown` only ever comes from the server.
enum ReportReason {
  cheating('cheating', 'Cheating'),
  abuse('abuse', 'Abusive language'),
  spam('spam', 'Spam'),
  inappropriateContent('inappropriate_content', 'Inappropriate name or picture'),
  harassment('harassment', 'Harassment'),
  other('other', 'Something else'),
  unknown('', 'Other');

  const ReportReason(this.wire, this.label);
  final String wire;
  final String label;

  /// The six the player can pick.
  static const choices = [cheating, abuse, spam, inappropriateContent, harassment, other];

  static ReportReason parse(Object? v) =>
      values.firstWhere((r) => r != unknown && r.wire == v, orElse: () => unknown);
}

/// A report's review state (§2). Anything else reads as `unknown` and is
/// shown like `pending` ("Received").
enum ReportStatus {
  pending('pending', 'Received', "We've received your report."),
  reviewed('reviewed', 'In review', 'Our team is looking at it.'),
  actionTaken('actiontaken', 'Action taken', 'Thanks. We took action on this report.'),
  dismissed('dismissed', 'Closed', 'We reviewed this and took no action.'),
  unknown('', 'Received', "We've received your report.");

  const ReportStatus(this.wire, this.chip, this.text);
  final String wire;
  final String chip;
  final String text;

  static ReportStatus parse(Object? v) =>
      values.firstWhere((s) => s != unknown && s.wire == v, orElse: () => unknown);
}

/// The kind of chat room a gateway chat line lives in.
enum ChatRoomType { match, lobby, global }

/// A gateway chat line attached to a report (sent with `chat_message`).
class ChatEvidence {
  const ChatEvidence({
    required this.roomType,
    required this.roomId,
    required this.messageId,
    this.body,
    this.createdAt,
    this.senderUserId,
  });

  final ChatRoomType roomType;
  final String roomId;

  /// The line's stream id, e.g. `1795514318726-0`.
  final String messageId;

  /// The line's text (in replies; also used to quote it when the line is
  /// gone and the report is resent without it).
  final String? body;
  final DateTime? createdAt;
  final String? senderUserId;

  /// Shape the server checks for [messageId].
  static final messageIdShape = RegExp(r'^\d+-\d+$');

  Map<String, dynamic> toJson() => {'room_type': roomType.name, 'room_id': roomId, 'message_id': messageId};

  static ChatEvidence? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = ChatRoomType.values.where((t) => t.name == json['room_type']).firstOrNull;
    final id = json['id'] ?? json['message_id'];
    if (id is! String) return null;
    return ChatEvidence(
      roomType: type ?? ChatRoomType.match,
      roomId: json['room_id'] is String ? json['room_id'] as String : '',
      messageId: id,
      body: json['body'] is String ? json['body'] as String : null,
      createdAt: _time(json['created_at']),
      senderUserId: json['sender_user_id'] is String ? json['sender_user_id'] as String : null,
    );
  }
}

/// A report this account sent (`POST /moderation/report` reply and each
/// `GET /moderation/my-reports` item). `reviewed_by` is never kept.
class Report {
  const Report({
    required this.id,
    required this.reason,
    required this.status,
    this.reporterId,
    this.reportedUserId,
    this.description,
    this.chatMessageRef,
    this.chatMessage,
    this.createdAt,
    this.reportedUsername,
    this.reportedAvatarUrl,
  });

  final int id;
  final String? reporterId;

  /// Null when that account was removed later.
  final String? reportedUserId;
  final ReportReason reason;

  /// `""` and `null` are the same: nothing written.
  final String? description;
  final ReportStatus status;
  final String? chatMessageRef;
  final ChatEvidence? chatMessage;
  final DateTime? createdAt;
  final String? reportedUsername;
  final String? reportedAvatarUrl;

  bool get hasDescription => (description ?? '').trim().isNotEmpty;

  factory Report.fromJson(Map<String, dynamic> j) {
    final evidence = j['evidence'];
    return Report(
      id: _int(j['id']) ?? 0,
      reporterId: j['reporter_id'] is String ? j['reporter_id'] as String : null,
      reportedUserId: j['reported_user_id'] is String ? j['reported_user_id'] as String : null,
      reason: ReportReason.parse(j['reason']),
      description: j['description'] is String ? j['description'] as String : null,
      status: ReportStatus.parse(j['status']),
      chatMessageRef: j['chat_message_ref'] is String ? j['chat_message_ref'] as String : null,
      chatMessage: evidence is Map ? ChatEvidence.fromJson(evidence['chat_message']) : null,
      createdAt: _time(j['created_at']),
      reportedUsername: j['reported_username'] is String ? j['reported_username'] as String : null,
      reportedAvatarUrl: j['reported_avatar_url'] is String ? j['reported_avatar_url'] as String : null,
    );
  }

  /// Never print the description or the quoted line (other players' words).
  @override
  String toString() => 'Report($id, ${reason.name}, ${status.name})';
}

/// `POST /matches/{id}/flag` reply (§3). No route reads flags back.
class MatchFlag {
  const MatchFlag({required this.id, required this.matchId, this.flaggedBy, this.status = 'pending'});
  final int id;
  final String matchId;
  final String? flaggedBy;
  final String status;

  factory MatchFlag.fromJson(Map<String, dynamic> j) => MatchFlag(
        id: _int(j['id']) ?? 0,
        matchId: j['match_id'] is String ? j['match_id'] as String : '',
        flaggedBy: j['flagged_by'] is String ? j['flagged_by'] as String : null,
        status: j['status'] is String ? j['status'] as String : 'pending',
      );

  @override
  String toString() => 'MatchFlag($id, $status)';
}

/// What a ban stops (§4). `unknown`: show a banner, change no buttons.
enum BanScope {
  full,
  chat,
  matchmaking,
  tournaments,
  unknown;

  static BanScope parse(Object? v) => values.firstWhere((s) => s != unknown && s.name == v, orElse: () => unknown);
}

/// The newest active ban. The server also sends the staff `reason` and
/// `banned_by`: they are deliberately NOT parsed, so they can't reach the
/// UI or a log (Known issues 5).
class Ban {
  const Ban({required this.scope, this.id, this.expiresAt, this.createdAt});
  final int? id;
  final BanScope scope;

  /// Null = until staff lift it.
  final DateTime? expiresAt;
  final DateTime? createdAt;

  bool activeAt(DateTime now) => expiresAt == null || expiresAt!.isAfter(now);

  factory Ban.fromJson(Map<String, dynamic> j) => Ban(
        id: _int(j['id']),
        scope: BanScope.parse(j['scope']),
        expiresAt: _time(j['expires_at']),
        createdAt: _time(j['created_at']),
      );

  @override
  String toString() => 'Ban(${scope.name}, until ${expiresAt?.toIso8601String() ?? 'lifted'})';
}

/// `GET /moderation/bans/check`. `isBanned` is true for ANY scope: decide on
/// [ban]'s scope, never on the flag alone.
class BanCheck {
  const BanCheck({required this.isBanned, this.ban});
  final bool isBanned;
  final Ban? ban;

  static const clear = BanCheck(isBanned: false);

  factory BanCheck.fromJson(Map<String, dynamic> j) {
    final b = j['ban'];
    return BanCheck(
      isBanned: j['is_banned'] == true,
      ban: b is Map ? Ban.fromJson(b.cast<String, dynamic>()) : null,
    );
  }

  /// The ban's scope when one is active at [now]; null when none.
  BanScope? scopeAt(DateTime now) {
    final b = ban;
    if (!isBanned || b == null || !b.activeAt(now)) return null;
    return b.scope;
  }
}

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// `2026-11-25 15:30` in the device's time zone.
String formatLocalTime(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}
