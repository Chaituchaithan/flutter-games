import 'package:flutter/material.dart';

import '../../widgets/aura.dart' show AuraColors;

/// A social contact (friend, incoming request, or suggestion).
///
/// [color] is the avatar tint. A live API can send it as a hex string; when
/// absent we derive a stable colour from the name so the UI never has a gap.
@immutable
class Friend {
  const Friend({
    required this.name,
    required this.level,
    required this.status,
    required this.online,
    required this.color,
  });

  final String name;
  final int level;
  final String status;
  final bool online;
  final Color color;

  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
        name: json['name'] as String? ?? '',
        level: (json['level'] as num?)?.toInt() ?? 1,
        status: json['status'] as String? ?? '',
        online: json['online'] as bool? ?? false,
        color: _parseColor(json['color']) ?? colorForName(json['name'] as String? ?? ''),
      );

  /// Deterministic avatar colour from a name — same input → same colour.
  static Color colorForName(String name) {
    const palette = [
      AuraColors.avatarBlue,
      AuraColors.avatarPurple,
      AuraColors.avatarOrange,
      AuraColors.avatarGreen,
      AuraColors.avatarPink,
      AuraColors.brandPurple,
    ];
    if (name.isEmpty) return palette.first;
    final hash = name.codeUnits.fold<int>(0, (a, c) => a + c);
    return palette[hash % palette.length];
  }

  static Color? _parseColor(Object? raw) {
    if (raw is int) return Color(raw);
    if (raw is String && raw.startsWith('#') && raw.length >= 7) {
      final hex = raw.substring(1);
      final value = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
      return value == null ? null : Color(value);
    }
    return null;
  }
}
