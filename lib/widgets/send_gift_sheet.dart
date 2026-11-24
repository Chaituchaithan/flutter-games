import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/social.dart';
import '../data/models/wallet.dart';
import '../services/app_exception.dart';
import '../services/social_api.dart';
import '../services/social_store.dart';
import '../services/wallet_store.dart';
import '../utils/uuid.dart';
import 'aura.dart';

/// Send a gift (tokens or gold with a look and a message) to a friend
/// (docs/services/09-social.md §4a). Asks to confirm; a new `Idempotency-Key`
/// per attempt, the same key when the player retries after "Can't reach the
/// server". Re-reads the wallet after. Resolves to the gift, or null.
///
/// Never shown for a blocked player (the sheet refuses to send).
Future<Gift?> showSendGiftSheet(
  BuildContext context, {
  required String recipientId,
  required String recipientName,
}) =>
    showModalBottomSheet<Gift>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SendGiftSheet(recipientId: recipientId, recipientName: recipientName),
    );

/// Kept to 200 (the in-game socket gift's limit), though the route takes 500.
const giftMessageMax = 200;

class SendGiftSheet extends ConsumerStatefulWidget {
  const SendGiftSheet({super.key, required this.recipientId, required this.recipientName});

  final String recipientId;
  final String recipientName;

  @override
  ConsumerState<SendGiftSheet> createState() => _SendGiftSheetState();
}

class _SendGiftSheetState extends ConsumerState<SendGiftSheet> {
  final _amount = TextEditingController(text: '5');
  final _message = TextEditingController();
  GiftLook _look = GiftLook.rose;
  WalletCurrency _currency = WalletCurrency.gold;
  bool _busy = false;
  String? _error;
  bool _paused = false;

  /// The pending attempt's key, kept only while its outcome is unknown.
  String? _key;
  Object? _keyFor;

  @override
  void dispose() {
    _amount.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    if (amount < 1) {
      setState(() => _error = 'Enter an amount of 1 or more.');
      return;
    }
    final message = _message.text.trim();
    if (message.length > giftMessageMax) {
      setState(() => _error = 'Keep the message to $giftMessageMax characters.');
      return;
    }
    final ok = await showAuraDialog(
      context,
      icon: _look.icon,
      title: 'Send gift',
      body: 'Send ${Wallet.formatAmount(amount)} ${_currency.noun} to ${widget.recipientName}? This can\'t be undone.',
      primaryLabel: 'Send',
      secondaryLabel: 'Cancel',
    );
    if (ok != true || !mounted) return;
    // The key covers receiver, amount, currency and the labels.
    final attempt = (amount, _currency, _look);
    if (_key == null || _keyFor != attempt) {
      _key = newUuidV4();
      _keyFor = attempt;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final g = await ref.read(socialApiProvider).sendGift(
            receiverId: widget.recipientId,
            itemType: _look.wire,
            itemId: _look.wire,
            amount: amount,
            currency: _currency,
            message: message.isEmpty ? null : message,
            idempotencyKey: _key!,
          );
      _key = null;
      // The reply has no balance: re-read it.
      ref.read(walletProvider.notifier).moneyMoved();
      if (!mounted) return;
      showAuraToast(context, 'Gift sent to ${widget.recipientName}.', kind: AuraToastKind.success);
      Navigator.of(context).pop(g);
    } on AppException catch (e) {
      if (!(e.isOffline || e.kind == AppErrorKind.timeout)) _key = null;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = socialErrorText(e, SocialOp.gift, currency: _currency);
        _paused = e.isKillSwitch;
      });
      if (e.code == ApiErrorCode.insufficientFunds) {
        final buy = await showInsufficientBalanceDialog(context);
        if (buy == true && mounted) Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = ref.watch(blockListProvider).containsKey(widget.recipientId);
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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Gift to ${widget.recipientName}', style: AuraText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 14),
                if (blocked)
                  Text("You blocked this player. Unblock them to send a gift.", style: AuraText.cardSub)
                else ...[
                  Row(
                    children: [
                      for (final l in GiftLook.values) ...[
                        Expanded(
                          child: _LookTile(look: l, selected: l == _look, onTap: () => setState(() => _look = l)),
                        ),
                        if (l != GiftLook.values.last) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  SegmentedTabs(
                    labels: const ['Tokens', 'Gold'],
                    index: _currency == WalletCurrency.token ? 0 : 1,
                    onChanged: (i) => setState(() {
                      _currency = i == 0 ? WalletCurrency.token : WalletCurrency.gold;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text('Balance ${wallet?.display(_currency.currency) ?? '—'}', style: AuraText.cardSub),
                  const SizedBox(height: 12),
                  AuraTextField(
                    hint: 'Amount',
                    icon: Icons.toll_rounded,
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: 10),
                  AuraTextField(
                    hint: 'Message (optional)',
                    icon: Icons.chat_bubble_outline_rounded,
                    controller: _message,
                    errorText: _error,
                    onChanged: (_) => setState(() => _error = null),
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 18),
                  GradientButton(label: 'Send gift', loading: _busy, enabled: !_paused, onPressed: _send),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LookTile extends StatelessWidget {
  const _LookTile({required this.look, required this.selected, required this.onTap});
  final GiftLook look;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AuraColors.brandPurple.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AuraColors.accentGlow : Colors.white12),
          ),
          child: Column(
            children: [
              Icon(look.icon, color: selected ? Colors.white : AuraColors.textSecondary, size: 24),
              const SizedBox(height: 4),
              Text(look.label, style: TextStyle(color: selected ? Colors.white : AuraColors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      );
}
