/// Local dev proxy (`tools/cors_proxy.dart`) — forwards REST and the realtime
/// WebSocket to the gateway, adding CORS for the browser, a Bearer header on
/// the WS upgrade, and frame logging.
///
/// * **Proxy ON**  — REST + WS go through `localhost:8899` (`10.0.2.2:8899`
///   from the Android emulator). Run `dart run tools/cors_proxy.dart` first.
/// * **Proxy OFF** — the app calls the gateway directly. Fine on Android/iOS;
///   a **web** build is blocked by CORS (the gateway sends no CORS headers).
///
/// Flip [proxyEnabledByDefault] ("turn on/off proxy"), or override one run
/// with `--dart-define=USE_PROXY=true|false`.
library;

import 'package:flutter/foundation.dart';

import 'build_overrides.dart';

/// MASTER SWITCH: true = proxy testing, false = direct (original) HTTP/WS.
const bool proxyEnabledByDefault = true;

/// Port the proxy listens on (matches `_listenPort` in tools/cors_proxy.dart).
const int proxyPort = 8899;

abstract final class ProxyConfig {
  /// Whether REST + WS route through the local proxy. Release builds (real
  /// phones, demos) never do — the proxy only exists on the developer's
  /// machine — unless `--dart-define=USE_PROXY=true` asks for it.
  static const bool enabled = BuildOverrides.useProxy == ''
      ? proxyEnabledByDefault && !kReleaseMode
      : BuildOverrides.useProxy == 'true';

  /// `host:port` of the proxy. The Android emulator reaches the host machine's
  /// localhost via 10.0.2.2.
  static String get host {
    if (BuildOverrides.proxyHost.isNotEmpty) return BuildOverrides.proxyHost;
    final androidEmulator = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return androidEmulator ? '10.0.2.2:$proxyPort' : 'localhost:$proxyPort';
  }

  static String get httpBase => 'http://$host';
  static String get wsBase => 'ws://$host';
}
