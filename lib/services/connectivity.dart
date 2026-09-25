import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams `true` when online, `false` when the device has no connection.
/// Consumers should treat loading/error as online (assume connected until we
/// positively know otherwise) so the offline banner never shows spuriously —
/// e.g. in tests where the platform channel is unavailable.
final connectivityProvider = StreamProvider<bool>((ref) {
  return Connectivity()
      .onConnectivityChanged
      .map((results) => !results.every((r) => r == ConnectivityResult.none));
});

/// Convenience: `true` unless we positively know we're offline.
bool isOnline(AsyncValue<bool> value) => value.maybeWhen(data: (v) => v, orElse: () => true);
