import 'package:flutter/material.dart';

import '../../widgets/aura.dart' show AuraColors;

/// The kind of inbox notification — drives its icon + accent colour so the
/// model carries no Flutter-specific fields over the wire.
enum InboxKind { challenge, tournament, friendRequest, dailyBonus, payout, announcement }

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
  final String? action;
  final bool unread;

  IconData get icon => switch (kind) {
        InboxKind.challenge => Icons.sports_esports,
        InboxKind.tournament => Icons.emoji_events,
        InboxKind.friendRequest => Icons.person_add_alt_1,
        InboxKind.dailyBonus => Icons.card_giftcard,
        InboxKind.payout => Icons.star_rounded,
        InboxKind.announcement => Icons.campaign,
      };

  Color get color => switch (kind) {
        InboxKind.challenge => AuraColors.brandPurple,
        InboxKind.tournament => AuraColors.gold,
        InboxKind.friendRequest => AuraColors.gems,
        InboxKind.dailyBonus => AuraColors.brandPink,
        InboxKind.payout => AuraColors.green,
        InboxKind.announcement => AuraColors.brandOrange,
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
