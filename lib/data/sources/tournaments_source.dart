import '../../services/api_client.dart';
import '../models/tournament.dart';

/// Tournament events for a given state.
abstract class TournamentsSource {
  Future<List<Tournament>> events(TournamentState state);
}

/// The lists that used to live inline in `tournaments_screen.dart`.
class StaticTournamentsSource implements TournamentsSource {
  const StaticTournamentsSource();

  @override
  Future<List<Tournament>> events(TournamentState state) async => switch (state) {
        TournamentState.live => const [
            Tournament(name: 'Neon Cup', when: 'Live · Round of 16', fee: 'Free entry', prize: '50,000', fill: 0.5, players: '128 players', state: TournamentState.live, cta: 'Open'),
            Tournament(name: 'Token Rush', when: 'Live · Quarter-finals', fee: '200 Tokens', prize: '20,000', fill: 0.7, players: '32 players', state: TournamentState.live, cta: 'Open'),
          ],
        TournamentState.upcoming => const [
            Tournament(name: 'Weekend Clash', when: 'Starts Sat 18:00', fee: '500 Tokens', prize: '80,000', fill: 0.35, players: '210 / 512', state: TournamentState.upcoming, cta: 'Register'),
            Tournament(name: 'Rookie Ladder', when: 'Starts Fri 20:00', fee: 'Free entry', prize: '10,000', fill: 0.6, players: '150 / 256', state: TournamentState.upcoming, cta: 'Register'),
          ],
        TournamentState.ended => const [
            Tournament(name: 'Midnight Masters', when: 'Ended · You placed #7', fee: '100 Tokens', prize: '40,000', fill: 1.0, players: '256 players', state: TournamentState.ended, cta: 'Recap'),
            Tournament(name: 'Neon Cup · S3', when: 'Ended · Champion: KaiStorm', fee: 'Free entry', prize: '50,000', fill: 1.0, players: '128 players', state: TournamentState.ended, cta: 'Recap'),
          ],
      };
}

/// Live-API implementation (off until remote sources are switched on).
class RemoteTournamentsSource implements TournamentsSource {
  const RemoteTournamentsSource(this._api);
  final ApiClient _api;

  @override
  Future<List<Tournament>> events(TournamentState state) async {
    final data = await _api.get('/tournaments', query: {'state': state.name}) as List<dynamic>;
    return data.map((e) => Tournament.fromJson(e as Map<String, dynamic>)).toList();
  }
}
