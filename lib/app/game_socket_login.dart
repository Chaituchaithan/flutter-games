import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configs/configs.dart';
import '../services/socket/app_socket.dart';
import '../services/socket/socket_client.dart';
import '../services/session.dart';
import '../services/token_store.dart';

/// Signs the app's realtime socket in for the current player: opens a live
/// game server (the active game's when it has one, else Ludo's,
/// `ws://<host>:1285/ws`) and sends `auth.login {token}`.
///
/// Used after Login and when a saved session is restored at startup. Throws
/// on failure — see [errorText] for a player-facing message.
class GameSocketLogin {
  GameSocketLogin(this._ref);
  final Ref _ref;

  /// Whether a socket sign-in applies (the socket switch is on).
  bool get applies => kSocketEnabled;

  /// The server to sign in to: the active game's when it is live, else Ludo.
  GameConfig get game {
    final active = _ref.read(activeGameProvider);
    return GameRegistry.of(liveSocketGames.contains(active) ? active : signInSocketGame);
  }

  Future<void> connect({String? username}) async {
    if (!applies) return;
    // Checked for expiry (refreshed first when it is about to run out).
    final token = await _ref.read(sessionProvider.notifier).validAccessToken() ?? '';
    if (token.isEmpty) return; // signed out / demo → nothing to sign in
    final socket = _ref.read(appSocketProvider);
    try {
      await socket.connect(token: token, username: username, game: game);
    } on SocketError catch (e) {
      // `auth.login_error` (ludo.md §1): an expired/invalid token → refresh
      // at the gateway, then retry once; a revoked session → log in again.
      if (e.code == 'token_revoked') {
        _ref.read(sessionProvider.notifier).forceSignOut();
        rethrow;
      }
      if (e.code != 'invalid_credentials') rethrow;
      if (!await _ref.read(sessionProvider.notifier).refreshSession()) rethrow;
      final fresh = await _ref.read(tokenStoreProvider).readAccess() ?? '';
      if (fresh.isEmpty || fresh == token) rethrow;
      await socket.connect(token: fresh, username: username, game: game);
    }
  }

  /// A player-facing message for a failed socket sign-in (details stay in the
  /// `[SOCKET]` log).
  static String errorText(Object e) {
    if (e is SocketError) {
      return switch (e.code) {
        'invalid_credentials' || 'unauthorized' || 'token_revoked' =>
          'Your session was rejected by the game server. Please log in again.',
        'banned' => 'This account is blocked from online play.',
        'duplicate' || 'already_connected' => 'You are already signed in on another device.',
        // An operator paused new games: their message is written for players.
        'kill_switch_engaged' => e.message.isNotEmpty ? e.message : 'New games are paused for a moment. Try again soon.',
        // The region gate refuses the upgrade with HTTP 403 (12-safety.md §6).
        'connect_failed' when e.message.contains('status code: 403') => "Games aren't available in your region.",
        'connect_timeout' ||
        'connect_failed' ||
        'disconnected' => "Couldn't reach the game server. Check your connection and try again.",
        // Other messages are developer text: never shown.
        _ => "Couldn't sign in to the game server.",
      };
    }
    return "Couldn't reach the game server. Check your connection and try again.";
  }
}

final gameSocketLoginProvider = Provider<GameSocketLogin>(GameSocketLogin.new);
