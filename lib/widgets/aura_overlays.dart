import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Shared feedback overlays — dialog, toast, offline banner.
/// See docs/DESIGN_SPEC.md.

// ─────────────────────────── Dialog ───────────────────────────

/// Modal confirm/alert dialog. Returns `true` if the primary action was tapped,
/// `false`/`null` otherwise. Set [destructive] for a red primary (e.g. Log out).
/// Visual tone of a dialog: brand (default), danger (destructive red),
/// or warning (amber/gold — e.g. "Not enough balance").
enum AuraDialogTone { brand, danger, warning, success }

Future<bool?> showAuraDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String body,
  required String primaryLabel,
  String? secondaryLabel,
  bool destructive = false,
  AuraDialogTone? tone,
}) {
  final resolved = tone ?? (destructive ? AuraDialogTone.danger : AuraDialogTone.brand);
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: const Color(0xC705040C), // rgba(5,4,12,0.78)
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, a1, a2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, _) {
      final curved = Curves.easeOutBack.transform(anim.value.clamp(0, 1));
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6 * anim.value, sigmaY: 6 * anim.value),
        child: Opacity(
          opacity: anim.value.clamp(0, 1),
          child: Center(
            child: Transform.scale(
              scale: 0.92 + 0.08 * curved,
              child: _DialogPanel(
                icon: icon,
                title: title,
                body: body,
                primaryLabel: primaryLabel,
                secondaryLabel: secondaryLabel,
                tone: resolved,
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Mockup `Dialog · balance`. Returns true if the player chose "Buy more".
Future<bool?> showInsufficientBalanceDialog(BuildContext context) => showAuraDialog(
      context,
      icon: Icons.warning_amber_rounded,
      title: 'Not enough balance',
      body: 'You need more to enter this match. Top up in the Store and jump right back in.',
      primaryLabel: 'Buy more',
      secondaryLabel: 'Maybe later',
      tone: AuraDialogTone.warning,
    );

class _DialogPanel extends StatelessWidget {
  const _DialogPanel({
    required this.icon,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String body;
  final String primaryLabel;
  final String? secondaryLabel;
  final AuraDialogTone tone;

  @override
  Widget build(BuildContext context) {
    final iconGrad = switch (tone) {
      AuraDialogTone.danger => const LinearGradient(colors: [AuraColors.danger, Color(0xFFBE123C)]),
      AuraDialogTone.warning => AuraGradients.goldCoin,
      AuraDialogTone.brand => AuraGradients.brand,
      AuraDialogTone.success => const LinearGradient(colors: [Color(0xFF34D399), Color(0xFF14B8A6)]),
    };
    final glowColor = switch (tone) {
      AuraDialogTone.danger => AuraColors.danger,
      AuraDialogTone.warning => AuraColors.gold,
      AuraDialogTone.brand => AuraColors.brandPink,
      AuraDialogTone.success => const Color(0xFF34D399),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A1330), Color(0xFF0C0A18)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.9), blurRadius: 70, spreadRadius: -20, offset: const Offset(0, 30)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: iconGrad,
                    borderRadius: BorderRadius.circular(19),
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withValues(alpha: 0.5),
                        blurRadius: 28,
                        spreadRadius: -8,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
              ),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: AuraText.title.copyWith(fontSize: 20)),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: AuraText.body.copyWith(fontSize: 14, color: AuraColors.textSecondary),
              ),
              const SizedBox(height: 18),
              _DialogButton(
                label: primaryLabel,
                gradient: iconGrad,
                onTap: () => Navigator.of(context).pop(true),
              ),
              if (secondaryLabel != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).pop(false),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.5),
                        ),
                        child: Text(
                          secondaryLabel!,
                          style: TextStyle(
                            fontFamily: AuraText.bodyFamily,
                            color: AuraColors.textPrimary.withValues(alpha: 0.8),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({required this.label, required this.gradient, required this.onTap});
  final String label;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
              gradient: gradient,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Toast ───────────────────────────

enum AuraToastKind { success, gold, info, error }

/// Dark glass pill toast (auto-dismiss ~2.6s). Uses [ScaffoldMessenger].
void showAuraToast(BuildContext context, String message, {AuraToastKind kind = AuraToastKind.success}) {
  final (grad, icon) = switch (kind) {
    AuraToastKind.success => (const LinearGradient(colors: [AuraColors.green, Color(0xFF14B8A6)]), Icons.check_rounded),
    AuraToastKind.gold => (AuraGradients.goldCoin, Icons.star_rounded),
    AuraToastKind.info => (AuraGradients.token, Icons.info_outline_rounded),
    AuraToastKind.error => (const LinearGradient(colors: [AuraColors.danger, Color(0xFFBE123C)]), Icons.close_rounded),
  };
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: const Duration(milliseconds: 2600),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 112),
        padding: EdgeInsets.zero,
        content: Align(
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment(-0.6, -1),
                end: Alignment(0.6, 1),
                colors: [Color(0xF51E1634), Color(0xF50C0A16)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.9), blurRadius: 40, spreadRadius: -14, offset: const Offset(0, 20)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(gradient: grad, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 11),
                Flexible(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontFamily: AuraText.bodyFamily,
                      color: Colors.white,
                      fontSize: 13.5,
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

// ─────────────────────────── Offline banner ───────────────────────────

/// Top offline banner (mockup `offline`). Not globally wired yet — drop into a
/// screen's Stack when an offline state exists.
class AuraOfflineBanner extends StatelessWidget {
  const AuraOfflineBanner({super.key, this.onRetry});
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AuraColors.danger.withValues(alpha: 0.32), const Color(0xFF140A14).withValues(alpha: 0.9)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AuraColors.dangerText.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AuraColors.dangerText.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.wifi_off_rounded, color: AuraColors.dangerText, size: 18),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("You're offline", style: AuraText.cardTitle.copyWith(fontSize: 13.5)),
                const SizedBox(height: 1),
                Text('Reconnecting… matches are paused',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5)),
              ],
            ),
          ),
          if (onRetry != null)
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: const Text('Retry', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}
