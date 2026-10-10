import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';
import '../../configs/feature_flags.dart';
import '../models/match_record.dart';
import '../sources/history_source.dart';

class HistoryRepository {
  const HistoryRepository(this._source);
  final HistorySource _source;

  Future<List<MatchRecord>> matches() => _source.matches();
}

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  final remote = ref.watch(useRemoteSourcesProvider);
  final api = ref.watch(apiClientProvider);
  return HistoryRepository(remote ? RemoteHistorySource(api) : const StaticHistorySource());
});

final matchHistoryProvider =
    FutureProvider.autoDispose<List<MatchRecord>>((ref) => ref.watch(historyRepositoryProvider).matches());
