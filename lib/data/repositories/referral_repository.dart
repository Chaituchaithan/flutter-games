import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/feature_flags.dart';
import '../../services/api_client.dart';
import '../../services/session.dart';
import '../models/referral.dart';
import '../sources/referral_source.dart';

/// Live when signed in against the real API; the demo source otherwise.
final referralSourceProvider = Provider<ReferralSource>((ref) {
  final live = ref.watch(useRemoteAuthProvider) && ref.watch(sessionProvider.select((u) => u != null));
  return live ? RemoteReferralSource(ref.watch(apiClientProvider)) : const StaticReferralSource();
});

/// Read when Invite Friends opens (auto-disposed when it closes, so the next
/// visit shows fresh numbers). No silent auto-retry: errors show Retry.
final referralCodeProvider = FutureProvider.autoDispose<ReferralCode>(
  (ref) => ref.watch(referralSourceProvider).myCode(),
  retry: (_, _) => null,
);

final referralStatsProvider = FutureProvider.autoDispose<ReferralStats>(
  (ref) => ref.watch(referralSourceProvider).stats(),
  retry: (_, _) => null,
);
