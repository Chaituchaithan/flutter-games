import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Present the purchase confirmation as a modal bottom sheet (mockup `purchaseOpen`).
Future<void> showPurchaseSheet(BuildContext context, {String? name, String? amount, String? price}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xBD05040C), // rgba(5,4,12,0.74)
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: PurchaseSheet(name: name, amount: amount, price: price),
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
  const PurchaseSheet({super.key, this.name, this.amount, this.price});

  final String? name;
  final String? amount;
  final String? price;

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
    final n = widget.name ?? 'Stack';
    final amt = widget.amount ?? '1,200';
    final p = widget.price ?? '\$4.99';
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
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.22))),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: Text('Confirm purchase', style: AuraText.title.copyWith(fontSize: 22))),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, color: AuraColors.textSecondary),
                    splashRadius: 22,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AuraCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const CurrencyGlyph(kind: Currency.gold, size: 26),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n, style: AuraText.cardTitle),
                              const SizedBox(height: 2),
                              Text('Gold', style: AuraText.cardSub),
                            ],
                          ),
                        ),
                        Text(
                          p,
                          style: TextStyle(
                            fontFamily: AuraText.displayFamily,
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
                    ),
                    _KvRow(
                      label: 'Balance after',
                      child: Text(
                        '$amt Gold',
                        style: TextStyle(
                          fontFamily: AuraText.displayFamily,
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _KvRow(
                      label: 'Payment',
                      child: InkWell(
                        onTap: _pickMethod,
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_method.$2, color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Text(_method.$1,
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, color: AuraColors.textSecondary, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              GradientButton(
                label: 'Pay $p',
                onPressed: () {
                  Navigator.of(context).maybePop();
                  showAuraToast(context, 'Purchase complete · +$amt Gold', kind: AuraToastKind.gold);
                },
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  'Secure checkout · Restore purchases in Settings',
                  style: AuraText.cardSub,
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
            style: const TextStyle(color: AuraColors.textSecondary, fontSize: 15),
          ),
        ),
        child,
      ],
    );
  }
}
