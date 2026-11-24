/// The single entry point for resolved configuration. Services ask this (and
/// [GameEndpoints]) for URLs — they never build one themselves.
///
/// Resolution order everywhere: `--dart-define` override → proxy (dev) →
/// environment default.
library;

import 'build_overrides.dart';
import 'environment.dart';
import 'proxy_config.dart';
import 'server_config.dart';

abstract final class AppConfig {
  static AppEnvironment get environment => currentEnvironment;

  /// Host, gateway port and schemes for the current environment — on the
  /// host picked in the debug "Server" setting, when one is set.
  static ServerConfig get server {
    final h = _debugHost;
    return h == null ? environment.server : environment.server.withHost(h);
  }

  /// AppPrefs key of the debug "Server" setting.
  static const serverHostPrefKey = 'server_host';
  static String? _debugHost;

  /// Applied at startup, before the first request (debug builds only; see
  /// bootstrap). Empty/null = the environment's host.
  static void useDebugHost(String? host) {
    final h = host?.trim();
    _debugHost = (h == null || h.isEmpty) ? null : h;
  }

  /// REST base used by ApiClient.
  static String get apiBaseUrl {
    if (BuildOverrides.apiBaseUrl.isNotEmpty) return BuildOverrides.apiBaseUrl;
    if (ProxyConfig.enabled) return '${ProxyConfig.httpBase}${server.apiPath}';
    return server.apiBaseUrl;
  }
}
