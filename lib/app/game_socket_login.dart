import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/configs.dart';
import '../services/socket/app_socket.dart';
import '../services/socket/socket_client.dart';
import '../services/token_store.dart';
import 'game_area.dart';

/// Signs the app's realtime socket in for the current player: opens the
/// socket game's service (the active game when it plays online, else the
/// app's online game) and sends `auth.login {token, username}`.
///
/// Used after Login and when a saved session is restored at startup. Throws
/// on failure — see [errorText] for a player-facing message.
class GameSocketLogin {
  GameSocketLogin(this._ref);
  final Ref _ref;

  /// Whether a socket sign-in applies (socket on, an online game in this app).
  bool get applies => kSocketEnabled && GameArea.socketGame(_ref.read(activeGameProvider)) != null;

  Future<void> connect({String? username}) async {
    if (!applies) return;
    final token = await _ref.read(tokenStoreProvider).readAccess() ?? '';
    if (token.isEmpty) return; // signed out / demo → nothing to sign in
    final game = GameRegistry.of(GameArea.socketGame(_ref.read(activeGameProvider))!);
    await _ref.read(appSocketProvider).connect(token: token, username: username, game: game);
  }

  /// A player-facing message for a failed socket sign-in (details stay in the
  /// `[SOCKET]` log).
  static String errorText(Object e) {
    if (e is SocketError) {
      return switch (e.code) {
        'invalid_credentials' || 'unauthorized' => 'Your session was rejected by the game server. Please log in again.',
        'banned' => 'This account is blocked from online play.',
        'already_connected' => 'You are already signed in on another device.',
        'connect_timeout' ||
        'connect_failed' ||
        'disconnected' => "Couldn't reach the game server. Check your connection and try again.",
        _ => e.message.isNotEmpty ? e.message : "Couldn't sign in to the game server.",
      };
    }
    return "Couldn't reach the game server. Check your connection and try again.";
  }
}

final gameSocketLoginProvider = Provider<GameSocketLogin>(GameSocketLogin.new);
