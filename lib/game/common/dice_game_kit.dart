import 'package:flutter/material.dart';

import 'package:snakeladder/game/common/dice_view.dart';
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

/// A row of compact player pills: colour dot/avatar, name, a status line;
/// the player to move glows in their colour.
class DicePlayersStrip extends StatelessWidget {
  const DicePlayersStrip({super.key, required this.players, required this.active, required this.status});
  final List<DicePlayer> players;

  /// Index of the player to move (null = nobody, e.g. game over).
  final int? active;

  /// Second line per player ("Square 47", "2/4 home", …).
  final String Function(int i) status;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < players.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _PlayerPill(player: players[i], active: active == i, status: status(i)),
          ),
        ],
      ],
    );
  }
}

class _PlayerPill extends StatelessWidget {
  const _PlayerPill({required this.player, required this.active, required this.status});
  final DicePlayer player;
  final bool active;
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = player.color;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        // Opaque base so the active glow never shows through.
        color: active ? Color.alphaBlend(c.withValues(alpha: 0.22), const Color(0xFF15102A)) : const Color(0xFF15102A),
        border: Border.all(color: active ? c : Colors.white.withValues(alpha: 0.12), width: active ? 1.6 : 1),
        boxShadow: active ? [BoxShadow(color: c.withValues(alpha: 0.45), blurRadius: 14, spreadRadius: -4)] : null,
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color.lerp(c, Colors.white, 0.25)!, c]),
            ),
            child: Text(
              player.initials,
              style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AuraText.cardTitle.copyWith(fontSize: 12.5),
                ),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AuraText.cardSub.copyWith(fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The dice tray: last move on the left, the animated die in the middle, a
/// prompt on the right. The die is tappable only when [canRoll].
class DiceTray extends StatelessWidget {
  const DiceTray({
    super.key,
    required this.value,
    required this.rollId,
    required this.canRoll,
    required this.onRoll,
    required this.lastMove,
    required this.prompt,
    this.color,
    this.onRolled,
  });

  final int value;
  final int rollId;
  final bool canRoll;
  final VoidCallback onRoll;
  final String lastMove;
  final String prompt;

  /// Tint of the die's glow (the player to move).
  final Color? color;
  final VoidCallback? onRolled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      decoration: AuraGlass.decoration(radius: 20, shadow: false),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('LAST MOVE', style: AuraText.section.copyWith(fontSize: 10)),
                const SizedBox(height: 3),
                Text(
                  lastMove,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AuraText.cardSub.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          DiceView(
            value: value,
            rollId: rollId,
            size: 46,
            enabled: canRoll,
            onTap: onRoll,
            glow: color ?? AuraColors.accentGlow,
            onRolled: onRolled,
          ),
          Expanded(
            child: Text(
              prompt,
              textAlign: TextAlign.right,
              maxLines: 2,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: canRoll ? Colors.white : AuraColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
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

  /// Build the game for (players, chosen colour index).
  final Widget Function(int players, int colorIndex) start;

  @override
  State<DiceGameSetupScreen> createState() => _DiceGameSetupScreenState();
}

class _DiceGameSetupScreenState extends State<DiceGameSetupScreen> {
  int _players = 2;
  late int _color = widget.colors.length - 1;

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Quick Play'),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(widget.title, style: AuraText.headline.copyWith(fontSize: 24)),
          const SizedBox(height: 6),
          Text(widget.blurb, style: AuraText.cardSub),
          const SizedBox(height: 22),
          const SectionBar('Players'),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final n in const [2, 3, 4]) ...[
                Expanded(
                  child: _SetupTile(
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
                          n == 2 ? 'You + 1 AI' : 'You + ${n - 1} AI',
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
          const SectionBar('Your colour'),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < widget.colors.length; i++) ...[
                Expanded(
                  child: _SetupTile(
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
          const SizedBox(height: 30),
          GradientButton(
            label: 'Start game',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => widget.start(_players, _color))),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SetupTile extends StatelessWidget {
  const _SetupTile({required this.selected, required this.onTap, required this.child});
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
