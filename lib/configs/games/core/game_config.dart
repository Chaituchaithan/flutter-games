/// The shape every game fills in. Shared values (host, schemes, proxy) come
/// from [ServerConfig] / proxy config; a game only declares what differs.
library;

import 'game_id.dart';

class GameConfig {
  const GameConfig({
    required this.id,
    required this.displayName,
    this.shortName,
    required this.icon,
    required this.port,
    required this.socketPath,
    required this.minPlayers,
    required this.maxPlayers,
    this.turnTimeMs = 30000,
    this.wsUrlOverride = '',
    this.available = false,
  });

  final GameId id;
  final String displayName;

  /// Name for tight spots (Home chips); defaults to [displayName].
  final String? shortName;
  String get chipName => shortName ?? displayName;

  /// Short glyph for chips and headers, e.g. '♞'.
  final String icon;

  /// The game service's port on the shared host — serves BOTH its REST API
  /// (`http://host:port/health`, `/metrics`, …) and its socket
  /// (`ws://host:port/ws`).
  final int port;

  /// Socket path on that port, e.g. '/ws'.
  final String socketPath;

  final int minPlayers;
  final int maxPlayers;

  /// Per-move time limit for online play.
  final int turnTimeMs;

  /// Full socket URL from `--dart-define=<GAME>_WS_URL=…` ('' = not set).
  final String wsUrlOverride;

  /// The game area (board + session) is built and playable. Others show as
  /// "Coming soon".
  final bool available;

  /// "2P" or "2–4P".
  String get playersLabel => minPlayers == maxPlayers ? '${maxPlayers}P' : '$minPlayers–${maxPlayers}P';
}
