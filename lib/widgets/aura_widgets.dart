import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The dark screen backdrop: a radial base gradient (violet → deep) plus one
/// soft coloured glow blob, matching the redesign. The glow colour/position can
/// be tuned per screen; the defaults suit most screens.
class AuraBackground extends StatelessWidget {
  const AuraBackground({
    super.key,
    required this.child,
    this.glowColor = AuraColors.brandPurple,
    this.glowAlignment = const Alignment(0, -1.15),
    this.glowSize = 380,
    this.showGlow = true,
  });

  final Widget child;

  /// Colour of the single blurred glow blob.
  final Color glowColor;

  /// Where the glow sits (in the screen's alignment space).
  final Alignment glowAlignment;

  /// Diameter of the glow blob.
  final double glowSize;

  /// Set false for screens that want only the base gradient.
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AuraGradients.screen),
      child: Stack(
        children: [
          if (showGlow)
            Align(
              alignment: glowAlignment,
              child: _Glow(color: glowColor, size: glowSize),
            ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            // Softer, more diffuse than before so it reads as a subtle backdrop
            // glow (matching the mockup's blurred blobs) rather than a bright blob.
            colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.0)],
            stops: const [0.0, 0.70],
          ),
        ),
      ),
    );
  }
}

/// Full-width gradient pill button with a soft glow, used for
/// "Continue" / "Get Started".
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;

  /// When true, shows a spinner instead of the label and ignores taps.
  final bool loading;

  /// When false, the button is dimmed and non-interactive (e.g. "Come back
  /// tomorrow" after a daily reward has been claimed).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final inert = loading || !enabled;
    // Disabled state is a FLAT glass button (mockup: white@7% fill, white@50%
    // text, no gradient/shadow) — not a dimmed gradient.
    return Opacity(
      opacity: loading ? 0.75 : 1,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: enabled ? AuraGradients.brand : null,
          color: enabled ? null : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(17),
          // Hairline top-edge highlight (inset 0 1px 0 rgba(255,255,255,.35)).
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AuraColors.brandPink.withValues(alpha: 0.5),
                    blurRadius: 28,
                    spreadRadius: -12,
                    offset: const Offset(0, 14),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: inert ? null : onPressed,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      label,
                      style: enabled
                          ? AuraText.button
                          : AuraText.button.copyWith(color: Colors.white.withValues(alpha: 0.5)),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three-dot pager where the active dot is an elongated gradient pill.
class AuraPageIndicator extends StatelessWidget {
  const AuraPageIndicator({
    super.key,
    required this.count,
    required this.index,
  });

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 26 : 8,
          height: 8,
          decoration: BoxDecoration(
            gradient: active ? AuraGradients.brand : null,
            color: active ? null : AuraColors.pagerInactive,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

/// Avatar with a conic XP ring, gradient initials disc, and an optional level
/// badge — the header/profile avatar from the redesign.
class AuraAvatar extends StatelessWidget {
  const AuraAvatar({
    super.key,
    required this.initials,
    this.size = 50,
    this.level,
    this.ringFraction = 0.65,
    this.gradient = AuraGradients.orb,
  });

  final String initials;
  final double size;
  final int? level;

  /// Portion of the ring filled with the accent colour (XP progress).
  final double ringFraction;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // XP ring.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  transform: const GradientRotation(-math.pi / 2),
                  colors: const [
                    AuraColors.accentGlow,
                    AuraColors.accentGlow,
                    Color(0x1FFFFFFF),
                    Color(0x1FFFFFFF),
                  ],
                  stops: [0, ringFraction, ringFraction, 1],
                ),
              ),
            ),
          ),
          // Gradient disc with initials (inset from the ring).
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
                child: Center(
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontFamily: AuraText.displayFamily,
                      color: Colors.white,
                      fontSize: size * 0.32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (level != null)
            Positioned(
              bottom: -4,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    gradient: AuraGradients.goldCoin,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: AuraColors.bgBase, width: 1.5),
                  ),
                  child: Text(
                    '$level',
                    style: TextStyle(
                      fontFamily: AuraText.displayFamily,
                      color: const Color(0xFF1A1206),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A circular avatar showing a single letter over a coloured gradient,
/// with an optional soft glow ring.
class LetterAvatar extends StatelessWidget {
  const LetterAvatar({
    super.key,
    required this.letter,
    required this.color,
    this.size = 44,
    this.glow = false,
  });

  final String letter;
  final Color color;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.18)!,
            Color.lerp(color, Colors.black, 0.12)!,
          ],
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.55),
                  blurRadius: 20,
                  spreadRadius: -2,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            fontFamily: AuraText.displayFamily,
            color: Colors.white,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
