import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../widgets/aura.dart';

/// Present the purchase confirmation as a modal bottom sheet (mockup `purchaseOpen`).
Future<void> showPurchaseSheet(
  BuildContext context, {
  String? name,
  String? amount,
  String? price,
  Currency kind = Currency.gold,
  String? bonus,
  String? balanceAfter,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xBD05040C), // rgba(5,4,12,0.74)
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: PurchaseSheet(
        name: name,
        amount: amount,
        price: price,
        kind: kind,
        bonus: bonus,
        balanceAfter: balanceAfter,
      ),
    ),
  );
}

/// A selectable payment method.
typedef _Method = (String label, IconData icon);

const _methods = <_Method>[
  ('Apple Pay', Icons.apple),
  ('Google Pay', Icons.account_balance_wallet),
  ('Card •••• 4242', Icons.credit_card),
];

/// Purchase confirmation panel — used both as a modal sheet ([showPurchaseSheet])
/// and by the routed [PurchaseConfirmScreen] fallback.
class PurchaseSheet extends StatefulWidget {
  const PurchaseSheet({
    super.key,
    this.name,
    this.amount,
    this.price,
    this.kind = Currency.gold,
    this.bonus,
    this.balanceAfter,
  });

  final String? name;
  final String? amount;
  final String? price;
  final Currency kind;
  final String? bonus;
  final String? balanceAfter;

  @override
  State<PurchaseSheet> createState() => _PurchaseSheetState();
}

class _PurchaseSheetState extends State<PurchaseSheet> {
  _Method _method = _methods.first;

  Future<void> _pickMethod() async {
    final picked = await showModalBottomSheet<_Method>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MethodPicker(selected: _method),
    );
    if (picked != null && mounted) setState(() => _method = picked);
  }

  @override
  Widget build(BuildContext context) {
    final isGold = widget.kind == Currency.gold;
    final unit = isGold ? 'Gold' : 'Tokens';
    final n = widget.name ?? 'Stack';
    final amt = widget.amount ?? '1,200';
    final p = widget.price ?? '\$4.99';
    final balAfter = widget.balanceAfter ?? amt;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF17112C), Color(0xFF0B0916)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.22), width: 1.5)),
          ),
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Text('Confirm purchase', style: AuraText.title.copyWith(fontSize: 22))),
                  // Circular close button (mockup: 32px, white@8% fill, white@20% ring).
                  Material(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Product summary card (mockup: 60px icon tile · tiny label · big
              // amount+unit · price on the right · green bonus line).
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AuraGlass.decoration(radius: 20, shadow: false),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: CurrencyGlyph(kind: widget.kind, size: 34),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.toUpperCase(),
                            style: TextStyle(
                              fontFamily: AuraText.displayFamily,
                              color: AuraColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: amt),
                                TextSpan(
                                  text: ' $unit',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AuraColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            style: TextStyle(
                              fontFamily: AuraText.displayFamily,
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (widget.bonus != null && widget.bonus!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${widget.bonus} included',
                              style: const TextStyle(
                                color: AuraColors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      p,
                      style: TextStyle(
                        fontFamily: AuraText.displayFamily,
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Key/value rows sit below the card (mockup), not inside it.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  children: [
                    _KvRow(
                      label: 'Balance after',
                      child: Text(
                        '$balAfter $unit',
                        style: TextStyle(
                          fontFamily: AuraText.displayFamily,
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    _KvRow(
                      label: 'Payment',
                      child: InkWell(
                        onTap: _pickMethod,
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_method.$2, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(_method.$1,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 2),
                            const Icon(Icons.chevron_right, color: AuraColors.textSecondary, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _PayButton(
                label: 'Pay $p',
                gold: isGold,
                onPressed: () {
                  // UI-only flow: hand off to the Purchase Complete screen,
                  // carrying the credited amount + currency for display.
                  Navigator.of(context).pushReplacementNamed(
                    Routes.purchaseComplete,
                    arguments: {'amount': amt, 'unit': unit, 'gold': isGold},
                  );
                },
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Secure checkout · Restore purchases in Settings',
                  style: TextStyle(
                    fontFamily: AuraText.bodyFamily,
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Routed fallback (kept for deep-links / tests). Anchors the sheet at the bottom.
class PurchaseConfirmScreen extends StatelessWidget {
  const PurchaseConfirmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      padding: EdgeInsets.zero,
      body: Column(
        children: const [
          Spacer(),
          PurchaseSheet(),
        ],
      ),
    );
  }
}

/// Currency-tinted confirm CTA (mockup `confirmPurchaseBtn`): gold gradient with
/// dark ink for Gold, cyan→blue with white ink for Tokens.
class _PayButton extends StatelessWidget {
  const _PayButton({required this.label, required this.gold, required this.onPressed});
  final String label;
  final bool gold;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final glow = gold ? AuraColors.gold : AuraColors.gems;
    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onPressed,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: gold
                  ? AuraGradients.goldCoin
                  : const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)]),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: glow.withValues(alpha: 0.45),
                  blurRadius: 30,
                  spreadRadius: -10,
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

/// Bottom sheet listing payment methods; pops the chosen [_Method].
class _MethodPicker extends StatelessWidget {
  const _MethodPicker({required this.selected});
  final _Method selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF17112C), Color(0xFF0B0916)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0x33FFFFFF))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Payment method', style: AuraText.title.copyWith(fontSize: 18)),
          const SizedBox(height: 14),
          for (final m in _methods) ...[
            Material(
              color: AuraColors.card,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).pop(m),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: m.$1 == selected.$1
                          ? AuraColors.accentGlow.withValues(alpha: 0.6)
                          : AuraColors.cardBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(m.$2, color: Colors.white, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(m.$1,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      if (m.$1 == selected.$1)
                        const Icon(Icons.check_circle, color: AuraColors.accentGlow, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _KvRow extends StatelessWidget {
  const _KvRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AuraColors.textSecondary, fontSize: 13),
          ),
        ),
        child,
      ],
    );
  }
}
