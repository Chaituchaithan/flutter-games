/// Opens a WebSocket, sending [headers] on the upgrade where the platform
/// allows it. Native (dart:io) can set headers such as `Authorization`;
/// browsers can't, so on web the headers are dropped (the dev proxy carries
/// the token instead — see `GameEndpoints.socketUrlWithToken`).
library;

export 'ws_connect_web.dart' if (dart.library.io) 'ws_connect_io.dart';
