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

  /// Host, gateway port and schemes for the current environment.
  static ServerConfig get server => environment.server;

  /// REST base used by ApiClient.
  static String get apiBaseUrl {
    if (BuildOverrides.apiBaseUrl.isNotEmpty) return BuildOverrides.apiBaseUrl;
    if (ProxyConfig.enabled) return '${ProxyConfig.httpBase}${server.apiPath}';
    return server.apiBaseUrl;
  }
}
