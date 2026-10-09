import 'package:flutter_test/flutter_test.dart';
import 'package:snakeladder/data/models/user.dart';

// Shapes from the live API (GET /users/me, GET /users/{id}/profile).
const _me = {
  'id': '418532b7-5c14-4e0e-8803-00ad6fb350ef',
  'username': 'chaitu01',
  'email': 'chaitu01@gmail.com',
  'role': 'user',
  'status': 'active',
  'created_at': '2026-10-08T16:25:55.915673Z',
  'updated_at': '2026-10-09T14:25:13.454630Z',
};
const _profile = {
  'user_id': '418532b7-5c14-4e0e-8803-00ad6fb350ef',
  'display_name': 'chaitu01',
  'avatar_id': null,
  'avatar_url': null,
  'bio': null,
  'country': null,
  'date_of_birth': null,
  'preferred_language': null,
  'updated_at': '2026-10-09T16:32:19.956503Z',
};

void main() {
  test('fromApi merges /users/me + profile', () {
    final u = User.fromApi(_me, _profile);
    expect(u.id, '418532b7-5c14-4e0e-8803-00ad6fb350ef');
    expect(u.displayName, 'chaitu01');
    expect(u.username, 'chaitu01');
    expect(u.handle, '@chaitu01');
    expect(u.email, 'chaitu01@gmail.com');
    expect(u.bio, '');
    expect(u.country, isNull);
    expect(u.createdAt, DateTime.parse('2026-10-08T16:25:55.915673Z'));
    expect(u.isGuest, isFalse);
  });

  test('missing profile falls back to the username', () {
    final u = User.fromApi(_me);
    expect(u.displayName, 'chaitu01');
  });

  test('withProfile applies a PATCH response and keeps account fields', () {
    final u = User.fromApi(_me, _profile).withProfile({
      ..._profile,
      'display_name': 'Chaitu',
      'bio': 'Chess fan',
      'country': 'IN',
    });
    expect(u.displayName, 'Chaitu');
    expect(u.bio, 'Chess fan');
    expect(u.country, 'IN');
    expect(u.email, 'chaitu01@gmail.com');
    expect(u.username, 'chaitu01');
  });
}
