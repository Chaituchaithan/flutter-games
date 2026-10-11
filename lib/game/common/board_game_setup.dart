import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../widgets/aura.dart';
import 'dice_game_kit.dart' show SetupTile;
import 'turn_timer.dart';

/// One side the player can take (e.g. Othello Black / White).
class SetupSide {
  const SetupSide({required this.label, required this.icon});
  final String label;

  /// The side's picture (a disc, a piece…).
  final Widget icon;
}

/// Quick Play setup for a 2-player board game vs the computer — the same
/// choices as chess: side (or random), difficulty, time per move. [start]
/// gets (side index or null = random, difficulty 1–3, ms per move or null).
class BoardGameSetupScreen extends StatefulWidget {
  const BoardGameSetupScreen({
    super.key,
    required this.title,
    required this.blurb,
    this.sides = const [],
    required this.start,
    this.timeOptions = turnTimeOptions,
    this.defaultClockMs = 30 * 1000,
    this.timeRule,
  });

  final String title;
  final String blurb;

  /// Sides to pick from; empty = no side section (e.g. Scrabble).
  final List<SetupSide> sides;
  final Widget Function(int? side, int difficulty, int? clockMs) start;

  /// Time choices (default: the chess ones) and the preselected one.
  final List<({String label, int? ms})> timeOptions;
  final int? defaultClockMs;

  /// What happens when time runs out (default: "you lose the game").
  final String? timeRule;

  @override
  State<BoardGameSetupScreen> createState() => _BoardGameSetupScreenState();
}

class _BoardGameSetupScreenState extends State<BoardGameSetupScreen> {
  int? _side = 0; // null = random
  int _difficulty = 2;
  late int? _clockMs = widget.defaultClockMs;

  String _timeLabel(BuildContext context, int? ms) => ms == null
      ? context.l10n.unlimited
      : ms < 60000
      ? context.l10n.timeSec(ms ~/ 1000)
      : context.l10n.timeMin(ms ~/ 60000);

  Widget _label(String text) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontFamily: AuraText.displayFamily,
      color: Colors.white,
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final levels = [
      (1, l.easy, l.relaxed, Icons.sentiment_satisfied_rounded),
      (2, l.medium, l.balanced, Icons.whatshot_rounded),
      (3, l.hard, l.tough, Icons.bolt_rounded),
    ];
    return AuraScaffold(
      appBar: AuraAppBar(title: l.quickPlay),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(widget.title, style: AuraText.headline.copyWith(fontSize: 24)),
          const SizedBox(height: 6),
          Text(widget.blurb, style: AuraText.cardSub),
          const SizedBox(height: 22),
          if (widget.sides.isNotEmpty) ...[
            SectionBar(l.playAs),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i <= widget.sides.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: SetupTile(
                      selected: i < widget.sides.length ? _side == i : _side == null,
                      onTap: () => setState(() => _side = i < widget.sides.length ? i : null),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 30,
                            child: i < widget.sides.length
                                ? widget.sides[i].icon
                                : const Icon(Icons.shuffle_rounded, color: Colors.white70, size: 26),
                          ),
                          const SizedBox(height: 6),
                          _label(i < widget.sides.length ? widget.sides[i].label : l.randomSide),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 22),
          ],
          SectionBar(l.difficulty),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (d, name, sub, icon) in levels) ...[
                if (d > 1) const SizedBox(width: 10),
                Expanded(
                  child: SetupTile(
                    selected: _difficulty == d,
                    onTap: () => setState(() => _difficulty = d),
                    child: Column(
                      children: [
                        Icon(icon, color: Colors.white, size: 24),
                        const SizedBox(height: 6),
                        _label(name),
                        Text(sub, style: AuraText.cardSub.copyWith(fontSize: 11, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 22),
          SectionBar(l.timePerMove),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < widget.timeOptions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: SetupTile(
                    selected: _clockMs == widget.timeOptions[i].ms,
                    onTap: () => setState(() => _clockMs = widget.timeOptions[i].ms),
                    child: Center(child: _label(_timeLabel(context, widget.timeOptions[i].ms))),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(widget.timeRule ?? l.timeOutLoses, style: AuraText.cardSub.copyWith(fontSize: 12)),
          const SizedBox(height: 26),
          GradientButton(
            label: l.startGame,
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => widget.start(_side, _difficulty, _clockMs))),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
