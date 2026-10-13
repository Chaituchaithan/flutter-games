import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../app/game_area.dart';
import '../../app/routes.dart';
import '../../configs/games/games.dart';
import '../../services/session.dart';
import '../../widgets/aura.dart';

/// Match result — Victory / Defeat / Draw (mockup `MATCH RESULT`).
///
/// Full-screen, centred: a 116px gradient icon tile with a glow behind it, the
/// 42px title, a one-line subtitle, the You · score · opponent row, a reward
/// chip, then Play Again / Back to Home. Defaults reproduce the mockup's demo
/// values; games pass real data (scores = captures, opponent, reward, and what
/// Play Again should do).
enum MatchOutcome { victory, defeat, draw }

class MatchResultScreen extends StatelessWidget {
  const MatchResultScreen({
    super.key,
    this.outcome = MatchOutcome.defeat,
    this.youScore,
    this.oppScore,
    this.youInitials,
    this.oppName = 'Rival',
    this.oppInitials,
    this.reward,
    this.subtitle,
    this.playAgain,
  });

  final MatchOutcome outcome;
  final int? youScore;
  final int? oppScore;
  /// Defaults to the signed-in player's initials.
  final String? youInitials;
  final String oppName;
  final String? oppInitials;

  /// Reward chip text, e.g. "+190 Tokens   ·   +50 XP". Defaults per outcome.
  final String? reward;

  /// Overrides the outcome's default subtitle (e.g. "You ran out of time.").
  final String? subtitle;

  /// Builds the next game for Play Again (it replaces this result screen).
  /// A builder rather than a callback: the finished game's screen is already
  /// gone, so only this screen's own context can navigate. Defaults to the
  /// Quick Play (chess) setup.
  final WidgetBuilder? playAgain;

  @override
  Widget build(BuildContext context) {
    // Mockup resMap: title, subtitle, gradient stops, glow, demo score, reward.
    final spec = switch (outcome) {
      MatchOutcome.victory => (
          c1: const Color(0xFF34D399),
          c2: const Color(0xFFFBBF24),
          icon: Icons.emoji_events_outlined,
          title: context.l10n.resultVictory,
          sub: context.l10n.resultVictorySub,
          you: 3,
          opp: 2,
          reward: '+250 Tokens   ·   +50 XP',
        ),
      MatchOutcome.defeat => (
          c1: const Color(0xFFF43F5E),
          c2: const Color(0xFFFB7185),
          icon: Icons.highlight_off_rounded,
          title: context.l10n.resultDefeat,
          sub: context.l10n.resultDefeatSub,
          you: 1,
          opp: 3,
          reward: '+20 XP',
        ),
      MatchOutcome.draw => (
          c1: const Color(0xFFFBBF24),
          c2: const Color(0xFFF59E0B),
          icon: Icons.compare_arrows_rounded,
          title: context.l10n.resultDraw,
          sub: context.l10n.resultDrawSub,
          you: 2,
          opp: 2,
          reward: '+60 Tokens   ·   +30 XP',
        ),
    };
    final opponentInitials = oppInitials ?? _initials(oppName);

    return Scaffold(
      backgroundColor: const Color(0xFF070510),
      body: Container(
        // Mockup background: radial #14102a → #0a0816 → #070510 from the top.
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.92),
            radius: 1.25,
            colors: [Color(0xFF14102A), Color(0xFF0A0816), Color(0xFF070510)],
            stops: [0, 0.54, 1],
          ),
        ),
        child: Stack(
          children: [
            // Outcome-coloured glow behind the icon.
            Positioned(
              top: 130,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 360,
                  height: 360,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [spec.c1.withValues(alpha: 0.42), spec.c1.withValues(alpha: 0)],
                      stops: const [0, 0.62],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: _ResultIcon(color1: spec.c1, color2: spec.c2, icon: spec.icon)),
                      const SizedBox(height: 24),
                      Text(
                        spec.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AuraText.displayFamily,
                          fontWeight: FontWeight.w700,
                          fontSize: 42,
                          letterSpacing: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle ?? spec.sub,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.6)),
                      ),
                      const SizedBox(height: 28),
                      _ScoreRow(
                        youInitials: youInitials ?? ProviderScope.containerOf(context).read(currentUserProvider).initials,
                        you: youScore ?? spec.you,
                        opp: oppScore ?? spec.opp,
                        oppName: oppName,
                        oppInitials: opponentInitials,
                      ),
                      const SizedBox(height: 26),
                      Center(child: _RewardChip(text: reward ?? spec.reward)),
                      const SizedBox(height: 30),
                      GradientButton(
                        label: context.l10n.playAgain,
                        onPressed: () {
                          if (playAgain != null) {
                            Navigator.pushReplacement(context, MaterialPageRoute(builder: playAgain!));
                            return;
                          }
                          // No builder: the active game's Quick Play setup.
                          final game = ProviderScope.containerOf(context).read(activeGameProvider);
                          final route = GameArea.practiceRoute(game);
                          if (route != null) {
                            Navigator.pushReplacementNamed(context, route);
                          } else {
                            Navigator.popUntil(context, ModalRoute.withName(Routes.home));
                          }
                        },
                      ),
                      const SizedBox(height: 11),
                      SecondaryButton(
                        label: context.l10n.backToHome,
                        onPressed: () => Navigator.popUntil(context, ModalRoute.withName(Routes.home)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, parts.first.length.clamp(1, 2)).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

/// You (purple→pink) · 38px score : score · opponent (red gradient + name).
class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.youInitials,
    required this.you,
    required this.opp,
    required this.oppName,
    required this.oppInitials,
  });

  final String youInitials;
  final int you;
  final int opp;
  final String oppName;
  final String oppInitials;

  @override
  Widget build(BuildContext context) {
    final score = TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 38);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _avatar(youInitials, const [AuraColors.brandPurple, AuraColors.brandPink], context.l10n.you),
          const SizedBox(width: 16),
          Text('$you', style: score.copyWith(color: Colors.white)),
          const SizedBox(width: 10),
          Text(':', style: score.copyWith(fontSize: 22, color: Colors.white.withValues(alpha: 0.3))),
          const SizedBox(width: 10),
          Text('$opp', style: score.copyWith(color: Colors.white.withValues(alpha: 0.7))),
          const SizedBox(width: 16),
          _avatar(oppInitials, const [Color(0xFFF43F5E), Color(0xFFFB7185)], oppName),
        ],
      ),
    );
  }

  Widget _avatar(String initials, List<Color> colors, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 2),
          ),
          child: Text(
            initials,
            style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 17, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 90),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
          ),
        ),
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
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color1, color2]),
        borderRadius: BorderRadius.circular(34),
        boxShadow: [BoxShadow(color: color1.withValues(alpha: 0.45), blurRadius: 50, spreadRadius: -8)],
      ),
      child: Icon(icon, color: Colors.white, size: 56),
    );
  }
}

/// Glass chip with a gold star + reward text (mockup: 10×20 padding, r14).
class _RewardChip extends StatelessWidget {
  const _RewardChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.04)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 18),
          const SizedBox(width: 9),
          // Shrinks rather than overflowing on narrow screens / long rewards.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                maxLines: 1,
                style: TextStyle(fontFamily: AuraText.displayFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
