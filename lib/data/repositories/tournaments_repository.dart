import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';
import '../data_config.dart';
import '../models/tournament.dart';
import '../sources/tournaments_source.dart';

class TournamentsRepository {
  const TournamentsRepository(this._source);
  final TournamentsSource _source;

  Future<List<Tournament>> events(TournamentState state) => _source.events(state);
}

final tournamentsRepositoryProvider = Provider<TournamentsRepository>((ref) {
  final remote = ref.watch(useRemoteSourcesProvider);
  final api = ref.watch(apiClientProvider);
  return TournamentsRepository(
    remote ? RemoteTournamentsSource(api) : const StaticTournamentsSource(),
  );
});

final tournamentEventsProvider =
    FutureProvider.autoDispose.family<List<Tournament>, TournamentState>(
  (ref, state) => ref.watch(tournamentsRepositoryProvider).events(state),
);
