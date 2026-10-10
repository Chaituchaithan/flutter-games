/// Timeouts and retry timings shared by the REST client and the sockets.
library;

abstract final class NetworkConfig {
  // REST (ApiClient / Dio)
  static const connectTimeout = Duration(seconds: 15);
  static const receiveTimeout = Duration(seconds: 20);

  // Realtime sockets (SocketClient)
  static const socketRequestTimeout = Duration(seconds: 8);
  static const socketPingInterval = Duration(seconds: 20);
  static const socketMaxBackoff = Duration(seconds: 30);
}
