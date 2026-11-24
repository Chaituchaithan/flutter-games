import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snakeladder/services/api_client.dart';
import 'package:snakeladder/services/server_clock.dart';

/// Answers every request with `{}` and the given `Date` header.
class _DateAdapter implements HttpClientAdapter {
  _DateAdapter(this.date);
  final String date;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async =>
      ResponseBody.fromString(jsonEncode({}), 200, headers: {
        'content-type': ['application/json'],
        'date': [date],
      });
  @override
  void close({bool force = false}) {}
}

String _httpDate(DateTime t) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[u.weekday - 1]}, ${two(u.day)} ${months[u.month - 1]} ${u.year} ${two(u.hour)}:${two(u.minute)}:${two(u.second)} GMT';
}

void main() {
  setUp(ServerClock.reset);

  test('an HTTP reply\'s Date header sets the offset (phone clock 1 h behind)', () async {
    final server = DateTime.now().add(const Duration(hours: 1));
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1/'))..httpClientAdapter = _DateAdapter(_httpDate(server));
    await ApiClient(dio: dio).get('/rewards/daily/status');
    expect(ServerClock.offset.inMinutes, inInclusiveRange(59, 60));
    // A countdown to a server time 2 h from server-now reads ~2 h, not ~3 h.
    final left = ServerClock.until(server.add(const Duration(hours: 2)));
    expect(left.inMinutes, inInclusiveRange(119, 120));
  });

  test('the socket timestamp wins; a close HTTP Date doesn\'t override it', () {
    final serverMs = DateTime.now().millisecondsSinceEpoch + 90 * 1000;
    ServerClock.fromSocket(serverMs);
    final socketOffset = ServerClock.offset;
    ServerClock.fromHttpDate(_httpDate(DateTime.now().add(const Duration(seconds: 91))));
    expect(ServerClock.offset, socketOffset);
    // A big jump (e.g. the phone's clock was changed) is taken.
    ServerClock.fromHttpDate(_httpDate(DateTime.now().add(const Duration(minutes: 10))));
    expect(ServerClock.offset.inMinutes, inInclusiveRange(9, 10));
  });

  test('bad or missing Date headers are ignored; until() never goes negative', () {
    ServerClock.fromHttpDate(null);
    ServerClock.fromHttpDate('yesterday');
    expect(ServerClock.offset, Duration.zero);
    expect(ServerClock.until(DateTime.now().subtract(const Duration(minutes: 1))), Duration.zero);
  });
}
