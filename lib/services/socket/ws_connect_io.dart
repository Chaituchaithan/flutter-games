import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Native: dart:io answers the server's pings; [pingInterval] also pings the
/// server so a dead network is noticed quickly.
WebSocketChannel connectWs(Uri url, {Duration? pingInterval}) => IOWebSocketChannel.connect(url, pingInterval: pingInterval);
