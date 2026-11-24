/// Opens a game-server WebSocket. No token on the upgrade: the socket signs
/// in with its first `auth.login` frame (00-conventions.md "Lifecycle").
library;

export 'ws_connect_web.dart' if (dart.library.io) 'ws_connect_io.dart';
