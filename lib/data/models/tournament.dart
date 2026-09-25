import 'package:flutter/foundation.dart';

enum TournamentState { live, upcoming, ended }

/// A tournament event card's data.
@immutable
class Tournament {
  const Tournament({
    required this.name,
    required this.when,
    required this.fee,
    required this.prize,
    required this.fill,
    required this.players,
    required this.state,
    required this.cta,
  });

  final String name;
  final String when;
  final String fee;
  final String prize;
  final double fill;
  final String players;
  final TournamentState state;
  final String cta;

  factory Tournament.fromJson(Map<String, dynamic> json) => Tournament(
        name: json['name'] as String? ?? '',
        when: json['when'] as String? ?? '',
        fee: json['fee'] as String? ?? '',
        prize: json['prize']?.toString() ?? '0',
        fill: (json['fill'] as num?)?.toDouble() ?? 0,
        players: json['players'] as String? ?? '',
        state: TournamentState.values.firstWhere(
          (s) => s.name == json['state'],
          orElse: () => TournamentState.upcoming,
        ),
        cta: json['cta'] as String? ?? 'Open',
      );
}
