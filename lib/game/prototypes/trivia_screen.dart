import 'package:flutter/material.dart';

import 'package:snakeladder/widgets/aura.dart';

/// Trivia quiz. [players] is 2 or 4. See docs/DESIGN_SPEC.md.
///
/// Static presentation only — no game logic. Everything below is drawn from
/// the Aura design system (`AuraScaffold`, `AuraCard`, `LetterAvatar`, …).
class TriviaScreen extends StatelessWidget {
  const TriviaScreen({super.key, this.players = 2});

  final int players;

  @override
  Widget build(BuildContext context) {
    final roster = _roster(players);

    return AuraScaffold(
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          GameHeader(
            title: 'Round 1',
            subtitle: '$players players · first to 3',
            pot: '400',
          ),
          const SizedBox(height: 18),
          _scoreStrip(roster),
          const SizedBox(height: 18),
          const _CategoryChip(label: 'SCIENCE'),
          const SizedBox(height: 14),
          const _QuestionCard(
            label: 'Q1',
            question: 'Which gas do plants absorb from the air?',
          ),
          const SizedBox(height: 16),
          _answerGrid(),
          const SizedBox(height: 18),
          _powerUpBar(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ---- 2) Player score strip -------------------------------------------

  Widget _scoreStrip(List<_Player> roster) {
    // Two chips per row; a trailing spacer keeps a lone chip half-width.
    final rows = <Widget>[];
    for (var i = 0; i < roster.length; i += 2) {
      final left = _PlayerChip(player: roster[i]);
      final Widget right = (i + 1 < roster.length)
          ? _PlayerChip(player: roster[i + 1])
          : const SizedBox.shrink();
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              const SizedBox(width: 10),
              Expanded(child: right),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  // ---- 5) Answer options (2×2) -----------------------------------------

  Widget _answerGrid() {
    const options = [
      ('A', 'Oxygen', false),
      ('B', 'Nitrogen', false),
      ('C', 'Carbon dioxide', true),
      ('D', 'Helium', false),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.6,
      children: [
        for (final (letter, text, selected) in options)
          _AnswerOption(letter: letter, text: text, selected: selected),
      ],
    );
  }

  // ---- 6) Power-up bar --------------------------------------------------

  Widget _powerUpBar() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          Expanded(
            child: _PowerUp(
              icon: Icons.lightbulb_outline,
              label: 'Hint',
              count: 0,
              active: false,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: _PowerUp(
              icon: Icons.ac_unit,
              label: 'Freeze',
              count: 3,
              active: true,
            ),
          ),
        ],
      ),
    );
  }

  // ---- Data -------------------------------------------------------------

  static List<_Player> _roster(int players) {
    final base = <_Player>[
      const _Player(
        name: 'You',
        initials: 'NR',
        color: AuraColors.brandPurple,
        detail: '7 pts',
      ),
      const _Player(
        name: 'ZeroCool',
        initials: 'ZE',
        color: AuraColors.green,
        detail: 'Thinking…',
        current: true,
      ),
    ];
    if (players >= 4) {
      base.addAll(const [
        _Player(
          name: 'NeonViper',
          initials: 'NV',
          color: AuraColors.avatarBlue,
          detail: '5 pts',
        ),
        _Player(
          name: 'PixelGhost',
          initials: 'PG',
          color: AuraColors.avatarPurple,
          detail: '6 pts',
        ),
      ]);
    }
    return base;
  }
}

// ============================================================================
// Private helpers
// ============================================================================

class _Player {
  const _Player({
    required this.name,
    required this.initials,
    required this.color,
    required this.detail,
    this.current = false,
  });

  final String name;
  final String initials;
  final Color color;
  final String detail;
  final bool current;
}

/// A single player chip: avatar + name + points/status. Subtly highlighted
/// when it is the current answerer.
class _PlayerChip extends StatelessWidget {
  const _PlayerChip({required this.player});
  final _Player player;

  @override
  Widget build(BuildContext context) {
    final highlight = player.current;
    return AuraCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      radius: 16,
      gradient: highlight
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AuraColors.brandPurple.withValues(alpha: 0.22),
                AuraColors.brandPink.withValues(alpha: 0.10),
              ],
            )
          : null,
      child: Row(
        children: [
          LetterAvatar(letter: player.initials, color: player.color, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  player.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: highlight
                        ? AuraColors.brandPink
                        : AuraColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small brand-tinted, letter-spaced category pill.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    // Aligned to the start, sized to its content (AuraBadge-style).
    return Row(
      children: [AuraBadge(label, color: AuraColors.brandPurple)],
    );
  }
}

/// The large question card with a purple-gradient tint.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.label, required this.question});
  final String label;
  final String question;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      padding: const EdgeInsets.all(20),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AuraColors.brandPurple.withValues(alpha: 0.28),
          AuraColors.brandPink.withValues(alpha: 0.14),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AuraColors.brandPink,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            question,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable answer option card with a letter badge + option text.
class _AnswerOption extends StatelessWidget {
  const _AnswerOption({
    required this.letter,
    required this.text,
    required this.selected,
  });

  final String letter;
  final String text;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      onTap: () {},
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      gradient: selected
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AuraColors.brandPurple.withValues(alpha: 0.30),
                AuraColors.brandPink.withValues(alpha: 0.16),
              ],
            )
          : null,
      child: Row(
        children: [
          _LetterBadge(letter: letter, selected: selected),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : AuraColors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.check_circle,
              size: 18,
              color: AuraColors.brandPink,
            ),
          ],
        ],
      ),
    );
  }
}

/// The small rounded-square A/B/C/D badge inside an answer option.
class _LetterBadge extends StatelessWidget {
  const _LetterBadge({required this.letter, required this.selected});
  final String letter;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: selected ? AuraGradients.brand : null,
        color: selected ? null : AuraColors.chipDark,
        borderRadius: BorderRadius.circular(9),
        border: selected
            ? null
            : Border.all(color: AuraColors.cardBorder),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontFamily: AuraText.displayFamily,
          color: selected ? Colors.white : AuraColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// A power-up button (Hint / Freeze) with a label + "×N" count badge.
/// [active] false renders a muted/disabled look.
class _PowerUp extends StatelessWidget {
  const _PowerUp({
    required this.icon,
    required this.label,
    required this.count,
    required this.active,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final fg = active ? AuraColors.badgeCyan : AuraColors.skip;
    return AuraCard(
      onTap: active ? () {} : null,
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      gradient: active
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AuraColors.gems.withValues(alpha: 0.20),
                AuraColors.gems.withValues(alpha: 0.06),
              ],
            )
          : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? Colors.white : AuraColors.skip,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: fg.withValues(alpha: 0.45)),
            ),
            child: Text(
              '×$count',
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
