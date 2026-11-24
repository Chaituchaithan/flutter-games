/// Drives the offline game's board view ([SnakesBoardView]) from server
/// frames only: positions come from the latest `state`, and the move to
/// animate from `last_action` (snake-and-ladder.md "The board").
library;

import '../snakes_engine.dart';
import 'snakes_online_models.dart';

class SnlBoardGame extends SnakesGame {
  SnlBoardGame({required super.players, required super.layout});

  /// Where the server says every token is (turn order).
  List<int> _server = const [];

  /// Set every token from the server. [move] (if any) animates first: its
  /// mover and any captured tokens stay where they were until it ends.
  void applyServer({
    required List<int> positions,
    required int turn,
    int? winner,
    SnakesMove? move,
    Set<int> captured = const {},
    int? dice,
    String? text,
  }) {
    final before = [...this.positions];
    _server = [...positions];
    for (var i = 0; i < players; i++) {
      final keep = move != null && (i == move.player || captured.contains(i));
      this.positions[i] = keep ? (i == move.player ? move.from : before[i]) : (i < positions.length ? positions[i] : 0);
    }
    this.turn = turn.clamp(0, players - 1);
    this.winner = winner;
    if (dice != null) {
      lastRoll = dice.clamp(1, 6);
      rollId++;
      moveCount++;
    }
    if (text != null) lastText = text;
    pending = move;
    notifyListeners();
  }

  /// The move finished animating: every token to its server square.
  void clearPending() {
    if (pending == null) return;
    pending = null;
    for (var i = 0; i < players && i < _server.length; i++) {
      positions[i] = _server[i];
    }
    notifyListeners();
  }

  /// The hop to animate for [r] by the player at board index [player].
  static SnakesMove? moveOf(SnlRoll r, int player, int fromFallback, SnakesLayout layout) {
    if (!r.isRoll) return null;
    final from = r.from ?? fromFallback;
    final to = r.to ?? from;
    // Too far past the finish, a lost turn, or no move yet: a shake in place.
    if (from == to && r.landingSquare == null) {
      return SnakesMove(player: player, roll: r.diceValue ?? 1, from: from, steps: const []);
    }
    final walkEnd = (r.landingSquare ?? to).clamp(0, layout.size);
    final steps = walkEnd > from ? [for (var s = from + 1; s <= walkEnd; s++) s] : <int>[];
    if (steps.isEmpty) {
      // Nothing to walk (a capture edge case): jump straight there.
      return SnakesMove(player: player, roll: r.diceValue ?? 1, from: from, steps: [to.clamp(1, layout.size)]);
    }
    var jump = SnakesJump.none;
    int? jumpTo;
    if (to != walkEnd) {
      // Down a snake, or up a ladder (a Snake Charmer lifts the token up a
      // snake: that climbs too).
      jump = to < walkEnd ? SnakesJump.snake : SnakesJump.ladder;
      jumpTo = to;
    }
    return SnakesMove(player: player, roll: r.diceValue ?? 1, from: from, steps: steps, jump: jump, jumpTo: jumpTo);
  }
}
