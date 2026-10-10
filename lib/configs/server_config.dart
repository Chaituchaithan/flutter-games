/// The backend host shared by every game and service. Pure Dart (no Flutter
/// imports) so the dev tools in `tools/` can import the same values.
library;

class ServerConfig {
  const ServerConfig({
    required this.host,
    required this.gatewayPort,
    this.apiPath = '/api/v1',
    this.secure = false,
  });

  /// IP or domain, e.g. `169.58.184.121`.
  final String host;

  /// The API gateway (REST) port.
  final int gatewayPort;

  /// REST prefix on the gateway.
  final String apiPath;

  /// `true` → https / wss.
  final bool secure;

  String get _http => secure ? 'https' : 'http';
  String get _ws => secure ? 'wss' : 'ws';

  /// `http://169.58.184.121:31294`
  String get gatewayBase => '$_http://$host:$gatewayPort';

  /// `http://169.58.184.121:31294/api/v1`
  String get apiBaseUrl => '$gatewayBase$apiPath';

  /// `http://169.58.184.121:<port>` — a game service's REST API. Each game
  /// serves its REST API and its socket on the SAME port.
  String serviceBase(int port) => '$_http://$host:$port';

  /// `ws://169.58.184.121:<port><path>` — a game service socket.
  String socketUrl(int port, String path) => '$_ws://$host:$port$path';
}
