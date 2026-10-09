/// Event names + error codes for the realtime WebSocket protocol.
/// Mirrors SOCKET_HOOKS.md (All Games Portal). Dot-notation `{domain}.{action}`.
library;

/// Client→Server and Server→Client event name constants.
abstract final class SocketEvent {
  // Connection lifecycle.
  static const established = 'connection.established';
  static const ping = 'connection.ping';
  static const pong = 'connection.pong';
  static const kicked = 'connection.kicked';
  static const connectionError = 'connection.error';

  // Auth.
  static const login = 'auth.login';
  static const loginSuccess = 'auth.login_success';
  static const loginError = 'auth.login_error';
  static const register = 'auth.register';
  static const registerSuccess = 'auth.register_success';
  static const registerError = 'auth.register_error';
  static const refresh = 'auth.refresh';
  static const tokenRefreshed = 'auth.token_refreshed';
  static const logout = 'auth.logout';
  static const loggedOut = 'auth.logged_out';
  static const sessionExpired = 'auth.session_expired';

  // Lobby / rooms.
  static const roomList = 'room.list';
  static const roomListResult = 'room.list_result';
  static const roomCreate = 'room.create';
  static const roomCreated = 'room.created';
  static const roomCreateError = 'room.create_error';
  static const roomJoin = 'room.join';
  static const roomJoined = 'room.joined';
  static const roomJoinError = 'room.join_error';
  static const roomLeave = 'room.leave';
  static const roomLeft = 'room.left';
  static const roomDestroy = 'room.destroy';
  static const roomDestroyed = 'room.destroyed';
  static const roomUserJoined = 'room.user_joined';
  static const roomUserLeft = 'room.user_left';
  static const roomCountUpdate = 'room.count_update';
  static const roomFull = 'room.full';

  // Matchmaking.
  static const matchFind = 'match.find';
  static const matchSearching = 'match.searching';
  static const matchFound = 'match.found';
  static const matchTimeout = 'match.timeout';
  static const matchCancel = 'match.cancel';
  static const matchCancelled = 'match.cancelled';

  // Ready / start.
  static const playerReady = 'player.ready';
  static const playerUnready = 'player.unready';
  static const playerReadyUpdate = 'player.ready_update';
  static const gameCountdown = 'game.countdown';
  static const gameCountdownCancelled = 'game.countdown_cancelled';
  static const gameStarted = 'game.started';

  // Game actions.
  static const gameAction = 'game.action';
  static const gameActionAck = 'game.action_ack';
  static const gameActionError = 'game.action_error';
  static const gameStateUpdate = 'game.state_update';
  static const gameTurnStart = 'game.turn_start';
  static const gameTurnTimeout = 'game.turn_timeout';
  static const gamePlayerForfeited = 'game.player_forfeited';
  static const gameOver = 'game.over';
  static const gameRematch = 'game.rematch';
  static const gameRematchProposed = 'game.rematch_proposed';
  static const gameRematchAccept = 'game.rematch_accept';
  static const gameRematchStarting = 'game.rematch_starting';

  // Chat.
  static const chatSend = 'chat.send';
  static const chatMessage = 'chat.message';

  // Economy.
  static const walletBalance = 'wallet.balance';
  static const walletBalanceResult = 'wallet.balance_result';
  static const walletBalanceChanged = 'wallet.balance_changed';
}

/// Standardized error codes (SOCKET_HOOKS.md §Error Codes).
abstract final class SocketErrorCode {
  static const unauthorized = 'unauthorized';
  static const forbidden = 'forbidden';
  static const notFound = 'not_found';
  static const invalidRequest = 'invalid_request';
  static const invalidState = 'invalid_state';
  static const rateLimited = 'rate_limited';
  static const insufficientBalance = 'insufficient_balance';
  static const roomFull = 'room_full';
  static const alreadyInRoom = 'already_in_room';
  static const gameInProgress = 'game_in_progress';
}
