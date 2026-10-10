import 'package:flutter/painting.dart';

import '../../services/api_client.dart';
import '../models/tournament.dart';
import '../../configs/endpoints/api_endpoints.dart';

/// Tournament events for a given state.
abstract class TournamentsSource {
  Future<List<Tournament>> events(TournamentState state);
}

/// The lists that used to live inline in `tournaments_screen.dart`.
class StaticTournamentsSource implements TournamentsSource {
  const StaticTournamentsSource();

  // Mockup `tourRaw` (Live / Upcoming / Past).
  @override
  Future<List<Tournament>> events(TournamentState state) async => switch (state) {
        TournamentState.live => const [
            Tournament(name: 'Neon Cup', prize: '50,000', fee: 500, players: '128 / 128', when: 'Round of 16 · live', colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)], live: true, fill: 1, state: TournamentState.live),
            Tournament(name: 'Midnight Rush', prize: '12,000', fee: 100, players: '61 / 64', when: 'Starts in 04:12', colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)], fill: 0.95, state: TournamentState.live),
          ],
        TournamentState.upcoming => const [
            Tournament(name: 'Weekend Clash', prize: '100,000', fee: 1000, players: '212 / 256', when: 'Fri · 8:00 PM', colors: [Color(0xFFFB923C), Color(0xFFF43F5E)], fill: 0.83, state: TournamentState.upcoming),
            Tournament(name: 'Rookie League', prize: '5,000', fee: 0, players: '38 / 64', when: 'Sat · 2:00 PM', colors: [Color(0xFF34D399), Color(0xFF14B8A6)], fill: 0.59, state: TournamentState.upcoming),
            Tournament(name: 'Gold Masters', prize: '2,500 Gold', fee: 2000, players: '17 / 32', when: 'Sun · 6:00 PM', colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)], fill: 0.53, state: TournamentState.upcoming),
          ],
        TournamentState.ended => const [
            Tournament(name: 'Aurora Open', prize: '75,000', fee: 500, players: '256 / 256', when: 'Won by ZeroCool', colors: [Color(0xFF6366F1), Color(0xFFA855F7)], fill: 1, state: TournamentState.ended),
            Tournament(name: 'Spring Brawl', prize: '20,000', fee: 200, players: '128 / 128', when: 'You placed #9', colors: [Color(0xFFF472B6), Color(0xFFEC4899)], fill: 1, state: TournamentState.ended),
          ],
      };
}

/// Live-API implementation (off until remote sources are switched on).
class RemoteTournamentsSource implements TournamentsSource {
  const RemoteTournamentsSource(this._api);
  final ApiClient _api;

  @override
  Future<List<Tournament>> events(TournamentState state) async {
    final data = await _api.get(ApiEndpoints.tournaments, query: {'state': state.name}) as List<dynamic>;
    return data.map((e) => Tournament.fromJson(e as Map<String, dynamic>)).toList();
  }
}
