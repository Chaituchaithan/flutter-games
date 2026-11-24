/// Money from the API (00-conventions.md "Money"): whole numbers that arrive
/// as a number (`100`) or a numeric string (`"100"`). Anything else is 0.
int parseAmount(Object? v) => switch (v) {
      int() => v,
      num() => v.toInt(),
      String() => int.tryParse(v.trim()) ?? num.tryParse(v.trim())?.toInt() ?? 0,
      _ => 0,
    };
