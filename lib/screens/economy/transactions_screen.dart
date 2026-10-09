import 'package:flutter/material.dart';

import '../../widgets/aura.dart';

/// Transactions history. See docs/DESIGN_SPEC.md (v2 §Transactions).
class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  static const List<_Txn> _txns = [
    _Txn(title: 'Welcome pack', subtitle: 'Bonus · Today 09:12', amount: '5,000', earn: true),
    _Txn(title: 'Online Play stake', subtitle: 'Match #4821 · Today 09:40', amount: '200', earn: false),
    _Txn(title: 'Victory payout', subtitle: 'Match #4821 · Today 09:46', amount: '800', earn: true),
    _Txn(title: 'Daily bonus', subtitle: 'Day 2 · Yesterday', amount: '800', earn: true),
    _Txn(title: 'Double XP', subtitle: 'Power-up · Yesterday', amount: '500', earn: false),
    _Txn(title: 'Lucky wheel', subtitle: 'Spin · Yesterday', amount: '200', earn: true),
    _Txn(title: 'Gold pack · Stack', subtitle: '\$4.99 · Mon', amount: '1,200', earn: true, gold: true),
  ];

  @override
  Widget build(BuildContext context) {
    return AuraScaffold(
      appBar: const AuraAppBar(title: 'Transactions'),
      scroll: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                Expanded(
                  child: _SummaryCard(
                    label: 'EARNED · 7D',
                    amount: '+6,600',
                    color: AuraColors.green,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    label: 'SPENT · 7D',
                    amount: '−200',
                    color: AuraColors.danger,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionBar(
            'Recent activity',
            trailing: Text(
              'Export',
              style: TextStyle(
                color: AuraColors.accentGlow,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final t in _txns) ...[
            _TxnRow(txn: t),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _Txn {
  const _Txn({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.earn,
    this.gold = false,
  });
  final String title;
  final String subtitle;
  final String amount;
  final bool earn;
  final bool gold;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.amount, required this.color});
  final String label;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AuraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AuraText.section),
          const SizedBox(height: 12),
          Row(
            children: [
              const CurrencyGlyph(kind: Currency.gems, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amount,
                    style: TextStyle(
                      fontFamily: AuraText.displayFamily,
                      color: color,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  const _TxnRow({required this.txn});
  final _Txn txn;

  @override
  Widget build(BuildContext context) {
    final earn = txn.earn;
    final amtColor = earn ? AuraColors.green : AuraColors.danger;
    return AuraCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (earn ? AuraColors.green : AuraColors.danger).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              earn ? Icons.arrow_upward : Icons.arrow_downward,
              color: earn ? AuraColors.green : AuraColors.danger,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn.title,
                  style: TextStyle(
                    fontFamily: AuraText.displayFamily,
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(txn.subtitle, style: AuraText.cardSub),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CurrencyGlyph(kind: txn.gold ? Currency.gold : Currency.gems, size: 14),
              const SizedBox(width: 5),
              Text(
                '${earn ? '+' : '−'}${txn.amount}',
                style: TextStyle(
                  fontFamily: AuraText.displayFamily,
                  color: amtColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
