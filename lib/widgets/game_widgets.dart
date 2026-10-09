import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'aura_overlays.dart';
import 'aura_widgets.dart';
import 'components.dart';

/// Shared gameplay chrome + in-game overlays for every board (Chess, Othello,
/// Scrabble, Ludo, Snakes & Ladders, Trivia). One source of truth for the
/// header, pot pill, player cards, turn clock, action bar, chat sheet, forfeit
/// dialog and paused overlay. See docs/VERIFICATION_AUDIT.md §A (game boards).
///
/// Presentation only — no game logic. Handlers are the integration seam.

// ─────────────────────────── Pot pill ───────────────────────────

/// The "Pot N" pill shown at the right of a game header (mockup: amber value).
class GamePotPill extends StatelessWidget {
  const GamePotPill({super.key, required this.amount, this.currency = Currency.gems});

  final String amount;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AuraColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AuraColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Pot',
            style: TextStyle(color: AuraColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 7),
          Text(
            amount,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: AuraColors.amber,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Header ───────────────────────────

/// Standard game header (mockup): pause (left) · centered title + subtitle · pot (right).
class GameHeader extends StatelessWidget {
  const GameHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.pot,
    this.currency = Currency.gems,
    this.trailing,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final String pot;
  final Currency currency;

  /// Optional right-side widget shown instead of the pot pill (e.g. a timer
  /// chip for games that surface a clock in the header — see [GameTimerChip]).
  final Widget? trailing;

  /// Optional left-side widget (defaults to a pause button).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        leading ?? GlassIconButton(icon: Icons.pause_rounded, onTap: () => showGamePaused(context)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AuraText.displayFamily,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AuraColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        trailing ?? GamePotPill(amount: pot, currency: currency),
      ],
    );
  }
}

/// Mockup-style timer chip for the game header: a glass pill with a clock icon
/// and a MM:SS (or "30s") value. Turns red when [urgent].
class GameTimerChip extends StatelessWidget {
  const GameTimerChip({super.key, required this.text, this.urgent = false});
  final String text;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final color = urgent ? AuraColors.danger : Colors.white;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: (urgent ? AuraColors.danger : Colors.white).withValues(alpha: urgent ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: (urgent ? AuraColors.danger : Colors.white).withValues(alpha: urgent ? 0.5 : 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 15, color: color.withValues(alpha: 0.9)),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Turn clock ───────────────────────────

/// "TURN CLOCK" card with a big countdown value.
class GameTurnClock extends StatelessWidget {
  const GameTurnClock({super.key, this.seconds = '30s'});
  final String seconds;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SectionHeader('TURN CLOCK'),
          const SizedBox(height: 6),
          Text(
            seconds,
            style: TextStyle(
              fontFamily: AuraText.displayFamily,
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Player cards ───────────────────────────

/// Opponent card: circle avatar + name + stat + trailing status. Used by the
/// 2-player boards (Chess / Othello / Scrabble).
class GameOpponentCard extends StatelessWidget {
  const GameOpponentCard({
    super.key,
    required this.name,
    required this.initials,
    required this.stat,
    this.color = AuraColors.avatarBlue,
    this.trailing = 'Waiting',
  });

  final String name;
  final String initials;
  final String stat;
  final Color color;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      child: Row(
        children: [
          LetterAvatar(letter: initials, color: color, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stat,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AuraColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(trailing, style: const TextStyle(color: AuraColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

/// "You" card mirroring the opponent card, with a your-turn hint.
class GameYouCard extends StatelessWidget {
  const GameYouCard({
    super.key,
    required this.stat,
    this.name = 'You',
    this.initials = 'NR',
    this.hint = 'Your move · 30s',
  });

  final String stat;
  final String name;
  final String initials;
  final String hint;

  @override
  Widget build(BuildContext context) {
    // Active-turn highlight (accent border) — it's your move (mockup).
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AuraGlass.decoration(border: AuraColors.accentGlow.withValues(alpha: 0.55)),
      child: Row(
        children: [
          LetterAvatar(letter: initials, color: AuraColors.brandPurple, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stat,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AuraColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AuraColors.brandPink, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact player chip: coloured square avatar + name/stat + status. Used by
/// the 4-player token boards (Ludo / Snakes & Ladders).
class GamePlayerChip extends StatelessWidget {
  const GamePlayerChip({
    super.key,
    required this.name,
    required this.initials,
    required this.stat,
    required this.status,
    required this.color,
    this.highlight = false,
  });

  final String name;
  final String initials;
  final String stat;
  final String status;
  final Color color;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AuraColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: highlight ? AuraColors.brandPink : AuraColors.cardBorder, width: highlight ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stat,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AuraColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status,
            style: TextStyle(
              color: highlight ? AuraColors.brandPink : AuraColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Action bar ───────────────────────────

/// Square danger-tinted forfeit button. Defaults to the shared forfeit dialog.
class GameForfeitButton extends StatelessWidget {
  const GameForfeitButton({super.key, this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 58,
      child: Material(
        color: AuraColors.danger.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap ?? () => confirmGameForfeit(context),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AuraColors.danger.withValues(alpha: 0.5)),
            ),
            child: const Icon(Icons.flag, color: AuraColors.danger),
          ),
        ),
      ),
    );
  }
}

/// The bottom action bar: chat + primary action + forfeit. Chat and forfeit
/// default to the shared chat sheet / forfeit dialog when no handler is given.
class GameActionBar extends StatelessWidget {
  const GameActionBar({super.key, required this.primaryLabel, this.onPrimary, this.onChat, this.onForfeit});

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onChat;
  final VoidCallback? onForfeit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleActionButton(icon: Icons.chat_bubble_outline, onTap: onChat ?? () => showGameChatSheet(context)),
        const SizedBox(width: 12),
        Expanded(
          child: GradientButton(
            label: primaryLabel,
            onPressed:
                onPrimary ??
                () => showAuraToast(context, 'Demo board — moves are not live yet', kind: AuraToastKind.info),
          ),
        ),
        const SizedBox(width: 12),
        GameForfeitButton(onTap: onForfeit),
      ],
    );
  }
}

// ───────────────────── Live board widgets (mockup 2×2) ─────────────────────
// Dynamic siblings of the static demo cards above, driven by live game state.
// Layout mirrors the mockup board screen: a player card beside an info panel,
// top and bottom, with a status/action bar below.

/// Player card (mockup `pcard`): a rounded-square avatar inside a timer ring,
/// then three rows — ● name / [sub] (e.g. "3 captures") / [turnText].
///
/// Active: the card takes the player's gradient tint, a 1.5px border in
/// [color] and a soft glow, and the ring becomes a timer — a stroke that runs
/// around the avatar's rounded-square edge and drains with [progress]
/// (1 = full, 0 = out of time; null = full ring). Inactive cards are plain
/// glass with a quiet "Waiting" line.
class BoardPlayerCard extends StatelessWidget {
  const BoardPlayerCard({
    super.key,
    required this.name,
    required this.initials,
    required this.sub,
    required this.color,
    this.color2,
    required this.active,
    this.turnText,
    this.progress,
  });

  final String name;
  final String initials;
  final String sub;

  /// Player colour (dot, border, glow, timer ring) and the gradient's second
  /// stop (avatar + active tint). Mockup pairs: purple→pink, cyan→blue.
  final Color color;
  final Color? color2;
  final bool active;

  /// Third row. Defaults to "Waiting" when inactive.
  final String? turnText;

  /// Remaining fraction of the active player's move time (0..1).
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final c2 = color2 ?? Color.lerp(color, Colors.black, 0.25)!;
    final third = turnText ?? (active ? '' : 'Waiting');
    // Glow lives on an OPAQUE base layer: a Flutter BoxShadow is painted
    // under the box and would show through the translucent tint as an inner
    // rectangle (CSS box-shadow never draws beneath its element).
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: active ? const Color(0xFF0E0B1A) : null,
        boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 28, spreadRadius: -6)] : null,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: active
                ? [color.withValues(alpha: 0.25), c2.withValues(alpha: 0.10)]
                : [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.03)],
          ),
          border: Border.all(color: active ? color : Colors.white.withValues(alpha: 0.16), width: 1.5), // fixed width: no layout shift on turn change
        ),
        child: Row(
          children: [
            _TimerAvatar(initials: initials, color: color, color2: c2, active: active, progress: progress),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: color, blurRadius: 8)],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AuraText.displayFamily,
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11.5),
                  ),
                  Text(
                    third,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? color : Colors.white.withValues(alpha: 0.4),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 46px rounded-square avatar with a 2px ring. When [active] the ring is a
/// timer: a [color] stroke tracing the rounded-square edge clockwise from the
/// top centre, shrinking as [progress] falls. Eased between clock ticks so it
/// glides instead of stepping.
class _TimerAvatar extends StatelessWidget {
  const _TimerAvatar({
    required this.initials,
    required this.color,
    required this.color2,
    required this.active,
    this.progress,
  });

  final String initials;
  final Color color;
  final Color color2;
  final bool active;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final target = active ? (progress ?? 1.0).clamp(0.0, 1.0) : 1.0;
    return SizedBox(
      width: 46,
      height: 46,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: target),
        // Matches the 200ms clock tick, so the sweep moves continuously.
        duration: const Duration(milliseconds: 220),
        builder: (context, value, child) => CustomPaint(
          painter: _RectTimerPainter(
            fraction: value,
            color: active ? color : Colors.white.withValues(alpha: 0.10),
            track: Colors.white.withValues(alpha: 0.12),
          ),
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsets.all(2.5),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, color2]),
            ),
            child: Text(
              initials,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RectTimerPainter extends CustomPainter {
  _RectTimerPainter({required this.fraction, required this.color, required this.track});
  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const w = 2.5;
    final r = RRect.fromRectAndRadius((Offset.zero & size).deflate(w / 2), const Radius.circular(14));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    // Path starting at the top centre, running clockwise, so the remaining
    // time reads like a clock hand sweeping around the square.
    final cx = size.width / 2;
    final path = Path()
      ..moveTo(cx, r.top)
      ..lineTo(r.right - r.trRadiusX, r.top)
      ..arcToPoint(Offset(r.right, r.top + r.trRadiusY), radius: r.trRadius)
      ..lineTo(r.right, r.bottom - r.brRadiusY)
      ..arcToPoint(Offset(r.right - r.brRadiusX, r.bottom), radius: r.brRadius)
      ..lineTo(r.left + r.blRadiusX, r.bottom)
      ..arcToPoint(Offset(r.left, r.bottom - r.blRadiusY), radius: r.blRadius)
      ..lineTo(r.left, r.top + r.tlRadiusY)
      ..arcToPoint(Offset(r.left + r.tlRadiusX, r.top), radius: r.tlRadius)
      ..close();
    canvas.drawPath(path, stroke..color = track);
    if (fraction <= 0) return;
    final metric = path.computeMetrics().first;
    canvas.drawPath(metric.extractPath(0, metric.length * fraction), stroke..color = color);
  }

  @override
  bool shouldRepaint(covariant _RectTimerPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}

/// Dashed-bordered info panel: an uppercase label over a value. `big` renders
/// the value as a large display number (the TURN CLOCK); `urgent` turns it red.
class BoardInfoPanel extends StatelessWidget {
  const BoardInfoPanel({super.key, required this.label, required this.value, this.big = false, this.urgent = false});

  final String label;
  final String value;
  final bool big;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedPanelPainter(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: Colors.white.withValues(alpha: 0.03)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: big ? 6 : 4),
            Text(
              value,
              maxLines: big ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: big
                  ? TextStyle(
                      fontFamily: AuraText.displayFamily,
                      color: urgent ? AuraColors.danger : Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    )
                  : TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedPanelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.14);
    const dash = 5.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPanelPainter oldDelegate) => false;
}

/// Bottom bar: optional chat button · status/action pill · optional resign.
/// The pill lights up with the brand gradient when it's the player's move.
class BoardActionBar extends StatelessWidget {
  const BoardActionBar({
    super.key,
    required this.statusLabel,
    this.active = false,
    this.onChat,
    this.onDraw,
    this.onResign,
    this.resignIcon = Icons.flag_outlined,
  });

  final String statusLabel;
  final bool active;
  final VoidCallback? onChat;

  /// Online only: offer a draw (square button before forfeit).
  final VoidCallback? onDraw;
  final VoidCallback? onResign;
  final IconData resignIcon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onChat != null) ...[
          _SquareIconButton(
            icon: Icons.chat_bubble_outline_rounded,
            onTap: onChat!,
            color: Colors.white,
            fill: Colors.white.withValues(alpha: 0.07),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: active
                ? BoxDecoration(
                    gradient: AuraGradients.brand,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AuraColors.brandPink.withValues(alpha: 0.4),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  )
                : BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
            child: Text(
              statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: Colors.white.withValues(alpha: active ? 1 : 0.7),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (onDraw != null) ...[
          const SizedBox(width: 10),
          _SquareIconButton(
            icon: Icons.handshake_outlined,
            onTap: onDraw!,
            color: Colors.white,
            fill: Colors.white.withValues(alpha: 0.07),
          ),
        ],
        if (onResign != null) ...[
          const SizedBox(width: 10),
          _SquareIconButton(
            icon: resignIcon,
            onTap: onResign!,
            color: AuraColors.danger,
            fill: AuraColors.danger.withValues(alpha: 0.15),
            border: AuraColors.danger.withValues(alpha: 0.5),
          ),
        ],
      ],
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({
    required this.icon,
    required this.onTap,
    required this.color,
    required this.fill,
    this.border,
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color fill;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 54,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border ?? Colors.white.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Forfeit dialog ───────────────────────────

/// Mockup `forfeit` dialog: "Forfeit the match?" with stake-aware copy,
/// Forfeit (danger) / Keep playing. Returns true when the player confirms.
/// Callers pause the game while it is open and end the match as a defeat.
Future<bool> confirmMatchForfeit(BuildContext context, {int stake = 0}) async {
  final ok = await showAuraDialog(
    context,
    icon: Icons.flag_rounded,
    title: 'Forfeit the match?',
    body: stake > 0
        ? 'You will lose your ${_thousands(stake)} stake and the round counts as a defeat.'
        : 'This round will count as a defeat and you will earn no reward.',
    primaryLabel: 'Forfeit',
    secondaryLabel: 'Keep playing',
    destructive: true,
  );
  return ok == true;
}

/// Legacy boards: confirm, then pop the board.
Future<void> confirmGameForfeit(BuildContext context) async {
  if (await confirmMatchForfeit(context) && context.mounted) Navigator.of(context).maybePop();
}

/// 12500 → "12,500" (mockup `fmt`).
String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

// ─────────────────────────── Chat / emotes sheet ───────────────────────────

const _emotes = ['👋', '🔥', 'GG', '😅', '👀', '💀', '🎯', '🤝'];
const _quickMessages = ['Good luck!', 'Nice move', 'Rematch?', 'GG'];

/// In-game chat panel (mockup `chat`): opponent header, empty conversation,
/// quick-message pills + emote row, and a message input with send button.
/// Presentation only — sending shows a toast.
void showGameChatSheet(
  BuildContext context, {
  String opponent = 'ZeroCool',
  String initials = 'ZE',
  Color color = AuraColors.avatarBlue,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _ChatSheet(opponent: opponent, initials: initials, color: color),
  );
}

class _ChatSheet extends StatelessWidget {
  const _ChatSheet({required this.opponent, required this.initials, required this.color});
  final String opponent;
  final String initials;
  final Color color;

  void _send(BuildContext context, String message) =>
      showAuraToast(context, 'Sent  $message', kind: AuraToastKind.info);

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.72;
    return Container(
      height: height,
      padding: EdgeInsets.fromLTRB(18, 12, 18, 14 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1330), Color(0xFF0C0A18)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0x33FFFFFF), width: 1.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: opponent + online + close.
          Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    LetterAvatar(letter: initials, color: color, size: 44),
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: AuraColors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: AuraColors.bgBase, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(opponent, style: AuraText.cardTitle.copyWith(fontSize: 15.5)),
                    const SizedBox(height: 1),
                    const Text(
                      'Online',
                      style: TextStyle(color: AuraColors.green, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              GlassIconButton(icon: Icons.close, onTap: () => Navigator.of(context).maybePop()),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          // Empty conversation.
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                    ),
                    child: Icon(Icons.chat_bubble_outline, color: AuraColors.textSecondary, size: 24),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Say hi or send an emote',
                    style: AuraText.body.copyWith(color: AuraColors.textSecondary, fontSize: 13.5),
                  ),
                ],
              ),
            ),
          ),
          // Quick-message pills.
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final m in _quickMessages) ...[
                  _QuickPill(text: m, onTap: () => _send(context, m)),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Emote row.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (final e in _emotes) _EmoteButton(emote: e, onTap: () => _send(context, e))],
          ),
          const SizedBox(height: 12),
          // Message input + send.
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  decoration: AuraGlass.decoration(radius: 14, shadow: false),
                  child: Text(
                    'Message…',
                    style: TextStyle(color: AuraColors.textPrimary.withValues(alpha: 0.34), fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _send(context, 'a message'),
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AuraGradients.brand,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickPill extends StatelessWidget {
  const _QuickPill({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AuraColors.card,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AuraColors.cardBorder),
          ),
          child: Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _EmoteButton extends StatelessWidget {
  const _EmoteButton({required this.emote, required this.onTap});
  final String emote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AuraColors.card,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AuraColors.cardBorder),
          ),
          child: Text(
            emote,
            style: TextStyle(
              fontSize: emote.length > 1 ? 14 : 22,
              fontWeight: emote.length > 1 ? FontWeight.w800 : FontWeight.w400,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Paused overlay ───────────────────────────

/// Mockup paused overlay: blurred backdrop + centred panel — pause tile,
/// "Paused", [subtitle], Resume, a Sound effects switch and "Forfeit match".
///
/// [onPause] runs as it opens (stop the clock). Resume closes it and runs
/// [onResume]. "Forfeit match" closes it and runs [onForfeit] (which shows the
/// forfeit confirm; that flow decides whether to resume). Not dismissible by
/// tapping outside — Resume is the way back, as in the mockup.
Future<void> showGamePaused(
  BuildContext context, {
  String subtitle = 'The clock is stopped for everyone.',
  VoidCallback? onPause,
  VoidCallback? onResume,
  VoidCallback? onForfeit,
}) async {
  onPause?.call();
  final forfeit = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Paused',
    barrierColor: const Color(0xCC05040C), // rgba(5,4,12,0.8)
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, a1, a2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, _) {
      final curved = Curves.easeOutBack.transform(anim.value.clamp(0, 1));
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8 * anim.value, sigmaY: 8 * anim.value),
        child: Opacity(
          opacity: anim.value.clamp(0, 1),
          child: Center(
            child: Transform.scale(scale: 0.92 + 0.08 * curved, child: _PausedPanel(subtitle: subtitle)),
          ),
        ),
      );
    },
  );
  if (forfeit == true) {
    (onForfeit ?? () => confirmGameForfeit(context))();
  } else {
    onResume?.call();
  }
}

class _PausedPanel extends StatelessWidget {
  const _PausedPanel({required this.subtitle});
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A1330), Color(0xFF0C0A18)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.9), blurRadius: 70, spreadRadius: -20, offset: const Offset(0, 30)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AuraColors.brandPurple, AuraColors.brandPink],
                  ),
                  borderRadius: BorderRadius.circular(21),
                  boxShadow: [
                    BoxShadow(
                      color: AuraColors.brandPink.withValues(alpha: 0.8),
                      blurRadius: 28,
                      spreadRadius: -12,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: const Icon(Icons.pause_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 16),
              Text(
                'Paused',
                style: TextStyle(fontFamily: AuraText.displayFamily, fontWeight: FontWeight.w700, fontSize: 22, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.5, color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: GradientButton(label: 'Resume', onPressed: () => Navigator.of(context).pop(false)),
              ),
              const SizedBox(height: 10),
              const _SoundToggleRow(),
              const SizedBox(height: 10),
              // Mockup: text-only danger button, 48px, r15.
              SizedBox(
                width: double.infinity,
                height: 48,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AuraColors.danger.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: const Color(0xFFFB7185).withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        'Forfeit match',
                        style: TextStyle(
                          fontFamily: AuraText.displayFamily,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: const Color(0xFFFB7185),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Session-scoped sound-effects preference (presentational for now — the mockup
/// toggles it locally; wire to a real audio service when sounds land).
bool gameSoundOn = true;

/// "Sound effects" row with a sliding switch (mockup pause panel).
class _SoundToggleRow extends StatefulWidget {
  const _SoundToggleRow();

  @override
  State<_SoundToggleRow> createState() => _SoundToggleRowState();
}

class _SoundToggleRowState extends State<_SoundToggleRow> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => gameSoundOn = !gameSoundOn),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(
          children: [
            const Expanded(child: Text('Sound effects', style: TextStyle(color: Colors.white, fontSize: 14))),
            // Plain Container + AnimatedAlign: AnimatedContainer can't tween a
            // gradient to null, which left the track stuck "on".
            Container(
              width: 46,
              height: 28,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                gradient: gameSoundOn ? AuraGradients.brand : null,
                color: gameSoundOn ? null : Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(99),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 160),
                alignment: gameSoundOn ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
