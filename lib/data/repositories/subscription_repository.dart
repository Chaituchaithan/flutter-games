import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../configs/feature_flags.dart';
import '../../services/api_client.dart';
import '../../services/session.dart';
import '../models/subscription.dart';
import '../sources/subscription_source.dart';

/// Live when signed in against the real API; the demo source otherwise.
final subscriptionSourceProvider = Provider<SubscriptionSource>((ref) {
  final live = ref.watch(useRemoteAuthProvider) && ref.watch(sessionProvider.select((u) => u != null));
  return live ? RemoteSubscriptionSource(ref.watch(apiClientProvider)) : StaticSubscriptionSource();
});

/// Active plans (inactive ones are hidden).
final subscriptionPlansProvider = FutureProvider.autoDispose<List<SubscriptionPlan>>((ref) async {
  final all = await ref.watch(subscriptionSourceProvider).plans();
  return [for (final p in all) if (p.isActive) p];
});

/// The player's subscription; failures read as "none" so the Store still
/// works when this endpoint isn't ready.
final mySubscriptionProvider = FutureProvider.autoDispose<MySubscription>((ref) async {
  try {
    return await ref.watch(subscriptionSourceProvider).my();
  } on Object {
    return MySubscription.none;
  }
});
