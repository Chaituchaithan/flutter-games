import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/store_repository.dart';
import 'aura.dart';

/// A [CurrencyPill] bound to the live wallet, so every header shows the same
/// balance. Keeps the last value while it refreshes; "—" before it loads.
/// Tokens and Gold pills share one width: that of the longer balance.
class WalletPill extends ConsumerWidget {
  const WalletPill({super.key, required this.kind, this.showPlus = true});

  final Currency kind;
  final bool showPlus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(walletProvider).value;
    return CurrencyPill(
      kind: kind,
      amount: w?.display(kind) ?? '—',
      showPlus: showPlus,
      matchWidthOf: w == null ? const [] : [w.gems, w.gold],
    );
  }
}

/// A tab's title row: title on the left, the Tokens + Gold pills on the
/// right. Fixed height and spacing, so the pills sit in exactly the same
/// spot on every tab that uses it (no shift when switching tabs).
class WalletTitleBar extends StatelessWidget {
  const WalletTitleBar({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(child: Text(title, style: AuraText.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const WalletPill(kind: Currency.gems, showPlus: false),
          const SizedBox(width: 8),
          const WalletPill(kind: Currency.gold, showPlus: false),
        ],
      ),
    );
  }
}
