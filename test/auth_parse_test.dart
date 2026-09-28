// Locks in the API-tolerance added when configuring Auth Services against the
// live backend (snake_case Rust/serde). See docs/INTEGRATION_PLAN.md §7b.

import 'package:flutter_test/flutter_test.dart';
import 'package:snakeladder/data/models/user.dart';

void main() {
  test('User.fromJson parses snake_case (real API shape)', () {
    final u = User.fromJson(const {
      'id': 42,
      'display_name': 'Nova Rider',
      'handle': 'nova_rider',
      'bio': 'gg',
      'level': 7,
      'tier': 'Gold III',
      'xp': 1300,
      'xp_max': 2000,
    });
    expect(u.id, '42');
    expect(u.displayName, 'Nova Rider');
    expect(u.handle, '@nova_rider'); // '@' prefixed when missing
    expect(u.level, 7);
    expect(u.xp, 1300);
    expect(u.xpMax, 2000);
    expect(u.initials, 'NR');
  });

  test('User.fromJson still accepts camelCase', () {
    final u = User.fromJson(const {
      'displayName': 'Kai Storm',
      'xpMax': 500,
    });
    expect(u.displayName, 'Kai Storm');
    expect(u.xpMax, 500);
    expect(u.handle, '@kai_storm');
  });

  test('User.fromJson tolerates missing fields with sane defaults', () {
    final u = User.fromJson(const {});
    expect(u.level, 1);
    expect(u.tier, 'Bronze I');
    expect(u.xpMax, 100);
  });
}
