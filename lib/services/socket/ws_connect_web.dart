import 'package:web_socket_channel/web_socket_channel.dart';

/// Web: a browser WebSocket can't carry custom headers, so they're ignored.
WebSocketChannel connectWs(Uri url, {Map<String, dynamic>? headers}) => WebSocketChannel.connect(url);
