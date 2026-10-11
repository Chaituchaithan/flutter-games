import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import 'turn_timer.dart';

import 'package:snakeladder/widgets/aura.dart';

/// Shared pieces for the dice games (Ludo, Snakes & Ladders): who's playing,
/// the player strip, the dice tray and the Quick Play setup screen.

/// A seat in a local dice game.
class DicePlayer {
  const DicePlayer({required this.name, required this.initials, required this.color, this.isYou = false});
  final String name;
  final String initials;
  final Color color;
  final bool isYou;
}

/// Computer opponents' names (seat order).
const diceBotNames = [('Nova', 'NV'), ('Rex', 'RX'), ('Mia', 'MI')];

/// One seat as the layout shows it.
class DiceSeatView {
  const DiceSeatView({required this.player, required this.sub, required this.active, this.turnText, this.progress});
  final DicePlayer player;

  /// Second row ("Square 47", "2 home · 1 out").
  final String sub;

  /// Their turn (card glows, timer ring runs).
  final bool active;

  /// Third row while active ("Rolling… · 27s").
  final String? turnText;

  /// Turn time left 1→0 (null = unlimited / not their turn).
  final double? progress;
}

/// The chess game-area layout for the dice games: header · opponents (with
/// the last move beside a single opponent, as in chess) · board · turn clock |
/// die | you · action bar. Same cards, timer rings and panels as chess.
class DiceBoardLayout extends StatelessWidget {
  const DiceBoardLayout({
    super.key,
    required this.header,
    required this.opponents,
    required this.you,
    required this.lastMove,
    required this.clockText,
    required this.clockUrgent,
    this.dice,
    required this.board,
    required this.actionBar,
  });

  final Widget header;
  final List<DiceSeatView> opponents;
  final DiceSeatView you;
  final String lastMove;

  /// Turn clock panel text; null hides the panel (the timer ring on the
  /// player cards still shows the time left).
  final String? clockText;
  final bool clockUrgent;
  /// The die (dice games); null = no dice slot (2-player board games, as in
  /// chess: Turn clock · You).
  final Widget? dice;
  final Widget board;
  final Widget actionBar;

  Widget _card(DiceSeatView s) => BoardPlayerCard(
    name: s.player.name,
    initials: s.player.initials,
    sub: s.sub,
    color: s.player.color,
    color2: Color.lerp(s.player.color, Colors.black, 0.3),
    active: s.active,
    turnText: s.turnText,
    progress: s.progress,
  );

  @override
  Widget build(BuildContext context) {
    final single = opponents.length == 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < opponents.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _card(opponents[i])),
              ],
              if (single) ...[
                const SizedBox(width: 10),
                Expanded(child: BoardInfoPanel(label: context.l10n.lastMove, value: lastMove)),
              ],
            ],
          ),
        ),
        if (!single) ...[
          const SizedBox(height: 8),
          Text(
            '${context.l10n.lastMove}: $lastMove',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AuraText.cardSub.copyWith(fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(child: board),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (clockText != null) ...[
                Expanded(
                  child: BoardInfoPanel(label: context.l10n.turnClock, value: clockText!, big: true, urgent: clockUrgent),
                ),
                if (dice != null) ...[
                  const SizedBox(width: 8),
                  // The dice in its own slot, centred (never over a panel edge).
                  SizedBox(width: 84, child: BoardSlot(padding: EdgeInsets.zero, child: Center(child: dice))),
                ],
              ] else if (dice != null)
                Expanded(child: BoardSlot(padding: EdgeInsets.zero, child: Center(child: dice))),
              const SizedBox(width: 8),
              Expanded(child: _card(you)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        actionBar,
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Quick Play setup for a dice game: number of players (you + computers) and
/// your colour, then [start] opens the game.
class DiceGameSetupScreen extends StatefulWidget {
  const DiceGameSetupScreen({
    super.key,
    required this.title,
    required this.blurb,
    required this.colors,
    required this.start,
  });

  final String title;
  final String blurb;

  /// Selectable colours (label, colour).
  final List<(String, Color)> colors;

  /// Build the game for (players, chosen colour index, time per turn in ms —
  /// null = unlimited).
  final Widget Function(int players, int colorIndex, int? clockMs) start;

  @override
  State<DiceGameSetupScreen> createState() => _DiceGameSetupScreenState();
}

class _DiceGameSetupScreenState extends State<DiceGameSetupScreen> {
  int _players = 2;
  late int _color = widget.colors.length - 1;
  int? _clockMs = 30 * 1000; // same default as chess Quick Play

  String _timeLabel(BuildContext context, int? ms) => ms == null
      ? context.l10n.unlimited
      : ms < 60000
      ? context.l10n.timeSec(ms ~/ 1000)
      : context.l10n.timeMin(ms ~/ 60000);

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: AuraAppBar(title: context.l10n.quickPlay),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(widget.title, style: AuraText.headline.copyWith(fontSize: 24)),
          const SizedBox(height: 6),
          Text(widget.blurb, style: AuraText.cardSub),
          const SizedBox(height: 22),
          SectionBar(context.l10n.players),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final n in const [2, 3, 4]) ...[
                Expanded(
                  child: SetupTile(
                    selected: _players == n,
                    onTap: () => setState(() => _players = n),
                    child: Column(
                      children: [
                        Text(
                          '$n',
                          style: TextStyle(
                            fontFamily: AuraText.displayFamily,
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.l10n.youPlusAi(n - 1),
                          style: AuraText.cardSub.copyWith(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
                if (n != 4) const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 22),
          SectionBar(context.l10n.yourColour),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < widget.colors.length; i++) ...[
                Expanded(
                  child: SetupTile(
                    selected: _color == i,
                    onTap: () => setState(() => _color = i),
                    child: Column(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color.lerp(widget.colors[i].$2, Colors.white, 0.3)!, widget.colors[i].$2],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: widget.colors[i].$2.withValues(alpha: 0.6),
                                blurRadius: 10,
                                spreadRadius: -2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.colors[i].$1,
                          style: AuraText.cardSub.copyWith(fontSize: 11.5, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                if (i < widget.colors.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 22),
          SectionBar(context.l10n.timePerTurn),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < turnTimeOptions.length; i++) ...[
                Expanded(
                  child: SetupTile(
                    selected: _clockMs == turnTimeOptions[i].ms,
                    onTap: () => setState(() => _clockMs = turnTimeOptions[i].ms),
                    child: Center(
                      child: Text(
                        _timeLabel(context, turnTimeOptions[i].ms),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AuraText.displayFamily,
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                if (i < turnTimeOptions.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(context.l10n.timeUpRule, style: AuraText.cardSub.copyWith(fontSize: 12)),
          const SizedBox(height: 26),
          GradientButton(
            label: context.l10n.startGame,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => widget.start(_players, _color, _clockMs)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class SetupTile extends StatelessWidget {
  const SetupTile({super.key, required this.selected, required this.onTap, required this.child});
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: selected
              ? AuraGradients.brand
              : LinearGradient(colors: [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.03)]),
          border: Border.all(
            color: selected ? Colors.white.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.14),
            width: 2,
          ),
        ),
        child: child,
      ),
    );
  }
}
