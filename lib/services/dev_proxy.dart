/// Local dev proxy config.
///
/// `tools/cors_proxy.dart` forwards both REST and the realtime WebSocket to the
/// gateway (adding CORS for the browser, a Bearer header on the WS upgrade, and
/// frame logging). Two modes, one switch:
///
/// * **Proxy ON**  — REST + WS go through the local proxy (localhost:8899;
///   `10.0.2.2:8899` from the Android emulator). Run `dart run
///   tools/cors_proxy.dart` first.
/// * **Proxy OFF** — the app calls the gateway directly over HTTP/WS (our
///   original setup). Fine on Android/iOS; a **web** build will be blocked by
///   CORS because the gateway sends no CORS headers.
///
/// Flip [_proxyEnabled] ("turn on/off proxy"), or override per run with
/// `--dart-define=USE_PROXY=true|false`. An explicit `API_BASE_URL` /
/// `CHESS_WS_URL` define still wins over both.
library;

import 'package:flutter/foundation.dart';

/// MASTER SWITCH: true = proxy testing, false = direct (original) HTTP/WS.
const bool _proxyEnabled = true;

const String _proxyDefine = String.fromEnvironment('USE_PROXY');

/// Whether REST + WS route through the local proxy.
const bool kUseProxy = _proxyDefine == '' ? _proxyEnabled : _proxyDefine == 'true';

/// Where the local proxy listens (matches `_listenPort` in tools/cors_proxy.dart).
/// The Android emulator reaches the host's localhost via 10.0.2.2. Override
/// with `--dart-define=PROXY_HOST=host:port`.
const String _proxyHostDefine = String.fromEnvironment('PROXY_HOST');
String get _proxyHost {
  if (_proxyHostDefine.isNotEmpty) return _proxyHostDefine;
  final androidEmulator = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  return androidEmulator ? '10.0.2.2:8899' : 'localhost:8899';
}

/// Base for proxied REST / WS (paths are appended by the callers).
String get kProxyHttpBase => 'http://$_proxyHost';
String get kProxyWsBase => 'ws://$_proxyHost';
