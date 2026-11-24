/// The backend host shared by every game and service. Pure Dart (no Flutter
/// imports) so the dev tools in `tools/` can import the same values.
library;

class ServerConfig {
  const ServerConfig({
    required this.host,
    required this.gatewayPort,
    this.apiPath = '/api/v1',
    this.secure = false,
    this.servicePortOffset = 0,
  });

  /// IP or domain, e.g. `169.58.184.121`.
  final String host;

  /// The API gateway (REST) port.
  final int gatewayPort;

  /// REST prefix on the gateway.
  final String apiPath;

  /// `true` → https / wss.
  final bool secure;

  /// Added to every game's configured port (see games/). The game configs list
  /// the cloud ports (31281–31292); a server that exposes the same services on
  /// other ports (the LAN server: 1281–1292) sets an offset (-30000).
  final int servicePortOffset;

  /// The real port of a game service whose configured port is [port].
  int servicePort(int port) => port + servicePortOffset;

  /// The same server on another host (the debug "Server" setting).
  ServerConfig withHost(String newHost) => ServerConfig(
        host: newHost,
        gatewayPort: gatewayPort,
        apiPath: apiPath,
        secure: secure,
        servicePortOffset: servicePortOffset,
      );

  String get _http => secure ? 'https' : 'http';
  String get _ws => secure ? 'wss' : 'ws';

  /// `http://192.168.0.235:1280`
  String get gatewayBase => '$_http://$host:$gatewayPort';

  /// `http://192.168.0.235:1280/api/v1`
  String get apiBaseUrl => '$gatewayBase$apiPath';

  /// `http://169.58.184.121:<port>` — a game service's REST API. Each game
  /// serves its REST API and its socket on the SAME port.
  String serviceBase(int port) => '$_http://$host:${servicePort(port)}';

  /// `ws://169.58.184.121:<port><path>` — a game service socket.
  String socketUrl(int port, String path) => '$_ws://$host:${servicePort(port)}$path';
}
