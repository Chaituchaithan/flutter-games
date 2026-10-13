import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/feature_flags.dart';
import '../../services/api_client.dart';
import '../../services/session.dart';
import '../models/daily_bonus.dart';
import '../sources/daily_bonus_source.dart';

/// Live when signed in against the real API; the demo source otherwise.
final dailyBonusSourceProvider = Provider<DailyBonusSource>((ref) {
  final live = ref.watch(useRemoteAuthProvider) && ref.watch(sessionProvider.select((u) => u != null));
  return live ? RemoteDailyBonusSource(ref.watch(apiClientProvider)) : StaticDailyBonusSource();
});

/// Kept for the session (not auto-disposed): scrolling the Profile tile out
/// of view and back must not re-call the API. It re-reads when invalidated
/// (after a claim, when the next claim opens) or when the signed-in user changes.
final dailyBonusStatusProvider = FutureProvider<DailyBonusStatus>(
  (ref) => ref.watch(dailyBonusSourceProvider).status(),
  // No silent auto-retry: a failure shows Retry instead of re-calling the API.
  retry: (_, _) => null,
);
