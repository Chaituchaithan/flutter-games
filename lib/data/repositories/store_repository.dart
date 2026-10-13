import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart' show Currency;
import '../../configs/feature_flags.dart';
import '../models/store_pack.dart';
import '../sources/store_source.dart';

class StoreRepository {
  const StoreRepository(this._source);
  final StoreSource _source;

  Future<Wallet> wallet() => _source.wallet();
  Future<List<StorePack>> packs(Currency kind) => _source.packs(kind);
}

final storeRepositoryProvider = Provider<StoreRepository>((ref) {
  final remote = ref.watch(useRemoteSourcesProvider);
  final api = ref.watch(apiClientProvider);
  return StoreRepository(remote ? RemoteStoreSource(api) : const StaticStoreSource());
});

/// Balance: live `GET /wallet/balance` when signed in against the real API
/// (re-read on sign-in / sign-out); the demo wallet otherwise. Kept for the
/// session, refreshed by invalidation (claims, purchases, match results,
/// app resume) rather than whenever a widget showing it is rebuilt.
/// No automatic retry on failure (Riverpod's default backs off and re-calls
/// the API on its own); a failed read waits for the next real refresh.
final walletProvider = FutureProvider<Wallet>(
  (ref) {
    final live = ref.watch(useRemoteAuthProvider) && ref.watch(sessionProvider.select((u) => u != null));
    if (!live) return ref.watch(storeRepositoryProvider).wallet();
    return RemoteStoreSource(ref.watch(apiClientProvider)).wallet();
  },
  retry: (_, _) => null,
);

/// Live balance of [kind] for checks (stake / buy-in / claim): the latest
/// wallet, kept across refreshes; null until it first loads.
int? walletBalance(WidgetRef ref, Currency kind) => ref.read(walletProvider).value?.of(kind);

final storePacksProvider = FutureProvider.autoDispose.family<List<StorePack>, Currency>(
  (ref, kind) => ref.watch(storeRepositoryProvider).packs(kind),
);
