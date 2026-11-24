/// Deployment environments and the server each one talks to. Pure Dart.
library;

import 'build_overrides.dart';
import 'server_config.dart';

enum AppEnvironment { dev, staging, prod }

/// The dev backend on the LAN (plain HTTP — see the Android cleartext rule).
/// API gateway (auth, profile, …) on 1280; each game service on its cloud port
/// minus 30000 (Ludo 31285 → 1285). Auth contract: docs/services/01-auth.md.
/// Override the host for one run with `--dart-define=SERVER_HOST=<ip>`.
const devServer = ServerConfig(
  host: BuildOverrides.serverHost == '' ? '192.168.0.235' : BuildOverrides.serverHost,
  gatewayPort: 1280,
  servicePortOffset: -30000,
);

/// The earlier cloud dev server (gateway 31294, games 31281–31292).
const cloudDevServer = ServerConfig(host: '169.58.184.121', gatewayPort: 31294);

extension AppEnvironmentServer on AppEnvironment {
  /// Server per environment. Staging/prod hosts aren't known yet: staging uses
  /// the cloud dev server and prod the LAN dev server until real values exist.
  ServerConfig get server => switch (this) {
        AppEnvironment.dev => devServer,
        AppEnvironment.staging => cloudDevServer, // TODO: staging host
        AppEnvironment.prod => devServer, // TODO: production HTTPS host (secure: true)
      };
}

/// The environment chosen at build time (`--dart-define=APP_ENV=…`), dev by
/// default.
AppEnvironment get currentEnvironment => AppEnvironment.values.firstWhere(
      (e) => e.name == BuildOverrides.env,
      orElse: () => AppEnvironment.dev,
    );
