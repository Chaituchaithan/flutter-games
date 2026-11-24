import 'package:web_socket_channel/web_socket_channel.dart';

/// Web: the browser answers the server's ping frames itself.
WebSocketChannel connectWs(Uri url, {Duration? pingInterval}) => WebSocketChannel.connect(url);
