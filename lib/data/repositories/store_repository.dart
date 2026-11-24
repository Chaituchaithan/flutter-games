import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';
import '../../widgets/aura.dart' show Currency;
import '../../configs/feature_flags.dart';
import '../models/store_pack.dart';
import '../sources/store_source.dart';

/// The balance now lives in the wallet store (03-wallet.md); re-exported
/// so existing `walletProvider` / `walletBalance` imports keep working.
export '../../services/wallet_store.dart' show walletProvider, walletBalance, refreshWallet, WalletStore;

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

final storePacksProvider = FutureProvider.autoDispose.family<List<StorePack>, Currency>(
  (ref, kind) => ref.watch(storeRepositoryProvider).packs(kind),
);
