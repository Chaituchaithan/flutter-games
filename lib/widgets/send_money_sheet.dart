import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/wallet.dart';
import '../services/app_exception.dart';
import '../services/wallet_store.dart';
import '../utils/uuid.dart';
import 'aura.dart';

/// Send tokens or gold to another player (docs/services/03-wallet.md §4).
/// Asks to confirm first; a new `Idempotency-Key` per send attempt, the same
/// key when the player retries after "Can't reach the server". Resolves to
/// the transfer, or null when closed without sending.
Future<TransferResult?> showSendMoneySheet(
  BuildContext context, {
  required String recipientId,
  required String recipientName,
}) =>
    showModalBottomSheet<TransferResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SendMoneySheet(recipientId: recipientId, recipientName: recipientName),
    );

class SendMoneySheet extends ConsumerStatefulWidget {
  const SendMoneySheet({super.key, required this.recipientId, required this.recipientName});

  final String recipientId;
  final String recipientName;

  @override
  ConsumerState<SendMoneySheet> createState() => _SendMoneySheetState();
}

class _SendMoneySheetState extends ConsumerState<SendMoneySheet> {
  final _amount = TextEditingController();
  WalletCurrency _currency = WalletCurrency.gold;
  bool _busy = false;
  String? _error;

  /// An operator paused transfers (`KILL_SWITCH_ENGAGED`): Send stays off.
  bool _paused = false;

  /// The pending attempt's key: kept only while its outcome is unknown (no
  /// network / timeout), so a retry of the same send reuses it.
  String? _key;
  ({int amount, WalletCurrency currency})? _keyFor;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Enter a whole amount above 0.');
      return;
    }
    final ok = await showAuraDialog(
      context,
      icon: Icons.send_rounded,
      title: 'Send money',
      body: 'Send ${Wallet.formatAmount(amount)} ${_currency.noun} to ${widget.recipientName}? This can\'t be undone.',
      primaryLabel: 'Send',
      secondaryLabel: 'Cancel',
    );
    if (ok != true || !mounted) return;
    final attempt = (amount: amount, currency: _currency);
    if (_key == null || _keyFor != attempt) {
      _key = newUuidV4();
      _keyFor = attempt;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(walletProvider.notifier).transfer(
            recipientId: widget.recipientId,
            amount: amount,
            currency: _currency,
            idempotencyKey: _key!,
          );
      _key = null;
      if (!mounted) return;
      showAuraToast(context, 'Sent ${Wallet.formatAmount(r.transferred)} ${r.currency.noun} to ${widget.recipientName}.');
      Navigator.of(context).pop(r);
    } on AppException catch (e) {
      // Outcome unknown → keep the key for a retry; otherwise a new attempt.
      if (!(e.isOffline || e.kind == AppErrorKind.timeout)) _key = null;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
        _paused = e.isKillSwitch;
      });
      if (e.code == ApiErrorCode.insufficientFunds) {
        final buy = await showInsufficientBalanceDialog(context);
        if (buy == true && mounted) Navigator.of(context).pop(); // the caller may open the Store
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider).value;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: AuraColors.bgBase,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Send to ${widget.recipientName}', style: AuraText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 16),
              SegmentedTabs(
                labels: const ['Tokens', 'Gold'],
                index: _currency == WalletCurrency.token ? 0 : 1,
                onChanged: (i) => setState(() {
                  _currency = i == 0 ? WalletCurrency.token : WalletCurrency.gold;
                  _error = null;
                }),
              ),
              const SizedBox(height: 8),
              Text(
                'Balance ${wallet?.display(_currency.currency) ?? '—'}',
                style: AuraText.cardSub,
              ),
              const SizedBox(height: 12),
              AuraTextField(
                hint: 'Amount',
                icon: Icons.toll_rounded,
                controller: _amount,
                keyboardType: TextInputType.number,
                errorText: _error,
                onChanged: (_) => setState(() => _error = null),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 18),
              GradientButton(
                label: 'Send',
                loading: _busy,
                enabled: !_paused,
                onPressed: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
