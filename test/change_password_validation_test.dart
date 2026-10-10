import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/utils/validators.dart';

void main() {
  test('current password is required', () {
    expect(Validators.currentPassword(''), isNotNull);
    expect(Validators.currentPassword('x'), isNull);
  });

  test('new password: 8–128 chars, letters + numbers, not the current one', () {
    expect(Validators.changedPassword('', current: 'Old12345'), 'Please enter a new password');
    expect(Validators.changedPassword('Ab1', current: 'Old12345'), 'Use at least 8 characters');
    expect(Validators.changedPassword('a1' * 65, current: 'Old12345'), 'Use at most 128 characters');
    expect(Validators.changedPassword('abcdefgh', current: 'Old12345'), 'Mix letters and numbers');
    expect(Validators.changedPassword('Old12345', current: 'Old12345'), contains('different'));
    expect(Validators.changedPassword('New12345', current: 'Old12345'), isNull);
  });

  test('confirmation must match', () {
    expect(Validators.confirmPassword('', password: 'New12345'), isNotNull);
    expect(Validators.confirmPassword('New1234', password: 'New12345'), 'Passwords don’t match');
    expect(Validators.confirmPassword('New12345', password: 'New12345'), isNull);
  });
}
