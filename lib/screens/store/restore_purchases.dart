import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/store_service.dart';
import '../../widgets/aura.dart';

/// "Restore Purchases" (11-store.md §3e; Apple requires one): re-reads
/// ad-free, the inventory and the subscription, then confirms.
Future<void> restorePurchasesWithToast(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(storeControllerProvider).restorePurchases();
    if (context.mounted) showAuraToast(context, 'Purchases restored', kind: AuraToastKind.success);
  } on Object catch (_) {
    if (context.mounted) {
      showAuraToast(context, "Couldn't restore purchases. Try again.", kind: AuraToastKind.error);
    }
  }
}
