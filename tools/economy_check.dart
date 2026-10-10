// Read-only check of the wallet, shop and daily-bonus services, printing the
// live responses so the app's parsing can match them exactly.
//
// Logs in through the API gateway, then only GETs (nothing is bought or
// claimed):
//   GET /wallet/balance
//   GET /sensitive/shop/items
//   GET /sensitive/daily-bonus/status
//
// Run (the password is asked at a hidden prompt — never pass it as an arg):
//   dart run tools/economy_check.dart <email>
//
// Host and port come from lib/configs (gateway 31294).

import 'dart:convert';
import 'dart:io';

import 'package:snakeladder/configs/environment.dart';

final _api = currentEnvironment.server.apiBaseUrl;

String _mask(String s) => s.replaceAllMapped(
    RegExp(r'"(token|refresh_token|access_token)"\s*:\s*"([^"]{6})[^"]*"'), (m) => '"${m[1]}":"${m[2]}…"');

String _prompt(String label) {
  stdout.write(label);
  stdin.echoMode = false;
  final v = stdin.readLineSync() ?? '';
  stdin.echoMode = true;
  stdout.writeln();
  return v;
}

Future<(int, String)> _call(HttpClient c, String method, String path, {String? token, Object? body}) async {
  final req = await c.openUrl(method, Uri.parse('$_api$path'));
  if (token != null) req.headers.set('Authorization', 'Bearer $token');
  if (body != null) {
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
  }
  final res = await req.close();
  return (res.statusCode, await utf8.decodeStream(res));
}

String _pretty(String body) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(body));
  } on FormatException {
    return body;
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tools/economy_check.dart <email>');
    exit(64);
  }
  final email = args.first;
  final password = _prompt('Password for $email: ');
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final (status, body) = await _call(c, 'POST', '/auth/login', body: {'email': email, 'password': password});
    if (status != 200) {
      stderr.writeln('login → $status ${_mask(body)}');
      exit(1);
    }
    final token = (jsonDecode(body) as Map)['access_token'] as String;
    stdout.writeln('login → 200\n');
    for (final path in ['/wallet/balance', '/sensitive/shop/items', '/sensitive/daily-bonus/status']) {
      final (s, b) = await _call(c, 'GET', path, token: token);
      stdout.writeln('── GET $path → $s');
      stdout.writeln(_mask(_pretty(b)));
      stdout.writeln();
    }
  } finally {
    c.close(force: true);
  }
}
