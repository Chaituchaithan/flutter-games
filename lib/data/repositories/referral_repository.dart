import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/feature_flags.dart';
import '../../services/api_client.dart';
import '../../services/app_exception.dart';
import '../../services/app_prefs.dart';
import '../../services/session.dart';
import '../models/referral.dart';
import '../sources/referral_source.dart';

/// Live when signed in against the real API; the demo source otherwise.
final referralSourceProvider = Provider<ReferralSource>((ref) {
  final live = ref.watch(useRemoteAuthProvider) && ref.watch(sessionProvider.select((u) => u != null));
  return live ? RemoteReferralSource(ref.watch(apiClientProvider)) : StaticReferralSource();
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

/// Whether this account already used a friend's code: the "Enter a friend's
/// code" field shows only until `POST /referrals/apply` succeeds or answers
/// `409` (09-social.md §5b). Remembered per user on the device.
class ReferralApplied extends AsyncNotifier<bool> {
  String get _key => 'referral_applied.${ref.read(sessionProvider)?.id ?? 'demo'}';

  @override
  Future<bool> build() async {
    ref.watch(sessionProvider.select((u) => u?.id));
    return await ref.read(appPrefsProvider).get(_key) == '1';
  }

  /// Applies [code] (trimmed, upper-cased). Throws [AppException]; a `409`
  /// (already used one) also hides the field.
  Future<void> apply(String code) async {
    try {
      await ref.read(referralSourceProvider).apply(code);
      await _done();
      ref.invalidate(referralStatsProvider);
    } on AppException catch (e) {
      if (e.code == ApiErrorCode.conflict) await _done();
      rethrow;
    }
  }

  Future<void> _done() async {
    await ref.read(appPrefsProvider).set(_key, '1');
    state = const AsyncData(true);
  }
}

final referralAppliedProvider = AsyncNotifierProvider<ReferralApplied, bool>(ReferralApplied.new, retry: (_, _) => null);
