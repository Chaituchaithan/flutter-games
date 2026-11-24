import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/progress.dart';
import 'package:snakeladder/services/progress_service.dart';

HistoryEntry _h(String? result, {int game = 1}) => HistoryEntry.fromJson({
      'match_id': 'm', 'game_id': game, 'status': result == null ? 'in_progress' : 'completed', 'result': result,
      'stake_amount': 0, 'payout_amount': 0,
    });

void main() {
  test('W/D/L/forfeits, win rate and the current win streak (newest first)', () {
    final s = ProfileStats.fromHistory(
      [_h(null), _h('win'), _h('win'), _h('loss'), _h('win'), _h('draw'), _h('forfeit'), _h('win', game: 2)],
      gameId: 1,
      rank: 7,
    );
    expect((s.matches, s.wins, s.losses, s.draws, s.forfeits), (6, 3, 1, 1, 1));
    expect(s.streak, 2, reason: 'the running match is skipped; the loss ends the streak');
    expect(s.winRate, closeTo(0.5, 1e-9));
    expect(s.rank, 7);
  });

  test('no finished matches: zeros, no rank', () {
    final s = ProfileStats.fromHistory(const []);
    expect((s.matches, s.wins, s.streak, s.winRate, s.rank), (0, 0, 0, 0.0, null));
  });
}
