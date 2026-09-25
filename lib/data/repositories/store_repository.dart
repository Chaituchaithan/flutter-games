import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';
import '../../widgets/aura.dart' show Currency;
import '../data_config.dart';
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

final walletProvider =
    FutureProvider.autoDispose<Wallet>((ref) => ref.watch(storeRepositoryProvider).wallet());

final storePacksProvider = FutureProvider.autoDispose.family<List<StorePack>, Currency>(
  (ref, kind) => ref.watch(storeRepositoryProvider).packs(kind),
);
