import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design tokens for the Aura UI.
///
/// Values come from the **Aura Components** handoff sheet (the authoritative
/// source) — see docs/DESIGN_SPEC.md. The palette is a glassmorphic dark
/// theme built on a violet→pink→orange brand gradient.
///
/// Kept as a static token class (not a `ThemeExtension`) so every screen keeps
/// using `AuraColors.x` directly; older token names are preserved as aliases so
/// the whole app compiles through the re-skin.
class AuraColors {
  AuraColors._();

  // ── Backgrounds ──
  /// Deepest background stop (radial outer edge).
  static const Color bgDeep = Color(0xFF070510);

  /// Base background.
  static const Color bgBase = Color(0xFF0C0A16);

  /// Raised surface / sheet base.
  static const Color bgRaised = Color(0xFF1A1330);

  /// App background base (alias of [bgBase], kept for existing screens).
  static const Color background = bgBase;

  // ── Screen radial-gradient stops (default screen backdrop) ──
  static const Color screenTop = Color(0xFF171130);
  static const Color screenMid = Color(0xFF0A0816);
  static const Color screenBottom = Color(0xFF070510);

  // ── Brand gradient stops ──
  static const Color brandPurple = Color(0xFF8B5CF6); // brand.violet
  static const Color brandPink = Color(0xFFEC4899);
  static const Color brandOrange = Color(0xFFFB923C);

  /// Accent used for links, labels, icons, focus rings.
  static const Color accentGlow = Color(0xFFC084FC); // accent.glow

  // ── Soft glows painted behind content ──
  static const Color glowPurple = Color(0x388B5CF6); // ~0.22 violet
  static const Color glowMagenta = Color(0x30EC4899); // ~0.19 pink

  // ── Text ──
  static const Color textPrimary = Color(0xFFF4F1FB);

  /// textPrimary @ 60% (const so it stays usable in `const TextStyle(...)`).
  static const Color textSecondary = Color(0x99F4F1FB);

  /// textPrimary @ 40%.
  static const Color textMuted = Color(0x66F4F1FB);

  /// Muted/skip label (alias of [textMuted]).
  static const Color skip = textMuted;

  // ── Glass surfaces ──
  /// Hairline stroke on glass surfaces (white @ ~20%).
  static const Color glassStroke = Color(0x33FFFFFF);

  /// Legacy solid card color (kept for any not-yet-reskinned surfaces).
  static const Color card = bgRaised;
  static const Color cardAlt = Color(0xFF1A1726);
  static const Color cardBorder = glassStroke;
  static const Color chipDark = Color(0xFF201C2B);
  static const Color pagerInactive = Color(0xFF352F47);
  static const Color field = Color(0x0FFFFFFF); // white @ ~0.06 (glass input fill)

  // ── Currencies & accents ──
  /// Token/gem cyan (currency.token gradient: [gems] → [gemsDeep]).
  static const Color gems = Color(0xFF22D3EE);
  static const Color gemsDeep = Color(0xFF3B82F6);

  /// Gold (currency.gold gradient: [goldLight] → [gold]).
  static const Color gold = Color(0xFFF59E0B);
  static const Color goldLight = Color(0xFFFDE68A);

  static const Color green = Color(0xFF34D399); // state.success
  static const Color amber = Color(0xFFFBBF24); // state.warning
  static const Color danger = Color(0xFFF43F5E); // state.danger
  static const Color dangerText = Color(0xFFFB7185);

  static const Color badgeCyan = Color(0xFF67E8F9);
  static const Color storeBlueA = Color(0xFF3B82F6);
  static const Color storeBlueB = Color(0xFF38BDF8);

  // ── Avatar accent colours ──
  static const Color avatarBlue = Color(0xFF22D3EE);
  static const Color avatarOrange = Color(0xFFFB923C);
  static const Color avatarGreen = Color(0xFF34D399);
  static const Color avatarPurple = Color(0xFFA78BFA);
  static const Color avatarPink = Color(0xFFEC4899);
}

class AuraGradients {
  AuraGradients._();

  /// Primary brand gradient — 135°, violet → pink (52%) → orange.
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AuraColors.brandPurple, AuraColors.brandPink, AuraColors.brandOrange],
    stops: [0.0, 0.52, 1.0],
  );

  /// Deeper CTA variant used on the featured/hero surfaces.
  static const LinearGradient brandDeep = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFFDB2777), Color(0xFFF97316)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Purple → pink used for the "You"/orb avatars.
  static const LinearGradient orb = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AuraColors.brandPurple, AuraColors.brandPink],
  );

  /// Frosted-glass surface fill (160°, white 10% → 4%).
  static const LinearGradient glass = LinearGradient(
    begin: Alignment(-0.6, -1),
    end: Alignment(0.6, 1),
    colors: [Color(0x1AFFFFFF), Color(0x0AFFFFFF)],
  );

  /// Token/gem currency gradient.
  static const LinearGradient token = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AuraColors.gems, AuraColors.gemsDeep],
  );

  /// Gold currency gradient.
  static const LinearGradient goldCoin = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AuraColors.goldLight, AuraColors.gold],
  );

  /// Default screen radial backdrop (120% 70% at 50% 0%).
  static const RadialGradient screen = RadialGradient(
    center: Alignment(0, -1),
    radius: 1.2,
    colors: [AuraColors.screenTop, AuraColors.screenMid, AuraColors.screenBottom],
    stops: [0.0, 0.58, 1.0],
  );
}

/// Radii scale from the handoff: 10 / 14 / 16 / 20 / 28. Spacing grid is 4px.
class AuraRadii {
  AuraRadii._();
  static const double xs = 10;
  static const double sm = 14;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
}

/// Frosted-glass surface recipe shared by cards, sheets and controls.
class AuraGlass {
  AuraGlass._();

  /// Standard glass surface. Pass [accentGradient] for the tinted accent variant
  /// (e.g. hero cards) and it will replace the neutral white gradient; [border]
  /// overrides the default hairline stroke.
  static BoxDecoration decoration({
    double radius = AuraRadii.lg,
    Gradient? accentGradient,
    Color? border,
    bool shadow = true,
  }) {
    final gradient = accentGradient ?? AuraGradients.glass;
    return BoxDecoration(
      // With a drop shadow, the fill is made opaque (the glass tint blended
      // onto the app's near-black base): a Flutter BoxShadow is painted UNDER
      // the box and showed through a translucent fill as a lighter inner panel
      // (CSS box-shadow never draws beneath its element). Visually identical
      // on the dark backgrounds the cards sit on.
      gradient: shadow ? _opaque(gradient) : gradient,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border ?? AuraColors.glassStroke),
      boxShadow: [
        // Inset-style top highlight is faked with a hairline border above; this
        // is the drop shadow (0 12px 28px -14px rgba(0,0,0,0.7)).
        if (shadow)
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 28,
            spreadRadius: -14,
            offset: const Offset(0, 12),
          ),
      ],
    );
  }

  /// Base the glass is composited onto (≈ the screen background).
  static const Color _base = Color(0xFF0D0A18);

  static Gradient _opaque(Gradient g) {
    if (g is! LinearGradient) return g;
    return LinearGradient(
      begin: g.begin,
      end: g.end,
      stops: g.stops,
      colors: [for (final c in g.colors) Color.alphaBlend(c, _base)],
    );
  }
}

/// Typography. Display face defaults to **Chakra Petch** (swappable via
/// [displayFamily]); body is **Manrope**. Loaded at runtime via `google_fonts`.
class AuraText {
  AuraText._();

  /// The single hook for the display face. Swap to e.g.
  /// `GoogleFonts.spaceGrotesk().fontFamily` to change every heading/number/button.
  static final String? displayFamily = GoogleFonts.spaceGrotesk().fontFamily;

  /// Body face.
  static final String? bodyFamily = GoogleFonts.manrope().fontFamily;

  // ── Type scale (component sheet) ──
  static TextStyle get display => TextStyle(
        fontFamily: displayFamily,
        color: AuraColors.textPrimary,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        height: 1.05,
      );

  /// Large screen headline (auth "Welcome back", etc.).
  static TextStyle get headline => TextStyle(
        fontFamily: displayFamily,
        color: AuraColors.textPrimary,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        height: 1.05,
      );

  /// Sub-page screen title (h2, 20/700).
  static TextStyle get title => TextStyle(
        fontFamily: displayFamily,
        color: AuraColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      );

  /// App-bar centred title.
  static TextStyle get appBarTitle => title;

  /// Tabular numerals (scores, balances).
  static TextStyle get numeric => TextStyle(
        fontFamily: displayFamily,
        color: AuraColors.textPrimary,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Uppercase grey group label (12/600 +0.8).
  static TextStyle get section => TextStyle(
        fontFamily: displayFamily,
        color: AuraColors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      );

  static TextStyle get body => TextStyle(
        fontFamily: bodyFamily,
        color: AuraColors.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
      );

  /// Secondary body (muted).
  static TextStyle get body2 => TextStyle(
        fontFamily: bodyFamily,
        color: AuraColors.textSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
      );

  static TextStyle get caption => TextStyle(
        fontFamily: bodyFamily,
        color: AuraColors.textPrimary.withValues(alpha: 0.5),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      );

  /// Primary-button label (Space/display face, 17 w600 on CTAs).
  static TextStyle get button => TextStyle(
        fontFamily: displayFamily,
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      );

  static TextStyle get cardTitle => TextStyle(
        fontFamily: displayFamily,
        color: AuraColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      );

  static TextStyle get cardSub => TextStyle(
        fontFamily: bodyFamily,
        color: AuraColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      );
}
