import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../widgets/aura.dart';

/// Match result — Victory / Defeat / Draw. See docs/DESIGN_SPEC.md (v2 §Results).
enum MatchOutcome { victory, defeat, draw }

class MatchResultScreen extends StatelessWidget {
  const MatchResultScreen({super.key, this.outcome = MatchOutcome.defeat});

  final MatchOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final spec = switch (outcome) {
      MatchOutcome.victory => (
          accent: AuraColors.green,
          accent2: AuraColors.gold,
          icon: Icons.emoji_events,
          title: 'VICTORY',
          sub: 'Flawless run, champion!',
          you: '3',
          rival: '1',
          reward: '+250 Tokens · +50 XP',
        ),
      MatchOutcome.defeat => (
          accent: AuraColors.danger,
          accent2: AuraColors.danger,
          icon: Icons.close_rounded,
          title: 'DEFEAT',
          sub: 'So close — run it back.',
          you: '1',
          rival: '3',
          reward: '+20 XP',
        ),
      MatchOutcome.draw => (
          accent: AuraColors.amber,
          accent2: AuraColors.brandOrange,
          icon: Icons.handshake,
          title: 'DRAW',
          sub: 'Evenly matched — rematch?',
          you: '2',
          rival: '2',
          reward: '+60 XP',
        ),
    };

    return AuraScaffold(
      glowColor: spec.accent,
      glowAlignment: const Alignment(0, -0.4),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: _ResultIcon(color1: spec.accent, color2: spec.accent2, icon: spec.icon)),
              const SizedBox(height: 24),
              Text(spec.title,
                  style: AuraText.headline.copyWith(fontSize: 42, letterSpacing: 2),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(spec.sub,
                  style: AuraText.body.copyWith(color: AuraColors.textSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 32),
              _scoreRow(spec.you, spec.rival),
              const SizedBox(height: 24),
              Center(child: _RewardChip(text: spec.reward)),
              const SizedBox(height: 36),
              GradientButton(
                label: 'Play Again',
                onPressed: () => Navigator.pushReplacementNamed(context, Routes.matchSetup),
              ),
              const SizedBox(height: 14),
              SecondaryButton(
                label: 'Back to Home',
                onPressed: () => Navigator.popUntil(context, ModalRoute.withName(Routes.home)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scoreRow(String you, String rival) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _player(letter: 'NR', color: AuraColors.brandPurple, label: 'You'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                '$you  :  $rival',
                style: TextStyle(
                  fontFamily: AuraText.displayFamily,
                  color: AuraColors.textPrimary,
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          _player(letter: 'RV', color: AuraColors.danger, label: 'Rival'),
        ],
      ),
    );
  }

  Widget _player({required String letter, required Color color, required String label}) {
    return Column(
      children: [
        LetterAvatar(letter: letter, color: color, size: 56),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(color: AuraColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ResultIcon extends StatelessWidget {
  const _ResultIcon({required this.color1, required this.color2, required this.icon});
  final Color color1;
  final Color color2;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color1, color2],
        ),
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(color: color1.withValues(alpha: 0.5), blurRadius: 40, spreadRadius: -8, offset: const Offset(0, 12)),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 56),
    );
  }
}

class _RewardChip extends StatelessWidget {
  const _RewardChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: AuraGlass.decoration(radius: 14, shadow: false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: AuraColors.amber, size: 18),
          const SizedBox(width: 7),
          Text(text,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: AuraColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}
