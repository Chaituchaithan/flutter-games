import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';
import '../data_config.dart';
import '../models/inbox_message.dart';
import '../sources/inbox_source.dart';

class InboxRepository {
  const InboxRepository(this._source);
  final InboxSource _source;

  Future<List<InboxMessage>> messages() => _source.messages();
}

final inboxRepositoryProvider = Provider<InboxRepository>((ref) {
  final remote = ref.watch(useRemoteSourcesProvider);
  final api = ref.watch(apiClientProvider);
  return InboxRepository(remote ? RemoteInboxSource(api) : const StaticInboxSource());
});

final inboxProvider =
    FutureProvider.autoDispose<List<InboxMessage>>((ref) => ref.watch(inboxRepositoryProvider).messages());
