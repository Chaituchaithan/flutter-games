import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Native: send [headers] (e.g. `Authorization: Bearer …`) on the upgrade.
WebSocketChannel connectWs(Uri url, {Map<String, dynamic>? headers}) => IOWebSocketChannel.connect(url, headers: headers);
