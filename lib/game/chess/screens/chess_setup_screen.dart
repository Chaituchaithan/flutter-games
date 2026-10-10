import 'package:flutter/material.dart';

import 'package:snakeladder/game/chess/screens/chess_vs_computer_screen.dart';
import 'package:snakeladder/game/chess/chess_engine.dart';
import 'package:snakeladder/widgets/aura.dart';

/// Quick Play setup: pick the computer's difficulty and a time control, then
/// start a local game vs the [ChessBot]. (More options planned later.)
class ChessSetupScreen extends StatefulWidget {
  const ChessSetupScreen({super.key});

  @override
  State<ChessSetupScreen> createState() => _ChessSetupScreenState();
}

class _ChessSetupScreenState extends State<ChessSetupScreen> {
  int _depth = 2; // Medium
  int? _clockMs = 30 * 1000; // 30 s per move
  PieceColor? _side = PieceColor.white; // null = random

  static const List<({String label, PieceColor? color})> _sides = [
    (label: 'White', color: PieceColor.white),
    (label: 'Black', color: PieceColor.black),
    (label: 'Random', color: null),
  ];

  static const List<({String label, int depth, String sub, IconData icon})> _difficulties = [
    (label: 'Easy', depth: 1, sub: 'Relaxed', icon: Icons.sentiment_satisfied_rounded),
    (label: 'Medium', depth: 2, sub: 'Balanced', icon: Icons.whatshot_rounded),
    (label: 'Hard', depth: 3, sub: 'Tough', icon: Icons.bolt_rounded),
  ];

  /// Time allowed for EACH move (resets every turn); null = no limit.
  static const List<({String label, int? ms})> _times = [
    (label: '30 sec', ms: 30 * 1000),
    (label: '1 min', ms: 60 * 1000),
    (label: '2 min', ms: 2 * 60 * 1000),
    (label: 'Unlimited', ms: null),
  ];

  void _start() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChessVsComputerScreen(depth: _depth, clockMs: _clockMs, playerColor: _side)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Quick Play'),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text('Play vs Computer', style: AuraText.headline.copyWith(fontSize: 24)),
          const SizedBox(height: 6),
          Text('Pick your side, difficulty and time control.', style: AuraText.cardSub),
          const SizedBox(height: 20),
          const SectionBar('Play as'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final s in _sides)
                _Chip(
                  label: s.label,
                  selected: _side == s.color,
                  onTap: () => setState(() => _side = s.color),
                ),
            ],
          ),
          const SizedBox(height: 22),
          const SectionBar('Difficulty'),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final d in _difficulties) ...[
                Expanded(
                  child: _OptionCard(
                    icon: d.icon,
                    title: d.label,
                    sub: d.sub,
                    selected: _depth == d.depth,
                    onTap: () => setState(() => _depth = d.depth),
                  ),
                ),
                if (d != _difficulties.last) const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 22),
          const SectionBar('Time per move'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final t in _times)
                _Chip(
                  label: t.label,
                  selected: _clockMs == t.ms,
                  onTap: () => setState(() => _clockMs = t.ms),
                ),
            ],
          ),
          const SizedBox(height: 30),
          GradientButton(label: 'Start game', onPressed: _start),
          const SizedBox(height: 10),
          SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).maybePop()),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.icon, required this.title, required this.sub, required this.selected, required this.onTap});
  final IconData icon;
  final String title;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          // Selected = the brand (Aurora) gradient; unselected = glass. Border
          // width is CONSTANT so selecting never changes the tile's size (which
          // was shifting the Start/Cancel buttons below).
          gradient: selected
              ? AuraGradients.brand
              : LinearGradient(colors: [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.03)]),
          border: Border.all(
            color: selected ? Colors.white.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.14),
            width: 2,
          ),
          boxShadow: selected
              ? [BoxShadow(color: AuraColors.brandPink.withValues(alpha: 0.45), blurRadius: 20, spreadRadius: -8, offset: const Offset(0, 8))]
              : null,
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.white.withValues(alpha: 0.75), size: 26),
            const SizedBox(height: 8),
            Text(title, style: AuraText.cardTitle.copyWith(fontSize: 15, color: Colors.white)),
            const SizedBox(height: 2),
            Text(sub, style: AuraText.cardSub.copyWith(fontSize: 11, color: Colors.white.withValues(alpha: selected ? 0.85 : 0.6))),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          // Game-theme styling: brand gradient + glow when selected, glass
          // otherwise. Border width is CONSTANT (no size change → no shake).
          gradient: selected
              ? AuraGradients.brand
              : LinearGradient(colors: [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.03)]),
          border: Border.all(
            color: selected ? Colors.white.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.16),
            width: 1.5,
          ),
          boxShadow: selected
              ? [BoxShadow(color: AuraColors.brandPink.withValues(alpha: 0.5), blurRadius: 16, spreadRadius: -8, offset: const Offset(0, 6))]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.8),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
