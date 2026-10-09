import 'package:flutter/material.dart';

import '../../widgets/aura.dart' show AuraColors;

/// The kind of inbox notification — drives its icon, accent gradient and the
/// destination its action routes to. Mirrors the mockup's notification feed.
enum InboxKind { invite, result, dailyBonus, tournament, friendRequest, shop, announcement }

@immutable
class InboxMessage {
  const InboxMessage({
    required this.kind,
    required this.title,
    required this.body,
    required this.when,
    this.action,
    this.unread = false,
  });

  final InboxKind kind;
  final String title;
  final String body;
  final String when;

  /// Call-to-action label (Join / Claim / View / Accept / Shop). Null = no CTA.
  final String? action;
  final bool unread;

  IconData get icon => switch (kind) {
        InboxKind.invite => Icons.groups_rounded,
        InboxKind.result => Icons.emoji_events,
        InboxKind.dailyBonus => Icons.card_giftcard,
        InboxKind.tournament => Icons.military_tech,
        InboxKind.friendRequest => Icons.person_add_alt_1,
        InboxKind.shop => Icons.shopping_bag,
        InboxKind.announcement => Icons.campaign,
      };

  /// Two-stop diagonal gradient for the icon tile (matches the mockup).
  List<Color> get gradient => switch (kind) {
        InboxKind.invite => const [Color(0xFF22D3EE), Color(0xFF6366F1)],
        InboxKind.result => const [Color(0xFF34D399), Color(0xFF14B8A6)],
        InboxKind.dailyBonus => const [Color(0xFF8B5CF6), Color(0xFFEC4899)],
        InboxKind.tournament => const [Color(0xFFFB923C), Color(0xFFF43F5E)],
        InboxKind.friendRequest => const [Color(0xFFF472B6), Color(0xFFEC4899)],
        InboxKind.shop => const [Color(0xFFFDE68A), Color(0xFFF59E0B)],
        InboxKind.announcement => const [AuraColors.brandOrange, AuraColors.brandPink],
      };

  InboxMessage copyWith({bool? unread}) => InboxMessage(
        kind: kind,
        title: title,
        body: body,
        when: when,
        action: action,
        unread: unread ?? this.unread,
      );

  factory InboxMessage.fromJson(Map<String, dynamic> json) => InboxMessage(
        kind: InboxKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => InboxKind.announcement,
        ),
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        when: json['when'] as String? ?? '',
        action: json['action'] as String?,
        unread: json['unread'] as bool? ?? false,
      );
}
