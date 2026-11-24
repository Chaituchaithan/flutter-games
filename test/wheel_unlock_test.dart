import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/data/models/daily_bonus.dart';
import 'package:snakeladder/data/repositories/rewards_repository.dart';

DailyReward _d(int day, {int? spin, bool enabled = true}) =>
    DailyReward.fromJson({'day_number': day, 'reward_tokens': '0', 'reward_gold': '10', 'bonus_game_id': spin, 'is_enabled': enabled});

void main() {
  final cycle = [for (var d = 1; d <= 30; d++) _d(d, spin: d == 28 ? 2 : null)];

  test('the next spin day ahead in the cycle', () {
    expect(nextSpinDay(cycle, from: 1, cycle: 30), (day: 28, ahead: 27));
    expect(nextSpinDay(cycle, from: 28, cycle: 30), (day: 28, ahead: 0));
  });

  test('wraps round to the next cycle; none → null; switched-off days skipped', () {
    expect(nextSpinDay(cycle, from: 29, cycle: 30), (day: 28, ahead: 29));
    expect(nextSpinDay([_d(1), _d(2)], from: 1, cycle: 2), isNull);
    expect(nextSpinDay([_d(3, spin: 2, enabled: false), _d(5, spin: 2)], from: 1, cycle: 7), (day: 5, ahead: 4));
  });
}
