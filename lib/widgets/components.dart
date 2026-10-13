import 'package:flutter/material.dart';

import '../theme.dart';
import 'aura_widgets.dart';

/// Scaffold + dark background + glows + SafeArea. Use as the root of a screen.
/// Pass [scroll] true to make the body scrollable.
class AuraScaffold extends StatelessWidget {
  const AuraScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNav,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.scroll = false,
    this.glowColor = AuraColors.brandPurple,
    this.glowAlignment = const Alignment(0, -1.15),
    this.showGlow = true,
  });

  final Widget body;
  final Widget? appBar;
  final Widget? bottomNav;
  final EdgeInsets padding;
  final bool scroll;

  /// Forwarded to [AuraBackground] so screens can place their glow.
  final Color glowColor;
  final Alignment glowAlignment;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuraColors.bgBase,
      body: AuraBackground(
        glowColor: glowColor,
        glowAlignment: glowAlignment,
        showGlow: showGlow,
        child: SafeArea(
          bottom: bottomNav == null,
          child: Column(
            children: [
              ?appBar,
              Expanded(
                child: scroll
                    ? SingleChildScrollView(padding: padding, child: body)
                    : Padding(padding: padding, child: body),
              ),
              ?bottomNav,
            ],
          ),
        ),
      ),
    );
  }
}

/// Back chevron + centered title + optional trailing widget.
class AuraAppBar extends StatelessWidget {
  const AuraAppBar({super.key, this.title, this.showBack = true, this.onBack, this.trailing});

  final String? title;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // Mockup screen header: 42px glass back button, then the title LEFT-
    // aligned beside it (22px display, bold), optional action on the right.
    // Aligned to the 20px content gutter.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            if (showBack)
              GlassIconButton(
                icon: Icons.chevron_left,
                iconSize: 24,
                onTap: onBack ?? () => Navigator.of(context).maybePop(),
              ),
            if (showBack && title != null) const SizedBox(width: 12),
            if (title != null)
              Expanded(
                child: Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    color: Colors.white,
                  ),
                ),
              )
            else
              const Spacer(),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Rounded-square glass icon button (42×42, radius 14) — the back chevron and
/// header actions throughout the redesign. Not a circle.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 42,
    this.iconSize = 20,
    this.gradient,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  /// Optional accent fill (e.g. brand gradient for a "+"/primary action).
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: AuraGlass.decoration(
        radius: AuraRadii.sm,
        accentGradient: gradient,
        border: gradient != null ? Colors.white.withValues(alpha: 0.3) : null,
        shadow: false,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AuraRadii.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AuraRadii.sm),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: AuraColors.textPrimary, size: iconSize),
          ),
        ),
      ),
    );
  }
}

/// Circular icon button usable as an app-bar trailing action (e.g. settings gear).
/// Retained name; now renders as the rounded-square glass [GlassIconButton].
class CircleActionButton extends StatelessWidget {
  const CircleActionButton({super.key, required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GlassIconButton(icon: icon, onTap: onTap);
}

enum Currency { gems, gold }

/// The "10,000 +" / "3,000 +" pills seen in headers.
class CurrencyPill extends StatelessWidget {
  const CurrencyPill({super.key, required this.kind, required this.amount, this.showPlus = true, this.matchWidthOf = const []});

  final Currency kind;
  final String amount;
  final bool showPlus;

  /// Other amounts to size for: the pill is as wide as the longest of these
  /// and [amount], so a Tokens/Gold pair renders at the same width.
  final List<String> matchWidthOf;

  @override
  Widget build(BuildContext context) {
    final isGems = kind == Currency.gems;
    final color = isGems ? AuraColors.gems : AuraColors.gold;
    return Container(
      padding: EdgeInsets.fromLTRB(7, 4, showPlus ? 4 : 11, 4),
      decoration: BoxDecoration(
        // Tinted gradient (colour @ 0.24 → 0.06) with a coloured stroke.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.24), color.withValues(alpha: 0.06)],
        ),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CurrencyGlyph(kind: kind, size: 15),
          const SizedBox(width: 6),
          Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Invisible copies reserve the widest amount's width.
              for (final other in matchWidthOf)
                Visibility(
                  visible: false,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Text(other, style: _amountStyle),
                ),
              Text(amount, style: _amountStyle),
            ],
          ),
          if (showPlus) ...[
            const SizedBox(width: 6),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.25), shape: BoxShape.circle),
              child: const Icon(Icons.add, size: 13, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

final _amountStyle = TextStyle(
  fontFamily: AuraText.displayFamily,
  color: Colors.white,
  fontSize: 13.5,
  fontWeight: FontWeight.w700,
);

/// A drawn currency glyph: the Aura-ring token (brand gradient ring with a
/// glowing pink core — matches the app logo) or a layered gold coin.
class CurrencyGlyph extends StatelessWidget {
  const CurrencyGlyph({super.key, required this.kind, this.size = 16});
  final Currency kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CurrencyPainter(kind)),
    );
  }
}

class _CurrencyPainter extends CustomPainter {
  _CurrencyPainter(this.kind);
  final Currency kind;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (kind == Currency.gems) {
      // Token: the Aura ring — a violet → pink → orange sweep ring, a dark
      // core, and a glowing pink dot (design #10, as the app logo).
      final c = rect.center;
      final r = size.width / 2;
      canvas.drawCircle(
        c,
        r * 0.86,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.24
          ..shader = const SweepGradient(
            colors: [AuraColors.brandPurple, AuraColors.brandPink, AuraColors.brandOrange, AuraColors.brandPurple],
          ).createShader(rect),
      );
      canvas.drawCircle(c, r * 0.62, Paint()..color = const Color(0xFF0A0812));
      canvas.drawCircle(
        c,
        r * 0.3,
        Paint()
          ..color = AuraColors.brandPink.withValues(alpha: 0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12),
      );
      canvas.drawCircle(c, r * 0.2, Paint()..color = AuraColors.brandPink);
    } else {
      final c = rect.center;
      canvas.drawCircle(c, size.width * 0.5, Paint()..color = const Color(0xFFB45309));
      canvas.drawCircle(c, size.width * 0.42, Paint()..shader = AuraGradients.goldCoin.createShader(rect));
    }
  }

  @override
  bool shouldRepaint(covariant _CurrencyPainter old) => old.kind != kind;
}

/// Glass rounded text input with a leading icon and optional trailing widget.
/// Shows an accent-glow focus ring when the field is focused.
class AuraTextField extends StatefulWidget {
  const AuraTextField({
    super.key,
    required this.hint,
    this.icon,
    this.obscure = false,
    this.trailing,
    this.keyboardType,
    this.controller,
    this.maxLines = 1,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
  });

  final String hint;
  final IconData? icon;
  final bool obscure;
  final Widget? trailing;
  final TextInputType? keyboardType;
  final TextEditingController? controller;
  final int maxLines;

  /// Validation message shown below the field; also tints the border red.
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  State<AuraTextField> createState() => _AuraTextFieldState();
}

class _AuraTextFieldState extends State<AuraTextField> {
  final FocusNode _node = FocusNode();

  @override
  void initState() {
    super.initState();
    _node.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _node.hasFocus;
    final hasError = widget.errorText != null;
    // Error state takes priority over the focus ring.
    final borderColor = hasError
        ? AuraColors.danger
        : (focused ? AuraColors.accentGlow : Colors.white.withValues(alpha: 0.22));
    final field = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: focused ? AuraColors.accentGlow.withValues(alpha: 0.08) : AuraColors.field,
        borderRadius: BorderRadius.circular(AuraRadii.md),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: hasError
            ? [BoxShadow(color: AuraColors.danger.withValues(alpha: 0.18), spreadRadius: 3, blurRadius: 0)]
            : focused
            ? [BoxShadow(color: AuraColors.accentGlow.withValues(alpha: 0.18), spreadRadius: 3, blurRadius: 0)]
            : const [
                BoxShadow(
                  color: Color(0x59000000), // inset-ish depth (0.35 black)
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: widget.maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            Padding(
              padding: EdgeInsets.only(top: widget.maxLines > 1 ? 18 : 0),
              child: Icon(widget.icon, size: 18, color: AuraColors.textSecondary),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: TextField(
              focusNode: _node,
              controller: widget.controller,
              obscureText: widget.obscure,
              keyboardType: widget.maxLines > 1 ? TextInputType.multiline : widget.keyboardType,
              textInputAction: widget.textInputAction,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              maxLines: widget.maxLines,
              minLines: widget.maxLines > 1 ? 3 : 1,
              style: TextStyle(fontFamily: AuraText.bodyFamily, color: AuraColors.textPrimary, fontSize: 15.5),
              cursorColor: AuraColors.accentGlow,
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: TextStyle(color: AuraColors.textPrimary.withValues(alpha: 0.34), fontSize: 15.5),
              ),
            ),
          ),
          ?widget.trailing,
        ],
      ),
    );
    // Always the same Column shape, error or not: switching between a bare
    // field and a Column re-created the TextField when an error appeared or
    // cleared, which dropped focus and closed the keyboard mid-typing.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 14, color: AuraColors.dangerText),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.errorText!,
                    style: const TextStyle(color: AuraColors.dangerText, fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// While [busy], the screen ignores every tap and the back gesture/button,
/// so a second action can't start (or navigate away) while a request is in
/// flight — e.g. tapping "Create account" during guest sign-in.
class BusyGuard extends StatelessWidget {
  const BusyGuard({super.key, required this.busy, required this.child});
  final bool busy;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AbsorbPointer(absorbing: busy, child: child),
  );
}

/// Small spinner shown inside a button while its action runs.
Widget _buttonSpinner(Color color) => SizedBox(
  width: 20,
  height: 20,
  child: CircularProgressIndicator(strokeWidth: 2.2, valueColor: AlwaysStoppedAnimation(color)),
);

/// Dark outline pill button (secondary action).
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onPressed, this.loading = false});
  final String label;
  final VoidCallback onPressed;

  /// Shows a spinner in place of the label.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AuraRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AuraRadii.md),
          onTap: onPressed,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AuraRadii.md),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24), width: 1.5),
            ),
            child: loading
                ? _buttonSpinner(AuraColors.textPrimary)
                : Text(
                    label,
                    style: TextStyle(
                      fontFamily: AuraText.bodyFamily,
                      color: AuraColors.textPrimary.withValues(alpha: 0.85),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// White pill button with an optional leading icon (e.g. "Continue with Apple").
class LightButton extends StatelessWidget {
  const LightButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading,
    this.dark = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback onPressed;
  final Widget? leading;

  /// Shows a spinner in place of the label.
  final bool loading;

  /// When true renders a dark surface (e.g. "Continue with Google").
  final bool dark;

  @override
  Widget build(BuildContext context) {
    // White (Apple) vs frosted-glass (Google) surface.
    final fg = dark ? AuraColors.textPrimary : Colors.black;
    return SizedBox(
      height: 52,
      child: Material(
        color: dark ? Colors.transparent : Colors.white,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onPressed,
          child: Container(
            alignment: Alignment.center,
            decoration: dark
                ? BoxDecoration(
                    gradient: AuraGradients.glass,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
                  )
                : BoxDecoration(borderRadius: BorderRadius.circular(15)),
            child: loading
                ? _buttonSpinner(fg)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (leading != null) ...[leading!, const SizedBox(width: 10)],
                      // Shrinks instead of overflowing on narrow phones.
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AuraText.bodyFamily,
                            color: fg,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Small uppercase grey section label.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.padding = EdgeInsets.zero});
  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Text(text.toUpperCase(), style: AuraText.section),
  );
}

/// Content section header: a 4×16 gradient bar + display-face label (the
/// "Earn rewards" / "Game stats" style). Distinct from [SectionHeader], which is
/// the uppercase grey group label used for settings-style groups.
class SectionBar extends StatelessWidget {
  const SectionBar(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AuraColors.brandPurple, AuraColors.brandPink],
            ),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        // Flexible so a long title + trailing can never overflow the row.
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: AuraColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// Rounded badge/pill (SOON, POPULAR, MEGA, +10% …).
class AuraBadge extends StatelessWidget {
  const AuraBadge(this.text, {super.key, this.color = AuraColors.badgeCyan, this.filled = true});
  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
      ),
    );
  }
}

/// Profile stat block: big value + small label.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label, this.valueColor});
  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: AuraGlass.decoration(radius: 18),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: valueColor ?? AuraColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AuraColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

/// Gradient iOS-style switch.
class AuraToggle extends StatelessWidget {
  const AuraToggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // Track is a plain Container (its decoration flips instantly and cleanly —
    // an AnimatedContainer can't tween a gradient back to null, which would
    // leave the "on" gradient stuck when toggled off). The knob slide is
    // animated separately via AnimatedAlign.
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 52,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          gradient: value ? AuraGradients.brand : null,
          color: value ? null : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: value ? null : Border.all(color: Colors.white.withValues(alpha: 0.2)),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: AuraColors.brandPink.withValues(alpha: 0.5),
                    blurRadius: 14,
                    spreadRadius: -6,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: value ? Colors.white : Colors.white.withValues(alpha: 0.75),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented pill tab control (Store categories, etc.).
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({super.key, required this.labels, required this.index, required this.onChanged});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AuraRadii.sm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = i == index;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: active ? AuraGradients.brand : null,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: AuraColors.brandPink.withValues(alpha: 0.5),
                            blurRadius: 18,
                            spreadRadius: -8,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: active ? Colors.white : AuraColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// A generic dark rounded card container.
class AuraCard extends StatelessWidget {
  const AuraCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.gradient,
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: AuraGlass.decoration(
        radius: radius,
        accentGradient: gradient,
        border: gradient != null ? AuraColors.accentGlow.withValues(alpha: 0.45) : null,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: card),
    );
  }
}

/// Floating bottom bar (mockup `BOTTOM NAV`): inset 16px, 64px tall, r24,
/// dark violet glass. Each tab = a 23px outline icon (stroke 1.9) + label
/// (10.5px); the active tab is white with a 5px pink dot under it, the others
/// 42% white. Tabs: Home · Wheel · Store · Profile.
class AuraBottomNav extends StatelessWidget {
  const AuraBottomNav({super.key, required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _items = [
    (_NavIcon.home, 'Home'),
    (_NavIcon.wheel, 'Wheel'),
    (_NavIcon.store, 'Store'),
    (_NavIcon.profile, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xEB221A38), Color(0xF00E0B1A)], // rgba(34,26,56,.92) → rgba(14,11,26,.94)
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 40,
              spreadRadius: -10,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Row(
          children: List.generate(_items.length, (i) {
            final active = i == index;
            final (icon, label) = _items[i];
            final color = active ? Colors.white : Colors.white.withValues(alpha: 0.42);
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CustomPaint(size: const Size(23, 23), painter: _NavIconPainter(icon, color)),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: AuraText.bodyFamily,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: active ? 1 : 0,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(color: AuraColors.brandPink, shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

enum _NavIcon { home, wheel, store, profile }

/// The mockup's nav icons, drawn from their SVG paths (24×24 viewBox,
/// round caps/joins, stroke 1.9).
class _NavIconPainter extends CustomPainter {
  _NavIconPainter(this.icon, this.color);
  final _NavIcon icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    switch (icon) {
      case _NavIcon.home: // M3 11.5L12 4l9 7.5M5.5 9.8V20h13V9.8
        canvas.drawPath(
          Path()
            ..moveTo(3, 11.5)
            ..lineTo(12, 4)
            ..lineTo(21, 11.5)
            ..moveTo(5.5, 9.8)
            ..lineTo(5.5, 20)
            ..lineTo(18.5, 20)
            ..lineTo(18.5, 9.8),
          p,
        );
      case _NavIcon.wheel: // two concentric circles r9 / r3.5
        canvas.drawCircle(const Offset(12, 12), 9, p);
        canvas.drawCircle(const Offset(12, 12), 3.5, p);
      case _NavIcon.store: // M6 8h12l-1.2 12H7.2z  M9 8V6.5a3 3 0 016 0V8
        canvas.drawPath(
          Path()
            ..moveTo(6, 8)
            ..lineTo(18, 8)
            ..lineTo(16.8, 20)
            ..lineTo(7.2, 20)
            ..close()
            ..moveTo(9, 8)
            ..lineTo(9, 6.5)
            ..arcToPoint(const Offset(15, 6.5), radius: const Radius.circular(3))
            ..lineTo(15, 8),
          p,
        );
      case _NavIcon.profile: // head r4 at (12,7.5) + shoulders curve
        canvas.drawCircle(const Offset(12, 7.5), 4, p);
        canvas.drawPath(
          Path()
            ..moveTo(4.5, 20)
            ..cubicTo(4.5, 16, 8, 14, 12, 14)
            ..cubicTo(16, 14, 19.5, 16, 19.5, 20),
          p,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _NavIconPainter old) => old.icon != icon || old.color != color;
}
