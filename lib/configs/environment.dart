/// Deployment environments and the server each one talks to. Pure Dart.
library;

import 'build_overrides.dart';
import 'server_config.dart';

enum AppEnvironment { dev, staging, prod }

/// The dev backend (plain HTTP on a raw IP — see the Android cleartext rule).
/// API gateway (login, register, profile, …) on 31294; each game service has
/// its own port (31281–31292) for its REST API and socket — see games/.
const devServer = ServerConfig(host: '169.58.184.121', gatewayPort: 31294);

extension AppEnvironmentServer on AppEnvironment {
  /// Server per environment. Staging/prod hosts aren't known yet, so they use
  /// the dev server until real values are added here.
  ServerConfig get server => switch (this) {
        AppEnvironment.dev => devServer,
        AppEnvironment.staging => devServer, // TODO: staging host
        AppEnvironment.prod => devServer, // TODO: production HTTPS host (secure: true)
      };
}

/// The environment chosen at build time (`--dart-define=APP_ENV=…`), dev by
/// default.
AppEnvironment get currentEnvironment => AppEnvironment.values.firstWhere(
      (e) => e.name == BuildOverrides.env,
      orElse: () => AppEnvironment.dev,
    );
