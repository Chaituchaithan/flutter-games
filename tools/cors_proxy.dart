// Tiny dev-only proxy so the Flutter *web* build can reach the gateway, which
// doesn't send CORS headers. It forwards every REST request to the real gateway
// and adds permissive CORS headers (and answers preflight OPTIONS). It ALSO
// proxies the realtime WebSocket (`/api/v1/ws`) so the whole app can talk to a
// single same-origin host (localhost:8899) during web dev.
//
// Run:   dart run tools/cors_proxy.dart        (listens on http://localhost:8899)
// The web build auto-targets it (see api_client.dart / chess_session.dart):
//   flutter run -d web-server --web-port=5000
// …or point it explicitly:
//   --dart-define=API_BASE_URL=http://localhost:8899/api/v1
//   --dart-define=CHESS_WS_URL=ws://localhost:8899/api/v1/ws
//
// Upstream defaults to the deployed gateway; edit the consts if the host changes.

import 'dart:convert';
import 'dart:io';

const _upstreamHost = '169.58.184.121';
const _upstreamPort = 30080;
const _listenPort = 8899;

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _listenPort);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  stdout.writeln('CORS proxy: http://localhost:$_listenPort  ->  http://$_upstreamHost:$_upstreamPort');
  await for (final req in server) {
    _handle(req, client);
  }
}

/// Proxies a browser WebSocket to the upstream gateway WS, piping frames both
/// ways.
///
/// The upstream is dialled FIRST: if the gateway refuses the upgrade (401
/// auth, 404 no such route, …) the browser gets that same status + body
/// instead of a 101 that immediately closes — which used to make every failure
/// look like a generic "socket closed" in the app.
Future<void> _proxyWs(HttpRequest req) async {
  // The gateway requires auth at the upgrade, but browsers can't set WS headers,
  // so the app passes the token as `?token=…`. Send it upstream BOTH as the
  // query param and as an Authorization: Bearer header.
  final token = req.uri.queryParameters['token'];
  final headers = <String, dynamic>{
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };
  final upUri = Uri(
    scheme: 'ws',
    host: _upstreamHost,
    port: _upstreamPort,
    path: req.uri.path,
    query: req.uri.query.isEmpty ? null : req.uri.query,
  );
  final logUri = upUri.replace(queryParameters: {
    ...upUri.queryParameters,
    if (token != null) 'token': _maskToken(token),
  });

  WebSocket upstream;
  try {
    upstream = await WebSocket.connect(upUri.toString(), headers: headers)
        .timeout(const Duration(seconds: 10));
  } catch (e) {
    final (status, body) = await _diagnoseUpgrade(upUri, headers);
    // The exception text embeds the full URL — mask the token before logging.
    final err = (token == null || token.isEmpty) ? '$e' : '$e'.replaceAll(token, _maskToken(token));
    stdout.writeln('[proxy] ws upstream REFUSED $logUri -> $status $body ($err)');
    final res = req.response;
    res.statusCode = status == 0 ? HttpStatus.badGateway : status;
    res.headers.contentType = ContentType.json;
    res.write(body.isEmpty ? '{"error":"UPSTREAM_WS","message":"$e"}' : body);
    await res.close();
    return;
  }

  final WebSocket browser;
  try {
    browser = await WebSocketTransformer.upgrade(req);
  } catch (e) {
    stdout.writeln('[proxy] ws browser upgrade failed: $e');
    await upstream.close();
    return;
  }
  stdout.writeln('[proxy] ws open  ${req.uri.path}  <->  $logUri');
  browser.listen(
    (f) {
      stdout.writeln('[proxy] ws >> ${_redactFrame(f)}');
      upstream.add(f);
    },
    onDone: () {
      stdout.writeln('[proxy] ws browser closed (${browser.closeCode} ${browser.closeReason})');
      upstream.close();
    },
    onError: (_) => upstream.close(),
    cancelOnError: false,
  );
  upstream.listen(
    (f) {
      stdout.writeln('[proxy] ws << ${_redactFrame(f)}');
      browser.add(f);
    },
    onDone: () {
      stdout.writeln('[proxy] ws upstream closed (${upstream.closeCode} ${upstream.closeReason})');
      browser.close(upstream.closeCode, upstream.closeReason);
    },
    onError: (_) => browser.close(),
    cancelOnError: false,
  );
}

/// Re-issues a refused upgrade as a plain request so we can log the gateway's
/// actual status code and error body (WebSocket.connect hides both).
Future<(int, String)> _diagnoseUpgrade(Uri wsUri, Map<String, dynamic> headers) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final r = await client.getUrl(wsUri.replace(scheme: 'http'));
    headers.forEach((k, v) => r.headers.set(k, v));
    r.headers
      ..set('Connection', 'Upgrade')
      ..set('Upgrade', 'websocket')
      ..set('Sec-WebSocket-Version', '13')
      ..set('Sec-WebSocket-Key', 'dGhlIHNhbXBsZSBub25jZQ==');
    final res = await r.close();
    final body = await utf8.decodeStream(res).timeout(const Duration(seconds: 5), onTimeout: () => '');
    return (res.statusCode, body.trim());
  } catch (e) {
    return (0, '');
  } finally {
    client.close(force: true);
  }
}

String _maskToken(String t) => t.length <= 10 ? '***' : '${t.substring(0, 6)}…${t.substring(t.length - 4)}';

/// Frame text for logging, with any token in auth payloads masked.
String _redactFrame(dynamic f) {
  final s = f is String ? f : '<${(f as List).length} bytes>';
  return s.replaceAllMapped(
    RegExp(r'"(token|access_token|refresh_token|password)"\s*:\s*"([^"]*)"'),
    (m) => '"${m[1]}":"${_maskToken(m[2]!)}"',
  );
}

/// Returns the request JSON with sensitive fields masked, for safe logging.
String _redact(List<int> body) {
  try {
    final j = jsonDecode(utf8.decode(body));
    if (j is Map) {
      final copy = Map<String, dynamic>.of(j.cast<String, dynamic>());
      for (final k in ['password', 'new_password', 'newPassword', 'old_password']) {
        if (copy.containsKey(k)) copy[k] = '***';
      }
      return jsonEncode(copy);
    }
  } catch (_) {/* not json */}
  return '<${body.length} bytes>';
}

Future<void> _handle(HttpRequest req, HttpClient client) async {
  // WebSocket upgrade → pipe to the upstream gateway WS (same path/query).
  if (WebSocketTransformer.isUpgradeRequest(req)) {
    await _proxyWs(req);
    return;
  }

  final res = req.response;
  // Permissive CORS for local dev.
  final origin = req.headers.value('origin') ?? '*';
  res.headers.set('Access-Control-Allow-Origin', origin);
  res.headers.set('Access-Control-Allow-Credentials', 'true');
  res.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  res.headers.set(
    'Access-Control-Allow-Headers',
    req.headers.value('access-control-request-headers') ?? 'authorization, content-type, accept',
  );

  if (req.method == 'OPTIONS') {
    res.statusCode = HttpStatus.noContent;
    await res.close();
    return;
  }

  try {
    final uri = Uri(
      scheme: 'http',
      host: _upstreamHost,
      port: _upstreamPort,
      path: req.uri.path,
      query: req.uri.query.isEmpty ? null : req.uri.query,
    );
    final up = await client.openUrl(req.method, uri);
    req.headers.forEach((name, values) {
      final n = name.toLowerCase();
      if (n == 'host' || n == 'connection' || n == 'origin') return;
      for (final v in values) {
        up.headers.add(name, v);
      }
    });
    final body = <int>[];
    await for (final chunk in req) {
      body.addAll(chunk);
    }
    if (body.isNotEmpty) up.add(body);

    // For auth routes, log the fields the app sent (password masked) so we can
    // verify the email/username without exposing the secret.
    final isAuth = req.uri.path.contains('/auth/');
    if (isAuth && body.isNotEmpty) {
      stdout.writeln('[proxy] req ${req.uri.path} body: ${_redact(body)}');
    }

    final upRes = await up.close();
    // Buffer the response so we can log the server's message (safe: no secrets).
    final resBytes = <int>[];
    await for (final chunk in upRes) {
      resBytes.addAll(chunk);
    }
    res.statusCode = upRes.statusCode;
    upRes.headers.forEach((name, values) {
      final n = name.toLowerCase();
      if (n == 'access-control-allow-origin' ||
          n == 'access-control-allow-credentials' ||
          n == 'transfer-encoding' ||
          n == 'content-length' ||
          n == 'connection') {
        return;
      }
      for (final v in values) {
        res.headers.add(name, v);
      }
    });
    final snippet = isAuth ? ' body: ${_redactFrame(utf8.decode(resBytes, allowMalformed: true))}' : '';
    stdout.writeln('[proxy] ${req.method} ${req.uri.path} -> ${upRes.statusCode}$snippet');
    res.add(resBytes);
    await res.close();
  } catch (e) {
    stdout.writeln('[proxy] ${req.method} ${req.uri.path} -> ERROR $e');
    res.statusCode = HttpStatus.badGateway;
    res.write('proxy error: $e');
    await res.close();
  }
}
