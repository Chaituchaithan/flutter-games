import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Tab a tournament belongs to (mockup: Live / Upcoming / Past).
enum TournamentState { live, upcoming, ended }

/// A tournament event card's data (mockup `tourRaw`).
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
    required this.colors,
    this.live = false,
  });

  final String name;

  /// "Round of 16 · live", "Starts in 04:12", "Won by ZeroCool", …
  final String when;

  /// Entry fee in Tokens (0 = free).
  final int fee;

  /// Prize text as shown ("50,000" or "2,500 Gold").
  final String prize;

  /// Seats filled, 0..1.
  final double fill;

  /// "128 / 128".
  final String players;
  final TournamentState state;

  /// Icon tile + fill-bar gradient.
  final List<Color> colors;

  /// Currently being played (green dot, "Watch" CTA).
  final bool live;

  factory Tournament.fromJson(Map<String, dynamic> json) => Tournament(
        name: json['name'] as String? ?? '',
        when: json['when'] as String? ?? '',
        fee: (json['fee'] as num?)?.toInt() ?? 0,
        prize: json['prize']?.toString() ?? '0',
        fill: ((json['fill'] as num?)?.toDouble() ?? 0).clamp(0, 1),
        players: json['players'] as String? ?? '',
        state: TournamentState.values.firstWhere(
          (s) => s.name == json['state'],
          orElse: () => TournamentState.upcoming,
        ),
        live: json['live'] as bool? ?? false,
        colors: [
          for (final c in (json['colors'] as List? ?? const ['#8B5CF6', '#EC4899']))
            Color(int.parse('FF${(c as String).replaceFirst('#', '')}', radix: 16)),
        ],
      );
}
