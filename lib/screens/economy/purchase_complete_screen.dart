import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../widgets/aura.dart';

/// Success screen shown after a (UI-only) purchase completes. Mirrors the
/// mockup's `purchased` dialog — centred glass panel, gradient check badge,
/// "Purchase complete" copy — promoted to a full screen so it can be routed
/// via [Routes.purchaseComplete]. The accent is tinted to the credited
/// currency (gold for Gold, cyan→blue for Tokens).
class PurchaseCompleteScreen extends StatelessWidget {
  const PurchaseCompleteScreen({
    super.key,
    this.amount,
    this.unit,
    this.gold = true,
  });

  /// Credited amount (e.g. "1,200"); when null the amount chip is hidden.
  final String? amount;

  /// Currency label ("Gold" / "Tokens").
  final String? unit;

  /// Gold vs. Tokens accent.
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final iconGradient = gold
        ? AuraGradients.goldCoin
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)],
          );
    final glow = gold ? AuraColors.gold : AuraColors.gemsDeep;
    final u = unit ?? (gold ? 'Gold' : 'Tokens');

    return AuraScaffold(
      showGlow: true,
      glowColor: glow,
      body: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A1330), Color(0xFF0C0A18)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.9),
                blurRadius: 70,
                spreadRadius: -20,
                offset: const Offset(0, 30),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Gradient check badge (mockup: 72px, radius 22, coloured glow).
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: iconGradient,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                    boxShadow: [
                      BoxShadow(
                        color: glow.withValues(alpha: 0.5),
                        blurRadius: 36,
                        spreadRadius: -10,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    color: gold ? const Color(0xFF1A1206) : Colors.white,
                    size: 38,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Purchase complete',
                textAlign: TextAlign.center,
                style: AuraText.title.copyWith(fontSize: 22),
              ),
              const SizedBox(height: 8),
              Text(
                'Your balance has been updated. A receipt was sent to your email.',
                textAlign: TextAlign.center,
                style: AuraText.body2.copyWith(color: AuraColors.textSecondary),
              ),
              if (amount != null && amount!.isNotEmpty) ...[
                const SizedBox(height: 18),
                // Credited-amount chip.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: AuraGlass.decoration(radius: 16, shadow: false),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CurrencyGlyph(kind: gold ? Currency.gold : Currency.gems, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          '+$amount $u',
                          style: TextStyle(
                            fontFamily: AuraText.displayFamily,
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('credited', style: AuraText.cardSub),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              _CompleteButton(
                label: 'Back to Store',
                gold: gold,
                glow: glow,
                gradient: iconGradient,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(height: 10),
              // Secondary: jump to the transactions ledger (the "receipt").
              SizedBox(
                height: 48,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: () => Navigator.of(context).pushReplacementNamed(Routes.transactions),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.5),
                      ),
                      child: Text(
                        'View receipt',
                        style: TextStyle(
                          fontFamily: AuraText.bodyFamily,
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
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

/// Primary CTA on the success panel — currency-tinted to match the badge
/// (mockup `dlgPrimaryStyle`).
class _CompleteButton extends StatelessWidget {
  const _CompleteButton({
    required this.label,
    required this.gold,
    required this.glow,
    required this.gradient,
    required this.onPressed,
  });
  final String label;
  final bool gold;
  final Color glow;
  final Gradient gradient;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: glow.withValues(alpha: 0.45),
                  blurRadius: 28,
                  spreadRadius: -12,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AuraText.displayFamily,
                color: gold ? const Color(0xFF1A1206) : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
