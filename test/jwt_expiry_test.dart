import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/services/session.dart';

String _jwt(Map<String, dynamic> claims) =>
    'h.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.s';

void main() {
  test('reads the exp claim; bad tokens give null', () {
    expect(jwtExpiry(_jwt({'exp': 1700000000})), DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
    expect(jwtExpiry(_jwt({'sub': 'x'})), isNull);
    expect(jwtExpiry('not-a-jwt'), isNull);
  });
}
