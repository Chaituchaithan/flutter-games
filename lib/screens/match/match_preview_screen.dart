import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../widgets/aura.dart';

/// Match preview — VS card + stake summary + "Create game". Standalone screen.
/// Create game → Routes.matchmaking (VS → Chess board → result). See docs/DESIGN_SPEC.md §12.
class MatchPreviewScreen extends StatelessWidget {
  const MatchPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Match preview'),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(
            'Online · 2P · Tokens',
            style: AuraText.body.copyWith(color: AuraColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          AuraCard(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const LetterAvatar(
                      letter: 'NR',
                      color: AuraColors.brandPurple,
                      size: 56,
                      glow: true,
                    ),
                    const SizedBox(width: 22),
                    Text(
                      'VS',
                      style: TextStyle(
                        color: AuraColors.textSecondary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(width: 22),
                    _mysteryAvatar(),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Matching you with 2 players online',
                  style: AuraText.cardSub,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AuraCard(
            child: Column(
              children: [
                _infoRow('Entry stake', '200'),
                _divider(),
                _infoRow('Total prize pot', '400', valueColor: AuraColors.amber),
                _divider(),
                _infoRow('Format', 'Winner takes all'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          GradientButton(
            label: 'Create game',
            // → matchmaking (VS) → Chess board → result, same as the main flow.
            onPressed: () =>
                Navigator.pushReplacementNamed(context, Routes.matchmaking),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _mysteryAvatar() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 2,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Center(
        child: Text(
          '?',
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: AuraColors.textSecondary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Divider(color: AuraColors.cardBorder, height: 1),
      );

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AuraText.body.copyWith(color: AuraColors.textSecondary)),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: valueColor ?? AuraColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
