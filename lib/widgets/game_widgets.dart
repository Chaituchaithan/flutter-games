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

/// The dark "POT ♦ N" pill shown in a game header.
class GamePotPill extends StatelessWidget {
  const GamePotPill({super.key, required this.amount, this.currency = Currency.gems});

  final String amount;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final gold = currency == Currency.gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AuraColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AuraColors.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'POT',
            style: TextStyle(
              color: AuraColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                gold ? Icons.monetization_on : Icons.diamond,
                size: 14,
                color: gold ? AuraColors.gold : AuraColors.gems,
              ),
              const SizedBox(width: 5),
              Text(
                amount,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Header ───────────────────────────

/// Standard game header: back + title (with optional subtitle) + pause + pot.
class GameHeader extends StatelessWidget {
  const GameHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.pot,
    this.currency = Currency.gems,
    this.showPause = true,
  });

  final String title;
  final String? subtitle;
  final String pot;
  final Currency currency;
  final bool showPause;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleActionButton(
          icon: Icons.chevron_left,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AuraColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (showPause) ...[
          GlassIconButton(
            icon: Icons.pause_rounded,
            onTap: () => showGamePaused(context),
          ),
          const SizedBox(width: 10),
        ],
        GamePotPill(amount: pot, currency: currency),
      ],
    );
  }
}

/// Secondary meta line under a header (e.g. "Move 1 / 12 · 2 players · 30s").
class GameMetaText extends StatelessWidget {
  const GameMetaText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: AuraColors.textSecondary, fontSize: 13),
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
            style: const TextStyle(
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
                  style: const TextStyle(
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
          Text(
            trailing,
            style: const TextStyle(color: AuraColors.textSecondary, fontSize: 13),
          ),
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
      decoration: AuraGlass.decoration(
        border: AuraColors.accentGlow.withValues(alpha: 0.55),
      ),
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
                  style: const TextStyle(
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
                  style: const TextStyle(
                    color: AuraColors.brandPink,
                    fontSize: 12,
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
        border: Border.all(
          color: highlight ? AuraColors.brandPink : AuraColors.cardBorder,
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: const TextStyle(
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
                  style: const TextStyle(
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
  const GameActionBar({
    super.key,
    required this.primaryLabel,
    this.onPrimary,
    this.onChat,
    this.onForfeit,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onChat;
  final VoidCallback? onForfeit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleActionButton(
          icon: Icons.chat_bubble_outline,
          onTap: onChat ?? () => showGameChatSheet(context),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GradientButton(
            label: primaryLabel,
            onPressed: onPrimary ??
                () => showAuraToast(context, 'Demo board — moves are not live yet',
                    kind: AuraToastKind.info),
          ),
        ),
        const SizedBox(width: 12),
        GameForfeitButton(onTap: onForfeit),
      ],
    );
  }
}

// ─────────────────────────── Forfeit dialog ───────────────────────────

/// Destructive confirm for leaving a match. On confirm, pops the board.
Future<void> confirmGameForfeit(BuildContext context) async {
  final ok = await showAuraDialog(
    context,
    icon: Icons.flag_rounded,
    title: 'Forfeit match?',
    body: "You'll lose your stake and this counts as a loss.",
    primaryLabel: 'Forfeit',
    secondaryLabel: 'Keep playing',
    destructive: true,
  );
  if (ok == true && context.mounted) {
    Navigator.of(context).maybePop();
  }
}

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
                    const Text('Online',
                        style: TextStyle(color: AuraColors.green, fontSize: 12, fontWeight: FontWeight.w700)),
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
                  Text('Say hi or send an emote',
                      style: AuraText.body.copyWith(color: AuraColors.textSecondary, fontSize: 13.5)),
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
            children: [
              for (final e in _emotes) _EmoteButton(emote: e, onTap: () => _send(context, e)),
            ],
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
                  child: Text('Message…',
                      style: TextStyle(color: AuraColors.textPrimary.withValues(alpha: 0.34), fontSize: 15)),
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
          child: Text(text,
              style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
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

/// Full-screen tap-blurred "Paused" overlay: Resume / Settings / Forfeit.
void showGamePaused(BuildContext context) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Paused',
    barrierColor: const Color(0xE605040C),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, a1, a2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, _) {
      final curved = Curves.easeOutBack.transform(anim.value.clamp(0, 1));
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8 * anim.value, sigmaY: 8 * anim.value),
        child: Opacity(
          opacity: anim.value.clamp(0, 1),
          child: Center(
            child: Transform.scale(
              scale: 0.92 + 0.08 * curved,
              child: const _PausedPanel(),
            ),
          ),
        ),
      );
    },
  );
}

class _PausedPanel extends StatelessWidget {
  const _PausedPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                gradient: AuraGradients.brand,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AuraColors.brandPink.withValues(alpha: 0.5),
                    blurRadius: 32,
                    spreadRadius: -8,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: const Icon(Icons.pause_rounded, color: Colors.white, size: 38),
            ),
            const SizedBox(height: 18),
            Text('Paused', style: AuraText.title.copyWith(fontSize: 24)),
            const SizedBox(height: 6),
            Text(
              'Your turn timer is on hold.',
              style: AuraText.body.copyWith(fontSize: 14, color: AuraColors.textSecondary),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: GradientButton(
                label: 'Resume',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(height: 10),
            _PausedSecondary(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () {
                Navigator.of(context).pop();
                showAuraToast(context, 'Settings coming soon', kind: AuraToastKind.info);
              },
            ),
            const SizedBox(height: 10),
            _PausedSecondary(
              icon: Icons.flag_outlined,
              label: 'Forfeit match',
              destructive: true,
              onTap: () {
                Navigator.of(context).pop();
                confirmGameForfeit(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PausedSecondary extends StatelessWidget {
  const _PausedSecondary({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final fg = destructive ? AuraColors.dangerText : Colors.white;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: destructive ? AuraColors.danger.withValues(alpha: 0.14) : null,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: destructive
                    ? AuraColors.danger.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.22),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: AuraText.bodyFamily,
                    color: fg,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
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
